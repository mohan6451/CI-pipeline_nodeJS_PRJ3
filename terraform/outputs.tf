output "master_public_ip" {
  description = "Public IP of the Kubernetes master node"
  value       = aws_instance.master.public_ip
}

output "worker_public_ip" {
  description = "Public IP of the Kubernetes worker node"
  value       = aws_instance.worker.public_ip
}

output "app_url" {
  description = "URL to access the deployed Node.js app"
  value       = "http://${aws_instance.worker.public_ip}:30080"
}

output "argocd_url" {
  description = "URL to access ArgoCD UI"
  value       = "http://${aws_instance.master.public_ip}:30090"
}

output "ssh_master" {
  description = "SSH command for master node"
  value       = "ssh -i ~/.ssh/id_rsa ec2-user@${aws_instance.master.public_ip}"
}

output "ssh_worker" {
  description = "SSH command for worker node"
  value       = "ssh -i ~/.ssh/id_rsa ec2-user@${aws_instance.worker.public_ip}"
}
