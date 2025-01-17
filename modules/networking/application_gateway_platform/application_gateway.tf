resource "azurecaf_name" "agw" {
  name          = var.settings.name
  resource_type = "azurerm_application_gateway"
  prefixes      = var.global_settings.prefixes
  suffixes      = var.global_settings.suffixes  
  random_length = var.global_settings.random_length
  clean_input   = true
  passthrough   = var.global_settings.passthrough
  use_slug      = var.global_settings.use_slug
}

resource "azurerm_application_gateway" "agw" {
  name                = azurecaf_name.agw.result
  resource_group_name = var.resource_group_name
  location            = var.location

  zones              = try(var.settings.zones, null)
  enable_http2       = try(var.settings.enable_http2, true)
  tags               = try(local.tags, null)
  firewall_policy_id = try(try(var.application_gateway_waf_policies[try(var.settings.waf_policy.lz_key, var.client_config.landingzone_key)][var.settings.waf_policy.key].id, var.settings.firewall_policy_id), null)

  sku {
    name     = var.sku_name
    tier     = var.sku_tier
    capacity = try(var.settings.capacity.autoscale, null) == null ? var.settings.capacity.scale_unit : null
  }

  gateway_ip_configuration {
    name      = azurecaf_name.agw.result
    subnet_id = local.ip_configuration["gateway"].subnet_id
  }

  dynamic "ssl_policy" {
    for_each = try(var.settings.ssl_policy, null) == null ? [] : [1]
    content {
      disabled_protocols   = try(var.settings.ssl_policy.disabled_protocols, null)
      policy_type          = try(var.settings.ssl_policy.policy_type, null)
      policy_name          = try(var.settings.ssl_policy.policy_name, null)
      cipher_suites        = try(var.settings.ssl_policy.cipher_suites, null)
      min_protocol_version = try(var.settings.ssl_policy.min_protocol_version, null)
    }
  }

  dynamic "autoscale_configuration" {
    for_each = try(var.settings.capacity.autoscale, null) == null ? [] : [1]

    content {
      min_capacity = var.settings.capacity.autoscale.minimum_scale_unit
      max_capacity = var.settings.capacity.autoscale.maximum_scale_unit
    }
  }

  dynamic "frontend_ip_configuration" {
    for_each = var.settings.front_end_ip_configurations

    content {
      name                          = frontend_ip_configuration.value.name
      public_ip_address_id          = try(local.ip_configuration[frontend_ip_configuration.key].ip_address_id, null)
      private_ip_address            = try(frontend_ip_configuration.value.public_ip_key, null) == null ? local.private_ip_address : null
      private_ip_address_allocation = try(frontend_ip_configuration.value.private_ip_address_allocation, null)
      subnet_id                     = local.ip_configuration[frontend_ip_configuration.key].subnet_id
    }
  }

  dynamic "frontend_port" {
    for_each = var.settings.front_end_ports

    content {
      name = frontend_port.value.name
      port = frontend_port.value.port
    }
  }

  dynamic "identity" {
    for_each = try(var.settings.identity, null) == null ? [] : [1]

    content {
      type         = "UserAssigned"
      identity_ids = local.managed_identities
    }

  }

  dynamic "waf_configuration" {
    for_each = try(var.settings.waf_configuration, null) == null ? [] : [1]
    content {
      enabled                  = var.settings.waf_configuration.enabled
      firewall_mode            = var.settings.waf_configuration.firewall_mode
      rule_set_type            = var.settings.waf_configuration.rule_set_type
      rule_set_version         = var.settings.waf_configuration.rule_set_version
      file_upload_limit_mb     = try(var.settings.waf_configuration.file_upload_limit_mb, 100)
      request_body_check       = try(var.settings.waf_configuration.request_body_check, true)
      max_request_body_size_kb = try(var.settings.waf_configuration.max_request_body_size_kb, 128)
      dynamic "disabled_rule_group" {
        for_each = try(var.settings.waf_configuration.disabled_rule_groups, {})
        content {
          rule_group_name = disabled_rule_group.value.rule_group_name
          rules           = try(disabled_rule_group.value.rules, null)
        }
      }
      dynamic "exclusion" {
        for_each = try(var.settings.waf_configuration.exclusions, {})
        content {
          match_variable          = exclusion.value.match_variable
          selector_match_operator = try(exclusion.value.selector_match_operator, null)
          selector                = try(exclusion.value.selector, null)
        }
      }
    }
  }

  backend_address_pool {
    name = var.settings.default.backend_address_pool_name
  }

  backend_http_settings {
    name                  = var.settings.default.http_setting_name
    cookie_based_affinity = var.settings.default.cookie_based_affinity
    port                  = var.settings.front_end_ports[var.settings.default.frontend_port_key].port
    protocol              = var.settings.front_end_ports[var.settings.default.frontend_port_key].protocol
    request_timeout       = var.settings.default.request_timeout
  }

  http_listener {
    name                           = var.settings.default.listener_name
    frontend_ip_configuration_name = var.settings.front_end_ip_configurations[var.settings.default.frontend_ip_configuration_key].name
    frontend_port_name             = var.settings.front_end_ports[var.settings.default.frontend_port_key].name
    protocol                       = var.settings.front_end_ports[var.settings.default.frontend_port_key].protocol
  }

  request_routing_rule {
    name                       = var.settings.default.request_routing_rule_name
    rule_type                  = var.settings.default.rule_type
    http_listener_name         = var.settings.default.listener_name
    backend_address_pool_name  = var.settings.default.backend_address_pool_name
    backend_http_settings_name = var.settings.default.http_setting_name
  }

  lifecycle {
    ignore_changes = [
      backend_address_pool,
      backend_http_settings,
      http_listener,
      request_routing_rule,
      url_path_map,
      trusted_root_certificate,
      ssl_certificate,
      probe,
      rewrite_rule_set,
      redirect_configuration
    ]
  }
}