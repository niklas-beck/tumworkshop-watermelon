##################################################################################
# GET RESOURCE GROUP
##################################################################################

data "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
}


##################################################################################
# Function App
##################################################################################
resource "azurerm_application_insights" "logging" {
  name                = "${var.basename}-ai"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  application_type    = "web"

  tags = {
    "CostCenter" = "SpikeReply"
  }
}

resource "azurerm_storage_account" "fxnstor" {
  name                     = "${var.basename}fx"
  resource_group_name      = data.azurerm_resource_group.rg.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  tags = {
    "CostCenter" = "SpikeReply"
  }
}

resource "azurerm_service_plan" "fxnapp" {
  name                = "${var.basename}-plan"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "Y1"

  tags = {
    "CostCenter" = "SpikeReply"
  }
}

resource "azurerm_linux_function_app" "fxn" {
  name                      = "funcApp-${var.basename}"
  location                  = var.location
  resource_group_name       = data.azurerm_resource_group.rg.name
  service_plan_id           = azurerm_service_plan.fxnapp.id
  storage_account_name       = azurerm_storage_account.fxnstor.name
  storage_account_access_key = azurerm_storage_account.fxnstor.primary_access_key

  site_config {
    application_insights_key               = azurerm_application_insights.logging.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.logging.connection_string
    application_stack {
      python_version = "3.9"
    }
  }

  app_settings = {
    APPINSIGHTS_INSTRUMENTATIONKEY = azurerm_application_insights.logging.instrumentation_key
    SCM_DO_BUILD_DURING_DEPLOYMENT = true
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    "CostCenter" = "SpikeReply"
  }
}


##################################################################################
# Publishing python script as function app
##################################################################################

resource "local_file" "app_deployment_script" {
  content  = <<CONTENT
#!/bin/bash

npm i -g azure-functions-core-tools@4 --unsafe-perm true

az functionapp config appsettings set -n ${azurerm_linux_function_app.fxn.name} -g ${data.azurerm_resource_group.rg.name} --settings "APPINSIGHTS_INSTRUMENTATIONKEY=""${azurerm_application_insights.logging.instrumentation_key}""" > /dev/null
cd ../src ; func azure functionapp publish ${azurerm_linux_function_app.fxn.name} --python --linux-fx-version "PYTHON|3.9"
CONTENT
  filename = "./deploy_function_app.sh"
}