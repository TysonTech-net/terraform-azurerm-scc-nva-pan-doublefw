# terraform-azurerm-scc-nva-pan-doublefw

SCC bespoke Terraform module for the **Palo Alto VM-Series HA pair (Common Firewall set with Load Balancers)** topology. Mirrors the `paloaltonetworks/vmseries-ngfw/doublefw` Azure Marketplace solution template, expressed natively in Terraform.

## v0.1.0 scope

Implements ONLY the `common` architecture (2 firewalls sandwiched between public + internal LBs, all traffic flows through both firewalls). This is the BBSWE UKS topology per LLD §8.1.

Other ARM-template architectures (`inbound`, `outbound`, `dedicated-in-out`) are declared in the schema but raise a precondition error. See "Roadmap" below.

Networking is **existing-only** in v0.1.0 — caller passes in subnet IDs from the accelerator-side hub VNet module. Greenfield "new" mode (where the module creates its own VNet + subnets + NSGs) is on the v0.2.0 roadmap.

## Marketplace agreement (caller-managed)

The module assumes `paloaltonetworks/vmseries-flex/byol` Marketplace agreement is already accepted on the subscription. Accept it once via:

```bash
az vm image terms accept --publisher paloaltonetworks --offer vmseries-flex --plan byol \
  --subscription <subscription-id>
```

## Usage (BBSWE UKS example)

```hcl
module "fw_uks" {
  source  = "git::https://github.com/TysonTech-net/terraform-azurerm-scc-nva-pan-doublefw.git?ref=v0.1.0"

  location              = "uksouth"
  resource_group_name   = "rg-hub-prod-firewall-uks-001"

  # Auth (sensitive from env / KV / TF_VAR_*)
  admin_username        = "paadmin"
  admin_password_or_key = var.vmseries_admin_password
  authentication_type   = "password"

  # Topology
  architecture          = "common"
  availability_option   = "Availability Set"
  firewall_vm_count     = 2
  firewall_vm_size      = "Standard_D8_v4"

  # Image (BBSWE LLD §8.1: BYOL, PAN-OS 12.1.4)
  image = {
    publisher = "paloaltonetworks"
    offer     = "vmseries-flex"
    sku       = "byol"
    version   = "12.1.4"
  }

  # LB
  load_balancer_frontend_port             = 80
  internal_lb_frontend_private_ip_address = "10.0.0.4"  # equals hub_router_ip_address in the hub repo

  # Existing networking (from accelerator hub VNet)
  existing_subnet_ids = {
    management = local.subnet_ids["uks"].management
    trust      = local.subnet_ids["uks"].private
    untrust    = local.subnet_ids["uks"].public
  }

  tags = var.tags
}
```

## Resources created

- 1× `azurerm_availability_set` (the HA-pair AvSet)
- 1× Public Load Balancer (`PaloAltoNetworks/swfw-modules/azurerm//modules/loadbalancer`) + its public IP + front-end + 1 inbound rule on `load_balancer_frontend_port`
- 1× Internal Load Balancer with HA-ports rule on the trust subnet
- 2× VM-Series VMs (`PaloAltoNetworks/swfw-modules/azurerm//modules/vmseries`) with 3 NICs each (mgmt, untrust, trust). Untrust + trust NICs attach to their respective LB backend pools.

## Inputs

See `variables.tf` for the full schema. Required:

- `location`
- `resource_group_name`
- `admin_password_or_key` (sensitive)
- `internal_lb_frontend_private_ip_address`
- `existing_subnet_ids` (mgmt / trust / untrust IDs)

## Outputs

- `availability_set_resource_id`
- `vm_resource_ids` (map fw1 / fw2 → VM ID)
- `vm_names`
- `public_lb_resource_id`
- `public_lb_frontend_public_ip_address`
- `internal_lb_resource_id`
- `internal_lb_frontend_ip_address` (= the input, surfaced for caller convenience)

## Roadmap

### v0.2.0

- `architecture = "inbound"`: 2 firewalls behind public LB only (no internal LB)
- `architecture = "outbound"`: 2 firewalls in front of internal LB only
- `architecture = "dedicated-in-out"`: 4 firewalls (2 ingress + 2 egress) with both LBs
- `subnets_new_or_existing = "new"` branch (module creates VNet + subnets + NSGs)
- `network_security_groups_new_or_existing` branch
- `public_ips_new_or_existing` branch

### v1.0.0

- Promotion to stable after BBSWE end-to-end production validation.

## Why wrap PaloAltoNetworks/swfw-modules

v0.1.0 builds on `PaloAltoNetworks/swfw-modules/azurerm` (`vmseries` + `loadbalancer` sub-modules) rather than reimplementing from `azurerm_virtual_machine` + `azurerm_lb` primitives. Rationale:

- The Palo Alto modules are vendor-blessed and BBSWE has been deploying with them since first apply
- They handle `enable_marketplace_plan`, multi-NIC ordering, and LB backend pool wiring correctly
- Wrapping them here adds the BBSWE niceties (CAF naming, existing-subnet inputs, consolidated schema) without rewriting working code

If a future requirement (e.g. AVM-only constraint, vendor support change) demands replacement, the wrapper interface stays the same — only the internals change.
