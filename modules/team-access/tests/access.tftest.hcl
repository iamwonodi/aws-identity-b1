# Run with: terraform init -backend=false && terraform test   (no AWS access needed)

mock_provider "aws" {
  mock_resource "aws_ssoadmin_permission_set" {
    defaults = { arn = "arn:aws:sso:::permissionSet/ssoins-0123456789abcdef/ps-0123456789abcdef" }
  }

  mock_resource "aws_identitystore_group" {
    defaults = { group_id = "0123456789-12345678-1234-1234-1234-123456789012" }
  }

  mock_resource "aws_identitystore_user" {
    defaults = { user_id = "0123456789-87654321-4321-4321-4321-210987654321" }
  }

  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws:sso:::instance/ssoins-0123456789abcdef"]
      identity_store_ids = ["d-0123456789"]
    }
  }
}

variables {
  accounts = {
    development = "111111111111"
    production  = "333333333333"
  }

  people = {
    ada   = { email = "Ada@Example.org", given_name = "Ada", family_name = "Lovelace", tunnels = ["production"] }
    tunde = { email = "tunde@example.org", given_name = "Tunde", family_name = "Bello", tunnels = ["development", "production"] }
  }
}

run "each_person_signs_in_with_their_email" {
  command = plan

  assert {
    condition     = aws_identitystore_user.person["ada"].user_name == "ada@example.org" && aws_identitystore_user.person["ada"].display_name == "Ada Lovelace"
    error_message = "a user per person, signing in with their email in lower case"
  }
}

run "one_group_per_environment_assigned_to_its_account" {
  command = plan

  assert {
    condition     = toset(keys(aws_identitystore_group.tunnel)) == toset(["development", "production"]) && aws_identitystore_group.tunnel["production"].display_name == "team-tools-tunnel-production"
    error_message = "a group per environment someone has a tunnel in"
  }

  assert {
    condition     = aws_ssoadmin_account_assignment.tunnel["production"].target_id == "333333333333" && aws_ssoadmin_account_assignment.tunnel["production"].principal_type == "GROUP"
    error_message = "the production group is assigned to the production account"
  }

  assert {
    condition     = toset(keys(aws_identitystore_group_membership.tunnel)) == toset(["ada/production", "tunde/development", "tunde/production"])
    error_message = "each person in the groups of their tunnels, and no other"
  }

  assert {
    condition     = jsonencode(output.tunnels) == jsonencode({ development = ["tunde"], production = ["ada", "tunde"] })
    error_message = "who may tunnel where"
  }
}

run "the_permission_set_tunnels_to_the_tools_and_does_nothing_else" {
  command = plan

  assert {
    condition     = aws_ssoadmin_permission_set.tunnel.name == "TeamToolsTunnel" && aws_ssoadmin_permission_set.tunnel.session_duration == "PT8H"
    error_message = "TeamToolsTunnel, eight hours"
  }

  assert {
    condition     = one([for s in jsondecode(local.tunnel_policy).Statement : s if s.Sid == "TunnelToTheToolsServerOnly"]).Condition.StringEquals["ssm:resourceTag/Service"] == "team-tools"
    error_message = "sessions only on the server tagged Service=team-tools"
  }

  assert {
    condition     = one([for s in jsondecode(local.tunnel_policy).Statement : s if s.Sid == "TunnelToTheToolsServerOnly"]).Condition.BoolIfExists["ssm:SessionDocumentAccessCheck"] == "true" && one([for s in jsondecode(local.tunnel_policy).Statement : s if s.Sid == "PortForwardingOnly"]).Resource == "arn:aws:ssm:*::document/AWS-StartPortForwardingSession"
    error_message = "only the port-forwarding document: no shell"
  }

  assert {
    condition     = one([for s in jsondecode(local.tunnel_policy).Statement : s if s.Sid == "OwnSessionsOnly"]).Resource == "arn:aws:ssm:*:*:session/$${aws:userid}-*"
    error_message = "a person may end or resume their own sessions only"
  }

  assert {
    condition     = output.access_portal == "https://d-0123456789.awsapps.com/start"
    error_message = "the portal people sign in at"
  }
}

run "a_tunnel_where_the_project_has_no_account_is_refused" {
  command = plan

  variables {
    people = {
      ada = { email = "ada@example.org", given_name = "Ada", family_name = "Lovelace", tunnels = ["staging"] }
    }
  }

  expect_failures = [terraform_data.invariants]
}

run "identity_center_not_enabled_is_refused" {
  command = plan

  override_data {
    target = data.aws_ssoadmin_instances.this
    values = { arns = [], identity_store_ids = [] }
  }

  variables {
    people = {}
  }

  expect_failures = [data.aws_ssoadmin_instances.this]
}

run "a_shared_email_is_refused" {
  command = plan

  variables {
    people = {
      ada  = { email = "ada@example.org", given_name = "Ada", family_name = "L", tunnels = ["production"] }
      ada2 = { email = "ADA@example.org", given_name = "Ada", family_name = "L", tunnels = ["production"] }
    }
  }

  expect_failures = [var.people]
}

run "a_missing_family_name_is_refused" {
  command = plan

  variables {
    people = {
      ada = { email = "ada@example.org", given_name = "Ada", family_name = " ", tunnels = ["production"] }
    }
  }

  expect_failures = [var.people]
}

run "an_unknown_environment_is_refused" {
  command = plan

  variables {
    people = {
      ada = { email = "ada@example.org", given_name = "Ada", family_name = "L", tunnels = ["prod"] }
    }
  }

  expect_failures = [var.people]
}
