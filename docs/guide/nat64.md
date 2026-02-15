# NAT64/DNS64

The cluster is IPv6-only -- but many services (GitHub CDN, container registries, package repos) are IPv4-only. **NAT64/DNS64** provides transparent IPv4 reachability at the network layer, no application changes needed.

## How it works

1. **DNS64 resolver** receives a query for `github.com`, sees it only has an A record (IPv4), and synthesizes an AAAA record with the `64:ff9b::/96` prefix
2. Node sends traffic to the synthesized IPv6 address
3. **NAT64 gateway** translates the traffic to IPv4 and forwards it

Default resolvers are from [nat64.net](https://nat64.net/public-providers) (Nuremberg, Helsinki, Amsterdam) -- close to Hetzner's `fsn1` datacenter.

## Configuration

NAT64/DNS64 is **enabled by default** (`enable_nat64 = true`). Cloud-init configures it on new nodes automatically.

### For existing nodes

Run the Ansible playbook:

```bash
cd ansible
ansible-playbook playbooks/configure-nat64.yml
```

Limit to specific node groups:

```bash
ansible-playbook playbooks/configure-nat64.yml --limit control_nodes
```

Override resolvers:

```bash
ansible-playbook playbooks/configure-nat64.yml \
  -e '{"dns64_resolvers":["2a01:4f8:c2c:123f::1"]}'
```

### Disabling NAT64

If you set up your own DNS infrastructure:

```hcl
# terraform.tfvars
enable_nat64 = false
```

## Verification

```bash
# DNS64 synthesis (should show AAAA record with 64:ff9b:: prefix)
resolvectl query github.com

# End-to-end connectivity
curl -6 https://github.com
```

## Technical details

### What cloud-init configures

- DNS64 resolvers in `/etc/systemd/resolved.conf.d/dns64.conf`
- NAT64 route: `64:ff9b::/96` via the default IPv6 gateway
- `networkd-dispatcher` script to persist the route across reboots

### What the Ansible playbook configures

The same as cloud-init, plus:

- Removes old Hetzner DNS UFW rules on worker nodes
- Adds DNS64 resolver allow rules in UFW (workers only)
- Adds NAT64 prefix UFW rule (workers only)
- Verifies DNS64 resolution and NAT64 connectivity

### Worker node specifics

Worker nodes have restricted outbound access. The NAT64 configuration adds:

- UFW rules allowing DNS to DNS64 resolvers (instead of Hetzner DNS)
- UFW rule allowing traffic to the `64:ff9b::/96` prefix
