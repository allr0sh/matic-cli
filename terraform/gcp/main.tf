# Provider and Terraform Configuration 

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.55.0"
    }
  }
  required_version = ">= 1.2.0"
}

provider "google" {
  project = var.PROJECT_ID
  region  = var.REGION_GCP
  zone    = var.ZONE
}

# Network and Subnet Creation
resource "google_compute_network" "vpc_network" {
  name                    = "${var.VM_NAME}-vpc"
  auto_create_subnetworks = false
  mtu                     = 1460
}

resource "google_compute_subnetwork" "public-subnetwork" {
  name          = "${var.VM_NAME}-public-subnet"
  ip_cidr_range = var.SUBNET_CIDR_RANGE
  region        = var.REGION_GCP
  network       = google_compute_network.vpc_network.name

}

# Reserve Static IP Address
resource "google_compute_address" "bor_static_ip" {
  count = (var.DOCKERIZED == "yes") ? 0 : (var.BOR_VALIDATOR_COUNT + var.BOR_SENTRY_COUNT + var.BOR_ARCHIVE_COUNT)

  name  = format("%s-bor-%s", var.VM_NAME, count.index)

}

resource "google_compute_address" "erigon_static_ip" {
  count = (var.DOCKERIZED == "yes") ? 0 : (var.ERIGON_VALIDATOR_COUNT + var.ERIGON_SENTRY_COUNT + var.ERIGON_ARCHIVE_COUNT)

  name  = format("%s-erigon-%s", var.VM_NAME, count.index)

}

resource "google_compute_address" "docker_static_ip" {
  count = (var.DOCKERIZED == "yes") ? 1 : 0

  name  = format("%s-docker-%s", var.VM_NAME, count.index)
}


# GCP Compute VM using Machine Image
resource "google_compute_instance" "bor_node_server" {

  count = (var.DOCKERIZED == "yes") ? 0 : (var.BOR_VALIDATOR_COUNT + var.BOR_SENTRY_COUNT + var.BOR_ARCHIVE_COUNT)

  name         = "${var.VM_NAME}-bor-${count.index + 1}"
  machine_type = (count.index >= var.BOR_VALIDATOR_COUNT + var.BOR_SENTRY_COUNT) ? var.BOR_ARCHIVE_MACHINE_TYPE : var.BOR_MACHINE_TYPE

  boot_disk {
    initialize_params {
      image = var.INSTANCE_IMAGE

      size = (count.index >= var.BOR_VALIDATOR_COUNT + var.BOR_SENTRY_COUNT) ? var.BOR_ARCHIVE_DISK_SIZE_GB : var.BOR_DISK_SIZE_GB

      type = (count.index >= var.BOR_VALIDATOR_COUNT + var.BOR_SENTRY_COUNT) ? var.BOR_ARCHIVE_VOLUME_TYPE_GCP : var.BOR_VOLUME_TYPE_GCP
    }
  }

  metadata = {
    ssh-keys = "${var.USER}:${file(var.GCE_PUB_KEY_FILE)}"
  }

  network_interface {
    network    = google_compute_network.vpc_network.name
    subnetwork = google_compute_subnetwork.public-subnetwork.name

    access_config {
      //IP
      nat_ip = google_compute_address.bor_static_ip[count.index].address
    }
  }
  tags = ["matic-cli"]
  labels = {
    name     = "polygon-matic"
    instance = "bor"
  }
}

resource "google_compute_instance" "erigon_node_server" {

  count = (var.DOCKERIZED == "yes") ? 0 : (var.ERIGON_VALIDATOR_COUNT + var.ERIGON_SENTRY_COUNT + var.ERIGON_ARCHIVE_COUNT)

  name = "${var.VM_NAME}-erigon-${count.index + 1}"

  machine_type = (count.index >= var.ERIGON_VALIDATOR_COUNT + var.ERIGON_SENTRY_COUNT) ? var.ERIGON_ARCHIVE_MACHINE_TYPE : var.ERIGON_MACHINE_TYPE

  boot_disk {
    initialize_params {
      image = var.INSTANCE_IMAGE
      size  = (count.index >= var.ERIGON_VALIDATOR_COUNT + var.ERIGON_SENTRY_COUNT) ? var.ERIGON_ARCHIVE_DISK_SIZE_GB : var.ERIGON_DISK_SIZE_GB
      type  = (count.index >= var.ERIGON_VALIDATOR_COUNT + var.ERIGON_SENTRY_COUNT) ? var.ERIGON_ARCHIVE_VOLUME_TYPE_GCP : var.ERIGON_VOLUME_TYPE_GCP
    }
  }

  metadata = {
    ssh-keys = "${var.USER}:${file(var.GCE_PUB_KEY_FILE)}"
  }

  network_interface {
    network    = google_compute_network.vpc_network.name
    subnetwork = google_compute_subnetwork.public-subnetwork.name

    access_config {
      //IP
      nat_ip = google_compute_address.erigon_static_ip[count.index].address
    }
  }
  tags = ["matic-cli"]
  labels = {
    name     = "polygon-matic",
    instance = "erigon"

  }
}


resource "google_compute_instance" "dockerized_server" {

  count = (var.DOCKERIZED == "yes") ? 1 : 0

  name         = "${var.VM_NAME}-docker-${count.index + 1}"
  machine_type = var.BOR_MACHINE_TYPE

  boot_disk {
    initialize_params {
      image = var.INSTANCE_IMAGE
      size  = var.BOR_DISK_SIZE_GB
      type  = var.BOR_VOLUME_TYPE_GCP
    }
  }

  metadata = {
    ssh-keys = "${var.USER}:${file(var.GCE_PUB_KEY_FILE)}"
  }

  network_interface {
    network    = google_compute_network.vpc_network.name
    subnetwork = google_compute_subnetwork.public-subnetwork.name

    access_config {
      //IP
      nat_ip = google_compute_address.docker_static_ip[count.index].address
    }
  }
  tags = ["matic-cli"]
  labels = {
    name = "polygon-matic",
    instance = "docker"
  }
}


resource "google_compute_firewall" "firewall_rules" {
  name    = format("%s-%s", var.VM_NAME, var.FW_RULE_SUFFIX)
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = var.PORTS_IN
  }
  source_ranges = var.SG_CIDR_BLOCKS
}

resource "google_compute_firewall" "all_node_instances" {
  name          = "allow-all-egress"
  project       = var.PROJECT_ID
  network       = google_compute_network.vpc_network.name
  direction     = "EGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["all-node-instances"]
  allow {
    protocol = "all"
  }
}

# output values
output "cloud" {
  value = "gcp"
}

output "instance_dns_ips" {
  value = concat(google_compute_address.bor_static_ip.*.address, google_compute_address.erigon_static_ip.*.address, google_compute_address.docker_static_ip.*.address)
}

output "instance_ids" {
  value = concat(google_compute_instance.bor_node_server.*.id, google_compute_instance.erigon_node_server.*.id, google_compute_instance.dockerized_server.*.id)
}
