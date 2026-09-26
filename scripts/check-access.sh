#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# WHO HAS A TUNNEL BUT NO DATABASE LOGIN, AND THE REVERSE
#
# A tunnel (this repository's data/people.json) reaches the team tools' server;
# inside the tools each person still signs in with their own database login:
# platform.<name> from core's infrastructure/<env>/data/people.json, or
# <service>.<name> from a service's infrastructure/<env>/data/agents.json. The
# two are kept in different repositories, so they can drift. This lists, for
# every environment:
#
#   A tunnel that leads nowhere   someone may tunnel in but has no database
#                                 login there.
#   A login they cannot reach     someone has a database login in an environment
#                                 whose tools are reached only by tunnel
#                                 (production, unless --tunnel-only says
#                                 otherwise) but no tunnel there.
#
# People are matched by email, ignoring case. It reads local clones and changes
# nothing.
#
# Usage:
#   scripts/check-access.sh --core <core folder> [--service <service-infra folder>]...
#                           [--tunnel-only <env>[,<env>...]]
#
# Exit status: 0 nothing found, 1 something found, 2 a usage or file problem.
# Needs bash and jq.
# ==============================================================================

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
TUNNELS_FILE="${SCRIPT_DIR}/../infrastructure/management/data/people.json"

CORE=""
SERVICES=()
TUNNEL_ONLY="production"

usage() {
  echo "Usage: ${0} --core <core folder> [--service <service-infra folder>]... [--tunnel-only <env>[,<env>...]]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --core)        [[ $# -ge 2 ]] || usage; CORE="$2"; shift 2 ;;
    --service)     [[ $# -ge 2 ]] || usage; SERVICES+=("$2"); shift 2 ;;
    --tunnel-only) [[ $# -ge 2 ]] || usage; TUNNEL_ONLY="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *)             echo "ERROR: unknown argument '$1'." >&2; usage ;;
  esac
done

[[ -n "${CORE}" ]] || { echo "ERROR: --core is required." >&2; usage; }

fail() { echo "ERROR: $*" >&2; exit 2; }

# jq's text output, one value per line. A native jq.exe under Git Bash ends
# lines with CRLF; the stray CR would stop an email or environment matching.
jqr() { jq -r "$@" | tr -d '\r'; }

# True if a "key<TAB>..." line with exactly this key is in the lines given.
has_key() { # <key> <lines>
  awk -F '\t' -v key="$1" '$1 == key { found = 1 } END { exit !found }' <<< "$2"
}

# A list must exist and be a JSON object of entries with an email.
read_list() { # <file> <what>
  [[ -f "$1" ]] || fail "$2 not found: $1"
  jq -e 'type == "object" and all(.[]; (.email | type) == "string")' "$1" >/dev/null 2>&1 ||
    fail "$2 is not an object of entries with an \"email\": $1"
}

read_list "${TUNNELS_FILE}" "this repository's people.json"

CORE_ENVIRONMENTS_FILE="${CORE}/environments.json"
[[ -f "${CORE_ENVIRONMENTS_FILE}" ]] || fail "not a core folder (no environments.json): ${CORE}"

mapfile -t CORE_ENVIRONMENTS < <(jqr '.environments[]' "${CORE_ENVIRONMENTS_FILE}")
[[ ${#CORE_ENVIRONMENTS[@]} -gt 0 ]] || fail "core's environments.json lists no environments."

for service in "${SERVICES[@]}"; do
  [[ -f "${service}/.github/environments.json" ]] || fail "not a service-infra folder (no .github/environments.json): ${service}"
done

# ------------------------------------------------------------------------------
# Every database login in one environment, as "email<TAB>login" lines.
# ------------------------------------------------------------------------------

logins_in() { # <environment>
  local environment="$1" file service label

  file="${CORE}/infrastructure/${environment}/data/people.json"
  if [[ -f "${file}" ]]; then
    read_list "${file}" "core's ${environment} people.json"
    jqr 'to_entries[] | "\(.value.email | ascii_downcase)\tplatform.\(.key)"' "${file}"
  fi

  for service in "${SERVICES[@]}"; do
    # A service runs only in the environments its own list names.
    jq -e --arg e "${environment}" 'index($e) != null' "${service}/.github/environments.json" >/dev/null || continue

    file="${service}/infrastructure/${environment}/data/agents.json"
    [[ -f "${file}" ]] || continue
    read_list "${file}" "${service}'s ${environment} agents.json"

    label="$(basename -- "$(cd -- "${service}" && pwd)")"
    jqr --arg l "${label}" 'to_entries[] | "\(.value.email | ascii_downcase)\t\(.key) in \($l)"' "${file}"
  done
}

# Tunnels into one environment, as "email<TAB>name" lines.
tunnels_into() { # <environment>
  jqr --arg e "$1" 'to_entries[] | select((.value.tunnels // []) | index($e)) | "\(.value.email | ascii_downcase)\t\(.key)"' "${TUNNELS_FILE}"
}

is_tunnel_only() { # <environment>
  [[ ",${TUNNEL_ONLY}," == *",$1,"* ]]
}

# ------------------------------------------------------------------------------
# Report
# ------------------------------------------------------------------------------

found=0
clean=()

# Tunnels into an environment core does not run lead nowhere at all.
mapfile -t TUNNEL_ENVIRONMENTS < <(jqr '[.[].tunnels // [] | .[]] | unique | .[]' "${TUNNELS_FILE}")
for environment in "${TUNNEL_ENVIRONMENTS[@]}"; do
  if ! printf '%s\n' "${CORE_ENVIRONMENTS[@]}" | grep -qx -- "${environment}"; then
    echo "${environment}"
    echo "  Tunnels into an environment core does not run (environments.json):"
    tunnels_into "${environment}" | while IFS=$'\t' read -r email name; do
      echo "    ${name} (${email})"
    done
    found=1
  fi
done

for environment in "${CORE_ENVIRONMENTS[@]}"; do
  logins="$(logins_in "${environment}")"
  tunnels="$(tunnels_into "${environment}")"

  nowhere=""
  while IFS=$'\t' read -r email name; do
    [[ -z "${email}" ]] && continue
    has_key "${email}" "${logins}" || nowhere+="    ${name} (${email})"$'\n'
  done <<< "${tunnels}"

  unreachable=""
  if is_tunnel_only "${environment}"; then
    while IFS=$'\t' read -r email login; do
      [[ -z "${email}" ]] && continue
      has_key "${email}" "${tunnels}" || unreachable+="    ${login} (${email})"$'\n'
    done <<< "$(sort -u <<< "${logins}")"
  fi

  if [[ -z "${nowhere}" && -z "${unreachable}" ]]; then
    clean+=("${environment}")
    continue
  fi

  found=1
  echo "${environment}"
  if [[ -n "${nowhere}" ]]; then
    echo "  A tunnel, but no database login here (add a login, or remove the tunnel):"
    printf '%s' "${nowhere}"
  fi
  if [[ -n "${unreachable}" ]]; then
    echo "  A database login, but no tunnel, and the tools here are reached only by tunnel:"
    printf '%s' "${unreachable}"
  fi
done

if [[ ${#clean[@]} -gt 0 ]]; then
  echo "Nothing to fix in: ${clean[*]}."
fi

if [[ ${#SERVICES[@]} -eq 0 ]]; then
  echo "(No --service given: agents' logins were not counted, only the platform list.)"
fi

exit "${found}"
