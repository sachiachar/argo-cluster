variable "token" {
    description = "Your Linode API Personal Access Token. (required)"
    default = "a0d125351b85f2450a4f17f14b5df54250fde0b34d1f8727b3610cb3b1fd4927"
}

variable "argo_admin_password" {
    description = "Argo CD admin password. (required)"
}

variable "k8s_version" {
    description = "The Kubernetes version to use for this cluster. (required)"
    default = "1.28"
}

variable "tags" {
    description = "Tags to apply to your cluster for organizational purposes. (optional)"
    type = list(string)
    default = ["control"]
}

variable "metric_store_region" {
    description = "Region to create object storage for metrics"
    type = string
    default = "in-maa-1"
}

variable "metric_store_bucket" {
    description = "Name of bucket to store metrics"
    type = string
    default = "platform-metrics"
}

variable "cluster" {
    description = "The cluster to create"
    type = object({
        label = string
        region = string
        pools = optional(list(object({
            
            type = optional(string, "g6-dedicated-4")
            count = optional(number, 3)
            
            autoscaler = optional(object ({
                min = number
                max = number
            }), {
                    min=3
                    max=3
                }
            )

        })), [{}])
    })
    default = {
        region = "in-maa"
        label = "sasriya.net"
    }
}


variable "bootstrap_repo_url" {
    description = "The URL of the bootstrap repository. (required)"
    default = "git@github.com:akamai-consulting/tiktok-obs-platform.git"
}

variable "bootstrap_repo_private_key" {
    description = "The URL of the bootstrap repository. (required)"
}

variable "bootstrap_app_path" {
    description = "The URL of the bootstrap repository. (required)"
    default = "bootstrap"
}

# variable "akamai_client_secret" {
#     description = "Akamai API Client Secret. (required)"
# }
# variable "akamai_host" {
#     description = "Akamai API Host. (required)"
# }
# variable "akamai_access_token" {
#     description = "Akamai API Access Token. (required)"
# }
# variable "akamai_client_token" {
#     description = "Akamai API Client Token. (required)"
# }