# OpenShift Agent-Based Install Automation for KVM and Bare Metal

This playbook deploys OpenShift clusters on **KVM virtual machines**, **bare-metal servers**, or a **mix of both** using the Agent-based installer. It is designed for infrastructure clusters that may go on to host tenant workloads (O^3, HCP).

## What the Automation Does

The deploy playbook (`openshift-kvm-bm-cluster-deploy.yaml`) performs the following:

1. Tears down any existing cluster (idempotent re-deploy)
2. Loads shared and cluster-specific configuration
3. Sets up staging directories on localhost, hypervisor, and web server
4. Downloads `oc`, `openshift-install`, and `butane` binaries
5. Generates `install-config.yaml`, `agent-config.yaml`, and OpenShift manifests
6. Creates the Agent installer ISO and stages it (to the hypervisor for KVM, to the web server for bare metal)
7. Deploys KVM VMs via libvirt (for `type: kvm` nodes)
8. Mounts the Agent ISO via iDRAC virtual media and boots bare-metal nodes (for `type: bm` nodes)
9. Waits for bootstrap completion and cluster installation
10. Runs **post-install configuration** via `openshift-cluster-configure.yaml` (imported from the deploy playbook)

**Post-install** (`openshift-cluster-configure.yaml`; many plays tagged `post-install`):

11. Ejects virtual CD from bare-metal iDRAC (`kvm_bm` + `type: bm` only; tag `eject-virtual-cd`)
12. Configures an HTPasswd OAuth identity provider (`configure/openshift-auth-provider`)
13. Wipes additional data disks on worker nodes (when `disks` is defined)
14. Installs a cluster storage provider (ODF or LVM Operator), per `storage_provider`
15. Installs the NMState Operator
16. Installs OpenShift Virtualization (optional, controlled by `ocp_virt_install`)
17. Creates network bridges on worker nodes via NNCP
18. Installs and configures MetalLB with BGP peering
19. Installs Red Hat Advanced Cluster Management (RHACM)
20. Installs cert-manager (operator) and issues a Let’s Encrypt wildcard certificate for the apps ingress (Cloudflare DNS-01)
21. Sets cluster metadata ConfigMap (used by tenant clusters to discover storage classes)

The destroy playbook (`openshift-kvm-bm-cluster-deco.yaml`) removes KVM VMs, storage pools, and cleans host disks.

## Prerequisites

### KVM Hypervisor Host

- libvirt, QEMU/KVM, and related tools installed:

```bash
dnf install libguestfs-tools virt-install qemu-kvm libvirt -y
```

- A Linux bridge for VM networking (bridge name defined in vars)
- Sufficient disk space for VM images (path configured via `cluster_vms_storage_base_dir`)
- For block-device passthrough: LVM volumes or NVMe devices available on the host

### Bare-Metal Servers (if applicable)

- Dell servers with iDRAC (iDRAC credentials managed via Bitwarden)
- Network boot / virtual media capability via iDRAC
- The `dellemc.openmanage` Ansible collection handles ISO mounting and power operations

### External Services

- **DHCP** -- entries for each node MAC address with reserved IPs
- **DNS** -- `api.<cluster>.<domain>`, `api-int.<cluster>.<domain>`, `*.apps.<cluster>.<domain>`, and individual node hostnames
- **Load Balancer** -- ports 6443 + 22623 balanced to control-plane IPs; ports 80 + 443 balanced to worker IPs
- **Web Server** -- reachable from all nodes, serves the Agent ISO over HTTP (required for bare-metal nodes; KVM nodes get the ISO copied directly to the hypervisor)

### Control Node (where Ansible runs)

Install dependencies:

```bash
cd src/ansible
./update_env.sh
```

This installs Python packages (`requirements.txt`), Ansible Galaxy collections (`requirements.yaml`, including `community.general`), and the Bitwarden Secrets CLI.

## Configuration

All cluster variables live under `src/ocp-cluster-vars/vars/`. Each cluster has its own directory (e.g. `infra1/`) containing three files:

### `main.yaml` -- config loader

Lists the variable files to include (common, cluster-specific, and vault-encrypted credentials). No changes needed unless adding new variable files.

### `vars.yaml` -- cluster-specific variables

| Variable | Description |
|----------|-------------|
| `platform` | `"kvm"`, `"kvm_bm"`, or `"O^3"` |
| `base_domain` | Base DNS domain |
| `ocp_cluster_name` | Cluster name (must match the directory name) |
| `ocp_version` | OpenShift version (e.g. `"4.20"`) |
| `ocp_bin_channel` | Release channel (`stable`, `fast`, `candidate`) |
| `ocp_network_type` | CNI plugin (`OVNKubernetes`, `Cilium`, `Calico`) |
| `cluster_role` | `infra` or `tenant` |
| `cluster_vms_storage_base_dir` | Path on hypervisor for VM disk images |
| `libvirt_bridge_name` | Base name for the libvirt bridge (VLAN number appended) |
| `storage_provider` | `"odf"` or `"lvm"` |
| `ocp_virt_install` | `True` to install OpenShift Virtualization |
| `bridge_interface_name` | Name for the NNCP bridge on the deployed cluster |
| `external_ip_range` | MetalLB IP address pool range |
| `cluster_bgp_asn` | BGP ASN for MetalLB peering |

Storage provider variables (ODF or LVM) and operator channel versions are also defined here.

### `inventory.yaml` -- node definitions

Defines host groups: `hypervisor`, `webserver`, `control`, `worker`, and `ocp_nodes`.

**Control nodes** specify:

| Variable | Example | Description |
|----------|---------|-------------|
| `nic1.mac_address` | `02:00:00:be:30:19` | Pre-generated MAC for DHCP |
| `nic1.vlan` | `7` | VLAN tag |
| `type` | `kvm` | Node type |
| `cpu` | `6` | vCPU count |
| `memory` | `28` | RAM in GiB |
| `rhcos_os_disk_size` | `100G` | OS disk size |

**Worker nodes** can be `kvm` or `bm` and support heterogeneous configurations per host:

- **KVM workers** add `disks` for block or file passthrough (with `path_on_hv_host`, `target_dev`, `bus`, `speed`)
- **Bare-metal workers** add `virtual_media_uefi_path` for iDRAC boot and `disks` with physical device paths
- Workers can have dual NICs (`nic1` + `nic2`) for separate networks

Generate MAC addresses using the included script:

```bash
src/scripts/generate-mac.sh
```

### Credentials (Bitwarden)

Sensitive values (pull secret, SSH keys, iDRAC passwords, trust bundles, **Cloudflare API token** for Let’s Encrypt DNS-01) are retrieved at runtime from Bitwarden Secrets Manager. The vault-encrypted `credentials.yaml` stores the Bitwarden access token. Zone name and contact email for certificates are set in `common.yaml` (`cloudflare_zone_name`, `letsencrypt_email`).

## Deploy

```bash
cd src/ansible
export CLUSTER_NAME=infra1
ansible-playbook playbooks/openshift-kvm-bm-cluster-deploy.yaml \
  -i ../ocp-cluster-vars/vars/$CLUSTER_NAME/inventory.yaml \
  -e cluster_name=$CLUSTER_NAME \
  --vault-password-file ./vault-password-file
```

### Useful Tags

Skip or target specific stages:

```bash
# Skip teardown and pre-deploy (re-run from manifest creation onward)
--skip-tags pre-deploy

# Only run install-time monitoring (before post-install configure)
--tags openshift-install-time-operations

# Post-install is applied by openshift-cluster-configure.yaml (imported at end of deploy).
# Run it standalone or target tags on that playbook:
ansible-playbook playbooks/openshift-cluster-configure.yaml \
  -i ../ocp-cluster-vars/vars/$CLUSTER_NAME/inventory.yaml \
  -e cluster_name=$CLUSTER_NAME \
  --vault-password-file ./vault-password-file

# Examples on the configure playbook
--tags openshift-auth-provider
--tags post-install
```

## Destroy

```bash
cd src/ansible
export CLUSTER_NAME=infra1
ansible-playbook playbooks/openshift-kvm-bm-cluster-deco.yaml \
  -i ../ocp-cluster-vars/vars/$CLUSTER_NAME/inventory.yaml \
  -e cluster_name=$CLUSTER_NAME \
  --vault-password-file ./vault-password-file
```

This removes KVM VMs (`virsh destroy` / `undefine`), destroys libvirt storage pools, and wipes additional host disks. Bare-metal nodes are not automatically powered off.

## How It Works

### Agent-Based Install

The Agent-based installer replaces the older UPI/ignition workflow. The automation generates an `agent-config.yaml` listing each node's MAC, role, and network config, then builds a bootable Agent ISO. Each node boots from this ISO, discovers its peers via a rendezvous IP, and self-assembles the cluster.

When `ocp_network_type` is `OVNKubernetes`, the manifest step adds `openshift/cluster-network-03-config.yaml` for **jumbo frames (MTU 9000)** on the OVN-Kubernetes network. Registry mirror `ImageContentSourcePolicy` / platform-registry `ImageTagMirrorSet` manifests are applied only when `image_content_sources` is defined in your variables.

### KVM Node Deployment

For KVM nodes, the `kvm-deploy-vms` role:
- Creates a libvirt storage pool under `cluster_vms_storage_base_dir`
- Generates qcow2 OS disks and optional extra storage (file images or block device passthrough)
- Renders a libvirt domain XML spec with the Agent ISO attached as a CDROM
- Defines, enables autostart, and boots the VMs

### Bare-Metal Node Deployment

For bare-metal nodes, the `idrac-operations` role:
- Mounts the Agent ISO as virtual media via Dell iDRAC
- Configures one-time boot from virtual CD
- Powers on the server
- After install completes, ejects the virtual CD (handled in `openshift-cluster-configure.yaml`, play **Eject Virtual CD Drive**)

### Mixed Clusters

Clusters can combine KVM and bare-metal nodes (platform `kvm_bm`). Control-plane nodes typically run as KVM VMs on a hypervisor, while workers can be a mix of KVM VMs and bare-metal servers. The `type` field on each host in the inventory controls which deployment path is used.
