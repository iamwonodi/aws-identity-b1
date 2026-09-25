#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
B="${SCRIPTS}/bootstrap.sh"
export FAKE_TF_LOG="${WORK}/tf.log" FAKE_GH_LOG="${WORK}/gh.log"

fresh(){
  rm -rf "${WORK}/repo"; mkdir -p "${WORK}/repo/infrastructure/management" "${WORK}/repo/bootstrap"
  printf 'project_name = "acme"\naws_region   = "af-south-1"\n' > "${WORK}/repo/infrastructure/management/terraform.tfvars"
  git -C "${WORK}/repo" init -q; git -C "${WORK}/repo" remote add origin https://github.com/acme/identity.git
  export INIT_REPO_ROOT="${WORK}/repo"; : > "${FAKE_TF_LOG}"; : > "${FAKE_GH_LOG}"
}

echo "== bootstrap.sh"
fresh; bash "$B" > "${WORK}/out.txt" 2>&1; rc=$?
check "run succeeds"                                  test $rc -eq 0
check "bootstrap/ is applied for this repository"     bash -c "grep -q 'apply -var project_name=acme -var aws_region=af-south-1 -var github_repository=acme/identity -var create_oidc_provider=true' '${FAKE_TF_LOG}'"
check "no -auto-approve: the administrator confirms"  bash -c "! grep -q 'auto-approve' '${FAKE_TF_LOG}'"
check "the role is set on both environments"          bash -c "grep -q -- '--env management --body arn:aws:iam::999999999999:role/' '${FAKE_GH_LOG}' && grep -q -- '--env management-plan --body arn:aws:iam::' '${FAKE_GH_LOG}'"
fresh; bash "$B" --existing-oidc-provider >/dev/null 2>&1
check "an existing OIDC provider is reused"           grep -q 'create_oidc_provider=false' "${FAKE_TF_LOG}"
fresh; FAKE_MANAGEMENT=111111111111 bash "$B" > "${WORK}/out.txt" 2>&1; rc=$?
check "another account than management is refused"    bash -c "[ $rc -ne 0 ] && [ ! -s '${FAKE_TF_LOG}' ] && grep -q 'not the Organization' '${WORK}/out.txt'"
fresh; printf 'project_name = "CHANGE_ME"\naws_region   = "CHANGE_ME"\n' > "${WORK}/repo/infrastructure/management/terraform.tfvars"
check "before init-identity.sh it is refused"         bash -c "! bash '$B' >/dev/null 2>&1"
fresh; FAKE_ROLE_ARN="nonsense" bash "$B" >/dev/null 2>&1; rc=$?
check "a malformed role ARN sets no secret"           bash -c "[ $rc -ne 0 ] && [ ! -s '${FAKE_GH_LOG}' ]"
finish
