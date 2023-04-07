# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION
# This is the common component configuration for mysql. The common variables for each environment to
# deploy mysql are defined here. This configuration will be merged into the environment configuration
# via an include block.
# ---------------------------------------------------------------------------------------------------------------------

# Terragrunt will copy the Terraform configurations specified by the source parameter, along with any files in the
# working directory, into a temporary folder, and execute your Terraform commands in that folder. If any environment
# needs to deploy a different module version, it should redefine this block with a different ref to override the
# deployed version.
terraform {
  source = "${local.source_module.base_url}${local.source_module.version}"
}

# ---------------------------------------------------------------------------------------------------------------------
# Locals are named constants that are reusable within the configuration.
# ---------------------------------------------------------------------------------------------------------------------
locals {
  source_module = {
    base_url = "git::git@github.com:logscale-contrib/tf-self-managed-logscale-aws-k8s-cluster.git"
    version  = "?ref=v3.6.0"
  }
  # Automatically load account-level variables
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  # Automatically load region-level variables
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  # Automatically load environment-level variables
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  # Extract out common variables for reuse
  env      = local.environment_vars.locals.environment
  name     = local.environment_vars.locals.name
  codename = local.environment_vars.locals.codename
  # Extract the variables we need for easy access
  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.aws_account_id
  aws_region   = local.region_vars.locals.aws_region

  # Automatically load region-level variables
  admin = read_terragrunt_config(find_in_parent_folders("admin.hcl"))

  aws_admin_arn = local.admin.locals.aws_admin_arn


}

dependency "vpc" {
  config_path = "${get_terragrunt_dir()}/../vpc/"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we have to pass in to use the module. This defines the parameters that are common across all
# environments.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  uniqueName          = "${local.name}-${local.env}-${local.codename}"
  aws_admin_arn       = local.aws_admin_arn
  vpc_id              = dependency.vpc.outputs.vpc_id
  vpc_public_subnets  = dependency.vpc.outputs.public_subnets
  vpc_private_subnets = dependency.vpc.outputs.private_subnets
  region              = local.aws_region

  # cluster_ip_family = "ipv6"
  # create_cni_ipv6_iam_policy = true
}