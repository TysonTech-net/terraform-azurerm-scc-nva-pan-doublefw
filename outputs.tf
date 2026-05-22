output "availability_set_resource_id" {
  description = "Resource ID of the auto-created Availability Set (null when `availability_option = \"Availability Zone\"`)."
  value       = try(azurerm_availability_set.this[0].id, null)
}

output "vm_resource_ids" {
  description = "Map of VM key (fw1, fw2, ...) → VM resource ID."
  value       = { for k, m in module.vmseries : k => m.virtual_machine.id }
}

output "vm_names" {
  description = "Map of VM key → VM name."
  value       = { for k, m in module.vmseries : k => m.virtual_machine.name }
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
  description = "Front-end private IP of the internal LB. Becomes `hub_router_ip_address` in the consumer hub repo (trust-side next-hop for downstream UDRs)."
  value       = var.internal_lb_frontend_private_ip_address
}
