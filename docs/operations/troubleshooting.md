# Troubleshooting

## Infrastructure Issues

### cloudflared won't start (IPv6-only)

Check `/etc/cloudflared/config.yml`:

```yaml
edge-ip-version: "6"
```

!!! important
    The value must be a string in quotes (`"6"`, not `6`). Cloudflared defaults to IPv4 connections to Cloudflare's edge servers.

### SSH key rotation failed

1. Connect via Hetzner web console (root password)
2. Add the new key manually:
   ```bash
   echo "ssh-ed25519 AAAA..." >> /home/kubernetes-admin/.ssh/authorized_keys
   ```

### Ansible cannot connect

Check:

1. Is `cloudflared` installed locally?
2. Is the tunnel running? (`cloudflared tunnel list`)
3. Is the inventory correct? (`./scripts/generate-ansible-inventory.sh`)
4. Is the ssh-agent running with keys loaded? (`ssh-add -l`)

### State lost / keys gone

With auto-generated keys:

1. Connect via web console (root)
2. Create new keys
3. Add them to `authorized_keys`
4. Import servers into new state:
   ```bash
   tofu import hcloud_server.master_control_node <server-id>
   ```

### SSH connection via tunnel fails

**Checklist**:

1. Is `cloudflared` installed locally? (`which cloudflared`)
2. Is the ProxyCommand path correct?
3. Is the Cloudflare Access Application configured?
4. Is the tunnel shown as "Connected" in Cloudflare?

### Hetzner Web Console does not work

- Use the "Send Clipboard" button above the console
- Use a simple password without special characters for the initial login
- Alternative: Create a temporary Admin Node with a public IP

### Cloud-Init password does not work

**Cause**: The old `chpasswd.list` syntax is deprecated.

**Solution**: Use the new syntax:

```yaml
users:
  - name: root
    plain_text_passwd: 'your-password'
    lock_passwd: false
```

## Kubernetes Issues

### Worker nodes not joining

```bash
# On the worker node, check kubelet logs
journalctl -xeu kubelet

# Common issues:
# - Swap not disabled: swapoff -a
# - containerd not running: systemctl status containerd
# - Port 6443 not reachable: curl -k https://10.0.0.2:6443
# - Token expired (24h default): kubeadm token create --print-join-command
```

### Cilium pods not ready

```bash
# Check Cilium status
cilium status

# Check Cilium pod logs
kubectl logs -n kube-system -l k8s-app=cilium

# Check Cilium endpoint status
cilium endpoint list
```

### Network policy blocking traffic unexpectedly

```bash
# Check which policies apply
kubectl get ciliumnetworkpolicies -n apps-restricted

# Check if FQDN rules are resolving
kubectl exec -n kube-system -it \
  $(kubectl get pods -n kube-system -l k8s-app=cilium -o name | head -1) \
  -- cilium fqdn cache list
```

### CSI volume not attaching

```bash
kubectl describe pvc -n apps-restricted
kubectl get events -n apps-restricted --sort-by='.lastTimestamp'
```

### Pod not starting (general)

```bash
kubectl describe pod -n <namespace> <pod-name>
kubectl logs -n <namespace> <pod-name> --previous
```

### OpenClaw Pod not starting

```bash
kubectl describe pod -n apps-restricted -l app=openclaw
kubectl logs -n apps-restricted -l app=openclaw --previous
```

### Cloudflare Tunnel not connecting (K8s workload)

```bash
kubectl logs -n system-unrestricted -l app=cloudflared
```
