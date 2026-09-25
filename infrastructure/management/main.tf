# ------------------------------------------------------------------------------
# WHO MAY OPEN A TUNNEL TO THE TEAM TOOLS
#
# The Organization's management account. data/people.json lists the people and
# the environments they may tunnel into; data/accounts.json the AWS account of
# each environment the project runs. See data/README.md.
# ------------------------------------------------------------------------------

module "team_access" {
  source = "../../modules/team-access"

  people   = jsondecode(file("${path.module}/data/people.json"))
  accounts = jsondecode(file("${path.module}/data/accounts.json"))
}
