provider "aws" {
  region = var.region
}

# Create ECS Cluster
resource "aws_ecs_cluster" "medusa_cluster" {
  name = "medusa-cluster"
}

# Create ECR repository for Medusa server
resource "aws_ecr_repository" "medusa_repo" {
  name = "medusa-server"
}

# RDS PostgreSQL Database
resource "aws_db_instance" "postgres" {
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "13"
  instance_class       = "db.t3.micro"
  name                 = var.db_name
  username             = var.db_username
  password             = var.db_password
  db_subnet_group_name = aws_db_subnet_group.medusa_db_subnet_group.name
  publicly_accessible  = false
  vpc_security_group_ids = [aws_security_group.db_security_group.id]
}

resource "aws_db_subnet_group" "medusa_db_subnet_group" {
  name       = "medusa-db-subnet-group"
  subnet_ids = ["subnet-06e061d9e41f360d6", "subnet-08afa8e9e0d30af6b"]
}

resource "aws_security_group" "db_security_group" {
  name        = "medusa-db-security-group"
  description = "Security group for PostgreSQL"
  vpc_id      = "vpc-id-here"

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # Modify this based on your VPC CIDR block
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "medusa" {
  family                   = "medusa-service"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "medusa"
      image     = "${aws_ecr_repository.medusa_repo.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 9000
        }
      ]
      environment = [
        {
          name  = "DATABASE_URL"
          value = "postgres://${var.db_username}:${var.db_password}@${aws_db_instance.postgres.endpoint}:5432/${var.db_name}"
        },
        {
          name = "JWT_SECRET"
          value = var.jwt_secret
        },
        {
          name = "COOKIE_SECRET"
          value = var.cookie_secret
        }
      ]
    }
  ])
}

# IAM role for ECS task execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs_task_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      }
    ]
  })
}

# Attach ECS task execution role policy
resource "aws_iam_role_policy_attachment" "ecs_task_ecr_access" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECSTaskExecutionRolePolicy"
}

# ECS Service Definition
resource "aws_ecs_service" "medusa_service" {
  name            = "medusa-service"
  cluster         = aws_ecs_cluster.medusa_cluster.id
  task_definition = aws_ecs_task_definition.medusa.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  depends_on      = [aws_lb_target_group.medusa_tg]

  network_configuration {
    subnets          = ["subnet-06e061d9e41f360d6", "subnet-08afa8e9e0d30af6b"]
    security_groups  = ["sg-08c3cd7d15aa177e3"]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.medusa_tg.arn
    container_name   = "medusa"
    container_port   = 9000
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
}

# Create an Application Load Balancer
resource "aws_lb" "medusa_alb" {
  name               = "medusa-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["sg-08c3cd7d15aa177e3"]
  subnets            = ["subnet-06e061d9e41f360d6", "subnet-08afa8e9e0d30af6b"]

  enable_deletion_protection = false
}

# Create ALB Listener
resource "aws_lb_listener" "medusa_listener" {
  load_balancer_arn = aws_lb.medusa_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.medusa_tg.arn
  }
}

# ALB Target Group for ECS tasks
resource "aws_lb_target_group" "medusa_tg" {
  name        = "medusa-tg"
  port        = 9000
  protocol    = "HTTP"
  vpc_id      = "vpc-id-here"
  target_type = "ip"
}

# ECS Service Auto Scaling
resource "aws_appautoscaling_target" "medusa_scaling" {
  max_capacity       = 5
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.medusa_cluster.name}/${aws_ecs_service.medusa_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu_scaling" {
  name               = "cpu-scaling"
  scaling_target_id  = aws_appautoscaling_target.medusa_scaling.id
  policy_type        = "TargetTrackingScaling"
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 50.0
  }
}

# Outputs
output "db_instance_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "ecs_service_name" {
  value = aws_ecs_service.medusa_service.name
}

output "alb_dns_name" {
  value = aws_lb.medusa_alb.dns_name
}

output "ecs_task_role_arn" {
  value = aws_iam_role.ecs_task_execution_role.arn
}
