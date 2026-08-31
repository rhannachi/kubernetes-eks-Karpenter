# Installation et configuration de Karpenter avec Helm sur un cluster EKS AWS 

Avant de passer à la mise en place d'un HPA avec un auto-scaling automatisé grâce à Karpenter sur un cluster EKS AWS, vous pouvez tester un HPA sur Minikube

[README-minikube.md](README-minikube.md)

---

### Étape 1 - Installation AWS CLI, eksctl et configuration d'un utilisateur AWS
[README-aws-user.md](README-aws-user.md)

---

### Étape 2 - Création cluster AWS EKS
[README-aws-cluster.md](README-aws-cluster.md)

---

### Étape 3 - Installation de Karpenter EKS AWS
[README-aws-karpenter.md](README-aws-karpenter.md)

---

### Étape 4 - Déployer votre application php-apache et tester karpenter autoscaling

Pour **déployer l'application de démonstration** et **tester le double-level autoscaling** (HPA + Karpenter) :

[README-aws-karpenter-autoscaling-test.md](README-aws-karpenter-autoscaling-test.md)

---

### Étape 5 - Nettoyage Complet (Suppression du Cluster et Ressources AWS)

Pour **supprimer complètement** le cluster EKS et toute la configuration AWS associée :

[README-aws-cleanup.md](README-aws-cleanup.md)
