

provider "azurerm" { 
  features {}  
  subscription_id = "c9228dd2-1a35-4c93-a47c-60f9e28a7aec"  
}

resource "azurerm_resource_group" "fastapi_rg" {
  name     = "fastapi-rg"
  location = "East US"
}

resource "azurerm_container_registry" "acr" {
  name                = "fastapiacrdm"  
  resource_group_name = azurerm_resource_group.fastapi_rg.name
  location            = azurerm_resource_group.fastapi_rg.location
  sku                 = "Basic"
  admin_enabled       = true
}



resource "azurerm_kubernetes_cluster" "fastapi_aks" {
  name                = "fastapi-aks-cluster-dm"
  location            = azurerm_resource_group.fastapi_rg.location
  resource_group_name = azurerm_resource_group.fastapi_rg.name
  dns_prefix          = "fastapi"

  default_node_pool {
    name       = "default"
    node_count = 1  
    vm_size    = "Standard_D2s_v7"  
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id         = azurerm_kubernetes_cluster.fastapi_aks.kubelet_identity[0].object_id
  role_definition_name = "AcrPull"
  scope               = azurerm_container_registry.acr.id
}





