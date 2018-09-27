variable "project" {
  default = "example"
}

variable "domain_name" {
  default = "example-project.com"
}

variable "do_token" {}

variable "do_region" {
  default = "lon1"
}

variable "ssh_fingerprint" {}

variable "ssh_public_key" {
  default = "./secrets/id_rsa.pub"
}

variable "ssh_private_key" {
  default = "./secrets/id_rsa"
}

variable "number_of_nodes" {
  default = "1"
}

variable "size_node" {
  default = "2gb"
}

provider "digitalocean" {
  token = "${var.do_token}"
  version = "~> 0.1"
}

resource "digitalocean_ssh_key" "default" {
  name       = "${var.project}-terraform"
  public_key = "${file("${var.ssh_public_key}")}"
}

resource "digitalocean_droplet" "manager" {
    depends_on = ["digitalocean_ssh_key.default"]
    image = "coreos-stable"
    name = "${var.project}-swarm-manager"
    region = "${var.do_region}"
    size = "${var.size_node}"
    private_networking = true
    ssh_keys = ["${split(",", var.ssh_fingerprint)}"]

    provisioner "file" {
      source      = "./00-init.sh"
      destination = "/tmp/00-init.sh"
      connection {
        type        = "ssh"
        user        = "core"
        private_key = "${file(var.ssh_private_key)}"
      }
    }

    provisioner "file" {
      source      = "./01-manager.sh"
      destination = "/tmp/01-manager.sh"
      connection {
        type        = "ssh"
        user        = "core"
        private_key = "${file(var.ssh_private_key)}"
      }
    }

    provisioner "remote-exec" {
      inline = [
        "export PRIVATE_IP=\"${self.ipv4_address_private}\"",
        "export PUBLIC_IP=\"${self.ipv4_address}\"",
        "chmod +x /tmp/00-init.sh /tmp/01-manager.sh",
        "sudo -E /tmp/00-init.sh",
        "sudo -E /tmp/01-manager.sh",
        "docker network create --driver=overlay traefik-net",
        "docker service create --name traefik --constraint=node.role==manager --publish 80:80 --publish 8080:8080 --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock --network traefik-net traefik --docker --docker.swarmMode --docker.domain=${var.domain_name} --docker.watch --api",
        "docker service create --name whoami0 --label \"traefik.frontend.rule=HostRegexp:{catchall:.*}\" --label \"traefik.frontend.priority=1\" --label \"traefik.docker.network=traefik-net\" --label \"traefik.port=80\" --network traefik-net emilevauge/whoami"
      ]
      connection {
        type        = "ssh"
        user        = "core"
        private_key = "${file(var.ssh_private_key)}"
      }
    }

    provisioner "local-exec" {
        command = <<EOF
            scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${var.ssh_private_key} core@${self.ipv4_address}:/tmp/join secrets/join.token
EOF
    }

}

resource "digitalocean_droplet" "worker" {
    depends_on = ["digitalocean_droplet.manager"]
    count = "${var.number_of_nodes}"
    image = "coreos-stable"
    name = "${var.project}-${format("swarm-worker-%02d", count.index + 1)}"
    region = "${var.do_region}"
    size = "${var.size_node}"
    private_networking = true
    ssh_keys = ["${split(",", var.ssh_fingerprint)}"]

    provisioner "file" {
      source      = "./00-init.sh"
      destination = "/tmp/00-init.sh"
      connection {
        type        = "ssh"
        user        = "core"
        private_key = "${file(var.ssh_private_key)}"
      }
    }

    provisioner "file" {
      source      = "./secrets/join.token"
      destination = "/tmp/join.token"
      connection {
        type        = "ssh"
        user        = "core"
        private_key = "${file(var.ssh_private_key)}"
      }
    }

    provisioner "remote-exec" {
      inline = [
        "export PRIVATE_IP=\"${self.ipv4_address_private}\"",
        "export PUBLIC_IP=\"${self.ipv4_address}\"",
        "export JOIN_TOKEN=`cat /tmp/join.token | tr -d '\n'`",
        "export MANAGER_IP=\"${digitalocean_droplet.manager.ipv4_address}\"",
        "chmod +x /tmp/00-init.sh",
        "sudo -E /tmp/00-init.sh",
        "docker swarm join --token $JOIN_TOKEN $MANAGER_IP:2377",
        "docker network create --driver=overlay traefik-net",
      ]
      connection {
        type        = "ssh"
        user        = "core"
        private_key = "${file(var.ssh_private_key)}"
      }
    }

}

resource "digitalocean_certificate" "default" {
  name              = "${var.project}"
  private_key       = "${file("./secrets/certs/${var.domain_name}/key.pem")}"
  leaf_certificate  = "${file("./secrets/certs/${var.domain_name}/cert.pem")}"
}

resource "digitalocean_loadbalancer" "public" {
  depends_on = ["digitalocean_certificate.default", "digitalocean_droplet.manager", "digitalocean_droplet.worker"]
  name = "${var.project}"
  region = "${var.do_region}"

  forwarding_rule {
    entry_port = 443
    entry_protocol = "https"

    target_port = 80
    target_protocol = "http"

    certificate_id  = "${digitalocean_certificate.default.id}"
  }

  healthcheck {
    port = 8080
    protocol = "http"
    path = "/health"
  }

  droplet_ids = ["${digitalocean_droplet.manager.*.id}"]
}

resource "digitalocean_domain" "default" {
  depends_on = ["digitalocean_loadbalancer.public"]
  name       = "${var.domain_name}"
  ip_address = "${digitalocean_loadbalancer.public.ip}"
}

resource "digitalocean_record" "manager" {
  domain = "${digitalocean_domain.default.name}"
  type   = "A"
  name   = "swarm-manager.internal"
  value  = "${digitalocean_droplet.manager.ipv4_address_private}"
}

resource "digitalocean_record" "manager_public" {
  domain = "${digitalocean_domain.default.name}"
  type   = "A"
  name   = "manager"
  value  = "${digitalocean_droplet.manager.ipv4_address}"
}

resource "digitalocean_record" "worker" {
  count = "${var.number_of_nodes}"
  domain = "${digitalocean_domain.default.name}"
  type   = "A"
  name   = "${format("swarm-worker-%02d", count.index + 1)}.internal"
  value  = "${digitalocean_droplet.worker.0.ipv4_address_private}"
}