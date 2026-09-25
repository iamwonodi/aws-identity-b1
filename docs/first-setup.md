# First setup

You need AWS credentials for the Organization's **management account**, and `gh` signed in.

1. **Create the repository** from this blueprint and clone it.
2. **Initialise it:**
   `scripts/init-identity.sh --project <project> --region <identity-center-region> --reviewers <login,...>`
   Writes the project and Region, and creates the `management` (reviewed, main only) and `management-plan` GitHub Environments.
3. **In the management account's console, once:**
   - **Enable IAM Identity Center** for the Organization, in that Region, if it is not already.
   - **Settings, Authentication, Standard authentication, Configure: tick "Send email OTP"** and save. Users created by this repository have no password; with this on, each gets a verification email at their first sign-in and sets their own.
4. **Bootstrap:** `scripts/bootstrap.sh` (add `--existing-oidc-provider` if the account already has GitHub's). Terraform shows what it will create and asks before creating it. Keep `bootstrap/terraform.tfstate`.
5. **Fill the lists:** `infrastructure/management/data/accounts.json` (the account ID of each environment the project runs; for tunnels, usually just production) and `data/people.json`. See `data/README.md`.
6. **Commit and open a pull request.** The plan shows who gains access where; merging applies it.
7. **Tell each person:** the access portal address (the Apply workflow's summary, or `terraform output access_portal`); they enter their email, follow the verification email, set a password and two-factor sign-in, and then follow the tools repository's `docs/tunnel.md`.
