#-------------------------------
# Local Declarations
#-------------------------------
locals {
  resource_group_name = element(coalescelist(data.azurerm_resource_group.rgrp.*.name, azurerm_resource_group.rg.*.name, [""]), 0)
  location            = element(coalescelist(data.azurerm_resource_group.rgrp.*.location, azurerm_resource_group.rg.*.location, [""]), 0)

  default_site_config = {
    default_documents = [
      "Default.htm",
      "Default.html",
      "Default.asp",
      "index.htm",
      "index.html",
      "iisstart.htm",
      "default.aspx",
      "hostingstart.html",
    ]
  }

  app_insights = try(data.azurerm_application_insights.main.0, {})

  default_app_settings = var.application_insights_enabled ? {
    APPINSIGHTS_INSTRUMENTATIONKEY             = try(local.app_insights.instrumentation_key, "")
    APPINSIGHTS_PROFILERFEATURE_VERSION        = "1.0.0"
    APPINSIGHTS_SNAPSHOTFEATURE_VERSION        = "1.0.0"
    APPLICATIONINSIGHTS_CONNECTION_STRING      = try(local.app_insights.connection_string, "")
    ApplicationInsightsAgent_EXTENSION_VERSION = "~2"
  } : {}
}

data "azurerm_client_config" "current" {}

#---------------------------------------------------------
# Resource Group Creation or selection - Default is "true"
#---------------------------------------------------------
data "azurerm_resource_group" "rgrp" {
  count = var.create_resource_group == false ? 1 : 0
  name  = var.resource_group_name
}

resource "azurerm_resource_group" "rg" {
  #ts:skip=AC_AZURE_0389 RSG lock should be skipped for now.
  count    = var.create_resource_group ? 1 : 0
  name     = lower(var.resource_group_name)
  location = var.location
  tags     = merge({ "ResourceName" = format("%s", var.resource_group_name) }, var.tags, )
}

#---------------------------------------------------------
# Application ClientID/Secret Creation or selection
#---------------------------------------------------------

resource "time_rotating" "main" {
  count = var.auth_settings_enabled ? 1 : 0

  rotation_years = var.years

  triggers = {
    years = var.years
  }
}

#---------------------------------------------------------
# App Service Creation or selection
#---------------------------------------------------------

#tfsec:ignore:azure-appservice-authentication-enabled
#tfsec:ignore:azure-appservice-require-client-cert
resource "azurerm_app_service" "main" {
  name                = lower(var.name)
  location            = local.location
  resource_group_name = local.resource_group_name
  app_service_plan_id = var.app_service_plan_id
  dynamic "site_config" {
    for_each = [merge(local.default_site_config, var.site_config)]

    content {
      always_on                 = lookup(site_config.value, "always_on", null)
      app_command_line          = lookup(site_config.value, "app_command_line", null)
      default_documents         = lookup(site_config.value, "default_documents", null)
      dotnet_framework_version  = lookup(site_config.value, "dotnet_framework_version", null)
      ftps_state                = lookup(site_config.value, "ftps_state", null)
      health_check_path         = lookup(site_config.value, "health_check_path", null)
      number_of_workers         = lookup(site_config.value, "number_of_workers", null)
      http2_enabled             = lookup(site_config.value, "http2_enabled", null)
      linux_fx_version          = lookup(site_config.value, "linux_fx_version", null)
      windows_fx_version        = lookup(site_config.value, "windows_fx_version", null)
      managed_pipeline_mode     = lookup(site_config.value, "managed_pipeline_mode", null)
      min_tls_version           = lookup(site_config.value, "min_tls_version", null)
      python_version            = lookup(site_config.value, "python_version", null)
      remote_debugging_enabled  = lookup(site_config.value, "remote_debugging_enabled", null)
      remote_debugging_version  = lookup(site_config.value, "remote_debugging_version", null)
      scm_type                  = lookup(site_config.value, "scm_type", null)
      use_32_bit_worker_process = lookup(site_config.value, "use_32_bit_worker_process", null)
      websockets_enabled        = lookup(site_config.value, "websockets_enabled", null)
    }
  }

  dynamic "auth_settings" {
    for_each = var.auth_settings_enabled ? ["auth_settings_enabled"] : []
    content {
      enabled                        = var.auth_settings_enabled
      issuer                         = format("https://sts.windows.net/%s/v2.0", data.azurerm_client_config.current.tenant_id)
      token_store_enabled            = false
      unauthenticated_client_action  = "RedirectToLoginPage"
      default_provider               = "AzureActiveDirectory"
      allowed_external_redirect_urls = []

      active_directory {
        client_id         = var.ad_client_id
        allowed_audiences = var.ad_allowed_audiences == "" ? null : [format("api://%s", var.ad_allowed_audiences)]
      }
    }
  }

  https_only = var.https_only

  identity {
    type = "SystemAssigned"
  }

  tags = merge({ "ResourceName" = lower(var.name) }, var.tags, )

  lifecycle {
    ignore_changes = [
      tags, identity.0.identity_ids, app_settings
    ]
  }
}

resource "azurerm_app_service_slot" "staging" {
  name                = var.slot_name
  app_service_name    = azurerm_app_service.main.name
  location            = local.location
  resource_group_name = local.resource_group_name
  app_service_plan_id = var.app_service_plan_id
  app_settings        = merge(local.default_app_settings, var.app_settings)

  dynamic "site_config" {
    for_each = [merge(local.default_site_config, var.site_config)]

    content {
      always_on                 = lookup(site_config.value, "always_on", null)
      app_command_line          = lookup(site_config.value, "app_command_line", null)
      default_documents         = lookup(site_config.value, "default_documents", null)
      dotnet_framework_version  = lookup(site_config.value, "dotnet_framework_version", null)
      ftps_state                = lookup(site_config.value, "ftps_state", null)
      health_check_path         = lookup(site_config.value, "health_check_path", null)
      number_of_workers         = lookup(site_config.value, "number_of_workers", null)
      http2_enabled             = lookup(site_config.value, "http2_enabled", null)
      linux_fx_version          = lookup(site_config.value, "linux_fx_version", null)
      windows_fx_version        = lookup(site_config.value, "windows_fx_version", null)
      managed_pipeline_mode     = lookup(site_config.value, "managed_pipeline_mode", null)
      min_tls_version           = lookup(site_config.value, "min_tls_version", null)
      python_version            = lookup(site_config.value, "python_version", null)
      remote_debugging_enabled  = lookup(site_config.value, "remote_debugging_enabled", null)
      remote_debugging_version  = lookup(site_config.value, "remote_debugging_version", null)
      scm_type                  = lookup(site_config.value, "scm_type", null)
      use_32_bit_worker_process = lookup(site_config.value, "use_32_bit_worker_process", null)
      websockets_enabled        = lookup(site_config.value, "websockets_enabled", null)
    }
  }

  dynamic "auth_settings" {
    for_each = var.auth_settings_enabled ? ["auth_settings_enabled"] : []
    content {
      enabled                        = var.auth_settings_enabled
      issuer                         = format("https://sts.windows.net/%s/v2.0", data.azurerm_client_config.current.tenant_id)
      token_store_enabled            = false
      unauthenticated_client_action  = "RedirectToLoginPage"
      default_provider               = "AzureActiveDirectory"
      allowed_external_redirect_urls = []

      active_directory {
        client_id         = var.ad_client_id
        allowed_audiences = var.ad_allowed_audiences == "" ? null : [format("api://%s", var.ad_allowed_audiences)]
      }
    }
  }

  https_only = var.https_only

  identity {
    type = "SystemAssigned"
  }

  tags = {}

  lifecycle {
    ignore_changes = [
      tags, identity.0.identity_ids, app_settings
    ]
  }
}

resource "azurerm_app_service_virtual_network_swift_connection" "main" {
  count          = var.vnet_integration ? 1 : 0
  app_service_id = azurerm_app_service.main.id
  subnet_id      = var.vnet_subnet_id
  lifecycle {
    ignore_changes = [
      subnet_id
    ]
  }
}

resource "azurerm_app_service_slot_virtual_network_swift_connection" "slot" {
  count          = var.slot_vnet_integration ? 1 : 0
  slot_name      = azurerm_app_service_slot.staging.name
  app_service_id = azurerm_app_service.main.id
  subnet_id      = var.vnet_subnet_id
  lifecycle {
    ignore_changes = [
      subnet_id
    ]
  }
}

resource "azurerm_private_endpoint" "main" {
  count               = var.private_endpoint ? 1 : 0
  name                = format("%s-PE", lower(var.name))
  location            = local.location
  resource_group_name = local.resource_group_name
  subnet_id           = var.vnet_pesubnet_id

  private_service_connection {
    name                           = "privateendpointconnection"
    private_connection_resource_id = azurerm_app_service.main.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  tags = {}

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

#---------------------------------------------------------
# Application Insights Creation or selection
#---------------------------------------------------------

data "azurerm_application_insights" "main" {
  count = var.application_insights_enabled && var.application_insights_name != null ? 1 : 0

  name                = var.application_insights_name
  resource_group_name = var.application_insights_rsg
}

provider "azurerm" {
  features {
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    key_vault {
      purge_soft_delete_on_destroy               = true
      purge_soft_deleted_secrets_on_destroy      = true
      purge_soft_deleted_certificates_on_destroy = true
    }
  }
  skip_provider_registration = true
}
