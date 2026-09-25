output "access_portal" {
  description = "Where people sign in."
  value       = module.team_access.access_portal
}

output "tunnels" {
  description = "Who may open a tunnel, by environment."
  value       = module.team_access.tunnels
}
