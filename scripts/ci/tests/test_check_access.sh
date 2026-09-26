#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Each case builds: this repository (the script and its tunnel list), a core
# folder (environments.json, each environment's people.json) and service-infra
# folders (.github/environments.json, each environment's agents.json).
ID="${WORK}/identity"; CORE="${WORK}/core"

setup() {
  rm -rf "${ID}" "${CORE}" "${WORK}"/svc-*
  mkdir -p "${ID}/scripts" "${ID}/infrastructure/management/data"
  cp "${SCRIPTS}/check-access.sh" "${ID}/scripts/"
  mkdir -p "${CORE}"
  printf '{"environments":["development","staging","production"]}' > "${CORE}/environments.json"
  for e in development staging production; do mkdir -p "${CORE}/infrastructure/${e}/data"; echo '{}' > "${CORE}/infrastructure/${e}/data/people.json"; done
  tunnels '{}'
}
tunnels()  { printf '%s' "$1" > "${ID}/infrastructure/management/data/people.json"; }
platform() { printf '%s' "$2" > "${CORE}/infrastructure/$1/data/people.json"; }            # <env> <json>
service()  { local d="${WORK}/svc-$1"; mkdir -p "${d}/.github"; printf '%s' "$2" > "${d}/.github/environments.json"; }  # <name> <env list>
agents()   { local d="${WORK}/svc-$1/infrastructure/$2/data"; mkdir -p "${d}"; printf '%s' "$3" > "${d}/agents.json"; }  # <name> <env> <json>
run()      { bash "${ID}/scripts/check-access.sh" --core "${CORE}" "$@" > "${WORK}/out.txt" 2>&1; }
said()     { grep -qF -- "$1" "${WORK}/out.txt"; }
ada='"ada":{"email":"Ada@Example.org","given_name":"Ada","family_name":"L","tunnels":["production"]}'

echo "== check-access.sh"
setup; run; rc=$?
check "empty lists: nothing found"                           test $rc -eq 0
check "  and says so"                                        said "Nothing to fix in: development staging production."

setup; tunnels "{${ada}}"; run; rc=$?
check "a tunnel but no login: found"                          test $rc -eq 1
check "  named with their email, under production"            bash -c "grep -A2 '^production' '${WORK}/out.txt' | grep -qF 'ada (ada@example.org)'"
check "  as a tunnel that leads nowhere"                      said "A tunnel, but no database login here"

setup; tunnels "{${ada}}"; platform production '{"ada":{"email":"ada@example.org","access":"read"}}'; run; rc=$?
check "a tunnel and a platform login: fine (case ignored)"    test $rc -eq 0

setup; tunnels "{${ada}}"; service orders '["development","staging","production"]'; agents orders production '{"ada":{"email":"ADA@example.org","access":"read"}}'
run --service "${WORK}/svc-orders"; rc=$?
check "a tunnel and an agent login: fine"                     test $rc -eq 0
run; rc=$?
check "the same without --service: the agent is not counted"  bash -c "[[ $rc -eq 1 ]] && grep -qF 'agents' '${WORK}/out.txt'"

setup; service orders '["development","staging","production"]'; agents orders production '{"bob":{"email":"bob@example.org","access":"read"}}'
platform production '{"tunde":{"email":"tunde@example.org","access":"write"}}'
run --service "${WORK}/svc-orders"; rc=$?
check "production logins with no tunnel: found"               test $rc -eq 1
check "  the platform login, by its login name"               said "platform.tunde (tunde@example.org)"
check "  the agent, with its service folder"                  said "bob in svc-orders (bob@example.org)"
check "  as logins they cannot reach"                         said "reached only by tunnel"

setup; platform staging '{"tunde":{"email":"tunde@example.org","access":"write"}}'; run; rc=$?
check "a login with no tunnel in staging: fine (web address)" test $rc -eq 0
run --tunnel-only staging,production; rc=$?
check "  unless staging is named tunnel-only"                 bash -c "[[ $rc -eq 1 ]] && grep -A2 '^staging' '${WORK}/out.txt' | grep -qF platform.tunde"

setup; tunnels '{"ada":{"email":"ada@example.org","given_name":"A","family_name":"L","tunnels":["development"]}}'
platform development '{"ada":{"email":"ada@example.org","access":"read"}}'
printf '{"environments":["production"]}' > "${CORE}/environments.json"; run; rc=$?
check "a tunnel into an environment core does not run"        bash -c "[[ $rc -eq 1 ]] && grep -qF 'core does not run' '${WORK}/out.txt'"

setup; tunnels "{${ada}}"; service billing '["development"]'; agents billing production '{"ada":{"email":"ada@example.org","access":"read"}}'
run --service "${WORK}/svc-billing"; rc=$?
check "an agents file for an environment the service does not run is ignored" test $rc -eq 1

setup; tunnels '{"ab":{"email":"a.b@example.org","given_name":"A","family_name":"B","tunnels":["production"]}}'
platform production '{"axb":{"email":"axb@example.org","access":"read"}}'; run; rc=$?
check "emails match exactly (a dot is not a wildcard)"         bash -c "[[ $rc -eq 1 ]] && grep -qF 'ab (a.b@example.org)' '${WORK}/out.txt'"

setup; tunnels "{${ada}}"; platform production '{"ada":{"email":"ada@example.org","access":"read"}}'
mkdir -p "${WORK}/bin"; printf '#!/bin/sh\n# jq.exe under Git Bash: CRLF line endings\n%s "$@" | sed "s/$/\\r/"\n' "$(command -v jq)" > "${WORK}/bin/jq"; chmod +x "${WORK}/bin/jq"
PATH="${WORK}/bin:${PATH}" run; rc=$?
check "Windows line endings from jq: a match still matches"    test $rc -eq 0
tunnels '{"ada":{"email":"ada@example.org","given_name":"A","family_name":"L","tunnels":["production"]},"bea":{"email":"bea@example.org","given_name":"B","family_name":"L","tunnels":["production"]}}'
PATH="${WORK}/bin:${PATH}" run; rc=$?
check "  and a missing login is still found"                   bash -c "[[ $rc -eq 1 ]] && grep -A2 '^production' '${WORK}/out.txt' | grep -qF 'bea (bea@example.org)' && ! grep -q \$'\\r' '${WORK}/out.txt'"

setup; run --core /nonexistent; rc=$?
check "not a core folder: a usage problem"                     test $rc -eq 2
setup; run --service "${WORK}/nope"; rc=$?
check "not a service-infra folder: a usage problem"            test $rc -eq 2
setup; tunnels '{"ada":{"given_name":"A"}}'; run; rc=$?
check "an entry without an email: a file problem"              bash -c "[[ $rc -eq 2 ]] && grep -qF 'email' '${WORK}/out.txt'"
setup; bash "${ID}/scripts/check-access.sh" >/dev/null 2>&1; rc=$?
check "no --core: a usage problem"                             test $rc -eq 2
finish
