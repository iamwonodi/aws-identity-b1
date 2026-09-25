#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# BOOTSTRAP THE MANAGEMENT ACCOUNT FOR THIS REPOSITORY'S PIPELINE
#
# Run once, by an administrator, with AWS credentials for the Organization's
# MANAGEMENT account, after scripts/init-identity.sh. It applies bootstrap/
# (the state bucket, GitHub's OIDC provider, the pipeline's role; Terraform shows
# the plan and asks before changing anything), then sets the role's ARN as the
# TF_AWS_ROLE_ARN secret on the management and management-plan GitHub
# Environments.
#
# bootstrap/'s own state stays on this machine (bootstrap/terraform.tfstate,
# never committed). Keep it, or import the resources before running this again.
#
# Usage: scripts/bootstrap.sh [--existing-oidc-provider] [--repo OWNER/REPO] [--skip-github]
#
#   --existing-oidc-provider   the account already has GitHub's OIDC provider
#
# Needs: terraform, aws, jq; gh (authenticated) unless --skip-github.
# ==============================================================================

REPO_ROOT="${INIT_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TFVARS="${REPO_ROOT}/infrastructure/management/terraform.tfvars"
CREATE_OIDC=true REPO="" SKIP_GITHUB=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --existing-oidc-provider) CREATE_OIDC=false; shift ;;
    --repo)                   REPO="${2:-}"; shift 2 ;;
    --skip-github)            SKIP_GITHUB=true; shift ;;
    *) echo "ERROR: unknown argument '$1'." >&2; exit 1 ;;
  esac
done

for command in terraform aws jq; do
  command -v "${command}" >/dev/null 2>&1 || { echo "ERROR: required command not found: ${command}" >&2; exit 1; }
done

read_value() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "${TFVARS}" | head -n 1; }
PROJECT="$(read_value project_name)"
REGION="$(read_value aws_region)"

if [[ -z "${PROJECT}" || "${PROJECT}" == "CHANGE_ME" || -z "${REGION}" || "${REGION}" == "CHANGE_ME" ]]; then
  echo "ERROR: project_name and aws_region are not set in ${TFVARS}: run scripts/init-identity.sh first." >&2
  exit 1
fi

if [[ -z "${REPO}" ]]; then
  REMOTE_URL="$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null || true)"
  [[ -n "${REMOTE_URL}" ]] || { echo "ERROR: no origin remote; pass --repo OWNER/REPO." >&2; exit 1; }
  REPO="$(sed -E 's#^(https?://[^/]+/|git@[^:]+:|ssh://[^/]+/)##; s#\.git$##; s#/$##' <<< "${REMOTE_URL}")"
fi
[[ "${REPO}" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || { echo "ERROR: '${REPO}' is not OWNER/REPOSITORY." >&2; exit 1; }

if [[ "${SKIP_GITHUB}" != "true" ]]; then
  command -v gh >/dev/null 2>&1 || { echo "ERROR: gh is required (or pass --skip-github)." >&2; exit 1; }
fi

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)" \
  || { echo "ERROR: no AWS credentials: point them at the Organization's management account." >&2; exit 1; }

MANAGEMENT="$(aws organizations describe-organization --query Organization.MasterAccountId --output text 2>/dev/null || true)"
if [[ "${MANAGEMENT}" != "${ACCOUNT}" ]]; then
  echo "ERROR: these credentials are for account ${ACCOUNT}, which is not the Organization's management account${MANAGEMENT:+ (${MANAGEMENT})}." >&2
  exit 1
fi

echo "Bootstrapping ${REPO}'s pipeline in the management account ${ACCOUNT} (${REGION})."

BOOTSTRAP="${REPO_ROOT}/bootstrap"
terraform -chdir="${BOOTSTRAP}" init -input=false
terraform -chdir="${BOOTSTRAP}" apply \
  -var "project_name=${PROJECT}" \
  -var "aws_region=${REGION}" \
  -var "github_repository=${REPO}" \
  -var "create_oidc_provider=${CREATE_OIDC}"

ROLE_ARN="$(terraform -chdir="${BOOTSTRAP}" output -raw role_arn)"
[[ "${ROLE_ARN}" =~ ^arn:aws:iam::[0-9]{12}:role/.+ ]] || { echo "ERROR: '${ROLE_ARN}' is not a role ARN." >&2; exit 1; }

if [[ "${SKIP_GITHUB}" == "true" ]]; then
  echo "Skipped GitHub: set TF_AWS_ROLE_ARN=${ROLE_ARN} on the management and management-plan environments."
  exit 0
fi

for TARGET in management management-plan; do
  echo "Setting TF_AWS_ROLE_ARN on ${REPO}'s ${TARGET} environment."
  gh secret set TF_AWS_ROLE_ARN --repo "${REPO}" --env "${TARGET}" --body "${ROLE_ARN}" \
    || { echo "ERROR: could not set the secret on ${TARGET}. Create the environments first: scripts/init-identity.sh" >&2; exit 1; }
done

echo "Done: ${REPO} will assume ${ROLE_ARN}."
