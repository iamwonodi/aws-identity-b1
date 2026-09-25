# aws-identity-b1

Who may reach the team tools where they have no web address: **production's tools are reached only through a Session Manager tunnel**, and this repository gives people the AWS sign-in that may open it. It lives in the Organization's **management account**, using **IAM Identity Center**.

```text
person ──► AWS access portal (email, password, two-factor)
             │  TeamToolsTunnel, in the accounts of their tunnels
             ▼
        aws ssm start-session ... AWS-StartPortForwardingSession
             │  only to the server tagged Service=team-tools; no shell
             ▼
        DbGate / CloudBeaver on localhost ──► their own database login
```

## What it builds

| | |
| --- | --- |
| Permission set `TeamToolsTunnel` | Find the tools' server, open a port-forwarding tunnel to it, end or resume their own sessions. Nothing else: no shell, no other server, no other AWS action |
| Users | One per person in `data/people.json`, signing in with their email |
| Groups | `team-tools-tunnel-<environment>`, one per environment someone has a tunnel in, assigned `TeamToolsTunnel` in that environment's account (`data/accounts.json`) |

A tunnel reaches the tools, not the data: inside them each person signs in to the database with their own login (`<service>.<name>` or `platform.<name>`). Production is normally the only environment that needs a tunnel (development and staging have web addresses behind core's front door), but any environment the project runs can be listed.

## Layout

| Path | |
| --- | --- |
| `modules/team-access/` | The permission set, users, groups and assignments |
| `infrastructure/management/` | The management account's root; `data/` holds the lists (see its README) |
| `bootstrap/` | Applied once by an administrator: state bucket, GitHub's OIDC provider, the pipeline's role |
| `scripts/init-identity.sh` | Sets up a clone and its GitHub Environments |
| `scripts/bootstrap.sh` | Applies `bootstrap/` and connects the role |

## Workflows

| Workflow | When | |
| --- | --- | --- |
| Tests | every pull request and push | shellcheck, script tests, format, lock files, validate, module tests |
| Plan | pull requests | under `management-plan`: who gains or loses access |
| Apply | merge to `main` | under `management`, with its reviewers |

The pipeline's role administers Identity Center, so it decides who may sign in to every account: only this repository's two GitHub Environments may assume it, and every change needs review.

First setup: `docs/first-setup.md`.
