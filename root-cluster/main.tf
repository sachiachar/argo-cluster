terraform {
  required_version = ">= 1.3"

  # backend "s3" {
  #   bucket = "argo-cluster"
  #   key    = "bootstrap.tfstate"
  #   region = "us-east-1"                  # e.g. us-east-1
  #   endpoint = "https://in-maa-1.linodeobjects.com"    # e.g. us-est-1.linodeobjects.com
  #   skip_credentials_validation = true                # just do it
  # }

  required_providers {
    linode = {
      source = "linode/linode"
      version = "~> 1.29.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.16.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.7.0"
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14.0"
    }
  }
}


//Use the Linode Provider
provider "linode" {
  token = var.token
}

data "linode_object_storage_cluster" "metrics" {
  id = var.metric_store_region
}

resource "linode_object_storage_bucket" "metrics" {
  cluster = data.linode_object_storage_cluster.metrics.id
  label = var.metric_store_bucket
}

resource "linode_object_storage_key" "metrics" {
    label = "metrics-access"
    bucket_access {
      cluster = linode_object_storage_bucket.metrics.cluster
      bucket_name = linode_object_storage_bucket.metrics.label
      permissions = "read_write"
    }
}


//Use the linode_lke_cluster resource to create
//a Kubernetes cluster
resource "linode_lke_cluster" "k8s_cluster" {

    k8s_version = var.k8s_version
    label = var.cluster.label
    region = var.cluster.region
    tags = var.tags
    
    control_plane {
      high_availability = true
    }

    dynamic "pool" {
        for_each = var.cluster.pools
        content {
            type  = pool.value["type"]
            count = pool.value["count"]
            autoscaler {
                min = pool.value.autoscaler.min
                max = pool.value.autoscaler.max
            }
        }
    }
    lifecycle {
        #HACK: suports up to 4 pools, avoids forceful resizing on each execution
        ignore_changes = [pool[0].count, pool[1].count, pool[2].count, pool[3].count]
    }
}


locals {
    root_cluster_kubeconfig = yamldecode(base64decode(linode_lke_cluster.k8s_cluster.kubeconfig))
}

provider "kubernetes" {
  host = local.root_cluster_kubeconfig["clusters"][0]["cluster"]["server"]

  cluster_ca_certificate = base64decode(local.root_cluster_kubeconfig["clusters"][0]["cluster"]["certificate-authority-data"])
  token = local.root_cluster_kubeconfig["users"][0]["user"]["token"]
}

provider "helm" {
  kubernetes {
    host = local.root_cluster_kubeconfig["clusters"][0]["cluster"]["server"]

    cluster_ca_certificate = base64decode(local.root_cluster_kubeconfig["clusters"][0]["cluster"]["certificate-authority-data"])
    token = local.root_cluster_kubeconfig["users"][0]["user"]["token"]
  }
}

provider "kubectl" {
  host                   = local.root_cluster_kubeconfig["clusters"][0]["cluster"]["server"]
  cluster_ca_certificate = base64decode(local.root_cluster_kubeconfig["clusters"][0]["cluster"]["certificate-authority-data"])
  token                  = local.root_cluster_kubeconfig["users"][0]["user"]["token"]
  load_config_file       = false
}


resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"
  create_namespace = true

  set {
    name = "controller.metrics.enabled"
    value = true
  }

  set {
    name = "controller.metrics.serviceMonitor.enabled"
    value = true
  }

  set {
    name = "server.metrics.enabled"
    value = true
  }

  set {
    name = "server.metrics.serviceMonitor.enabled"
    value = true
  }

  set {
    name = "repoServer.metrics.enabled"
    value = true
  }

  set {
    name = "repoServer.metrics.serviceMonitor.enabled"
    value = true
  }

  set {
    name = "applicationSet.metrics.enabled"
    value = true
  }

  set {
    name = "applicationSet.metrics.serviceMonitor.enabled"
    value = true
  }

  set_sensitive{
    name = "configs.secret.argocdServerAdminPassword"
    value = bcrypt(var.argo_admin_password)
  }

  set {
    name  = "server.service.type"
    value = "LoadBalancer"  # Customize as needed
  }

  set {
    name  = "server.ingress.enabled"
    value = "true"  # Customize as needed
  }

  set {
    name  = "server.ingress.host"
    value = "continuous-deploy.platform.sasriya.net"  
  }

  set {
    name  = "server.ingress.tls[0].secretName"
    value = "argocd-secret"  
  }

  set {
    name  = "server.ingress.tls[0].hosts[0]"
    value = "continuous-deploy.platform.sasriya.net"  
  }

  set {
    name  = "server.ingress.annotations.cert-manager.io/cluster-issuer"
    value = "letsencrypt-prod"
  }
}

resource "kubernetes_secret" "platform_github_secret" {
    depends_on = [helm_release.argocd]
    metadata {
        name = "github-repo"
        namespace = "argocd"
        labels = {
            "argocd.argoproj.io/secret-type" = "repository"
        }
    }
    data = {
        project = "default"
        type = "git"
        url = var.bootstrap_repo_url
        sshPrivateKey = var.bootstrap_repo_private_key
    }
}

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "kubernetes_secret_v1" "metrics_bucket" {
#    depends_on = [kubernetes_namespace_v1.external-dns]
    metadata {
        name = "metrics-bucket"
        namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    }
    data = {
#      "objstore.yaml" = yamlencode({
      "objstore.yml" = yamlencode({
        type = "s3"
        config = {
          bucket = linode_object_storage_bucket.metrics.label
          endpoint = data.linode_object_storage_cluster.metrics.domain
          access_key = linode_object_storage_key.metrics.access_key
          secret_key = linode_object_storage_key.metrics.secret_key
          insecure = false
          signature_version2 = false
        }
      })
    }
}

# resource "kubectl_manifest" "platform-application" {
#     depends_on = [helm_release.argocd]
#     yaml_body = <<-YAML
#         apiVersion: argoproj.io/v1alpha1
#         kind: Application
#         metadata:
#           name: platform-application
#           namespace: argocd
#         spec:
#           project: default
#           source:
#             repoURL: ${var.bootstrap_repo_url}
#             targetRevision: HEAD
#             path: ${var.bootstrap_app_path}
#           destination:
#             server: https://kubernetes.default.svc
#             namespace: default
#           syncPolicy:
#             automated: {} 
#     YAML
# }

//Export this cluster's attributes
output "kubeconfig" {
    value = linode_lke_cluster.k8s_cluster.kubeconfig
    sensitive = true
}

output "api_endpoints" {
    value = linode_lke_cluster.k8s_cluster.api_endpoints
}

output "status" {
    value = linode_lke_cluster.k8s_cluster.status
}

output "id" {
    value = linode_lke_cluster.k8s_cluster.id
}

output "pool" {
    value = linode_lke_cluster.k8s_cluster.pool
}

output "metrics_bucket_endpoint" {
  value = data.linode_object_storage_cluster.metrics.domain
}

output "metrics_bucket_label" {
  value = linode_object_storage_bucket.metrics.label
}

output "metrics_bucket_access_key" {
  value = linode_object_storage_bucket.metrics.access_key

}

output "metrics_bucket_secret_key" {
  value = linode_object_storage_bucket.metrics.secret_key
  sensitive = true
}