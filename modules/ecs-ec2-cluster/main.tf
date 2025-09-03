#IAM for instance ECS + SSM
resource "aws_iam_role" "ecs_instance" {
  name = "${var.project}-ecs-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_instance_core" {
  role = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs" {
  name = "${var.project}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance.name
}

#AMI ECS-Optimized with SSM

data "aws_ssm_parameter" "ecs_al2" {
    name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended"
}
  
locals {
  ecs_ami_id = jsondecode(data.aws_ssm_parameter.ecs_al2.value).image_id
}

#SG instance (egress all)
resource "aws_security_group" "instances" {
  name = "${var.project}-ecs-instances-sg"
  vpc_id = var.vpc_id
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-ecs-instances-sg"
  })
}

#UserData: into cluster and SSM
locals {
  userdata = <<-EOF
  #!/bin/bash -xe
  echo "ECS_CLUSTER=${aws_ecs_cluster.main.name}" >> /etc/ecs/ecs.config
  echo "ECS_ENABLE_TASK_IAM_ROLE=true" >> /etc/ecs/ecs.config
  echo "ECS_ENABLE_TASK_ENI=true" >> /etc/ecs/ecs.config
  EOF
}

resource "aws_launch_template" "ecs" {
  name_prefix = "${var.project}-lt-"
  image_id = local.ecs_ami_id
  instance_type = var.instance_type
  key_name = var.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs.name
  }
  vpc_security_group_ids = [aws_security_group.instances.id]

  user_data = base64encode(local.userdata)

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
        Name = "${var.project}-ecs-instance"
    })
  }

  dynamic "instance_market_options" {
  for_each = var.use_spot ? [1] : []
  content {
    market_type = "spot"
  }
}
}

#ASG On-deman default, optional SPOT
resource "aws_autoscaling_group" "ecs"{
    name = "${var.project}-asg"
    vpc_zone_identifier = var.private_subnets

    desired_capacity = var.desired
    max_size = var.max_size
    min_size = var.min_size
    protect_from_scale_in = true

    # mixed_instances_policy {
    #   launch_template {
    #     launch_template_specification {
    #       launch_template_id = aws_launch_template.ecs.id
    #       launch_template_name = aws_launch_template.ecs.name
    #     }
    #     override {
    #       instance_type = var.instance_type
    #     }
    #   }
    #   instances_distribution {
    #     on_demand_base_capacity = 0
    #     on_demand_percentage_above_base_capacity = 0
    #     spot_allocation_strategy = "capacity-optimized"
    #   }
    # }

    launch_template {
      id = aws_launch_template.ecs.id
      version = "$Latest"
    }

    lifecycle {
      create_before_destroy = true
    }

    tag {
        key = "Name"
        value = "${var.project}-ecs-instance"
        propagate_at_launch = true
    }
}

#ECS CLuster + Capacity Provider (managed scaling + termination protection)

resource "aws_ecs_cluster" "main" {
   name = "${var.project}-ecs"
   setting {
    name = "containerInsights"
    value = "enabled"
   } 
}

resource "aws_ecs_capacity_provider" "cp" {
  name = "${var.project}_cp"
  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "ENABLED"
    managed_scaling {
      status = "ENABLED"
      target_capacity = 80
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 2
    }
   
  }
}

resource "aws_ecs_cluster_capacity_providers" "attach" {
    cluster_name = aws_ecs_cluster.main.name
    capacity_providers = [aws_ecs_capacity_provider.cp.name]
    default_capacity_provider_strategy {
      capacity_provider = aws_ecs_capacity_provider.cp.name
      weight = 1
    }
}