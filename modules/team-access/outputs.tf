output "access_portal" {
  description = "Where people sign in: the AWS access portal (unless its address was customised in Identity Center's settings)."
  value       = local.identity_store_id == null ? null : "https://${local.identity_store_id}.awsapps.com/start"
}

output "tunnels" {
  description = "Who may open a tunnel, by environment."
  value       = { for env in local.tunnel_environments : env => sort([for key, m in local.memberships : m.name if m.environment == env]) }
}
