# Kubernetes namespace для Argo CD
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.namespace
  }
}

# Namespace для Django застосунку
resource "kubernetes_namespace" "django_app" {
  metadata {
    name = var.django_app_namespace
  }
}

# Argo CD Helm Release
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [
    file("${path.module}/values.yaml")
  ]

  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }

  depends_on = [kubernetes_namespace.argocd]
}

# Argo CD Applications Helm Chart
resource "helm_release" "argocd_apps" {
  name      = "argocd-apps"
  chart     = "${path.module}/charts"
  namespace = kubernetes_namespace.argocd.metadata[0].name

  set {
    name  = "gitRepoUrl"
    value = var.git_repo_url
  }

  set {
    name  = "targetRevision"
    value = var.git_target_revision
  }

  set {
    name  = "djangoAppNamespace"
    value = var.django_app_namespace
  }

  depends_on = [helm_release.argocd]
}