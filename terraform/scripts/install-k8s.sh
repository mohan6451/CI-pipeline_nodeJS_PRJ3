#!/bin/bash
set -e

echo "=== Disabling Swap ==="
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

echo "=== Loading kernel modules ==="
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

echo "=== Setting sysctl params ==="
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

echo "=== Installing containerd ==="
yum install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Critical: set SystemdCgroup = true
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl enable --now containerd

echo "=== Disabling SELinux ==="
setenforce 0 || true
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

echo "=== Adding Kubernetes repo (new URL) ==="
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.31/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.31/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

echo "=== Installing kubeadm kubelet kubectl ==="
yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable kubelet

echo "=== Node bootstrap complete ==="
echo "Next: SSH in and run kubeadm init (master) or kubeadm join (worker)"