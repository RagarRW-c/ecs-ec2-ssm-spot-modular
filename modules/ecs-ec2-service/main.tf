# SG for tasks: in with ALB SG on 80

resource "aws_security_group" "tasks" {
  name = "${var.project}-tasks-sg"
  vpc_id = var.vpc_id

  ingress{
    from_port = 80
    to_port = 80
    protocol = "tcp"
    security_groups = [var.alb_sg_id]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags,{
    Name = "${var.project}-tasks-sg"
  })
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project}"
  retention_in_days = 7
  kms_key_id        = aws_kms_key.ecs_logs.arn
}

resource "aws_kms_key" "ecs_logs" {
  description = "KMS key for ECS CloudWatch logs encryption"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "ecs_logs" {
  name          = "alias/${var.project}-ecs-logs"
  target_key_id = aws_kms_key.ecs_logs.key_id
}

data "aws_caller_identity" "current" {}

#Role exec for tasks
resource "aws_iam_role" "ecs_exec" {
  name = "${var.project}-ecs-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_exec_policy" {
  role = aws_iam_role.ecs_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

#Task definition (EC2 + awsvpc)
resource "aws_ecs_task_definition" "web" {
  family = "${var.project}-web"
  network_mode = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu = "256"
  memory = "512"
  execution_role_arn = aws_iam_role.ecs_exec.arn

  container_definitions = jsonencode([
    {
        name = "web"
        image = "nginxdemos/hello:latest"
        essential = true
        portMappings = [ {
            containerPort = 80
            hostPort = 80
            protocol = "tcp"
        }]
        logConfiguration = {
            logDriver = "awslogs"
            options = {
                awslogs-group = aws_cloudwatch_log_group.ecs.name
                awslogs-region  = var.region
                awslogs-stream-prefix = "web"
            }
        }
        secrets = [ {
            name = "APP_SECRET"
            valueFrom = var.secret_arn
        }]
    }
  ])
}

resource "aws_ecs_service" "web" {
  name = "${var.project}-web"
  cluster = var.cluster_arn
  task_definition = aws_ecs_task_definition.web.arn
  desired_count = 2
  enable_execute_command = true

  capacity_provider_strategy {
    capacity_provider = var.cp_name
    weight = 1
  }

  network_configuration {
    subnets = var.private_subnets
    security_groups = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.alb_tg_arn
    container_name = "web"
    container_port = 80
  }

  lifecycle {
    ignore_changes = [ task_definition ]
  }
}

