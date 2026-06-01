output "availability_set_resource_id" {
  description = "Resource ID of the auto-created Availability Set (null when `availability_option = \"Availability Zone\"`)."
  value       = try(azurerm_availability_set.this[0].id, null)
}

output "vm_names" {
  description = "Map of VM key (instance number 001, 002, ...) → VM name."
  value       = { for k, m in module.vmseries : k => "${local._name_prefix}${k}" }
}

output "mgmt_ip_addresses" {
  description = "Map of VM key → management IP. Passthrough from the underlying Palo Alto vmseries module (private IP since mgmt NICs have no PIP in this module)."
  value       = { for k, m in module.vmseries : k => m.mgmt_ip_address }
}

output "vm_interfaces" {
  description = "Map of VM key → NIC map (from the vmseries sub-module). Keys at the inner level are the NIC names (e.g. `nic-mgmt-<vm_name>`)."
  value       = { for k, m in module.vmseries : k => m.interfaces }
}

output "public_lb_resource_id" {
  description = "Resource ID of the public Load Balancer."
  value       = module.lb_public.id
}

output "public_lb_frontend_public_ip_address" {
  description = "Public IP address attached to the public LB front-end. Drives spoke UDRs for inbound paths."
  value       = try(module.lb_public.frontend_ip_configs["public_inbound"].public_ip_address, null)
}

output "internal_lb_resource_id" {
  description = "Resource ID of the internal Load Balancer."
  value       = module.lb_internal.id
}

output "internal_lb_frontend_ip_address" {
  description = "Front-end private IP of the internal LB. Becomes `hub_router_ip_address` in the consumer hub repo (trust-side next-hop for downstream UDRs). Echo of `var.internal_lb_frontend_private_ip_address`."
  value       = var.internal_lb_frontend_private_ip_address
}

output "nsg_resource_ids" {
  description = "Map of NSG role → resource ID (mgmt/trust/untrust). Empty when `create_nsgs = false`."
  value = {
    mgmt    = try(module.nsg_mgmt[0].resource_id, null)
    trust   = try(module.nsg_trust[0].resource_id, null)
    untrust = try(module.nsg_untrust[0].resource_id, null)
  }
}

output "route_table_resource_ids" {
  description = "Map of RT role → resource ID (egress/ingress). Empty when `create_route_tables = false`."
  value = {
    egress  = try(module.route_table_egress[0].resource_id, null)
    ingress = try(module.route_table_ingress[0].resource_id, null)
  }
}
