variable "people" {
  type = map(object({
    email       = string
    given_name  = string
    family_name = string
    tunnels     = list(string)
  }))
  default     = {}
  description = "Who may open a tunnel to the team tools, and in which environments: { name = { email, given_name, family_name, tunnels = [\"production\"] } }. Each gets an IAM Identity Center user, signing in with their email."

  validation {
    condition     = alltrue([for name in keys(var.people) : can(regex("^[a-z][a-z0-9]{1,19}$", name))])
    error_message = "Each person's key must be 2-20 lowercase letters and digits, starting with a letter."
  }

  validation {
    condition     = alltrue([for p in values(var.people) : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", p.email))])
    error_message = "Each person needs a valid email address: it is their sign-in."
  }

  validation {
    condition     = length(distinct([for p in values(var.people) : lower(p.email)])) == length(var.people)
    error_message = "Two people share an email address."
  }

  validation {
    condition     = alltrue([for p in values(var.people) : trimspace(p.given_name) != "" && trimspace(p.family_name) != ""])
    error_message = "Identity Center requires each person's given name and family name."
  }

  validation {
    condition     = alltrue(flatten([for p in values(var.people) : [for t in p.tunnels : contains(["development", "staging", "production"], t)]]))
    error_message = "tunnels may list development, staging and production."
  }
}

variable "accounts" {
  type        = map(string)
  default     = {}
  description = "The AWS account of each environment the project runs: { production = \"123456789012\" }. A tunnel can be given only for an environment listed here."

  validation {
    condition     = alltrue([for env, id in var.accounts : contains(["development", "staging", "production"], env) && can(regex("^[0-9]{12}$", id))])
    error_message = "accounts maps development, staging or production to a 12-digit AWS account ID."
  }
}

variable "session_hours" {
  type        = number
  default     = 8
  description = "How long a sign-in to the tunnel lasts, in hours (1-12)."

  validation {
    condition     = var.session_hours >= 1 && var.session_hours <= 12
    error_message = "session_hours must be 1-12."
  }
}
