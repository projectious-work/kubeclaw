# Password Management

## Which credentials exist?

| Credential | Purpose | Storage |
|------------|---------|---------|
| Hetzner API Token | Create infrastructure | `terraform.tfvars` |
| Root password | Emergency web console | `terraform.tfvars` |
| SSH private keys | Server access | `~/.ssh/` or password manager |
| Cloudflare Tunnel token | Tunnel auth | Cloudflare Dashboard |

## Recommended Dashlane structure

```
📁 K8s Cluster
├── 🔐 Hetzner API Token
│   └── Token: xxx
├── 🔐 Root Password
│   └── Password: xxx
├── 📝 SSH Keys (Secure Note)
│   ├── Control Node Private Key: ...
│   ├── Control Node Public Key: ...
│   ├── Worker Node Private Key: ...
│   └── Worker Node Public Key: ...
└── 🔐 Cloudflare Tunnel Token
    └── Token: xxx
```

## Securing terraform.tfvars

`terraform.tfvars` contains sensitive data. Options:

1. **Do not commit**: exclude via `.gitignore` (default)
2. **Encrypt**: with `git-crypt` or `sops`
3. **Use environment variables** instead of tfvars:
   ```bash
   export TF_VAR_hcloud_token="xxx"
   export TF_VAR_root_password="xxx"
   ```
