###############################################################################
# Always required
###############################################################################

variable "location" {
  description = "Azure region for the VM-Series + LB stack. e.g. \"uksouth\"."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group that the VM-Series VMs, Availability Set, Load Balancers + Public IPs land in."
  type        = string
}

variable "admin_username" {
  description = "Initial PA-OS admin username. LLD §8.1 pins `paadmin` for BBSWE."
  type        = string
  default     = "pandemo"
}

variable "admin_password_or_key" {
  description = "Initial PA-OS admin password (for `authentication_type = \"password\"`) or SSH public key (for `\"sshPublicKey\"`). Rotate post-deploy via PA-OS web UI / Panorama."
  type        = string
  sensitive   = true
}

variable "authentication_type" {
  description = "PA-OS admin auth type. ARM template default is `password`; SSH key requires Linux-style key string."
  type        = string
  default     = "password"
  validation {
    condition     = contains(["password", "sshPublicKey"], var.authentication_type)
    error_message = "authentication_type must be \"password\" or \"sshPublicKey\"."
  }
}

###############################################################################
# Architecture + placement
###############################################################################

variable "architecture" {
  description = <<DESCRIPTION
Topology variant from the `paloaltonetworks/vmseries-ngfw/doublefw` ARM template:

  - `common` (BBSWE UKS): 2 firewalls sandwiched between public + internal LBs.
                          All traffic flows through both firewalls.

v0.1.0 implements `common` only. `inbound`/`outbound`/`dedicated-in-out` are
declared in the schema for future ARM-template parity but currently raise a
precondition error. See module README "Roadmap" for v0.2.0+ scope.
DESCRIPTION
  type        = string
  default     = "common"
  validation {
    condition     = contains(["common", "inbound", "outbound", "dedicated-in-out"], var.architecture)
    error_message = "architecture must be one of: common, inbound, outbound, dedicated-in-out."
  }
}

variable "availability_option" {
  description = <<DESCRIPTION
VM placement strategy. Mirrors the ARM template's `availabilityOption` parameter:

  - `Availability Set` (default): module creates an `azurerm_availability_set` and
    joins every VM to it. Required for zoneless regions (UK West has no AZs).
  - `Availability Zone`: VMs placed across zones from `availability_zone_config.zones`.
    Falls back to Availability Set if the region has no zones (mirrors the ARM
    template's `shouldDeployIntoAvailabilityZones` runtime check).

BBSWE UKS uses `Availability Set` per user-confirmation 2026-05-22 (the
BBSWE-Connectivity sub's UKS x86 SKU availability is effectively single-AZ in
practice, removing the AZ resilience benefit).
DESCRIPTION
  type        = string
  default     = "Availability Set"
  validation {
    condition     = contains(["Availability Set", "Availability Zone"], var.availability_option)
    error_message = "availability_option must be \"Availability Set\" or \"Availability Zone\"."
  }
}

variable "availability_set_config" {
  description = "Config for the auto-created Availability Set when `availability_option = \"Availability Set\"`."
  type = object({
    name                         = optional(string)
    platform_fault_domain_count  = optional(number, 2)
    platform_update_domain_count = optional(number, 2)
  })
  default = {}
}

variable "availability_zone_config" {
  description = "Config for AZ placement when `availability_option = \"Availability Zone\"`. VMs cycle through `zones` (e.g. VM 1 → zone 1, VM 2 → zone 2)."
  type = object({
    zones = optional(list(string), ["1", "2"])
  })
  default = {}
}

###############################################################################
# VM-Series
###############################################################################

variable "firewall_vm_count" {
  description = "Number of VM-Series VMs. `common`/`inbound`/`outbound` architectures require exactly 2; `dedicated-in-out` requires 4. Defaults to 2 (the BBSWE common-architecture value)."
  type        = number
  default     = 2
}

variable "firewall_vm_size" {
  description = "Azure VM size for VM-Series. ARM template recommended default is `Standard_D8_v4` (8 vCPU / 32 GB), modern equivalent of the LLD-pinned legacy `Standard_DS4_v2`."
  type        = string
  default     = "Standard_D8_v4"
}

variable "firewall_vm_name_prefix" {
  description = "Name prefix for VM-Series VMs. Module appends `fw<n>001` per VM (e.g. `$${prefix}fw1001`). When null, auto-generated as `vm-fw-<region_short>-`."
  type        = string
  default     = null
}

variable "disk_type" {
  description = "OS disk storage account type. ARM template allows `Standard_LRS` or `Premium_LRS`."
  type        = string
  default     = "Premium_LRS"
  validation {
    condition     = contains(["Standard_LRS", "Premium_LRS"], var.disk_type)
    error_message = "disk_type must be \"Standard_LRS\" or \"Premium_LRS\"."
  }
}

variable "image" {
  description = "Marketplace image reference. Defaults align with BBSWE LLD §8.1 (BYOL, PAN-OS 12.1.4) on the `vmseries-flex` offer the ARM template's VMs use under the hood."
  type = object({
    publisher = optional(string, "paloaltonetworks")
    offer     = optional(string, "vmseries-flex")
    sku       = optional(string, "byol")
    version   = optional(string, "12.1.4")
  })
  default = {}
}

variable "enable_palo_alto_bootstrap" {
  description = "Mirrors ARM template's `enable-palo-alto-bootstrap` parameter. When true, the VMs expect a Palo Alto bootstrap storage account; provide the bootstrap content via `custom_data`. v0.1.0 passes through as-is; richer bootstrap helper TBD in v0.2.0+."
  type        = bool
  default     = false
}

variable "custom_data" {
  description = "Bootstrap content passed to the VMs (PA-OS init-cfg.txt / bootstrap.xml). Mirrors the ARM template's `customData` parameter. PA-OS team supplies the actual content; module just passes through."
  type        = string
  default     = ""
}

variable "encryption_at_host_enabled" {
  description = "Per LLD §7.2 — host-level encryption enabled on all VMs."
  type        = bool
  default     = true
}

###############################################################################
# Load balancer
###############################################################################

variable "load_balancer_frontend_port" {
  description = "Public LB front-end port. ARM template default = 80 (BBSWE LLD §8.1 uses 80 too)."
  type        = number
  default     = 80
}

variable "public_lb_name" {
  description = "Public LB name. When null, auto-generated as `lb-fw-public-<region_short>-001`."
  type        = string
  default     = null
}

variable "internal_lb_name" {
  description = "Internal LB name. When null, auto-generated as `lb-fw-internal-<region_short>-001`."
  type        = string
  default     = null
}

variable "internal_lb_frontend_private_ip_address" {
  description = "Static private IP for the internal LB front-end on the trust subnet. This is the IP that downstream UDRs use as `next_hop_in_ip_address` (becomes `hub_router_ip_address` in the hub repo). Must be in the trust subnet's CIDR."
  type        = string
}

variable "public_lb_frontend_public_ip_name" {
  description = "Public IP resource name for the public LB front-end. When null, auto-generated as `pip-lb-fw-public-<region_short>-001`."
  type        = string
  default     = null
}

###############################################################################
# Existing networking (BBSWE / ALZ-context inputs)
###############################################################################
# v0.1.0 supports only `existing` mode for networking — the workload-side hub
# VNet + subnets are managed by the accelerator-side `platform-landing-zone.auto.tfvars`
# and passed in as IDs. Greenfield "new" mode is on the v0.2.0 roadmap.

variable "existing_subnet_ids" {
  description = "IDs of the 3 firewall subnets (already created by the AVM hub VNet module)."
  type = object({
    management = string
    trust      = string
    untrust    = string
  })
}

###############################################################################
# Tags
###############################################################################

variable "tags" {
  description = "Tags applied to every resource the module creates."
  type        = map(string)
  default     = {}
}
