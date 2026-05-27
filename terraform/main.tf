# ================================================================
# TERRAFORM CONFIGURATION
# This file creates your entire AWS infrastructure:
# VPC → Subnets → NAT Gateway → EKS Cluster → ECR Repos
# ================================================================
 
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}
 
# Tell Terraform which AWS region to use
provider "aws" {
  region = "ap-south-1"   # Mumbai — lowest latency + cost for India
}
 
# Get list of availability zones in ap-south-1
# ap-south-1 has: ap-south-1a, ap-south-1b, ap-south-1c
data "aws_availability_zones" "available" {}
 
# Get your AWS account ID (used in outputs)
data "aws_caller_identity" "current" {}
 
# ── VPC ─────────────────────────────────────────────────────────
# VPC = Virtual Private Cloud = your isolated network in AWS
# Think of it as a building. Subnets are floors. Resources are rooms.
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"   # 65,536 IP addresses available
  enable_dns_hostnames = true             # Pods get DNS names
  enable_dns_support   = true
  tags = { Name = "stockai-vpc" }
}
 
# ── INTERNET GATEWAY ────────────────────────────────────────────
# The front door of your VPC — connects it to the internet
# Without this, nothing in your VPC can reach the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "stockai-igw" }
}
 
# ── PUBLIC SUBNETS ──────────────────────────────────────────────
# Public subnets are directly reachable from the internet
# ONLY the Load Balancer lives here
# count = 2 means we create 2 subnets in 2 different AZs
# (if one AZ goes down, ALB still works from other AZ)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"   # 10.0.0.0/24 and 10.0.1.0/24
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true   # Resources here get public IPs
 
  tags = {
    Name                     = "stockai-public-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"   # Tells AWS LB Controller to use these for ALB
  }
}
 
# ── PRIVATE SUBNETS ─────────────────────────────────────────────
# Private subnets are NOT directly reachable from internet
# Your application pods (api-gateway, analysis-service) run here
# They can reach the internet via NAT Gateway (outbound only)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"   # 10.0.10.0/24 and 10.0.11.0/24
  availability_zone = data.aws_availability_zones.available.names[count.index]
 
  tags = {
    Name                              = "stockai-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}
 
# ── NAT GATEWAY ─────────────────────────────────────────────────
# NAT Gateway = one-way door for private subnet resources
# Private pods can call the internet (e.g., Claude AI API)
# But internet CANNOT initiate connection to private pods
# This is the key security benefit of private subnets
#
# COST NOTE: NAT Gateway = ~₹5/hour. Only 1 gateway to save money.
# Production would have 2 (one per AZ) for high availability.
resource "aws_eip" "nat" {
  domain = "vpc"   # Elastic IP = static IP address for NAT Gateway
  tags   = { Name = "stockai-nat-eip" }
}
 
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id   # NAT lives in public subnet
  depends_on    = [aws_internet_gateway.main]
  tags          = { Name = "stockai-nat" }
}
 
# ── ROUTE TABLES ────────────────────────────────────────────────
# Route tables = GPS for network packets. They say:
# "Where does traffic go when it wants to reach X?"
 
# Public route table: all traffic → Internet Gateway (direct internet)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"                   # All traffic
    gateway_id = aws_internet_gateway.main.id   # → out to internet
  }
  tags = { Name = "stockai-public-rt" }
}
 
# Private route table: all traffic → NAT Gateway (goes to internet but source IP hidden)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = { Name = "stockai-private-rt" }
}
 
# Associate route tables with subnets
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
 
resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
 
# ── EKS IAM ROLES ───────────────────────────────────────────────
# EKS needs permission to create load balancers, manage ENIs, etc.
# IAM Role = identity with permissions in AWS
 
resource "aws_iam_role" "eks_cluster" {
  name = "stockai-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}
 
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}
 
# ── EKS CLUSTER ─────────────────────────────────────────────────
# EKS = Elastic Kubernetes Service = managed Kubernetes
# AWS manages the control plane (master nodes) for you
# You only manage worker nodes (EC2 instances that run your pods)
resource "aws_eks_cluster" "main" {
  name     = "stockai-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.30"
 
  vpc_config {
    # Cluster uses all subnets (public for LB, private for nodes)
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    endpoint_private_access = true    # kubectl from within VPC works
    endpoint_public_access  = true    # kubectl from your laptop works
  }
 
  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
  tags = { Name = "stockai-cluster" }
}
 
# IAM Role for EC2 worker nodes
resource "aws_iam_role" "eks_nodes" {
  name = "stockai-eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}
 
resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}
 
resource "aws_iam_role_policy_attachment" "eks_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}
 
resource "aws_iam_role_policy_attachment" "eks_ecr" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}
 
# ── EKS NODE GROUP ──────────────────────────────────────────────
# Node Group = the actual EC2 machines that run your containers
# t3.small = 2 vCPU, 2GB RAM — cheapest that runs K8s comfortably
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "stockai-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private[*].id   # Nodes in private subnet (secure)
 
  instance_types = ["t3.small"]   # Cost optimized
  ami_type       = "AL2_x86_64"   # Amazon Linux 2 (default for EKS)
 
  scaling_config {
    desired_size = 3   # Run 2 nodes normally
    min_size     = 1   # Scale down to 1 if needed
    max_size     = 3   # Scale up to 3 under load
  }
 
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.eks_ecr
  ]
  tags = { Name = "stockai-nodes" }
}
 
# ── ECR REPOSITORIES ────────────────────────────────────────────
# ECR = Elastic Container Registry = private Docker Hub in your AWS account
# Each service gets its own repository to store Docker images
resource "aws_ecr_repository" "services" {
  for_each             = toset(["api-gateway", "analysis-service", "frontend"])
  name                 = "stockai/${each.key}"
  image_tag_mutability = "MUTABLE"   # Allow overwriting tags (needed for CI/CD)
 
  image_scanning_configuration {
    scan_on_push = true   # AWS scans for vulnerabilities on every push
  }
}

# ECR Lifecycle Policy — separate resource (correct way)
# Keeps only latest 10 images per repo to save storage cost
resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = toset(["api-gateway", "analysis-service", "frontend"])
  repository = aws_ecr_repository.services[each.key].name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "ecr_base" {
  value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.ap-south-1.amazonaws.com"
}

output "region" {
  value = "ap-south-1"
}
