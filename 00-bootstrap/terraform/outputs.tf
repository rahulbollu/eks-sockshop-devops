output "cluster_name" {
  value = module.eks.cluster_name
}

output "argocd_access" {
  value = "kubectl port-forward svc/argocd-server -n argocd 8080:443"
}

output "argocd_password_cmd" {
  value = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
}
