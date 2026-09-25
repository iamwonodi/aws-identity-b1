#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
INIT="${SCRIPTS}/init-identity.sh"
SOURCE_ROOT="$(cd "${SCRIPTS}/.." && pwd)"

fresh(){
  rm -rf "${WORK}/repo"; mkdir -p "${WORK}/repo/scripts/ci" "${WORK}/repo/infrastructure"
  cp -r "${SOURCE_ROOT}/infrastructure/management" "${WORK}/repo/infrastructure/"; rm -rf "${WORK}/repo/infrastructure/management/.terraform"
  cp "${SCRIPTS}/ci/check-placeholders.sh" "${WORK}/repo/scripts/ci/"
  git -C "${WORK}/repo" init -q; git -C "${WORK}/repo" remote add origin https://github.com/acme/identity.git
  export INIT_REPO_ROOT="${WORK}/repo" FAKE_GH_LOG="${WORK}/gh.log"; : > "${FAKE_GH_LOG}"
}
M="${WORK}/repo/infrastructure/management"
run(){ bash "${INIT}" --project acme --region af-south-1 "$@"; }

echo "== init-identity.sh"
fresh; run --reviewers alice > "${WORK}/out.txt" 2>&1; rc=$?
check "run succeeds"                                  test $rc -eq 0
check "project and region are set"                    bash -c "grep -qx 'project_name = \"acme\"' '$M/terraform.tfvars' && grep -qx 'aws_region   = \"af-south-1\"' '$M/terraform.tfvars'"
check "the management state bucket is set"            grep -q 'bucket = "acme-management-tfstate"' "$M/backend.tf"
check "the state key keeps identity/"                 grep -q 'key = "identity/terraform.tfstate"' "$M/backend.tf"
check "no placeholder remains"                        bash "${WORK}/repo/scripts/ci/check-placeholders.sh" "$M"
check "management is main-only and reviewed"          bash -c "grep -A1 'environments/management --input' '${FAKE_GH_LOG}' | grep -q 'custom_branch_policies\":true' && grep -A1 'environments/management --input' '${FAKE_GH_LOG}' | grep -q '\"id\":4242'"
check "management-plan exists"                        grep -q 'environments/management-plan --input' "${FAKE_GH_LOG}"
check "the next step is the bootstrap"                grep -q 'scripts/bootstrap.sh' "${WORK}/out.txt"
fresh; run > "${WORK}/out.txt" 2>&1
check "no reviewers is warned about"                  grep -q 'WARNING: no --reviewers' "${WORK}/out.txt"
fresh; run --dry-run >/dev/null 2>&1
check "a dry run writes nothing"                      grep -q 'CHANGE_ME' "$M/terraform.tfvars"
fresh
check "a bad region is refused"                       bash -c "! bash '${INIT}' --project acme --region africa >/dev/null 2>&1"
finish
