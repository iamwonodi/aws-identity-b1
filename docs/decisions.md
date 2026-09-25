# Decisions

| Decision | Why |
| --- | --- |
| A repository of its own for the management account | Whoever changes the management account decides who may sign in to every account. Core's pipeline changes often; this one rarely, with its own role and reviewers |
| Its own list of people, not one worked out from the services' agents and core's platform list | Reaching production is a deliberate decision of its own. Either half alone (tunnel, database login) gives nothing |
| `TeamToolsTunnel` allows only port forwarding to the server tagged `Service=team-tools` | `ssm:SessionDocumentAccessCheck` makes the session document part of the permission, so no shell session is possible; the tag condition limits it to the tools' server |
| One group per environment, assigned in that environment's account | Access is added and removed by membership; the assignment itself changes only when an environment gains or loses its first tunnel |
| CI with a GitHub OIDC role trusted only by the `management` and `management-plan` environments | Every change is reviewed and recorded; nothing else (a branch, a fork) can assume the role |
| Bootstrap applied once by hand, with local state | The pipeline cannot create the role it runs as. Its three resources are small and can be imported if the state is lost |
| "Send email OTP" | Users created through the API have no password; with it on, a new person gets a verification email at their first sign-in and sets their own |
