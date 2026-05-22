# Changelog

All notable changes to this module are documented in this file. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
