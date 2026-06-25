terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ─────────────────────────────────────────────
# VPC
# ─────────────────────────────────────────────
resource "aws_vpc" "k8s_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "k8s-vpc"
    Project = "nodejs-cicd"
  }
}

# ─────────────────────────────────────────────
# Subnet
# ─────────────────────────────────────────────
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name    = "k8s-public-subnet"
    Project = "nodejs-cicd"
  }
}

# ─────────────────────────────────────────────
# Internet Gateway + Route Table
# ─────────────────────────────────────────────
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.k8s_vpc.id
  tags   = { Name = "k8s-igw" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "k8s-public-rt" }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# ─────────────────────────────────────────────
# Security Group
# ─────────────────────────────────────────────
resource "aws_security_group" "k8s_sg" {
  name        = "k8s-sg"
  description = "Security group for Kubernetes cluster nodes"
  vpc_id      = aws_vpc.k8s_vpc.id

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  # Kubernetes API server
  ingress {
    description = "K8s API Server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NodePort range (for app access)
  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ArgoCD UI
  ingress {
    description = "ArgoCD UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all internal cluster traffic
  ingress {
    description = "Internal cluster traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "k8s-sg", Project = "nodejs-cicd" }
}

# ─────────────────────────────────────────────
# SSH Key Pair
# ─────────────────────────────────────────────
resource "aws_key_pair" "k8s_key" {
  key_name   = "k8s-key"
  public_key = file(var.public_key_path)
}

# ─────────────────────────────────────────────
# Master Node
# ─────────────────────────────────────────────
resource "aws_instance" "master" {
  ami                    = var.ami_id
  instance_type          = "m7i-flex.large"  # Minimum recommended for master
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  key_name               = aws_key_pair.k8s_key.key_name
  user_data              = file("scripts/install-k8s.sh")

  root_block_device {
    volume_size           = 20
    volume_type           = "gp2"
    delete_on_termination = true
  }

  tags = {
    Name    = "k8s-master"
    Role    = "master"
    Project = "nodejs-cicd"
  }
}

# ─────────────────────────────────────────────
# Worker Node
# ─────────────────────────────────────────────
resource "aws_instance" "worker" {
  ami                    = var.ami_id
  instance_type          = "m7i-flex.large"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  key_name               = aws_key_pair.k8s_key.key_name
  user_data              = file("scripts/install-k8s.sh")

  root_block_device {
    volume_size           = 20
    volume_type           = "gp2"
    delete_on_termination = true
  }

  tags = {
    Name    = "k8s-worker"
    Role    = "worker"
    Project = "nodejs-cicd"
  }
}
