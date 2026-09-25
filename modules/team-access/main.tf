# ------------------------------------------------------------------------------
# TEAM ACCESS: THE TOOLS TUNNEL
#
# IAM Identity Center, in the Organization's management account. Each person on
# the list gets a user (signing in with their email) and, for each environment
# in their tunnels, membership of that environment's group, which is assigned
# the TeamToolsTunnel permission set in that environment's account.
#
# TeamToolsTunnel can find the team tools' server and open a Session Manager
# port-forwarding tunnel to it, and nothing else: the server must carry
# Service=team-tools, and the only session allowed is AWS-StartPortForwardingSession
# (no shell). Their database login is separate: <service>.<name> or
# platform.<name>, created elsewhere.
#
# Identity Center must already be enabled for the Organization (a console step).
# Users created here have no password: with "Send email OTP" on (Identity
# Center, Settings, Authentication), they receive a verification email at their
# first sign-in and set their own.
# ------------------------------------------------------------------------------

locals {
  instance_arn      = one(data.aws_ssoadmin_instances.this.arns)
  identity_store_id = one(data.aws_ssoadmin_instances.this.identity_store_ids)

  # Environments someone has a tunnel in, and that the project runs.
  tunnel_environments = toset([for env in distinct(flatten([for p in values(var.people) : p.tunnels])) : env if contains(keys(var.accounts), env)])

  memberships = merge([
    for name, p in var.people : { for env in p.tunnels : "${name}/${env}" => { name = name, environment = env } }
  ]...)

  unknown_tunnels = sort(distinct([for m in values(local.memberships) : m.environment if !contains(keys(var.accounts), m.environment)]))
}

data "aws_ssoadmin_instances" "this" {
  lifecycle {
    # Checked on the lookup itself, before anything uses the instance.
    postcondition {
      condition     = length(self.arns) == 1
      error_message = "IAM Identity Center is not enabled for the Organization in this Region: enable it once in the management account's console (docs/first-setup.md)."
    }
  }
}

resource "terraform_data" "invariants" {
  lifecycle {
    precondition {
      condition     = length(local.unknown_tunnels) == 0
      error_message = "people.json gives tunnels in ${join(", ", local.unknown_tunnels)}, which accounts.json does not list: the project does not run it, or its account is missing."
    }
  }
}

# ------------------------------------------------------------------------------
# The permission set
# ------------------------------------------------------------------------------

resource "aws_ssoadmin_permission_set" "tunnel" {
  instance_arn     = local.instance_arn
  name             = "TeamToolsTunnel"
  description      = "Open a port-forwarding tunnel to the team tools' server, and nothing else."
  session_duration = "PT${var.session_hours}H"
}

resource "aws_ssoadmin_permission_set_inline_policy" "tunnel" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.tunnel.arn
  inline_policy      = local.tunnel_policy
}

locals {
  tunnel_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Finding the server (docs/tunnel.md in the tools repository). Read-only.
      {
        Sid      = "FindTheToolsServer"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ssm:DescribeInstanceInformation", "ssm:GetConnectionStatus"]
        Resource = "*"
      },
      # A session only on the tools' server, and only with a document this
      # policy names (SessionDocumentAccessCheck): no shell.
      {
        Sid      = "TunnelToTheToolsServerOnly"
        Effect   = "Allow"
        Action   = "ssm:StartSession"
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          StringEquals = { "ssm:resourceTag/Service" = "team-tools" }
          BoolIfExists = { "ssm:SessionDocumentAccessCheck" = "true" }
        }
      },
      {
        Sid      = "PortForwardingOnly"
        Effect   = "Allow"
        Action   = "ssm:StartSession"
        Resource = "arn:aws:ssm:*::document/AWS-StartPortForwardingSession"
      },
      {
        Sid      = "OwnSessionsOnly"
        Effect   = "Allow"
        Action   = ["ssm:ResumeSession", "ssm:TerminateSession"]
        Resource = "arn:aws:ssm:*:*:session/$${aws:userid}-*"
      },
    ]
  })
}

# ------------------------------------------------------------------------------
# People, groups and assignments
# ------------------------------------------------------------------------------

resource "aws_identitystore_user" "person" {
  for_each = var.people

  identity_store_id = local.identity_store_id
  user_name         = lower(each.value.email)
  display_name      = "${each.value.given_name} ${each.value.family_name}"

  name {
    given_name  = each.value.given_name
    family_name = each.value.family_name
  }

  emails {
    value   = lower(each.value.email)
    primary = true
  }
}

resource "aws_identitystore_group" "tunnel" {
  for_each = local.tunnel_environments

  identity_store_id = local.identity_store_id
  display_name      = "team-tools-tunnel-${each.key}"
  description       = "May open a tunnel to the team tools in ${each.key}."
}

resource "aws_identitystore_group_membership" "tunnel" {
  for_each = { for key, m in local.memberships : key => m if contains(keys(var.accounts), m.environment) }

  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.tunnel[each.value.environment].group_id
  member_id         = aws_identitystore_user.person[each.value.name].user_id
}

resource "aws_ssoadmin_account_assignment" "tunnel" {
  for_each = local.tunnel_environments

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.tunnel.arn

  principal_type = "GROUP"
  principal_id   = aws_identitystore_group.tunnel[each.key].group_id

  target_type = "AWS_ACCOUNT"
  target_id   = var.accounts[each.key]

  depends_on = [aws_ssoadmin_permission_set_inline_policy.tunnel]
}
