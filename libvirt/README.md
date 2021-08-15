# OpenShift UPI Install Automation for libvirt

## Functionality

This playbook will do the following tasks

- Download the oc and openshift-install binaries
- Download the appropriate RHCOS image for the platform
- Deploy an OpenShift cluster

## Pre-req

1. Install Ansible, libvirt and other required tools
``` shell
dnf install libguestfs-tools virt-install ansible unzip tar -y
```

2. Run the following command to install required collection from ansilbe galaxy
```Shell
cd src/ansible
ansible-galaxy collection install -r requirements.yml
```

3. run the following pip command to install OpenShift library for python
```Shell
pip3 install openshift
```
4. Install a web-server that will serve files over HTTP (In future updates I will add functionality to be able to upload the ignition files to a remote http server)

5. Create a bridge interface to be used by the VMs


## Update vars

Update the following variables

### <b>src/ansible/vars/common.yaml</b>

<b>rhcos_ssh_pub_key</b> - Your public key that you can use to ssh into your RHCOS VMs

<b>additional_trust_bundle</b> - Certificate of your private registry (optional) 

<b>pull_secret</b> - Your pull secret json

<b>http_file_server_base_path</b> - The base path for the web-server that will be serving up the bootstrap ignition file for your cluster. For now this has to be local to the machine that will run this playbook

<b>http_base_url</b> - The base URL of your web-server. Make sure you don't have an / at the end

### <b>src/ansible/vars/libvirt/vars.yaml</b>

<b>base_domain</b> - The base domain of your cluster.

<b>ocp_cluster_name</b> - The name of your cluster

<b>staging_dir</b> - Changing the stating location is optional. Make sure to have at least 4GB of space on that drive

<b>cluster_vms_storage_base_dir</b> - Update the base path to where you want all virtual disks for your cluster to be stored
 
<b>libvirt_bridge_name</b> - The name of the bridge insterface on the KVM virtualization host


## Update inventory file

You can use the existing MAC addresses in the inventory file or generate your own using the generate-mac script located in the scripts folder or a method of your own choosing.

Update the domain name of the nodes to match your domain

If you will be installing OCS as a storage provider in your cluster, you need to provide a path where the disk image will be created for each node. You can set the variable ocs_disk_path to the desired location. If you don't intend to use OCS, you can remove the variable.

## Update infrastructure services

- Update your DHCP service with the MACS used in your inventory file.
- Add the required DNS entries for your cluster (api,*.apps, vm hostname)
- I will update the automation to work with remote web servers, but at the moment you need to run the web server on the same machine that you will run this playbook. Ensure that the web server can serve up files to the OpenShift host network.

## Run the playbook

```Shell
cd ocp-upi/src/ansible
ansible-playbook playbooks/openshift-libvirt-cluster-deploy.yaml -i `pwd`/vars/libvirt/inventory -e config=`pwd`/vars/libvirt/main.yaml
```
