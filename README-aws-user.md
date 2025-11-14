# Installation AWS CLI, eksctl et configuration d'un utilisateur AWS

## 1. Installation
Tu dois disposer de :
* D’un compte AWS actif
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

---

## 2. Créer un utilisateur IAM sécurisé (Access Key / Secret Key)

### Étape 1 : Créer un nouvel utilisateur IAM avec tous les droits EKS

> Console → **IAM** → **Users** → **Create user**

* Nom de l’utilisateur : `eks-user`

### Étape 2 : Donner les permissions
Crée un **groupe IAM “eks-user-group”** et attache-lui ce policies :
  ```
  IAMFullAccess
  ```

Puis ajoute ton utilisateur `eks-user` à ce groupe.

### Étape 3 : Récupérer les clés

À la fin de la création, dans les informations de l'utilisateur `eks-user`, crée une clé d'accès :

* Télécharge le fichier CSV
* Ou note :
    * **Access key ID** (ex: `AKIA...`)
    * **Secret access key** (ex: `abcd...`)

=> Tu **ne pourras plus revoir la clé secrète** plus tard, garde-la bien.

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
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/eks-user"
  }
  ```

### Étape 5 : Attacher les policies AWS managées à notre groupe IAM "eks-user-group"

#### 1 — Attacher la policy **AmazonEKSClusterPolicy**
  ```bash
  aws iam attach-group-policy \
  --group-name eks-user-group \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
  ```

#### 2 — Attacher la policy **AmazonEKSServicePolicy**
  ```bash
  aws iam attach-group-policy \
  --group-name eks-user-group \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSServicePolicy
  ```

#### 3 — Attacher la policy **AmazonEKSWorkerNodePolicy**
  ```bash
  aws iam attach-group-policy \
  --group-name eks-user-group \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
  ```

#### 4 — Attacher la policy **AmazonEC2FullAccess**
  ```bash
  aws iam attach-group-policy \
  --group-name eks-user-group \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
  ```

#### 5 — Attacher la policy **AmazonVPCFullAccess**
  ```bash
  aws iam attach-group-policy \
  --group-name eks-user-group \
  --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess
  ```

#### 6 — Attacher la policy **AWSCloudFormationFullAccess**
  ```bash
  aws iam attach-group-policy \
  --group-name eks-user-group \
  --policy-arn arn:aws:iam::aws:policy/AWSCloudFormationFullAccess
  ```

#### 7 — Vérifie que tout est bien attaché
  ```bash
  aws iam list-attached-group-policies --group-name eks-user-group --output table
  ------------------------------------------------------------------------------------------
  |                                ListAttachedGroupPolicies                               |
  +----------------------------------------------------------------------------------------+
  ||                                   AttachedPolicies                                   ||
  |+------------------------------------------------------+-------------------------------+|
  ||                       PolicyArn                      |          PolicyName           ||
  |+------------------------------------------------------+-------------------------------+|
  ||  arn:aws:iam::aws:policy/AmazonEC2FullAccess         |  AmazonEC2FullAccess          ||
  ||  arn:aws:iam::aws:policy/IAMFullAccess               |  IAMFullAccess                ||
  ||  arn:aws:iam::aws:policy/AmazonEKSClusterPolicy      |  AmazonEKSClusterPolicy       ||
  ||  arn:aws:iam::aws:policy/AmazonVPCFullAccess         |  AmazonVPCFullAccess          ||
  ||  arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy   |  AmazonEKSWorkerNodePolicy    ||
  ||  arn:aws:iam::aws:policy/AmazonEKSServicePolicy      |  AmazonEKSServicePolicy       ||
  ||  arn:aws:iam::aws:policy/AWSCloudFormationFullAccess |  AWSCloudFormationFullAccess  ||
  |+------------------------------------------------------+-------------------------------+|
  
  ```

#### 8 — Ajouter la policy "AllowEksFullAccess" à notre groupe

Cette policy accorde à ton groupe (et donc à ton utilisateur `eks-user`) toutes les permissions EKS.
C’est équivalent à `AmazonEKSFullAccess`, qui n’existe pas comme policy managée mais que nous recréons ici.

  ```bash
  $ aws iam put-group-policy \
  --group-name eks-user-group \
  --policy-name AllowEksFullAccess \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "eks:*"
        ],
        "Resource": "*"
      }
    ]
}'
  ```

Vérifie que la policy a bien été ajoutée :

  ```bash
  aws iam list-group-policies --group-name eks-user-group
  ```

Résultat attendu :

  ```
  {
    "PolicyNames": [
      "AllowEksFullAccess"
    ]
  }
  ```

Teste l’accès EKS :

  ```bash
  aws eks describe-addon-versions
  ```

Si tout est bon, la commande doit retourner une longue liste d’add-ons EKS (versions de vpc-cni, kube-proxy, coredns, etc.).
