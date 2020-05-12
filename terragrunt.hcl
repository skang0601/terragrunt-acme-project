remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
  config = {
    bucket         = "acme-bucket"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    // we cant put this in a local block because the get_parent_terragrunt_dir doesnt get resolved correctly. not sure why.
    role_arn       = "my-role-arn"
    dynamodb_table = "acme-lockin-table"
    s3_bucket_tags = {
      team                  = "acme"
      sub-environment       = "terraform-state-bucket"
      managed-by            = "https://github.com/skang0601/terragrunt-acme-project"
    }
  }
}

// If we are in an environment folder, then we force a dep on the environment's deployment-role - this ensures it gets destroyed last.
// On initial bootstrap, it needs to get created last. We enforce this in the bootstrap.sh.
// We assume if the environment is not bld/stg/prd... that it is a non-prod env - e.g. it *must* live in the stg account
dependencies {
  paths = fileexists(find_in_parent_folders("environment.yaml", "ignore")) ? (
      contains(
        ["bld", "stg", "prd"],
        yamldecode(
          file(find_in_parent_folders("environment.yaml"))
        ).environment
      )
      ? ["${dirname(find_in_parent_folders("environment.yaml"))}/account-bootstrap/deployment-role"]
      : ["${dirname(find_in_parent_folders("account.yaml"))}/environments/stg/account-bootstrap/deployment-role"]
  ) : []
}

// the function calls cant be refactored into the locals block because of when the locals get resolved vs when the inputs block get resolved.
// We merge in the follow order with the later items taking precedence:
// parent defaults.yaml
// parents secrets.yaml
// account.yaml
// environment.yaml
// the last secrets.yaml found in the tree
// the last overrides.yaml specified in the tree
// module secrets.yaml
// module inputs defined in its terragrunt.hcl
// some constants we provide here
// bootstrap.yaml
inputs = merge(
  yamldecode(
    fileexists("${get_parent_terragrunt_dir()}/defaults.yaml") ? file("${get_parent_terragrunt_dir()}/defaults.yaml") : "{}"
  ),
  yamldecode(
    fileexists("${get_parent_terragrunt_dir()}/secrets.yaml") ? file("${get_parent_terragrunt_dir()}/secrets.yaml") : "{}"
  ),
  yamldecode(
    fileexists(find_in_parent_folders("account.yaml", "ignore"))
      ? file(find_in_parent_folders("account.yaml"))
      : "{}"
  ),
  yamldecode(
    fileexists(find_in_parent_folders("environment.yaml", "ignore"))
      ? file(find_in_parent_folders("environment.yaml"))
      : "{}"
  ),
  yamldecode(
    fileexists(find_in_parent_folders("secrets.yaml", "ignore"))
      ? file(find_in_parent_folders("secrets.yaml"))
      : "{}"
  ),
  yamldecode(
    fileexists(find_in_parent_folders("overrides.yaml", "ignore"))
      ? file(find_in_parent_folders("overrides.yaml"))
      : "{}"
  ),
  yamldecode(
    fileexists("${get_terragrunt_dir()}/secrets.yaml") ? file("${get_terragrunt_dir()}/secrets.yaml") : "{}"
  ),
  // we manage the bootstrap file and it gets deleted after initial run
  // we used to use a local_file, but we cant not preserve it on destroy
  // that would risk deleting user provided overrides + poses other destroy challenges
  // instead we delete this file after first run
  // see: https://github.com/terraform-providers/terraform-provider-local/pull/10
  yamldecode(
    fileexists(find_in_parent_folders("bootstrap.yaml", "ignore"))
      ? file(find_in_parent_folders("bootstrap.yaml"))
      : "{}"
  ),
  {
    parent_terragrunt_dir = get_parent_terragrunt_dir(),
    terragrunt_dir        = get_terragrunt_dir(),
  }
)

terraform {
  // Force Terraform to not ask for input value if some variables are undefined.
  extra_arguments "disable_input" {
    commands  = get_terraform_commands_that_need_input()
    arguments = ["-input=false"]
  }

  // Force Terraform to keep trying to acquire a lock for up to 10 minutes if someone else already has the lock
  extra_arguments "retry_lock" {
    commands  = get_terraform_commands_that_need_locking()
    arguments = ["-lock-timeout=10m"]
  }

  # Force Terraform to run with reduced parallelism
  # this is probably overly aggressive... default is 10.
  # since terragrunt already parallelizes across modules, we can hit AWS API rate limits
  # open PR to support configuring terragrunts parallelism https://github.com/gruntwork-io/terragrunt/pull/636
  extra_arguments "parallelism" {
    commands  = get_terraform_commands_that_need_parallelism()
    arguments = ["-parallelism=10"]
  }
}

generate "provider" {
  path = "provider.tf"
  if_exists = "skip"
  contents = <<EOF
  provider "aws" {
    region = var.region
    assume_role {
      role_arn = var.deployment_role_arn
    }
  }

  variable "region" {
    type        = string
    description = "region to use for aws resources"
  }

  variable "deployment_role_arn" {
    type = string
  }

EOF
}
