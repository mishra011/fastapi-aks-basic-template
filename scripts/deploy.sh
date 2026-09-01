docker build -t fastapiacrdm.azurecr.io/dmfastapi-app:latest .
docker push fastapiacrdm.azurecr.io/dmfastapi-app:latest
az aks get-credentials --admin --name fastapi-aks-cluster-dm --resource-group fastapi-resource-group
kubectl get nodes
cd infrastructure/kubernetes/
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml