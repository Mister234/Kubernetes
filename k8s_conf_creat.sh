#!/bin/bash

# МСК ЗК
NAMESPACE="prod"

# Ввод имени пользователя
read -p "Введите имя пользователя: " USERNAME
if [[ -z "$USERNAME" ]]; then
    echo "Имя пользователя не может быть пустым!"
    exit 1
fi

# Ввод роли
echo "Выберите роль:"
echo "1. View"
echo "2. Edit"
echo "3. Admin"
read -p "Выберите роль (View(1)/Edit(2)/Admin(3)): " ROLE_CHOICE

if [[ "$ROLE_CHOICE" == "1" ]]; then
    ROLE="view"
elif [[ "$ROLE_CHOICE" == "2" ]]; then
    ROLE="edit"
elif [[ "$ROLE_CHOICE" == "3" ]]; then
    ROLE="admin"
else
    echo "Неверный выбор роли!"
    exit 1
fi

USER_DIR=$(pwd)/$USERNAME

# Создаем директорию для пользователя
mkdir -p "$USER_DIR"

# Создаем ключ и сертификатный запрос
openssl genrsa -out "$USER_DIR/$USERNAME.key" 2048
openssl req -new -key "$USER_DIR/$USERNAME.key" -out "$USER_DIR/$USERNAME.csr" -subj "/CN=$USERNAME/O=$ROLE"

# Создаем CSR в Kubernetes
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $USERNAME
spec:
  request: $(cat "$USER_DIR/$USERNAME.csr" | base64 | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF

# Подписываем сертификат
kubectl certificate approve $USERNAME

# Получаем сертификат
kubectl get csr $USERNAME -o jsonpath='{.status.certificate}' | base64 -d > "$USER_DIR/$USERNAME.crt"

# Создаем namespace, если не существует
kubectl get namespace $NAMESPACE &>/dev/null || kubectl create namespace $NAMESPACE

# Создаем RoleBinding
kubectl create rolebinding $USERNAME-$ROLE \
  --clusterrole=$ROLE \
  --user=$USERNAME \
  --namespace=$NAMESPACE

# Генерируем kubeconfig
KUBE_API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA_CERT=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

cat <<EOF > "$USER_DIR/$USERNAME.kubeconfig"
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $CA_CERT
    server: $KUBE_API_SERVER
  name: kubernetes
users:
- name: $USERNAME
  user:
    client-certificate-data: $(cat "$USER_DIR/$USERNAME.crt" | base64 | tr -d '\n')
    client-key-data: $(cat "$USER_DIR/$USERNAME.key" | base64 | tr -d '\n')
contexts:
- context:
    cluster: kubernetes
    namespace: $NAMESPACE
    user: $USERNAME
  name: $USERNAME-context
current-context: $USERNAME-context
EOF

# Выводим результат
echo "Пользователь $USERNAME успешно создан с ролью $ROLE."
echo "Все файлы сохранены в директорию $USER_DIR."
