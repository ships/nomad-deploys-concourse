job "concourse" {
  datacenters = ["dc1"]
  type = "service"

  update {
    max_parallel = 1
    min_healthy_time = "10s"
    healthy_deadline = "3m"
    progress_deadline = "10m"
    auto_revert = false
    auto_promote = true
    canary = 1
  }

  migrate {
    max_parallel = 1
    health_check = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "5m"
  }

  vault {
    policies = ["concourse"]

    change_mode = "noop"
  }

# groups


  group "web" {
    count = 1

    restart {
      attempts = 2
      interval = "30m"
      delay = "15s"
      mode = "fail"
    }

    task "web" {
      driver = "docker"

      config {
        image = "concourse/concourse"
        dns_servers = [ "${attr.unique.network.ip-address}" ]
        args = [
          "web",
          "--tsa-host-key", "${NOMAD_SECRETS_DIR}/concourse-keys/tsa_host_key",
          "--tsa-authorized-keys", "${NOMAD_SECRETS_DIR}/concourse-keys/authorized_worker_keys",
          "--tsa-session-signing-key", "${NOMAD_SECRETS_DIR}/concourse-keys/session_signing_key",
          "--vault-ca-cert", "${NOMAD_SECRETS_DIR}/ssl/vault/vault_ca_certificate.pem",
					"--vault-client-token", "${VAULT_TOKEN}",
        ]

        port_map = {
          "atc" = 8080
          "tsa" = 2222
        }
      }

      env {
        CONCOURSE_POSTGRES_USER = "pgadmin"
        CONCOURSE_POSTGRES_DATABASE = "concourse"
        CONCOURSE_MAIN_TEAM_LOCAL_USER = "test"
        CONCOURSE_VAULT_PATH_PREFIX = "/kvv1/concourse"
      }

      template {
        data = <<EOH
          CONCOURSE_EXTERNAL_URL="http://ci.service.skelter:50808"
          {{ with service "postgres" }}
          {{ with index . 0}}
          CONCOURSE_POSTGRES_HOST="{{.Address}}"
          CONCOURSE_POSTGRES_PORT="{{.Port}}"
          {{end}}{{end}}
					{{with secret "kv/data/ci/web"}}
					CONCOURSE_POSTGRES_PASSWORD={{.Data.data.pg_password}}
          CONCOURSE_GITHUB_CLIENT_ID={{.Data.data.github_client_id}}
          CONCOURSE_GITHUB_CLIENT_SECRET={{.Data.data.github_client_secret}}
          CONCOURSE_MAIN_TEAM_GITHUB_USER={{.Data.data.github_main_user}}
					{{end}}
          {{ with service "active.vault" }}
          {{ with index . 0 }}
          CONCOURSE_VAULT_URL="https://active.vault.service.skelter:{{.Port}}"
          {{end}}
          {{end}}
        EOH

        env = true
        destination = "run/secrets.env"
				change_mode = "restart"
      }

      template {
        source = "/var/vcap/jobs/nomad-client/ssl/vault_ca_certificate.pem"
			  destination = "secrets/ssl/vault/vault_ca_certificate.pem"
      }

      template {
        data = <<EOH
{{with secret "kv/data/ci/web"}}{{.Data.data.tsa_host_key}}{{end}}EOH

        destination = "secrets/concourse-keys/tsa_host_key"
      }

      template {
        data = <<EOH
{{with secret "kv/data/ci/web"}}{{.Data.data.authorized_worker_keys}}{{end}}EOH

        destination = "secrets/concourse-keys/authorized_worker_keys"
      }

      template {
        data = <<EOH
{{with secret "kv/data/ci/web"}}{{.Data.data.session_signing_key}}{{end}}EOH

        destination = "secrets/concourse-keys/session_signing_key"
      }

      resources {
        cpu    = 2000 # 2000 MHz
        memory = 1536
        network {
          port "atc" {
            static = 50808
          }
          port "tsa" {}
        }
      }

      service {
        name = "ci-tsa"
        tags = ["internal"]
        port = "tsa"
      }

      service {
        name = "ci"
        tags = ["global"]
        port = "atc"
        check {
          name     = "alive"
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }

  group "worker" {
    count = 2

    restart {
      attempts = 2
      interval = "30m"
      delay = "15s"
      mode = "fail"
    }

    ephemeral_disk {
      size = 30000
    }

    task "work" {
      driver = "docker"

      config {
        image = "concourse/concourse"
        dns_servers = [ "${attr.unique.network.ip-address}" ]
        privileged = true
        args = [
          "worker",
          "--work-dir", "${NOMAD_TASK_DIR}/worker",
          "--tsa-worker-private-key", "${NOMAD_SECRETS_DIR}/concourse-keys/worker_ssh_key",
          "--tsa-public-key", "${NOMAD_SECRETS_DIR}/concourse-keys/tsa_host_key.pub",
          "--tsa-host", "${CONCOURSE_TSA_HOST}",
          "--baggageclaim-bind-port",  "${NOMAD_PORT_baggageclaim}",
          "--bind-port", "${NOMAD_PORT_garden}",
        ]
      }

      template {
        data = <<EOH
{{with secret "kv/data/ci/worker"}}{{.Data.data.tsa_host_key_pub}}{{end}}EOH

        destination = "secrets/concourse-keys/tsa_host_key.pub"
      }

      template {
        data = <<EOH
{{with secret "kv/data/ci/worker"}}{{.Data.data.worker_ssh_key}}{{end}}EOH

        destination = "secrets/concourse-keys/worker_ssh_key"
      }

      template {
        data = <<EOH
        {{ with service "ci-tsa" }}
        {{ with index . 0}}
        CONCOURSE_TSA_HOST="{{.Address}}:{{.Port}}"
        {{end}}{{end}}
        EOH

        env = true
        destination = "run/secrets.env"
      }


      resources {
        cpu    = 2000 # 1000 MHz
        memory = 1024 # 512MB
        network {
          port "garden" {}
          port "baggageclaim" {}
          port "garbagecollection" {}
        }
      }
    }
  }
}
