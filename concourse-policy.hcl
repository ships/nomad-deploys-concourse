path "kv/data/ci/*" {
  capabilities = ["read", "list"]
}

path "kvv1/concourse/*" {
  capabilities = ["read"]
}

path "pki/issue/skelter-services" {
  capabilities = ["create","read","update","delete"]
}
