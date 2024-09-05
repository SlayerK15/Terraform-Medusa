provider "aws" {
  region = var.region
}

resource "aws_ecs_cluster" "medusa_cluster" {
  name = "medusa-cluster"
}

# Create ECR repository for Medusa server
resource "aws_ecr_repository" "medusa_repo" {
  name = "medusa-server"
}

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

resource "aws_ecs_service" "medusa_service" {
  name            = "medusa-service"
  cluster         = aws_ecs_cluster.medusa_cluster.id
  task_definition = aws_ecs_task_definition.medusa.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = ["subnet-06e061d9e41f360d6", "subnet-08afa8e9e0d30af6b"]
    security_groups  = ["sg-08c3cd7d15aa177e3"]
    assign_public_ip = true
  }
}

# Outputs
output "db_instance_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "ecs_service_name" {
  value = aws_ecs_service.medusa_service.name
}
