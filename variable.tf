variable "region" {
  default = "ap-south-1"
}

variable "aws_account_id" {
  default = "your-account-id"
}

variable "db_username" {
  description = "The username for the PostgreSQL database."
}

variable "db_password" {
  description = "The password for the PostgreSQL database."
}

variable "db_name" {
  description = "The name of the PostgreSQL database."
  default     = "medusadb"
}

variable "jwt_secret" {
  description = "The JWT secret for securing tokens."
}

variable "cookie_secret" {
  description = "The Cookie secret for securing cookies."
}
