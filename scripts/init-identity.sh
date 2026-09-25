#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# INITIALISE A CLONE OF THIS BLUEPRINT FOR ONE PROJECT
#
# Values that differ per project ship as the marker CHANGE_ME, and CI refuses to
# plan while any remain. This sets them and prepares GitHub to guard the
# pipeline. Safe to re-run.
#
#   Files   infrastructure/management/terraform.tfvars   project_name, aws_region
#           infrastructure/management/backend.tf         state bucket and region
#
#   GitHub  Environment management        guards the apply: deployments only
#           from main, reviewers (if given) required. This repository decides
#           who may sign in where: give it reviewers.
#           Environment management-plan   guards plans on pull requests.
#           Each gets the AWS_REGION variable. TF_AWS_ROLE_ARN is set by
#           scripts/bootstrap.sh.
#
# Usage:
#   scripts/init-identity.sh --project NAME --region REGION \
#       [--reviewers login1,login2] [--repo OWNER/REPO] [--skip-github] [--dry-run]
#
#   --project   the project core was set up with
#   --region    the Region of the Organization's IAM Identity Center
#   --dry-run   show what would change; write and call nothing
#
# Needs: bash, sed, jq; gh (authenticated) unless --skip-github or --dry-run.
# ==============================================================================

REPO_ROOT="${INIT_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

PROJECT="" REGION="" REVIEWERS="" REPO=""
SKIP_GITHUB=false
DRY_RUN=false

usage() { sed -n '/^# Usage:/,/^# Needs:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' | head -n -1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)     PROJECT="${2:-}"; shift 2 ;;
    --region)      REGION="${2:-}"; shift 2 ;;
    --reviewers)   REVIEWERS="${2:-}"; shift 2 ;;
    --repo)        REPO="${2:-}"; shift 2 ;;
    --skip-github) SKIP_GITHUB=true; shift ;;
    --dry-run)     DRY_RUN=true; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "ERROR: unknown argument '$1'." >&2; usage >&2; exit 1 ;;
  esac
done

errors=()
[[ "${PROJECT}" =~ ^[a-z][a-z0-9-]{1,14}[a-z0-9]$ ]] || errors+=("--project must be 3-16 lowercase letters, digits or hyphens, starting with a letter.")
[[ "${REGION}" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]$ ]] || errors+=("--region must look like af-south-1.")
if [[ -n "${REPO}" && ! "${REPO}" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]]; then errors+=("--repo must be OWNER/REPOSITORY."); fi
if [[ -n "${REVIEWERS}" && ! "${REVIEWERS}" =~ ^[A-Za-z0-9-]+(,[A-Za-z0-9-]+)*$ ]]; then errors+=("--reviewers must be comma-separated GitHub logins."); fi

if [[ ${#errors[@]} -gt 0 ]]; then
  printf 'ERROR: %s\n' "${errors[@]}" >&2
  exit 1
fi

for command in sed jq; do
  command -v "${command}" >/dev/null 2>&1 || { echo "ERROR: required command not found: ${command}" >&2; exit 1; }
done

if [[ "${SKIP_GITHUB}" != "true" && "${DRY_RUN}" != "true" ]]; then
  command -v gh >/dev/null 2>&1 || { echo "ERROR: gh is required (or pass --skip-github)." >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "ERROR: gh is not authenticated. Run: gh auth login" >&2; exit 1; }
fi

if [[ -z "${REPO}" && "${SKIP_GITHUB}" != "true" ]]; then
  REMOTE_URL="$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null || true)"
  [[ -n "${REMOTE_URL}" ]] || { echo "ERROR: no origin remote; pass --repo OWNER/REPOSITORY." >&2; exit 1; }
  REPO="$(sed -E 's#^(https?://[^/]+/|git@[^:]+:|ssh://[^/]+/)##; s#\.git$##; s#/$##' <<< "${REMOTE_URL}")"
fi

ENVIRONMENTS=(management)

# ------------------------------------------------------------------------------
# Files
# ------------------------------------------------------------------------------

# Replaces the quoted value on the line that sets KEY, keeping alignment and any
# trailing comment. Writes through a temporary file (sed -i differs between GNU
# and BSD) and fails loudly if the line is missing.
set_string() {
  local file="$1" key="$2" value="$3" tmp d=$'\001'
  grep -qE "^[[:space:]]*${key}[[:space:]]*=" "${file}" || { echo "ERROR: ${file} has no '${key} =' line to set." >&2; exit 1; }
  tmp="$(mktemp)"
  sed -E "s${d}^([[:space:]]*${key}[[:space:]]*=[[:space:]]*)\"[^\"]*\"${d}\\1\"${value}\"${d}" "${file}" > "${tmp}"
  cat "${tmp}" > "${file}"
  rm -f "${tmp}"
}

echo "Files"
for ENVIRONMENT in "${ENVIRONMENTS[@]}"; do
  DIR="${REPO_ROOT}/infrastructure/${ENVIRONMENT}"
  [[ -f "${DIR}/terraform.tfvars" && -f "${DIR}/backend.tf" ]] || { echo "ERROR: ${DIR} is missing terraform.tfvars or backend.tf." >&2; exit 1; }
  echo "  ${ENVIRONMENT}: project=${PROJECT} region=${REGION} state=${PROJECT}-${ENVIRONMENT}-tfstate:identity/"

  if [[ "${DRY_RUN}" != "true" ]]; then
    set_string "${DIR}/terraform.tfvars" project_name "${PROJECT}"
    set_string "${DIR}/terraform.tfvars" aws_region "${REGION}"
    set_string "${DIR}/backend.tf" bucket "${PROJECT}-${ENVIRONMENT}-tfstate"
    set_string "${DIR}/backend.tf" region "${REGION}"
  fi
done

# ------------------------------------------------------------------------------
# GitHub Environments
# ------------------------------------------------------------------------------

gh_call() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "  [dry run] gh ${*}"
    if [[ "$*" == *"--input -"* ]]; then cat > /dev/null; fi
    return 0
  fi
  gh "$@"
}

reviewer_json() {
  local login id out="[]"
  IFS=',' read -ra logins <<< "${REVIEWERS}"
  for login in "${logins[@]}"; do
    if [[ "${DRY_RUN}" == "true" ]]; then
      id=0
    else
      id="$(gh api "users/${login}" --jq '.id')" || { echo "ERROR: could not find GitHub user '${login}'." >&2; exit 1; }
    fi
    out="$(jq -c --argjson id "${id}" '. + [{type: "User", id: $id}]' <<< "${out}")"
  done
  echo "${out}"
}

configure_environment() {
  local name="$1" restrict_to_main="$2" reviewers="$3" body

  body="$(jq -cn --argjson reviewers "${reviewers}" --argjson restrict "${restrict_to_main}" \
    '{reviewers: $reviewers}
     + (if $restrict then {deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}}
        else {deployment_branch_policy: null} end)')"

  echo "  environment ${name}: reviewers=$(jq 'length' <<< "${reviewers}") main-only=${restrict_to_main}"

  printf '%s' "${body}" | gh_call api -X PUT "repos/${REPO}/environments/${name}" --input - >/dev/null

  if [[ "${restrict_to_main}" == "true" ]]; then
    # 422 means the policy already exists, which is the state we want.
    printf '%s' '{"name":"main","type":"branch"}' \
      | gh_call api -X POST "repos/${REPO}/environments/${name}/deployment-branch-policies" --input - >/dev/null 2>&1 || true
  fi

  gh_call variable set AWS_REGION --repo "${REPO}" --env "${name}" --body "${REGION}" >/dev/null
}


if [[ "${SKIP_GITHUB}" == "true" ]]; then
  echo "GitHub Environments: skipped (--skip-github)."
else
  echo "GitHub Environments in ${REPO}"
  reviewers="[]"
  if [[ -n "${REVIEWERS}" ]]; then
    reviewers="$(reviewer_json)"
  else
    echo "  WARNING: no --reviewers given, so changes to who may sign in need no approval."
  fi
  for ENVIRONMENT in "${ENVIRONMENTS[@]}"; do
    configure_environment "${ENVIRONMENT}" true "${reviewers}"
    configure_environment "${ENVIRONMENT}-plan" false "[]"
  done

fi

if [[ "${DRY_RUN}" == "true" ]]; then
  echo
  echo "Dry run: nothing was written and GitHub was not called."
  exit 0
fi

echo
echo "Checking that no placeholder remains."
for ENVIRONMENT in "${ENVIRONMENTS[@]}"; do
  bash "${REPO_ROOT}/scripts/ci/check-placeholders.sh" "${REPO_ROOT}/infrastructure/${ENVIRONMENT}"
done

cat <<NEXT

Done. Next, with AWS credentials for the Organization's MANAGEMENT account:

  1. Enable IAM Identity Center for the Organization, in ${REGION}, if it is not
     already (console, once), and turn on Settings > Authentication > Send email
     OTP (docs/first-setup.md).

  2. scripts/bootstrap.sh
     creates the state bucket, GitHub's OIDC provider and the pipeline's role,
     and sets TF_AWS_ROLE_ARN on both GitHub Environments.

  3. Fill data/accounts.json and data/people.json, commit, and open a pull request.

NEXT
