// Include all the settings from the root .tfvars file
include {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_parent_terragrunt_dir()}/modules//ec2"
}
# This is an example of using the dependency featurse.
# No more setting remote_data_sources, let terragrunt parse out the output from one statefile and pass them as inputs
# to another.
dependency "ec2" {
  config_path = "../ec2"

  # We set mock outputs in the case where the dependency state is not yet initialized/provisioned.
  # This is to not break certain commands.
  mock_outputs = {
    foo = ""
  }
  mock_outputs_allowed_terraform_commands = ["validate", "destroy", "import"]
}

inputs = {
  foo = dependency.ec2.outputs.foo
}