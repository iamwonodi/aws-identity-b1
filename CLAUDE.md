# aws-identity-b1

IAM Identity Center in the Organization's management account: who may open a tunnel to the team tools. A blueprint: values ship as `CHANGE_ME`; `scripts/init-identity.sh` sets them.

## Ground rules

- This repository decides who may sign in to the project's accounts. Keep its pipeline's power where it is (Identity Center, reading the Organization, its own state under `identity/`), and every change reviewed.
- `TeamToolsTunnel` grants a port-forwarding session to the server tagged `Service=team-tools`, and nothing else. Never add actions to it; another need is another permission set.
- `data/people.json` and `data/accounts.json` ship empty. A tunnel only in an environment `accounts.json` lists.
- Users created through the API have no password: "Send email OTP" must stay on (Identity Center, Settings, Authentication).

## Checks before a commit

```bash
terraform fmt -check -recursive
(cd modules/team-access && terraform init -backend=false && terraform test)
bash scripts/ci/tests/run-all.sh
shellcheck -S warning scripts/*.sh scripts/ci/*.sh
bash scripts/ci/check-lock-files.sh infrastructure/management && bash scripts/ci/check-lock-files.sh bootstrap
```

## Contracts with the other repositories

- **Team tools** tags its servers `Service=team-tools` and documents the tunnel (its `docs/tunnel.md`).
- **Core and the services** create the database logins people use inside the tools.
