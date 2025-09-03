locals {
  tags = {
    project = var.project
    owner   = "devops"
  }
}


# VPC module from rejestry

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 10)]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = local.tags
}

data "aws_availability_zones" "available" {
  state = "available"
}

# ALB (from module)
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.7"

  name               = "${var.project}-alb"
  load_balancer_type = "application"
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets
  security_groups    = [module.alb_sg.security_group_id]

  http_tcp_listeners = [{
    port               = 80
    protocol           = "HTTP"
    target_group_index = 0
  }]

  target_groups = [{
    name_prefix          = "web"
    backend_protocol     = "HTTP"
    backend_port         = 80
    target_type          = "ip"
    deregistration_delay = 10
    health_check = {
      enabled  = true
      path     = "/"
      matcher  = "200-399"
      interval = 15
      timeout  = 5
    }
  }]

  tags = local.tags
}


#SG for ALB
module "alb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.1"

  name        = "${var.project}-alb-sg"
  description = "ALLOW HTTP for Internet"
  vpc_id      = module.vpc.vpc_id

  ingress_rules       = ["http-80-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules        = ["all-all"]

  tags = local.tags
}

#ECS Cluster + ASG (local module)
module "ecs_cluster" {
  source = "./modules/ecs-ec2-cluster"

  project         = var.project
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets
  instance_type   = var.instance_type
  desired         = var.desired
  min_size        = var.min_size
  max_size        = var.max_size
  key_name        = var.key_name
  use_spot        = var.use_spot

  tags = local.tags
}


#ECS Service (local module)
resource "aws_ssm_parameter" "app_secret" {
  name  = "/${var.project}/APP_SECRET"
  type  = "SecureString"
  value = "dev-secret-change-me"
}

module "service" {
  source = "./modules/ecs-ec2-service"

  project         = var.project
  cluster_arn     = module.ecs_cluster.cluster_arn
  cluster_name    = module.ecs_cluster.cluster_name
  cp_name         = module.ecs_cluster.capacity_provider_name
  private_subnets = module.vpc.private_subnets
  vpc_id          = module.vpc.vpc_id

  alb_tg_arn = module.alb.target_group_arns[0]
  alb_sg_id  = module.alb_sg.security_group_id
  region     = var.region
  secret_arn = aws_ssm_parameter.app_secret.arn
  tags       = local.tags
}

