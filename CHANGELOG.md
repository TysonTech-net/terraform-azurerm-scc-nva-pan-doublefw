# Changelog

All notable changes to this module are documented in this file. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.2] - 2026-06-01

### Changed

- **BREAKING**: VM naming pattern. The per-VM map keys and the resulting VM names are now zero-padded instance numbers (`001`, `002`) instead of `fw1`/`fw2`. Names go from `${prefix}fw1001` / `${prefix}fw2001` → `${prefix}001` / `${prefix}002`. Matches the conventional Azure / LLD `vmfw{customer}{region}{NNN}` naming pattern; the `fw{N}{instance}` shape was an accidental artefact of the v0.1.0 module's per-VM key naming.
- Affects: VM name, OS disk name, 3× NIC names (mgmt/trust/untrust) per VM.
- Output `vm_names` map keys change from `fw1`/`fw2` to `001`/`002`. Same for `mgmt_ip_addresses` + `vm_interfaces`. Consumers iterating the map (rather than key-lookup) are unaffected; key-lookup consumers need updating.
- Re-applying against state created with v0.2.0 or v0.2.1 forces destroy+recreate of the VM-Series HA pair (rename = recreate in Azure).

## [0.2.0] - 2026-05-22

### Added

- **NSG creation** for the 3 firewall subnets (mgmt/trust/untrust). Module owns the NSG resources (named via `nsg_names` input, with sensible CAF defaults). Default security rules match the BBSWE current scc.nva.tf pattern: untrust allows Internet inbound; trust + mgmt allow VirtualNetwork inbound. Caller can extend per-NSG via `additional_nsg_rules`.
- **Route Table creation** for trust + untrust subnets. Each carries a cross-region UDR (peer-region spoke CIDR → peer-region NVA IP). Ingress RT additionally carries optional downstream spoke routes pointing at the local NVA (LLD §6.6).
- New inputs: `create_nsgs`, `nsg_names`, `additional_nsg_rules`, `create_route_tables`, `route_table_names`, `peer_region_cidr`, `peer_nva_ip`, `local_nva_ip`, `downstream_spoke_routes`.
- New outputs: `nsg_resource_ids`, `route_table_resource_ids`.

### Compatibility

- New features default-off-ish: `create_nsgs` + `create_route_tables` both default to `true` (matching BBSWE's expected usage). Set false to opt out.
- v0.1.x consumers that DIDN'T have the module create NSGs/RTs (because v0.1.x couldn't) now will. Coordinate with caller-side scc.nva.tf to either accept module ownership OR set the toggles to false.

## [0.1.1] - 2026-05-22

### Fixed

- **Outputs referenced non-existent vmseries module attributes.** v0.1.0's `vm_resource_ids` + `vm_names` referenced `module.vmseries[k].virtual_machine.id` / `.name`, but the underlying `PaloAltoNetworks/swfw-modules/azurerm//modules/vmseries` doesn't expose a `virtual_machine` output. Terraform deferred the type-check inside the for-loop so `terraform validate` passed at module-build time, but any consumer reading these outputs would error at plan.
- **Fix**: replaced with what the underlying module actually exposes — `mgmt_ip_addresses` (passthrough) + `vm_interfaces` (NIC map) — and computed `vm_names` from the deterministic name prefix.

## [0.1.0] - 2026-05-22

### Added

Initial release. Implements the `common` architecture from the `paloaltonetworks/vmseries-ngfw/doublefw` Azure Marketplace solution template:

- 2× Palo Alto VM-Series VMs (BBSWE LLD §8.1 default: BYOL, PAN-OS 12.1.4, modern equivalent `Standard_D8_v4`)
- Public Load Balancer with configurable front-end port + auto-created Public IP
- Internal Load Balancer with HA-ports rule on the trust subnet, static front-end IP (caller-supplied)
- 1× Availability Set (when `availability_option = "Availability Set"`, the BBSWE default for zoneless-region consistency)
- 3 NICs per VM (mgmt + untrust + trust) with untrust/trust NICs attached to their respective LB backend pools

### Schema scope

- `architecture` accepts all 4 ARM-template values but only `common` is implemented in v0.1.0; others raise a precondition error
- `availability_option` accepts both `"Availability Set"` and `"Availability Zone"`
- Networking is existing-only — caller supplies subnet IDs

### Dependencies

- Built on `PaloAltoNetworks/swfw-modules/azurerm` (`vmseries` + `loadbalancer` sub-modules), pinned `~> 3.5`. v0.2.0+ may swap to AVM where stable AVM coverage exists.
