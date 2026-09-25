terraform {
  backend "s3" {
    # Created by bootstrap/ (scripts/bootstrap.sh). Backend blocks cannot use
    # variables, so scripts/init-identity.sh writes the bucket and region.
    bucket = "CHANGE_ME-management-tfstate"

    # The pipeline's role may read and write only keys under identity/.
    key = "identity/terraform.tfstate"

    region       = "CHANGE_ME"
    encrypt      = true
    use_lockfile = true
  }
}
