terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

provider "google" {
  project = "myproj-xyz"
  region  = "us-central1"
  zone    = "us-central1-c"
}

# Full spec: https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_database_instance
resource "google_sql_database_instance" "main" {
  name             = "main-instance"
  database_version = "POSTGRES_17"
  deletion_protection = false

  settings {
    # Lowest Enterprise Plus option is db-perf-optimized-N-2 with 2 vCPU / 16 G
    # For prod one could start with db-perf-optimized-N-32 or db-perf-optimized-N-48 to be on the safe side
    tier = "db-perf-optimized-N-32"
    edition = "ENTERPRISE_PLUS"  # PS ENTERPRISE_PLUS only makes sense for prod envs, for dev/testing ENTERPRISE is around to 30% cheaper

    ip_configuration {
      authorized_networks {
        name  = "allow-all"
        value = "0.0.0.0/0"
      }
    }
    
    insights_config {
      query_insights_enabled  = "true"
    }

    # PS GCP does some basic level of tuning based on HW, so need less params compared to on-prem. On the other hand a lot of settings can't be changed
    # at all on global level, only on role or database (preferred) level, like "jit".
    # PS2 normal Postgres "human readable" values can't be used mostly, see units from: https://cloud.google.com/sql/docs/postgres/flags

    # Below settings assume a 48 vCPU / 384 GB RAM machine !!!

    # max_connection needs tuning only for smaller SKUs, from 120GB RAM it's 1000, which should be more than enough if app pooling used.
    # Still it's recommended to lower from 1K, if no need is seen - as a general best practice, to safeguard against "bricking" the DB in case some slow queries slip through.
    database_flags {
      name  = "max_connections"
      value = "700"  # Postgres default 100
    }

    # CPU dependent, max($NUM_CORES, 8)
    database_flags {
      name  = "max_worker_processes"
      value = "48"  # Postgres default 8
    }

    # CPU dependent, $NUM_CORES/2
    database_flags {
      name  = "max_parallel_workers"
      value = "24"  # Postgres default 8
    }

    # database_flags {
    #   name  = "max_parallel_workers_per_gather"
    #   value = "4"  # Postgres default 2. Increase for larger vCPU machines / datasets with analytics queries
    # }

    database_flags {
      name  = "max_parallel_maintenance_workers"
      value = "4"  # Postgres default 2
    }

    database_flags {
      name  = "effective_io_concurrency"
      value = "100"
    }

    database_flags {
      name  = "random_page_cost"
      value = "1.5"
    }
    
    database_flags {
      name  = "work_mem"
      value = "131072"  # 128MB
    }
    
    database_flags {
      name  = "maintenance_work_mem"
      value = "1048576"  # 1GB
    }
    
    database_flags {
      name  = "max_wal_size"
      value = "10000"  # 10GB
    }
    
    database_flags {
      name  = "checkpoint_timeout"
      value = "600"  # 10min
    }

    database_flags {
      name  = "idle_in_transaction_session_timeout"
      value = "3600000"  # 1h
    }

    database_flags {
      name  = "log_min_duration_statement"
      value = "2000"  # log queries slower than 2s
    }

    database_flags {
      name  = "log_temp_files"
      value = "1000000"  # 1GB
    }

    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }

    database_flags {
      name  = "wal_compression"
      value = "zstd"
    }
    
    database_flags {
      name  = "default_toast_compression"
      value = "lz4"
    }
    
    database_flags {
      name  = "autovacuum_vacuum_scale_factor"
      value = "0.05"
    }
    
    database_flags {
      name  = "autovacuum_analyze_scale_factor"
      value = "0.05"
    }    

    database_flags {
      name  = "cloudsql.enable_auto_explain"
      value = "on"
    }
    
    database_flags {
      name  = "auto_explain.log_min_duration"
      value = "2000"
    }
        
    database_flags {
      name  = "auto_explain.log_analyze"
      value = "on"
    }
    
    database_flags {
      name  = "auto_explain.log_timing"
      value = "off"
    }
    
    database_flags {
      name  = "auto_explain.sample_rate"
      value = "0.1"
    }
    
    database_flags {
      name  = "pg_stat_statements.track_utility"
      value = "off"
    }
    
  }
}


resource "random_password" "postgres_password" {
  length  = 20
  special = false
}

resource "google_sql_user" "postgres_user" {
  name     = "testapp1"
  instance = google_sql_database_instance.main.name
  password = random_password.postgres_password.result
}


output "public_ip_address" {
  description = "The public IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.main.public_ip_address
}


output "public_connstr" {
  description = "PostgreSQL connection string"
  value       = "postgresql://${google_sql_user.postgres_user.name}:${random_password.postgres_password.result}@${google_sql_database_instance.main.public_ip_address}:5432/postgres?sslmode=require"
  sensitive = true
}
