output "alb_dns" {
  value = module.alb.lb_dns_name
}

output "cluster_name" {
  value = module.ecs_cluster.cluster_name
}

output "service_name" {
  value = module.service.service_name
}