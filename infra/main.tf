terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

# Authentication comes from DIGITALOCEAN_TOKEN, never a committed variable.
provider "digitalocean" {}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "size" {
  type    = string
  default = "s-4vcpu-8gb"
  validation {
    condition     = contains(["s-2vcpu-4gb", "s-4vcpu-8gb"], var.size)
    error_message = "Choose the $24 4GB or $48 8GB Basic size; verify pricing before applying."
  }
}

resource "digitalocean_ssh_key" "valheim" {
  name       = "valheim-wsl"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "digitalocean_droplet" "valheim" {
  name       = "valheim"
  region     = "nyc3"
  size       = var.size
  image      = "ubuntu-24-04-x64"
  ssh_keys   = [digitalocean_ssh_key.valheim.fingerprint]
  monitoring = true
  backups    = false
  user_data  = file("${path.module}/cloud-init.yaml")
  tags       = ["valheim"]

  # World saves live on this disk. Back up before any deliberate replacement.
  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_firewall" "valheim" {
  name        = "valheim"
  droplet_ids = [digitalocean_droplet.valheim.id]
  # No public SSH. Administration travels through Tailscale.
  inbound_rule {
    protocol         = "udp"
    port_range       = "2456-2457"
    source_addresses = ["0.0.0.0/0"]
  }
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

output "server_ip" {
  value = digitalocean_droplet.valheim.ipv4_address
}
