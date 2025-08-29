locals {
  name = var.cluster_name
  tags = {
    Project     = "eks-sockshop"
    Environment = "dev"
    Terraform   = "true"
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = local.name
  cidr = "10.0.0.0/16"

  azs             = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.1.5"

  cluster_name    = local.name
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  manage_aws_auth_configmap = true
  enable_irsa               = true

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      ami_type       = "AL2023_x86_64_STANDARD"
      min_size       = 2
      max_size       = 4
      desired_size   = 2
    }
  }

  aws_auth_roles = [
    {
      rolearn  = "arn:aws:iam::014030150269:role/EKS"
      username = "admin"
      groups   = ["system:masters"]
    }
  ]
 
  
  tags        = local.tags
}

data "aws_eks_cluster" "eks" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "token" {
  name = module.eks.cluster_name
}

# ---------------------------------------------------
# ArgoCD Helm Chart
# ---------------------------------------------------
resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.52.0"

  create_namespace = true

  values = [
    <<-EOF
    server:
      service:
        type: LoadBalancer
    EOF
  ]

  depends_on = [module.eks]
}

# ---------------------------
# IAM Role for ALB Controller (IRSA)
# ---------------------------
module "alb_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.34.0"

  role_name                              = "alb-controller-irsa"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
    }
  }
}

# ---------------------------------------------------
# AWS Load Balancer Controller (ALB) via Helm
# ---------------------------------------------------
resource "kubernetes_service_account" "alb" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.alb_irsa.iam_role_arn
    }
  }
}

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.8.1"

  values = [
    yamlencode({
      clusterName = module.eks.cluster_name
      region      = var.region
      serviceAccount = {
        create = false
        name   = "aws-load-balancer-controller"
      }
    })
  ]

  depends_on = [
    kubernetes_service_account.alb,
    module.eks
  ]
}