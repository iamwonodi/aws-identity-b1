# people.json

Who may open a tunnel to the team tools, and where. **It ships empty (`{}`)**; `people.example.json` shows the shape.

| Field | Meaning |
| --- | --- |
| key | A short name: 2-20 lowercase letters and digits |
| `email` | Their sign-in to the AWS access portal. Unique |
| `given_name`, `family_name` | Required by IAM Identity Center |
| `tunnels` | The environments whose tools they may tunnel into: any of `development`, `staging`, `production`, each listed in `accounts.json` |

A tunnel reaches the tools' server only; inside the tools each person still signs in to the database with their own login (`<service>.<name>` from their service, or `platform.<name>` from core). Give a tunnel only to someone who has one.

**Checking the two agree.** The logins live in other repositories, so the lists can drift. With local clones:

```bash
scripts/check-access.sh --core ../core-infrastructure \
  --service ../aws-service-infra-b1 --service ../another-service-infra
```

It lists, per environment, anyone with a tunnel but no database login there, and anyone with a database login in production (reached only by tunnel) but no tunnel there. `--tunnel-only staging,production` adds staging to the second check. People are matched by email; nothing is changed. Exit status 1 means something was found. Without `--service`, only core's platform list is counted.

**Adding someone:** add their entry and merge. They open the access portal (`terraform output access_portal`), enter their email, and follow the verification email to set a password and two-factor sign-in ("Send email OTP" must be on; docs/first-setup.md).

**Removing someone:** delete their entry and merge: their user, and every tunnel, goes.

# accounts.json

The AWS account ID of each environment the project runs, `{ "production": "333333333333" }`. Account IDs are not secret. **It ships empty (`{}`)**; a tunnel can be given only in an environment listed here.
