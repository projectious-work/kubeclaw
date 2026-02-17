# Cilium Dual-Stack Pod Network

!!! success "Implemented"
    This feature has been implemented. The [Kubernetes guide](../guide/kubernetes.md) now uses dual-stack `kubeadm init` and Cilium with `ipv6.enabled=true` as the standard configuration.

## Summary

The cluster uses **dual-stack networking** (IPv4 + IPv6) in the Cilium pod network. Every pod gets both an IPv4 address (from `10.244.0.0/16`) for internal cluster communication and an IPv6 address (from `fd00:10:244::/48`) for external connectivity via DNS64/NAT64.

This eliminates the need for `hostNetwork: true` on any pod, which means:

- **Cilium FQDN egress policies** apply to all pods (CoreDNS, CSI controller, OpenClaw)
- **No port conflicts** from hostNetwork bindings
- **Full pod network isolation** is maintained by Cilium

## How It Works

1. **kubeadm init** with dual-stack CIDRs: `--pod-network-cidr=10.244.0.0/16,fd00:10:244::/48 --service-cidr=10.96.0.0/12,fd00:10:96::/108`
2. **Cilium** with `ipv4.enabled=true`, `ipv6.enabled=true`, `enableIPv6Masquerade=true`
3. **VXLAN tunnel** runs over IPv4 underlay (proven, stable -- nodes communicate via `10.0.0.0/24`)
4. **CoreDNS** forwards to DNS64 resolvers (`2001:67c:2b0::4`) which synthesize AAAA records for IPv4-only domains
5. **Pods** route to `64:ff9b::/96` NAT64 addresses via their IPv6 address; Cilium masquerades to the node's public IPv6
6. **Cilium DNS proxy** intercepts DNS64-synthesized AAAA responses and maps them to FQDNs for policy enforcement

## Research Findings

The following questions were investigated before implementation:

| Question | Answer |
|----------|--------|
| Does `ipv6.enabled=true` require kubeadm dual-stack CIDRs? | **Yes** -- kubeadm must be initialized with both IPv4 and IPv6 CIDRs. CIDRs cannot be changed after init. |
| Can Cilium manage IPv6 IPAM independently? | **Yes** (cluster-pool mode), but Kubernetes IPAM with kubeadm-allocated CIDRs is simpler. |
| Does VXLAN work with IPv6 pod addresses? | **Yes** -- VXLAN tunnel runs over IPv4 underlay (auto mode), encapsulating both IPv4 and IPv6 pod traffic. |
| Do FQDN egress rules work with DNS64? | **Yes** -- Cilium's DNS proxy intercepts all DNS responses (A and AAAA). DNS64-synthesized AAAA records are just AAAA records from Cilium's perspective. |
| Can pods route to `64:ff9b::/96`? | **Yes** -- via `enableIPv6Masquerade=true` (default). Pod IPv6 traffic is masqueraded to the node's public IPv6. |
| Does CoreDNS still need `hostNetwork`? | **No** -- with dual-stack, CoreDNS has an IPv6 pod address and can reach DNS64 resolvers via masquerade. |

## References

- [Cilium IPv6 tunnel support (PR #40324)](https://github.com/cilium/cilium/pull/40324) -- merged into v1.19.0
- [Cilium Cluster-Pool IPAM](https://docs.cilium.io/en/stable/network/concepts/ipam/cluster-pool/)
- [Kubernetes dual-stack docs](https://kubernetes.io/docs/concepts/services-networking/dual-stack/)
- [kubeadm dual-stack support](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/dual-stack-support/)
- [CoreDNS dns64 plugin](https://coredns.io/plugins/dns64/)
- [NAT64/DNS64 on KubeClaw](../guide/nat64.md)
