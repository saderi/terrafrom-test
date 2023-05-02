provider "google" {
  credentials = var.credentials_file
  project     = var.project
  region      = var.region
  zone        = var.zone
}

resource "google_project_service" "compute_service" {
  project = var.project
  service = "compute.googleapis.com"
}

resource "google_compute_network" "privet_network" {
  name                    = "privet-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "privet_subnetwork" {
  name          = "privet-subnetwork"
  ip_cidr_range = "10.20.0.0/16"
  region        = "us-central1"
  network       = google_compute_network.privet_network.id
}

resource "google_compute_router" "router" {
  name    = "quickstart-router"
  network = google_compute_network.privet_network.self_link
}

resource "google_compute_router_nat" "nat" {
  name                               = "quickstart-router-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_route" "private_network_internet_route" {
  name             = "private-network-internet"
  dest_range       = "0.0.0.0/0"
  network          = google_compute_network.privet_network.self_link
  next_hop_gateway = "default-internet-gateway"
  priority    = 100
}

resource "google_compute_instance" "privet_nginx" {
  name                      = "privet-nginx"
  machine_type              = "f1-micro"
  zone                      = "us-central1-a"
  allow_stopping_for_update = true
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
  network_interface {
    network    = google_compute_network.privet_network.self_link
    subnetwork = google_compute_subnetwork.privet_subnetwork.self_link
  }

  tags = ["privet-nginx" ]
  
  metadata_startup_script = <<-EOF
#!/bin/bash
sudo apt-get update
sudo apt-get install nginx -y
EOF

}

resource "google_compute_instance_group" "nginx_group" {
  name        = "nginx-group"
  description = "Test instance group"

  instances = [
    google_compute_instance.privet_nginx.self_link
  ]

  named_port {
    name = "http"
    port = "80"
  }
}

resource "google_compute_health_check" "nginx_health_check" {
  name        = "nginx-health-check"
  description = "Health check via TCP"

  timeout_sec         = 5
  check_interval_sec  = 10
  healthy_threshold   = 3
  unhealthy_threshold = 2

  tcp_health_check {
    port_name          = "http"
  }

  depends_on = [
    google_project_service.compute_service
  ]
}

resource "google_compute_backend_service" "nginx-backend-service" {
  name                            = "nginx-backend-service"
  timeout_sec                     = 30
  connection_draining_timeout_sec = 10
  load_balancing_scheme = "EXTERNAL"
  protocol = "HTTP"
  port_name = "http"
  health_checks = [google_compute_health_check.nginx_health_check.self_link]
  backend {
    group = google_compute_instance_group.nginx_group.self_link
    balancing_mode = "UTILIZATION"
  }
}

resource "google_compute_target_http_proxy" "default" {
  name    = "nginx-proxy"
  url_map = google_compute_url_map.default.id
}

resource "google_compute_url_map" "default" {
  name            = "nginx-map"
  default_service = google_compute_backend_service.nginx-backend-service.self_link
}

resource "google_compute_forwarding_rule" "nginx-loadbalancer" {
  name                  = "nginx-forwarding-rule"
  ip_protocol           = "TCP"
  port_range            = 80
  load_balancing_scheme = "EXTERNAL"
  network_tier          = "STANDARD"
  target                = google_compute_target_http_proxy.default.id
}

resource "google_compute_firewall" "load_balancer_inbound" {
  name    = "nginx-load-balancer"
  network = google_compute_network.privet_network.self_link

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  direction = "INGRESS"
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags = ["privet-nginx"]
}
