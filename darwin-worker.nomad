job "concourse-darwin-worker" {
  datacenters = ["maeve"]
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

  group "worker" {
    count = 1

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
      driver = "raw_exec"

      config {
        command = "/usr/local/bin/concourse"
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
        memory = 2048
        network {
          port "garden" {}
          port "baggageclaim" {}
          port "garbagecollection" {}
        }
      }
    }
  }
}
