check "replica_range_is_valid" {
  assert {
    condition     = var.container_max_replicas >= var.container_min_replicas
    error_message = "container_max_replicas must be greater than or equal to container_min_replicas."
  }
}

check "container_consumption_allocation_is_valid" {
  assert {
    condition = contains([
      "0.25|0.5Gi",
      "0.5|1Gi",
      "0.75|1.5Gi",
      "1|2Gi",
      "1.25|2.5Gi",
      "1.5|3Gi",
      "1.75|3.5Gi",
      "2|4Gi",
    ], "${var.container_cpu}|${var.container_memory}")
    error_message = "container_cpu and container_memory must form a supported Azure Container Apps Consumption allocation."
  }
}

check "subnets_are_distinct" {
  assert {
    condition     = var.container_apps_subnet_cidr != var.postgresql_subnet_cidr
    error_message = "Container Apps and PostgreSQL must use separate dedicated subnets."
  }
}
