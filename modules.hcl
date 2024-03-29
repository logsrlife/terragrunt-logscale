#This file contains all external modules and versions

locals {

  aws_k8s_helm_w_iam = {
    base_url = "git::git@github.com:logscale-contrib/tf-self-managed-logscale-aws-k8s-helm-with-iam.git"
    version  = "?ref=v2.1.9"
  }

  k8s_ns = {
    base_url = "git::git@github.com:logscale-contrib/terraform-k8s-namespace.git"
    version  = "?ref=v1.0.0"
  }

  k8s_helm = {
    base_url = "git::git@github.com:logscale-contrib/tf-self-managed-logscale-k8s-helm.git"
    version  = "?ref=v1.4.0"
  }
  helm_release = {
    base_url = "tfr:///terraform-module/release/helm"
    version  = "?version=2.8.0"
  }
  argocd_project = {
    #base_url = "tfr:///project-octal/k8s-argocd-project/kubernetes"
    #version  = "?version=2.0.0"
    base_url = "git::git@github.com:logscale-contrib/terraform-kubernetes-argocd-project.git"
    version  = ""

  }

  aws_k8s_logscale_bucket_with_iam = {
    base_url = "git::git@github.com:logscale-contrib/terraform-aws-logscale-bucket-with-iam.git"
    version  = "?ref=v1.4.1"
  }

  azure_rg = {
    base_url = "git::git@github.com:logscale-contrib/teraform-self-managed-logscale-azure-resource-group.git"
    version  = "?ref=v1.0.4"
  }  
}