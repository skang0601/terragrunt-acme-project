// Include all the settings from the root .tfvars file
include {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_parent_terragrunt_dir()}/modules//ec2"
}


# If I had a real sops file I can pass in secrets like so
# This calls the terraform merge functio and gerenates an input like so
/*
inputs = {
  some = "secret"
  foo = "bar" # Notice this was overwritten due to the order
  user = "set"
}
*/
inputs = merge(
  {
    user = "set"
    foo = "foo"
  },
  yamldecode(run_cmd("--terragrunt-quiet", "sops", "-d", "${get_terragrunt_dir()}/secrets.enc.yaml"))
)