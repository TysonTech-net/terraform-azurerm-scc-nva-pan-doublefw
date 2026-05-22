###############################################################################
# SCC: Palo Alto VM-Series HA pair (doublefw — Common Firewall set w/ LBs)
###############################################################################
# Mirrors the topology of the `paloaltonetworks/vmseries-ngfw/doublefw` Azure
# Marketplace solution template, expressed natively in Terraform.
#
# v0.1.0 implements ONLY the `common` architecture (2 firewalls sandwiched between
# public + internal LBs). Other ARM-template architectures (inbound, outbound,
# dedicated-in-out) are declared in the schema but raise a precondition.
#
# Built on the official `PaloAltoNetworks/swfw-modules/azurerm` modules for the
# vmseries + loadbalancer primitives (vetted, in-use by BBSWE since first deploy).
# Wraps them with BBSWE conventions: existing-subnet inputs, CAF naming, single
# input schema, deterministic outputs.

locals {
  region_short_map = {
    uksouth = "uks"
    ukwest  = "ukw"
  }
  _region_short = try(local.region_short_map[var.location], substr(var.location, 0, 3))

  _name_prefix         = coalesce(var.firewall_vm_name_prefix, "vm-fw-${local._region_short}-")
  _avset_name          = coalesce(var.availability_set_config.name, "avset-fw-${local._region_short}-001")
  _public_lb_name      = coalesce(var.public_lb_name, "lb-fw-public-${local._region_short}-001")
  _internal_lb_name    = coalesce(var.internal_lb_name, "lb-fw-internal-${local._region_short}-001")
  _public_lb_pip_name  = coalesce(var.public_lb_frontend_public_ip_name, "pip-lb-fw-public-${local._region_short}-001")
  _backend_pool_public = "bep-fw-public-${local._region_short}"
  _backend_pool_intl   = "bep-fw-internal-${local._region_short}"

  # Per-VM zones list (cycled when count > zones)
  _zones = var.availability_zone_config.zones
  _zone_for_vm = {
    for i in range(var.firewall_vm_count) :
    format("fw%d", i + 1) => element(local._zones, i % length(local._zones))
  }

  _use_avset = var.availability_option == "Availability Set"
}

###############################################################################
# Preconditions
###############################################################################
check "architecture_supported_in_v0_1_0" {
  assert {
    condition     = var.architecture == "common"
    error_message = "v0.1.0 supports only `architecture = \"common\"`. `${var.architecture}` is declared in the schema for future ARM-template parity (v0.2.0+ roadmap)."
  }
}

check "vm_count_matches_architecture" {
  assert {
    condition     = var.architecture != "common" || var.firewall_vm_count == 2
    error_message = "`architecture = \"common\"` requires exactly 2 VMs (the HA pair). Got `firewall_vm_count = ${var.firewall_vm_count}`."
  }
}

check "internal_lb_static_ip_in_trust_subnet" {
  assert {
    condition     = length(trimspace(var.internal_lb_frontend_private_ip_address)) > 0
    error_message = "`internal_lb_frontend_private_ip_address` is required for the `common` architecture — it's the static private IP that becomes the next-hop for downstream UDRs (hub_router_ip_address in the hub repo)."
  }
}

###############################################################################
# Availability Set (single — all common-architecture VMs share one RG)
###############################################################################
resource "azurerm_availability_set" "this" {
  count = local._use_avset ? 1 : 0

  name                         = local._avset_name
  resource_group_name          = var.resource_group_name
  location                     = var.location
  platform_fault_domain_count  = var.availability_set_config.platform_fault_domain_count
  platform_update_domain_count = var.availability_set_config.platform_update_domain_count
  managed                      = true

  tags = var.tags
}

###############################################################################
# Load Balancers (public + internal)
###############################################################################
module "lb_public" {
  source  = "PaloAltoNetworks/swfw-modules/azurerm//modules/loadbalancer"
  version = "~> 3.5"

  name                = local._public_lb_name
  region              = var.location
  resource_group_name = var.resource_group_name
  backend_name        = local._backend_pool_public

  frontend_ips = {
    public_inbound = {
      name             = "fe-public"
      create_public_ip = true
      public_ip_name   = local._public_lb_pip_name
      in_rules = {
        http = {
          name     = "rule-${var.load_balancer_frontend_port}"
          protocol = "Tcp"
          port     = var.load_balancer_frontend_port
        }
      }
    }
  }

  tags = var.tags
}

module "lb_internal" {
  source  = "PaloAltoNetworks/swfw-modules/azurerm//modules/loadbalancer"
  version = "~> 3.5"

  name                = local._internal_lb_name
  region              = var.location
  resource_group_name = var.resource_group_name
  backend_name        = local._backend_pool_intl

  frontend_ips = {
    ha_ports = {
      name               = "fe-internal"
      subnet_id          = var.existing_subnet_ids.trust
      private_ip_address = var.internal_lb_frontend_private_ip_address
      in_rules = {
        ha_ports = {
          name     = "rule-ha-ports"
          protocol = "All"
          port     = 0
        }
      }
    }
  }

  tags = var.tags
}

###############################################################################
# VM-Series HA pair
###############################################################################
module "vmseries" {
  source  = "PaloAltoNetworks/swfw-modules/azurerm//modules/vmseries"
  version = "~> 3.5"

  for_each = toset([for i in range(var.firewall_vm_count) : format("fw%d", i + 1)])

  name                = "${local._name_prefix}${each.key}001"
  region              = var.location
  resource_group_name = var.resource_group_name

  authentication = {
    username                        = var.admin_username
    password                        = var.authentication_type == "password" ? var.admin_password_or_key : null
    ssh_keys                        = var.authentication_type == "sshPublicKey" ? [var.admin_password_or_key] : []
    disable_password_authentication = var.authentication_type == "sshPublicKey"
  }

  image = {
    publisher               = var.image.publisher
    offer                   = var.image.offer
    sku                     = var.image.sku
    version                 = var.image.version
    enable_marketplace_plan = true
  }

  virtual_machine = {
    size                       = var.firewall_vm_size
    zone                       = local._use_avset ? null : local._zone_for_vm[each.key]
    avset_id                   = local._use_avset ? azurerm_availability_set.this[0].id : null
    disk_type                  = var.disk_type
    disk_name                  = "osdisk-${local._name_prefix}${each.key}001"
    bootstrap_options          = var.custom_data
    encryption_at_host_enabled = var.encryption_at_host_enabled
    allow_extension_operations = false
    enable_boot_diagnostics    = true
  }

  interfaces = [
    {
      name      = "nic-mgmt-${local._name_prefix}${each.key}001"
      subnet_id = var.existing_subnet_ids.management
      ip_configurations = {
        primary = {
          name             = "ipcfg-mgmt"
          primary          = true
          create_public_ip = false
        }
      }
    },
    {
      name                      = "nic-untrust-${local._name_prefix}${each.key}001"
      subnet_id                 = var.existing_subnet_ids.untrust
      attach_to_lb_backend_pool = true
      lb_backend_pool_id        = module.lb_public.backend_pool_id
      ip_configurations = {
        primary = {
          name             = "ipcfg-untrust"
          primary          = true
          create_public_ip = false
        }
      }
    },
    {
      name                      = "nic-trust-${local._name_prefix}${each.key}001"
      subnet_id                 = var.existing_subnet_ids.trust
      attach_to_lb_backend_pool = true
      lb_backend_pool_id        = module.lb_internal.backend_pool_id
      ip_configurations = {
        primary = {
          name             = "ipcfg-trust"
          primary          = true
          create_public_ip = false
        }
      }
    },
  ]

  tags = var.tags
}
