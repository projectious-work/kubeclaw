# Enable IPv6 in Cilium Pod Network

## Problem

The cluster runs on an IPv6-only Hetzner Cloud network with DNS64/NAT64 for IPv4 reachability. However, the Kubernetes pod network (Cilium with VXLAN) is IPv4-only (`10.244.0.0/16`). This means:

- Pods cannot reach external IPv6 addresses (DNS64 resolvers, public APIs)
- Pods cannot use NAT64 because they have no IPv6 connectivity to reach the NAT64 prefix (`64:ff9b::/96`)
- DNS64 synthesized AAAA records are useless to IPv4-only pods

**Current workaround**: Infrastructure pods that need external access (CoreDNS, hcloud-csi-controller) use `hostNetwork: true` to bypass the pod network and use the node's IPv6 stack directly. This works but is not scalable for application workloads -- it bypasses pod network isolation and can cause port conflicts.

## Goal

Enable IPv6 (dual-stack or IPv6-only) in the Cilium pod network so that all pods can natively reach external IPv6 destinations and use DNS64/NAT64 for IPv4-only services. This would:

- Eliminate the need for `hostNetwork: true` on CoreDNS and the CSI controller
- Allow application pods in `apps-restricted` to reach whitelisted external APIs (Anthropic, Telegram) without `hostNetwork`
- Maintain Cilium network policy enforcement on all traffic (which `hostNetwork` partially bypasses)

## Research Required

### 1. Cilium IPv6 / dual-stack configuration

Cilium supports IPv6 natively. Key Helm values to investigate:

```yaml
ipv6:
  enabled: true
ipam:
  operator:
    clusterPoolIPv6PodCIDRList:
      - "fd00::/104"  # ULA range for pod IPs
```

Questions to answer:

- Does enabling `ipv6.enabled=true` in Cilium require kubeadm re-initialization with dual-stack CIDRs, or can Cilium manage IPv6 IPAM independently?
- Can Cilium allocate IPv6 pod addresses alongside IPv4 (true dual-stack), or does it need to be IPv6-only?
- How does VXLAN encapsulation work with IPv6 pod addresses on an IPv6-only node network?

### 2. kubeadm dual-stack initialization

If kubeadm needs to know about the IPv6 pod CIDR, re-initialization is required:

```bash
sudo kubeadm init \
  --apiserver-advertise-address=10.0.0.2 \
  --pod-network-cidr=10.244.0.0/16,fd00::/104 \
  --service-cidr=10.96.0.0/12,fd01::/108 \
  --skip-phases=addon/kube-proxy
```

Questions to answer:

- Does the service CIDR also need to be dual-stack?
- Will existing IPv4-only ClusterIP services continue to work?
- What changes are needed in CoreDNS configuration for dual-stack services?

### 3. DNS64 integration

With IPv6-enabled pods, DNS resolution changes:

- Pods can reach the DNS64 resolvers directly (no `hostNetwork` needed for CoreDNS)
- CoreDNS could forward to DNS64 resolvers (`2001:67c:2b0::4`, `2001:67c:2b0::6`) since pods can route to them
- Alternatively, CoreDNS could use the [dns64 plugin](https://coredns.io/plugins/dns64/) to synthesize AAAA records itself, removing the dependency on external DNS64 resolvers

### 4. Cilium network policies with IPv6

- Do existing CiliumNetworkPolicies (FQDN-based egress rules) work with IPv6 pod addresses?
- Does FQDN-based filtering work when destinations resolve to NAT64-synthesized addresses?
- Are there any differences in how Cilium enforces policies on IPv6 vs IPv4 traffic?

### 5. NAT64 routing from pods

With IPv6 pod addresses, pods can reach the NAT64 prefix. Verify:

- Can pods route to `64:ff9b::/96` addresses through the node?
- Does the node need additional routing rules for NAT64 traffic originating from pods?
- Does Cilium's VXLAN or native routing mode affect NAT64 reachability?

## Implementation Plan (Draft)

!!! warning "This plan needs validation against the research questions above"

### Phase 1: Test on a fresh cluster

1. Initialize kubeadm with dual-stack CIDRs
2. Install Cilium with `ipv6.enabled=true` and IPv6 pod CIDR
3. Verify pods get both IPv4 and IPv6 addresses
4. Test DNS resolution and external connectivity from pods
5. Test Cilium network policies with IPv6 traffic

### Phase 2: Update CoreDNS

1. Remove `hostNetwork: true` from CoreDNS
2. Configure CoreDNS to forward to DNS64 resolvers (or enable the dns64 plugin)
3. Verify cluster DNS works for both internal and external names
4. Verify the host can still resolve cluster service names via CoreDNS

### Phase 3: Update infrastructure pods

1. Remove `hostNetwork: true` from hcloud-csi-controller
2. Verify CSI controller can reach `api.hetzner.cloud`
3. Remove UFW rule for port 53 (no longer needed if CoreDNS is not on hostNetwork)
4. Remove `--node-ip` kubelet flag if no longer required

### Phase 4: Update documentation

1. Update the Kubernetes guide (Steps 4 and 5)
2. Remove the "IPv6-only Network: Pod External Access" section
3. Update the CoreDNS and CSI sections to reflect the simpler configuration
4. Document any new Cilium Helm values in the reference section

## References

- [Cilium IPv6 documentation](https://docs.cilium.io/en/stable/network/concepts/ipam/cluster-pool/#ipv6)
- [kubeadm dual-stack documentation](https://kubernetes.io/docs/concepts/services-networking/dual-stack/)
- [CoreDNS dns64 plugin](https://coredns.io/plugins/dns64/)
- [NAT64/DNS64 on KubeClaw](../guide/nat64.md)
