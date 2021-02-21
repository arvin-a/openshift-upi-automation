#!/bin/bash
set -x 
ocp_version=4.6
channel=fast
rhcos_version=latest
base_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp"
release_url="${base_url}/${channel}-${ocp_version}"
client_archive_name=openshift-client-linux.tar.gz
installer_archive_name=openshift-install-linux.tar.gz

rhcos_base_url=https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos
rhcos_release_url="${rhcos_base_url}/${ocp_version}/${rhcos_version}"
rhcos_file_name=rhcos-openstack.x86_64.qcow2.gz
rhcos_qcow_url="${rhcos_release_url}/${rhcos_file_name}"

##virtctl binary
virtctl_source=https://github.com/kubevirt/kubevirt/releases/download/v0.35.0/virtctl-v0.35.0-linux-amd64



client_url="${release_url}/${client_archive_name}"
installer_url="${release_url}/${installer_archive_name}"

rm -rf temp 2> /dev/null
mkdir temp
cd temp

wget $client_url
tar xvf $client_archive_name
sudo cp -f oc /usr/bin/oc

wget $installer_url
tar xvf $installer_archive_name
mv -f openshift-install ../

wget $virtctl_source
mv virtctl-v0.35.0-linux-amd64 /usr/bin/virtctl


wget $rhcos_qcow_url
gunzip $rhcos_file_name
mv -f *.qcow2 ../rhcos.qcow2

rm -rf temp


