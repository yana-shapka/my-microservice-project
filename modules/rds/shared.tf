locals {
  # Common tags aligned with project conventions
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    Module      = "rds"
    ManagedBy   = "terraform"
  })

  # Database port based on engine
  db_port = var.port != null ? var.port : (var.engine == "postgres" ? 5432 : 3306)

  # Parameter group family based on engine and version
  parameter_group_family = var.engine == "postgres" ? 
    "postgres${split(".", var.engine_version)[0]}" : 
    "mysql${split(".", var.engine_version)[0]}.${split(".", var.engine_version)[1]}"

  # Aurora cluster parameter group family
  aurora_cluster_family = var.engine == "postgres" ? 
    "aurora-postgresql${split(".", var.engine_version)[0]}" : 
    "aurora-mysql${split(".", var.engine_version)[0]}.${split(".", var.engine_version)[1]}"

  # Aurora engine based on regular engine
  aurora_engine = var.engine == "postgres" ? "aurora-postgresql" : "aurora-mysql"

  # Default parameters optimized for Django applications
  default_parameters = var.engine == "postgres" ? [
    {
      name  = "max_connections"
      value = "100"
    },
    {
      name  = "log_statement"
      value = "all"
    },
    {
      name  = "work_mem"
      value = "4MB"
    },
    {
      name  = "shared_preload_libraries"
      value = "pg_stat_statements"
    },
    {
      name  = "log_min_duration_statement"
      value = "1000"
    },
    {
      name  = "timezone"
      value = "UTC"
    }
  ] : [
    {
      name  = "max_connections"
      value = "100"
    },
    {
      name  = "general_log"
      value = "1"
    },
    {
      name  = "slow_query_log"
      value = "1"
    },
    {
      name  = "long_query_time"
      value = "1"
    },
    {
      name  = "innodb_buffer_pool_size"
      value = "{DBInstanceClassMemory*3/4}"
    },
    {
      name  = "time_zone"
      value = "UTC"
    }
  ]

  # Merge default and custom parameters
  all_parameters = concat(local.default_parameters, var.custom_db_parameters)
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  })
}

# Security Group for Database
resource "aws_security_group" "db" {
  name        = "${var.project_name}-${var.environment}-db-sg"
  description = "Security group for ${var.use_aurora ? "Aurora" : "RDS"} database"
  vpc_id      = var.vpc_id

  # Allow access from EKS nodes and other specified security groups
  dynamic "ingress" {
    for_each = length(var.allowed_security_group_ids) > 0 ? [1] : []
    content {
      from_port       = local.db_port
      to_port         = local.db_port
      protocol        = "tcp"
      security_groups = var.allowed_security_group_ids
    }
  }

  # Allow access from specified CIDR blocks
  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      from_port   = local.db_port
      to_port     = local.db_port
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-db-sg"
  })
}

# Parameter Group for RDS Instance
resource "aws_db_parameter_group" "main" {
  count  = var.use_aurora ? 0 : 1
  name   = "${var.project_name}-${var.environment}-db-params"
  family = local.parameter_group_family

  dynamic "parameter" {
    for_each = local.all_parameters
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-db-params"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Cluster Parameter Group for Aurora
resource "aws_rds_cluster_parameter_group" "aurora" {
  count  = var.use_aurora ? 1 : 0
  name   = "${var.project_name}-${var.environment}-aurora-cluster-params"
  family = local.aurora_cluster_family

  dynamic "parameter" {
    for_each = local.all_parameters
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-aurora-cluster-params"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# DB Parameter Group for Aurora instances
resource "aws_db_parameter_group" "aurora_instance" {
  count  = var.use_aurora ? 1 : 0
  name   = "${var.project_name}-${var.environment}-aurora-instance-params"
  family = local.parameter_group_family

  # Aurora instance parameters (different from cluster parameters)
  dynamic "parameter" {
    for_each = var.engine == "postgres" ? [
      {
        name  = "shared_preload_libraries"
        value = "pg_stat_statements"
      },
      {
        name  = "pg_stat_statements.track"
        value = "ALL"
      }
    ] : [
      {
        name  = "innodb_print_all_deadlocks"
        value = "1"
      }
    ]
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-aurora-instance-params"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Random password if not provided
resource "random_password" "master" {
  count   = var.master_password == null ? 1 : 0
  length  = 16
  special = true
}

# KMS Key for encryption
resource "aws_kms_key" "db" {
  count                   = var.storage_encrypted ? 1 : 0
  description             = "KMS key for ${var.project_name}-${var.environment} database encryption"
  deletion_window_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-db-kms-key"
  })
}

resource "aws_kms_alias" "db" {
  count         = var.storage_encrypted ? 1 : 0
  name          = "alias/${var.project_name}-${var.environment}-db-key"
  target_key_id = aws_kms_key.db[0].key_id
}