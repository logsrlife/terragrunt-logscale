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
  # Automatically load environment-level variables
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  # Extract out common variables for reuse
  env      = local.environment_vars.locals.environment
  name     = local.environment_vars.locals.name
  codename = local.environment_vars.locals.codename

  # Expose the base source URL so different versions of the module can be deployed in different environments. This will
  # be used to construct the terraform block in the child terragrunt configurations.
  module_vars   = read_terragrunt_config(find_in_parent_folders("modules.hcl"))
  source_module = local.module_vars.locals.k8s_helm

  # Automatically load account-level variables
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  # Automatically load region-level variables
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  # Automatically load region-level variables
  admin = read_terragrunt_config(find_in_parent_folders("admin.hcl"))

  # Extract the variables we need for easy access
  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.aws_account_id
  aws_region   = local.region_vars.locals.aws_region

  dns         = read_terragrunt_config(find_in_parent_folders("dns.hcl"))
  domain_name = local.dns.locals.domain_name

  humio                    = read_terragrunt_config(find_in_parent_folders("humio.hcl"))
  humio_rootUser           = local.humio.locals.humio_rootUser
  humio_license            = local.humio.locals.humio_license
  humio_sso_idpCertificate = local.humio.locals.humio_sso_idpCertificate
  humio_sso_signOnUrl      = local.humio.locals.humio_sso_signOnUrl
  humio_sso_entityID       = local.humio.locals.humio_sso_entityID
}


dependency "eks" {
  config_path = "${get_terragrunt_dir()}/../../../eks/"
}
dependency "acm_ui" {
  config_path = "${get_terragrunt_dir()}/../../../acm-ui/"
}
dependency "bucket" {
  config_path = "${get_terragrunt_dir()}/../bucket/"
}
dependencies {
  paths = [
    "${get_terragrunt_dir()}/../../../eks-addons/",
    "${get_terragrunt_dir()}/../../argocd/helm/",
    "${get_terragrunt_dir()}/../ns/",
    "${get_terragrunt_dir()}/../project/"
  ]
}
generate "provider" {
  path      = "provider_k8s.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF

provider "helm" {
  kubernetes {
    host                   = "${dependency.eks.outputs.eks_endpoint}"
    cluster_ca_certificate = base64decode("${dependency.eks.outputs.eks_cluster_certificate_authority_data}")

    exec {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.eks_cluster_name}"]
    }
  }
}
EOF
}
# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we have to pass in to use the module. This defines the parameters that are common across all
# environments.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  uniqueName = "${local.name}-${local.codename}"

  repository = "https://logscale-contrib.github.io/helm-logscale"

  release          = "ops"
  chart            = "logscale"
  chart_version    = "v6.0.0-next.14"
  namespace        = "${local.name}-${local.codename}"
  create_namespace = false
  project          = "${local.name}-${local.codename}"


  values = yamldecode(<<EOF
platform: aws
humio:
  # External URI
  fqdn: logscale-ops.${local.domain_name}
  fqdnInputs: "logscale-ops-inputs.${local.domain_name}"

  license: ${local.humio_license}
  
  # Signon
  rootUser: ${local.humio_rootUser}

  sso:
    idpCertificate: "${base64encode(local.humio_sso_idpCertificate)}"
    signOnUrl: "${local.humio_sso_signOnUrl}"
    entityID: "${local.humio_sso_entityID}"

  # Object Storage Settings
  s3mode: aws
  buckets:
    region: ${local.aws_region}
    storage: ${dependency.bucket.outputs.s3_bucket_id}

  #Kafka
  kafka:
    manager: strimzi
    prefixEnable: true
    strimziCluster: "ops-logscale"
    # externalKafkaHostname: "ops-logscale-kafka-bootstrap:9092"

  #Image is shared by all node pools
  image:
    # tag: 1.75.0--SNAPSHOT--build-353635--SHA-96e5fc2254e11bf9a10b24b749e4e5b197955607
    tag: 1.70.1

  # Primary Node pool used for digest/storage
  nodeCount: 3
  #In general for these node requests and limits should match
  resources:
    requests:
      memory: 2Gi
      cpu: 1
    limits:
      memory: 2Gi
      cpu: 1

  serviceAccount:
    name: "logscale-ops"
    annotations:
      "eks.amazonaws.com/role-arn": "${dependency.bucket.outputs.iam_role_arn}"
  tolerations:
    - key: "workloadClass"
      operator: "Equal"
      value: "nvme"
      effect: "NoSchedule"
    - key: "node.kubernetes.io/disk-pressure"
      operator: "Exists"
      tolerationSeconds: 300
      effect: "NoExecute"
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: "kubernetes.io/arch"
                operator: "In"
                values: ["amd64"]
              - key: "kubernetes.io/os"
                operator: "In"
                values: ["linux"]
              # - key: "kubernetes.azure.com/agentpool"
              #   operator: "In"
              #   values: ["nvme"]
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/instance
                operator: In
                values: ["ops-logscale"]
              - key: humio.com/node-pool
                operator: In
                values: ["ops-logscale"]
          topologyKey: "kubernetes.io/hostname"
  dataVolumePersistentVolumeClaimSpecTemplate:
    accessModes: ["ReadWriteOnce"]
    resources:
      requests:
        storage: "100Gi"
    storageClassName: "ebs-gp3-enc"

  ingress:
    ui:
      enabled: true
      tls: false
      annotations:
        "kubernetes.io/ingress.class" : "alb"
        "alb.ingress.kubernetes.io/certificate-arn": "${dependency.acm_ui.outputs.acm_certificate_arn}"
        "alb.ingress.kubernetes.io/listen-ports": '[{"HTTP": 80}, {"HTTPS": 443}]'
        "alb.ingress.kubernetes.io/ssl-redirect": "443"
        "alb.ingress.kubernetes.io/scheme": "internet-facing"
        "alb.ingress.kubernetes.io/target-type": "ip"
        "alb.ingress.kubernetes.io/group.name": "logscale-${local.env}"
        "external-dns.alpha.kubernetes.io/hostname": "logscale-ops.${local.domain_name}"

    inputs:
      enabled: true
      tls: false
      annotations:
          "kubernetes.io/ingress.class" : "alb"
          "alb.ingress.kubernetes.io/certificate-arn" : "${dependency.acm_ui.outputs.acm_certificate_arn}"
          "alb.ingress.kubernetes.io/listen-ports"    : "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
          "alb.ingress.kubernetes.io/ssl-redirect"    : "443"
          "alb.ingress.kubernetes.io/scheme"          : "internet-facing"
          "alb.ingress.kubernetes.io/target-type"     : "ip"
          "alb.ingress.kubernetes.io/group.name"      : "logscale-${local.env}"
          "external-dns.alpha.kubernetes.io/hostname" : "logscale-ops-inputs.${local.domain_name}"
  nodepools:
    ingest:
      nodeCount: 2
      resources:
        limits:
          cpu: "1"
          memory: 2Gi
        requests:
          cpu: "1"
          memory: 2Gi
      tolerations:
        - key: "workloadClass"
          operator: "Equal"
          value: "nvme"
          effect: "NoSchedule"
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: "kubernetes.io/arch"
                    operator: "In"
                    values: ["amd64"]
                  - key: "kubernetes.io/os"
                    operator: "In"
                    values: ["linux"]
                  # - key: "kubernetes.azure.com/agentpool"
                  #   operator: "In"
                  #   values: ["compute"]
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  - key: app.kubernetes.io/instance
                    operator: In
                    values: ["ops-logscale"]
                  - key: humio.com/node-pool
                    operator: In
                    values: ["ops-logscale-ingest-only"]
              topologyKey: "kubernetes.io/hostname"

    ui:
      nodeCount: 2
      resources:
        limits:
          cpu: "1"
          memory: 2Gi
        requests:
          cpu: "1"
          memory: 2Gi
      tolerations:
        - key: "workloadClass"
          operator: "Equal"
          value: "nvme"
          effect: "NoSchedule"
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: "kubernetes.io/arch"
                    operator: "In"
                    values: ["amd64"]
                  - key: "kubernetes.io/os"
                    operator: "In"
                    values: ["linux"]
                  # - key: "kubernetes.azure.com/agentpool"
                  #   operator: "In"
                  #   values: ["compute"]
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  - key: app.kubernetes.io/instance
                    operator: In
                    values: ["ops-logscale"]
                  - key: humio.com/node-pool
                    operator: In
                    values: ["ops-logscale-http-only"]
              topologyKey: "kubernetes.io/hostname"
otel:  
  components:
    app: true
    cluster: true
    nodes: true
    serviceaccount: true
EOF
  )

}
