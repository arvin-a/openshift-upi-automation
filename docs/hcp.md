# HCP — Hosted Control Planes on KubeVirt

This playbook deploys OpenShift tenant clusters using **Hosted Control Planes (HCP)** with the **KubeVirt provider**. The control plane runs as pods on the infrastructure (management) cluster, while worker nodes are provisioned as KubeVirt virtual machines. The cluster is automatically registered with **Red Hat Advanced Cluster Management (RHACM)** as a managed cluster.

## What the Automation Does

The deploy playbook (`openshift-hcp-cluster-deploy.yaml`) performs the following:

1. Tears down any existing HCP cluster with the same name (idempotent re-deploy)
2. Loads shared and cluster-specific configuration
3. Resolves the latest OCP release image from the Cincinnati API for the configured version/channel
4. Downloads the required `oc` binary
5. Patches the infra cluster ingress controller to allow wildcard routes (required for HCP routing)
6. Creates the `clusters` namespace, pull secret, and SSH key secret on the infra cluster
7. Creates an HTPasswd secret for the tenant cluster's OAuth
8. Applies the `HostedCluster` resource (control plane definition)
9. Applies the `NodePool` resource (KubeVirt worker VMs)
10. Registers the cluster with RHACM (`ManagedCluster` + `KlusterletAddonConfig`)
11. Waits for the API server to become available
12. Saves the tenant cluster kubeconfig and stores it in Bitwarden
13. Grants cluster-admin to configured users
14. Waits for full cluster rollout to complete

The destroy playbook (`openshift-hcp-cluster-destroy.yaml`) tears down in reverse order:

1. Removes the `KlusterletAddonConfig` and `ManagedCluster` (RHACM)
2. Removes the `NodePool` (deprovisions KubeVirt worker VMs)
3. Removes the `HostedCluster` (tears down the hosted control plane)
4. Cleans up secrets (htpasswd, pull secret, SSH key)

## Prerequisites

### Infrastructure Cluster

- An OpenShift cluster with:
  - **RHACM** (Red Hat Advanced Cluster Management) installed with the HCP add-on enabled
  - **OpenShift Virtualization** installed (KubeVirt provider for worker nodes)
  - A storage class suitable for etcd persistent volumes and VM root disks (e.g. `odf-storagecluster-ceph-rbd`)
- Cluster-admin access (kubeconfig stored in Bitwarden)

### Networking

HCP with KubeVirt uses the **baseDomainPassthrough** strategy. The tenant cluster's API and apps endpoints are exposed as routes on the infra cluster's ingress. This means:

- The infra cluster ingress controller must allow **wildcard routes** (the automation patches this automatically)
- The base domain is derived from the infra cluster's apps domain: `apps.<infra-cluster>.<infra-domain>`
- No separate DNS, DHCP, or load balancer configuration is required -- the infra cluster handles everything

### Control Node (where Ansible runs)

Install dependencies:

```bash
cd src/ansible
./update_env.sh
```

`update_env.sh` installs Ansible Galaxy collections from `context/_build/requirements.yml` (including `community.general`).

## Configuration

All cluster variables live under `src/ocp-cluster-vars/vars/`. The HCP cluster directory (e.g. `hcp1/`) contains two files:

### `main.yaml` -- config loader

Lists the variable files to include. No changes needed unless adding new variable files.

### `vars.yaml` -- cluster-specific variables

| Variable | Description |
|----------|-------------|
| `platform` | Must be `"hcp"` |
| `cluster_type` | `"kubevirt"` |
| `cluster_role` | `"tenant"` |
| `ocp_cluster_name` | Cluster name (e.g. `hcp1`) |
| `ocp_version` | OpenShift version (e.g. `"4.21"`) |
| `ocp_bin_channel` | Release channel (`stable`, `fast`, `candidate`) |
| `ocp_network_type` | CNI plugin (default `OVNKubernetes`) |
| `infra_cluster_fqdn` | FQDN of the infrastructure cluster |
| `infra_cluster_tenant_namespace` | Namespace for the HCP resources (auto-derived as `clusters-<name>`) |
| `infra_cluster_storage_class_name` | Storage class for etcd PVs and VM root volumes |
| `hcp_image_content_sources` | Registry mirror configuration (optional) |

The `base_domain` is automatically constructed as `apps.<infra_cluster_name>.<infra_cluster_base_domain>`, routing tenant cluster traffic through the infra cluster's ingress.

**Note:** HCP clusters do not use an inventory file. There are no individual node definitions -- the `NodePool` resource manages the worker VM fleet declaratively.

### Cluster Sizing

Worker node sizing is defined in the `NodePool` template (`05-hcp-node-pool.yaml`):

| Setting | Default |
|---------|---------|
| Replicas | 2 |
| CPU cores | 8 |
| Memory | 16Gi |
| Root volume | 32Gi, Block mode, RWX |
| Architecture | amd64 |

Etcd storage is configured in the `HostedCluster` template (`04-hcp-hosted-cluster.yaml`) at 8Gi with PersistentVolume storage.

### Credentials (Bitwarden)

Sensitive values (pull secret, SSH keys, infra kubeconfig) are retrieved at runtime from Bitwarden Secrets Manager. The vault-encrypted `credentials.yaml` stores the Bitwarden access token.

## Deploy

```bash
cd src/ansible
export CLUSTER_NAME=hcp1
ansible-playbook playbooks/openshift-hcp-cluster-deploy.yaml \
  -i ../ocp-cluster-vars/vars/$CLUSTER_NAME/inventory.yaml \
  -e cluster_name=$CLUSTER_NAME \
  --vault-password-file ./vault-password-file
```

### Useful Tags

```bash
# Skip teardown and pre-deploy
--skip-tags pre-deploy

# Only deploy the HCP cluster (after config is loaded)
--tags hcp-cluster-deploy
```

## Destroy

```bash
cd src/ansible
export CLUSTER_NAME=hcp1
ansible-playbook playbooks/openshift-hcp-cluster-destroy.yaml \
  -i ../ocp-cluster-vars/vars/$CLUSTER_NAME/inventory.yaml \
  -e cluster_name=$CLUSTER_NAME \
  --vault-password-file ./vault-password-file
```

The destroy process removes resources in dependency order: RHACM registration first, then NodePool (which deprovisions KubeVirt VMs), then HostedCluster (which tears down the control plane pods), and finally cleanup of secrets.

## How It Works

### HCP Architecture

Unlike traditional OpenShift clusters where the control plane runs on dedicated nodes, HCP runs the control plane components (API server, etcd, controllers) as **pods on the infrastructure cluster**. Worker nodes are KubeVirt VMs managed by a `NodePool` resource.

This provides:
- **Faster provisioning** -- no need to boot and configure control-plane machines
- **Lower resource overhead** -- control plane pods share infra cluster resources
- **Centralized management** -- multiple tenant clusters managed from one infra cluster via RHACM

### Release Image Resolution

The automation queries the **Cincinnati API** to resolve the latest release image for the configured `ocp_version` and `ocp_bin_channel`. The multi-arch release image (`ocp-release:<version>-multi`) is used for both the HostedCluster and NodePool.

### RHACM Integration

Each HCP cluster is automatically registered with RHACM on the infra cluster:
- A `ManagedCluster` resource imports the cluster in **Hosted** klusterlet mode
- A `KlusterletAddonConfig` enables application management, policy controller, search collector, and cert policy controller

### Service Publishing

All HCP services are published via **Routes** on the infra cluster:
- OAuth server
- OIDC
- Konnectivity (tunnel between control plane and workers)
- Ignition (for worker node bootstrap)

## Directory Layout

```
docs/
└── hcp.md                                 # this file

src/ansible/
├── playbooks/
│   ├── openshift-hcp-cluster-deploy.yaml
│   └── openshift-hcp-cluster-destroy.yaml
├── roles/
│   ├── hcp/
│   │   ├── hcp-cluster-deploy/
│   │   │   ├── tasks/main.yaml
│   │   │   ├── templates/
│   │   │   │   ├── 01-hcp-ns.yaml             # clusters namespace
│   │   │   │   ├── 02-hcp-pull-secret.yaml     # pull secret
│   │   │   │   ├── 03-hcp-ssh-key-secret.yaml  # SSH key
│   │   │   │   ├── 04-hcp-hosted-cluster.yaml  # HostedCluster CR
│   │   │   │   ├── 05-hcp-node-pool.yaml       # NodePool CR
│   │   │   │   ├── 06-hcp-managed-cluster.yaml # RHACM ManagedCluster
│   │   │   │   └── 07-hcp-klusterlet-addon-config.yaml
│   │   │   └── files/
│   │   │       └── users.htpasswd
│   │   └── hcp-cluster-destroy/
│   │       └── tasks/main.yaml
│   └── common/
│       └── ansible-config-load/
│           └── tasks/hcp-config-load.yaml      # Cincinnati release resolution

src/ocp-cluster-vars/vars/
├── common.yaml
├── credentials.yaml
└── hcp1/
    ├── main.yaml
    └── vars.yaml
```
