output "cluster_name" {
  value = module.eks.cluster_name
}

output "argocd_url" {
  value = "LoadBalancer URL - will be available via: kubectl get svc -n argocd"
}

output "node_group_role" {
  value = module.eks.eks_managed_node_groups["default"].iam_role_arn
}
