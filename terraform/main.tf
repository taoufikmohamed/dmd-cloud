
terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  
  # Uncomment for remote state storage
  # backend "azurerm" {
  #   resource_group_name  = "terraform-state-rg"
  #   storage_account_name = "dmdstorage"
  #   container_name       = "tfstate"
  #   key                  = "prod.terraform.tfstate"
  # }
}

provider "azurerm" {
  features {}
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "west europe"
}

variable "node_count" {
  description = "Number of AKS nodes"
  type        = number
  default     = 3  # Production-grade
}

resource "azurerm_resource_group" "rg" {
  name     = "dmd-${var.environment}-rg"
  location = var.location
  
  tags = {
    Environment = var.environment
    Project     = "DMD-Cloud"
    ManagedBy   = "Terraform"
  }
}

# Azure Container Registry for Docker images
resource "azurerm_container_registry" "acr" {
  name                = "dmdacr${var.environment}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  admin_enabled       = true
  
  tags = azurerm_resource_group.rg.tags
}

# Log Analytics for monitoring
resource "azurerm_log_analytics_workspace" "logs" {
  name                = "dmd-${var.environment}-logs"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  
  tags = azurerm_resource_group.rg.tags
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "dmd-aks-${var.environment}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "dmd-${var.environment}"
  kubernetes_version  = "1.28"  # Update to latest stable version

  default_node_pool {
    name            = "default"
    vm_size         = "Standard_D2s_v3"  # Production size
    min_count       = 2
    max_count       = 5
    os_disk_size_gb = 100
    
    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }
  
  # Integrate with Azure Monitor
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id
  }
  
  # Enable Azure AD integration
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
  }
  
  network_profile {
    network_plugin     = "azure"
    network_policy     = "azure"
    load_balancer_sku  = "standard"
    service_cidr       = "10.0.0.0/16"
    dns_service_ip     = "10.0.0.10"
  }

  tags = azurerm_resource_group.rg.tags
}

# Grant AKS access to ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

# Key Vault for secrets
resource "azurerm_key_vault" "kv" {
  name                = "dmd-kv-${var.environment}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  
  purge_protection_enabled   = true
  soft_delete_retention_days = 7
  
  tags = azurerm_resource_group.rg.tags
}

data "azurerm_client_config" "current" {}

# Outputs
output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "acr_admin_username" {
  value     = azurerm_container_registry.acr.admin_username
  sensitive = true
}

output "acr_admin_password" {
  value     = azurerm_container_registry.acr.admin_password
  sensitive = true
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}

output "get_credentials_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name}"
}
