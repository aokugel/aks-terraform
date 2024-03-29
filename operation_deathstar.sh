#!/bin/bash

az login

terraform init
terraform plan -out main.tfplan
terraform apply "main.tfplan"

echo "$(terraform output kube_config)" | tail -n +2 | head -n -1 > ./azurek8s
export KUBECONFIG=./azurek8s

kubectl create namespace django
kubectl config set-context --current --namespace=django
kubectl create secret generic azure-blob-secret --from-literal=BLOB_KEY=$(terraform output storage_account_primary_key)
kubectl apply -f ../django-kubernetes/


helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx   --create-namespace   \
--namespace django   --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/

unset external_ip 

while [ -z $external_ip ]
do echo "Waiting for end point..."
external_ip=$(kubectl get ingress blog-ingress --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}")
[ -z "$external_ip" ] && sleep 10
done

echo "End point ready-" && echo $external_ip

curl $external_ip

kubectl exec -c blog deployment/django-blog-app -- python manage.py createsuperuser --noinput

token=$(python ../get_token.py $external_ip $1 $2)

python ../website_article_push.py $external_ip $token

xdg-open http://$external_ip

if grep -q django-unchained-k8s.com "/etc/hosts"; then
  sudo sed -i '$d' /etc/hosts
fi

echo "$(kubectl get ingress blog-ingress --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}") django-unchained-k8s.com" | sudo tee -a  /etc/hosts

HOST='django-unchained-k8s.com'
KEY_FILE='tls.key'
CERT_FILE='tls.crt'
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ${KEY_FILE} -out ${CERT_FILE} -subj "/CN=${HOST}/O=${HOST}" -addext "subjectAltName = DNS:${HOST}"
kubectl create secret tls django-unchained-k8s-com-tls --key ${KEY_FILE} --cert ${CERT_FILE}

xdg-open https://django-unchained-k8s.com


# HOST='k8s.anthonykugel.com'
# KEY_FILE='k8s-tls.key'
# CERT_FILE='k8s-tls.crt'
# SECRET_NAME='k8s-anthonykugel-com-tls'
# openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ${KEY_FILE} -out ${CERT_FILE} -subj "/CN=${HOST}/O=${HOST}" -addext "subjectAltName = DNS:${HOST}"
# kubectl create secret tls ${k8s-anthonykugel-com-tls} --key ${KEY_FILE} --cert ${CERT_FILE}