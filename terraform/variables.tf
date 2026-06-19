variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "ami_id" {
  description = "AMI ID for EC2 instances (Amazon Linux 2 - us-east-1)"
  type        = string
  default     = "ami-0c02fb55956c7d316"
}

variable "public_key_path" {
  description = "Path to your SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "my_ip_cidr" {
  description = "Your IP in CIDR format for SSH access e.g. 203.0.113.0/32"
  type        = string
  default     = "0.0.0.0/0"  # Replace with your actual IP in production
}
