#!/bin/bash
set -e

# Trap to cleanup port-forward on script exit/interrupt
cleanup() {
    echo -e "\n\nCleaning up..."
    if [[ -n "${argo_port_forward_pid}" ]] && kill -0 "${argo_port_forward_pid}" 2>/dev/null; then
        echo "Stopping port-forward (PID: ${argo_port_forward_pid})..."
        kill "${argo_port_forward_pid}" 2>/dev/null || true
    fi
    echo "Done!"
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT


# Linux amd64
if [[ "$(uname)" == "Linux" ]] && [[ "$(arch)" == "x86_64" ]]; then
    vm_driver="kvm2"
    echo -e "You are on Linux with amd64 architecture, using ${vm_driver} driver\n"

    # Create the control, stage, prod and monitoring clusters
    minikube start --driver=${vm_driver} --addons=ingress -p control-cluster --network=multi-cluster-observability &> /dev/null &
    echo "(background process pid=$!) Creating control-cluster..."

    minikube start --driver=${vm_driver} --addons=ingress -p stage-cluster --network=multi-cluster-observability &> /dev/null &
    echo "(background process pid=$!) Creating stage-cluster..."

    minikube start --driver=${vm_driver} --addons=ingress -p prod-cluster --network=multi-cluster-observability &> /dev/null &
    echo "(background process pid=$!) Creating prod-cluster..."

    minikube start --driver=${vm_driver} --addons=ingress -p monitoring-cluster --network=multi-cluster-observability --memory=4096M --cpus=2 &> /dev/null &
    echo -e "(background process pid=$!) Creating monitoring-cluster...\n"

    echo -e "Waiting for the cluster creation background processes to finish\n\n"
    wait

# macOS arm64
elif [[ "$(uname)" == "Darwin" ]] && [[ "$(uname -m)" == "arm64" ]]; then
    vm_driver="docker"
    echo -e "You are on macOS with arm64 architecture, using ${vm_driver} driver\n"

    # Create the control, stage, prod and monitoring clusters
    # The --listen-address and --apiserver-names are used to enable argocd to connect to the other clusters (docker containers) through the apiserver-name
    minikube start -p control-cluster --driver=${vm_driver} --addons=ingress --memory=2048M --cpus=2 --listen-address=0.0.0.0 --apiserver-names=multi-cluster.local &> /dev/null &
    echo "(background process pid=$!) Creating control-cluster..."

    minikube start -p stage-cluster --driver=${vm_driver} --addons=ingress --memory=2048M --cpus=2 --listen-address=0.0.0.0 --apiserver-names=multi-cluster.local &> /dev/null &
    echo "(background process pid=$!) Creating stage-cluster..."

    minikube start -p prod-cluster --driver=${vm_driver} --addons=ingress --memory=2048M --cpus=2 --listen-address=0.0.0.0 --apiserver-names=multi-cluster.local &> /dev/null &
    echo "(background process pid=$!) Creating prod-cluster..."

    minikube start -p monitoring-cluster --driver=${vm_driver} --addons=ingress --memory=4096M --cpus=2 --listen-address=0.0.0.0 --apiserver-names=multi-cluster.local &> /dev/null &
    echo -e "(background process pid=$!) Creating monitoring-cluster...\n"

    echo -e "Waiting for the cluster creation background processes to finish\n\n"
    wait

    # This logic is meant for allowing argocd to add other clusters that are also running as docker containers
    echo -e "[macOS] Changing the cluster servers in kubeconfig to multi-cluster.local from 127.0.0.1"
    clusters=("control-cluster" "stage-cluster" "prod-cluster" "monitoring-cluster")
    for cluster in "${clusters[@]}"; do
        current_server=$(kubectl config view -o jsonpath="{.clusters[?(@.name=='$cluster')].cluster.server}")

        if [[ -n "${current_server}" ]]; then
            new_server="${current_server//127.0.0.1/multi-cluster.local}"

            kubectl config set-cluster "${cluster}" --server="${new_server}"
            echo "Updated cluster '${cluster}' server URL to '${new_server}'"
        else
            echo "Cluster ${cluster} is not in the kubeconfig!"
            exit 1
        fi
    done
else
    echo -e "Unknown system or architecture.\n"
    exit 1;
fi

# Get back to the control-cluster context in kubectl
kubectl config use-context control-cluster

# Install ArgoCD in the control-cluster
echo -e "Creating 'argocd' namespace in the control-cluster...\n"
kubectl create namespace argocd --context control-cluster --dry-run=client -o yaml | kubectl apply -f -
echo -e "Installing ArgoCD in the argocd namespace...\n"
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --context control-cluster

# Wait for up to 5 minutes until the argocd initial admin secret is present
echo -e "\nWait for the argocd initial admin secret to be present...\n"
kubectl wait -n argocd --for=create secret/argocd-initial-admin-secret --timeout=300s --context control-cluster

# Wait for up to 5 minutes until all the argocd pods are ready
echo -e "\nWait for all the argocd pods to be ready...\n"
kubectl wait -n argocd pod --all --for=condition=ready --timeout=300s --context control-cluster

# Enable Helm support in Kustomize for ArgoCD
echo -e "\nConfiguring ArgoCD to enable Helm in Kustomize...\n"
kubectl patch configmap argocd-cm -n argocd --context control-cluster --type merge -p '{"data":{"kustomize.buildOptions":"--enable-helm"}}'

# Restart all ArgoCD components to pick up the new config
echo -e "Restarting all ArgoCD deployments and statefulsets...\n"
kubectl rollout restart deployment -n argocd --context control-cluster
kubectl rollout restart statefulset -n argocd --context control-cluster

# Wait for all deployments to be ready
echo -e "Waiting for ArgoCD deployments, and statefulsets pods to be ready...\n"
kubectl rollout status deployment -n argocd --context control-cluster --timeout=300s
kubectl rollout status statefulset -n argocd --context control-cluster --timeout=300s

# Start kubectl port-forward in the background
echo -e "port forwarding the argocd-server to 127.0.0.1:9797 in the background\n"
kubectl port-forward service/argocd-server -n argocd 9797:443 --context control-cluster &
argo_port_forward_pid=$!

echo -e "Waiting for 5 seconds to make sure the port forwarding is started\n"
sleep 5

# Store the argocd initial admin password
argoURL="127.0.0.1:9797"
argoPassword=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" --context control-cluster | base64 -d)

# Login to argocd
argocd login --insecure ${argoURL} --username admin --password ${argoPassword}

# Add clusters to ArgoCD so that it can actually manage deployments in them
# Note that I am adding labels to these clusters for identification when using the ApplicationSet CR
echo "Adding stage-cluster, prod-cluster, and monitoring-cluster to argocd"

argocd cluster add --upsert stage-cluster --name stage-cluster --label environment=stage -y
argocd cluster add --upsert prod-cluster --name prod-cluster --label environment=prod -y
argocd cluster add --upsert monitoring-cluster --name monitoring-cluster --label environment=monitoring -y

# Update the Alloy agent configurations with the actual monitoring cluster IP
echo -e "Updating the Alloy agent configurations with the actual monitoring cluster IP...\n"
./scripts/update-alloy-agents-endpoints.sh

# Keep the script running to maintain port-forward
echo -e "\n\n================================"
echo "✅ Setup Complete!"
echo "================================"
echo "ArgoCD UI: https://127.0.0.1:9797"
echo "Username: admin"
echo "Password: ${argoPassword}"
echo ""
echo "Press Ctrl+C to stop port-forwarding and exit..."
echo "================================"

# Wait indefinitely until interrupted
wait ${argo_port_forward_pid}
