# Guide

> Deploy and operate the KubeClaw infrastructure step by step.

---

LLMS index: [llms.txt](/kubeclaw/llms.txt)

---

Follow these guides to provision the infrastructure, configure the nodes, and
deploy OpenClaw on Kubernetes.

---

Section pages:

- [Dev Container](/kubeclaw/docs/guide/dev-container/): Set up the aibox Dev Container that carries every tool this project needs.
- [Infrastructure (OpenTofu)](/kubeclaw/docs/guide/infrastructure/): Configure terraform.tfvars, run tofu apply, and set up SSH access to the new nodes.
- [Cloudflare Tunnel Setup](/kubeclaw/docs/guide/cloudflare-tunnel/): Create the tunnel, route SSH through it, and protect it with a Cloudflare Access policy.
- [Server Management (Ansible)](/kubeclaw/docs/guide/ansible/): Generate the inventory and run the update, hardening, NAT64, and Kubernetes-prerequisite playbooks.
- [Kubernetes (kubeadm)](/kubeclaw/docs/guide/kubernetes/): Bootstrap a dual-stack kubeadm cluster with Cilium CNI and the Hetzner CSI driver.
- [OpenClaw Deployment](/kubeclaw/docs/guide/openclaw/): Deploy OpenClaw into an egress-restricted namespace with Cilium FQDN policies.
