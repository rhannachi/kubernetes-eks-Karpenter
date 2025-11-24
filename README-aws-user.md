# Installation AWS CLI, eksctl et configuration d'un utilisateur AWS

## 1. Installation
Tu dois disposer de :
* D'un compte AWS actif
* De droits IAM suffisants (création de cluster EKS, VPC, EC2…)

### Sur ton poste local :
* Installer :
    * `awscli`
    * `eksctl`
    * `kubectl`

#### Installer AWS CLI

  ```bash
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install
  aws --version
  ```

#### Installer `eksctl`

  ```bash
  curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz"
  tar -xzf eksctl_$(uname -s)_amd64.tar.gz -C /tmp
  sudo mv /tmp/eksctl /usr/local/bin
  eksctl version
  ```

#### Installer `kubectl`

  ```bash
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  kubectl version --client
  ```

---

## 2. Créer un utilisateur IAM sécurisé (Access Key / Secret Key)

### Étape 1 : Créer un nouvel utilisateur IAM

> ⚠️ IMPORTANT : Les Étapes 1, 2 et 5 doivent être effectuées via la **Console AWS** (interface web) avec un compte administrateur, car un utilisateur IAM sans permissions ne peut pas se créer ou s'attribuer des permissions lui-même via CLI.

#### Via la Console AWS :

1. Connecte-toi à https://console.aws.amazon.com avec un compte **administrateur**
2. Va dans **IAM** → **Users** → **Create user**
3. Nom de l'utilisateur : `eks-user`
4. Coche **Provide user access to the AWS Management Console** (optionnel, si tu veux un accès console)
5. Clique sur **Next**
6. Ne sélectionne aucun groupe ou permission pour l'instant
7. Clique sur **Next** puis **Create user**

### Étape 2 : Créer un groupe IAM et y ajouter l'utilisateur

#### Via la Console AWS :

1. Va dans **IAM** → **Groups** → **Create group**
2. Nom du groupe : `eks-user-group`
3. Ne sélectionne aucune policy pour l'instant
4. Clique sur **Create group**

5. Va dans **IAM** → **Users** → `eks-user`
6. Onglet **Groups** → **Add user to groups**
7. Sélectionne `eks-user-group`
8. Clique sur **Add to groups**

### Étape 3 : Récupérer les clés d'accès

#### Via la Console AWS :

1. Va dans **IAM** → **Users** → `eks-user`
2. Onglet **Security credentials**
3. Section **Access keys** → **Create access key**
4. Sélectionne **Command Line Interface (CLI)**
5. Coche la case de confirmation
6. Clique sur **Next** puis **Create access key**
7. ⚠️ IMPORTANT : Télécharge le fichier CSV ou note bien :
   - **Access key ID** (ex: `AKIA...`)
   - **Secret access key** (ex: `abcd...`)

=> Tu **ne pourras plus revoir la clé secrète** après cette étape, garde-la bien !

### Étape 4 : Configurer AWS CLI

  ```bash
  aws configure
  ```

Entre tes clés :
  ```
    AWS Access Key ID [None]: AKIA...
    AWS Secret Access Key [None]: xxxxxxx
    Default region name [None]: us-east-1
    Default output format [None]: json
  ```

Vérifie :

  ```bash
  aws sts get-caller-identity
  ```

Tu dois voir ton utilisateur IAM :

  ```json
  {
    "UserId": "AIDAEXAMPLE123",
    "Account": "12546789742356",
    "Arn": "arn:aws:iam::12546789742356:user/eks-user"
  }
  ```

### Étape 5 : Créer et attacher une policy IAM personnalisée pour EKS et Karpenter

> ⚠️ IMPORTANT : Cette étape doit être effectuée via la **Console AWS** avec un compte administrateur.

Pour suivre le principe du moindre privilège, nous allons créer une policy personnalisée qui donne uniquement les permissions nécessaires pour gérer un cluster EKS avec Karpenter.

#### 1 — Préparer le document de policy

Le fichier [eks-admin-policy.json](infra/eks-admin-policy.json) contient les permissions nécessaires pour EKS et Karpenter.\
Explication détaillée de ce fichier : [README-eks-admin-policy.md](README-eks-admin-policy.md).\
Remplace les variables dans le fichier :
```shell
export AWS_REGION="us-east-1"                     # Région la plus proche
sed -i "s/\${AWS_REGION}/${AWS_REGION}/g" infra/eks-admin-policy.json
```

#### 2 — Créer la policy dans AWS via la Console

1. Va dans **IAM** → **Policies** → **Create policy**
2. Clique sur l'onglet **JSON**
3. Copie-colle le contenu du fichier [eks-admin-policy.json](infra/eks-admin-policy.json) dans l'éditeur
4. Clique sur **Next**
5. Nom de la policy : `EKSAdminPolicy`
6. Description : `Policy for EKS cluster management with Karpenter support`
7. Clique sur **Create policy**

#### 3 — Attacher toutes les policies au groupe eks-user-group

1. Va dans **IAM** → **Groups** → `eks-user-group`
2. Onglet **Permissions** → **Add permissions** → **Attach policies**
3. Cherche et sélectionne les 5 policies suivantes :
   - ✅ EKSAdminPolicy (celle que tu viens de créer)
   - ✅ AmazonEKSClusterPolicy
   - ✅ AmazonEKSWorkerNodePolicy
   - ✅ AmazonEC2ContainerRegistryReadOnly
   - ✅ IAMReadOnlyAccess (permet de vérifier les configurations IAM)
4. Clique sur **Attach policies**

#### 4 — Vérifier que toutes les policies sont bien attachées

Maintenant, depuis ton terminal avec l'utilisateur `eks-user`, tu peux vérifier :

  ```bash
  aws iam list-attached-group-policies --group-name eks-user-group --output table
  ```

Résultat attendu :
  ```
  ----------------------------------------------------------------------------------
  |                        ListAttachedGroupPolicies                               |
  +--------------------------------------------------------------------------------+
  ||                              AttachedPolicies                                ||
  |+-----------------------------------------------------------+------------------+|
  ||                        PolicyArn                          |   PolicyName     ||
  |+-----------------------------------------------------------+------------------+|
  ||  arn:aws:iam::aws:policy/AmazonEKSClusterPolicy           | AmazonEKSCluster...||
  ||  arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy        | AmazonEKSWorker...||
  ||  arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly| AmazonEC2Conta...||
  ||  arn:aws:iam::aws:policy/IAMReadOnlyAccess                | IAMReadOnlyAccess||
  ||  arn:aws:iam::272391830312:policy/EKSAdminPolicy          | EKSAdminPolicy   ||
  |+-----------------------------------------------------------+------------------+|
  ```

#### 5 — Tester l'accès EKS

```bash
aws eks describe-addon-versions --query "addons[*].addonName" --output table
```
```shell
aws eks describe-addon-versions --output json | grep -E "vpc-cni|kube-proxy|coredns" | head -5
```

Si tout est bon, la commande doit retourner une liste des add-ons EKS disponibles (vpc-cni, kube-proxy, coredns, etc.).

---

## Récapitulatif

### Résumé des Étapes

| # | Étape | Responsable | Détails |
|---|-------|-------------|---------|
| 1 | Installation des outils | Utilisateur local | Installer `awscli`, `eksctl`, `kubectl` |
| 2 | Créer utilisateur IAM | Admin Console AWS | Créer user `eks-user` via IAM Console |
| 3 | Créer groupe IAM | Admin Console AWS | Créer group `eks-user-group` et ajouter l'utilisateur |
| 4 | Générer Access Keys | Admin Console AWS | Créer Access Key ID + Secret Access Key |
| 5 | Attacher policies IAM | Admin Console AWS | Attacher 5 policies au groupe (EKSAdminPolicy, AmazonEKSClusterPolicy, etc.) |
| 6 | Configurer AWS CLI | Utilisateur eks-user | Exécuter `aws configure` avec les clés générées |
| 7 | Vérifier la configuration | Utilisateur eks-user | Exécuter `aws sts get-caller-identity` |

### ✅ Vérifications Finales

**La configuration est réussie si** :
- ✅ `aws sts get-caller-identity` retourne `arn:aws:iam::*:user/eks-user`
- ✅ `aws iam list-attached-group-policies --group-name eks-user-group` affiche les 5 policies
- ✅ Les clés Access Key et Secret Access Key sont stockées en sécurité

### Points Clés à Retenir

- ⚠️ **Sécurité** : Les clés secrètes ne sont visibles qu'une seule fois → à conserver précieusement
- ⚠️ **Permissions** : Utilisateur sans `iam:CreatePolicy` (créé par admin uniquement)
- ✅ **Moindre privilège** : Permissions minimales et restreintes via custom policy `EKSAdminPolicy`
- ✅ **Prêt pour étape suivante** : Utilisateur `eks-user` configuré pour créer le cluster EKS