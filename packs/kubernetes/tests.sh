#!/usr/bin/env bash
# shellcheck disable=SC2088,SC2016  # '~/…' and '$(…)' are passed to the helpers as the agent types them
# Tests for the kubernetes pack: bin/ro reads, destructive commands, deny/ask rules and ro-guard. Runs nothing real.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=tests/lib/pack-test.sh
. "$ROOT/tests/lib/pack-test.sh"

# bin/ro: read verbs first, --context mandatory, never Secrets
ro_ok kubectl get pods -A --context c
ro_ok kubectl get externalsecrets,clustersecretstores -A --context c
ro_ok kubectl auth can-i list pods --context c
ro_no kubectl get pods
RO_CONTEXTS=c ro_no kubectl get pods --context c --context d
ro_no kubectl get pods --context c --context=d
ro_no kubectl get secrets -A --context c
ro_no kubectl get secret/x -n y --context c
ro_no kubectl describe Secret x --context c
ro_no kubectl get cm,secrets --context c
ro_no kubectl delete pod x --context c
ro_no kubectl apply -f x --context c
ro_no kubectl exec x --context c
ro_no kubectl get pods -w --context c
ro_no kubectl get pods --as admin --context c
ro_no kubectl --context c get pods
RO_CONTEXTS=a ro_no kubectl get pods --context c

# block-destructive-platform
blk "kubectl delete ns x"
blk "kubectl -n prod delete deploy api"
blk "kubectl --context pro delete pod x"
blk "/usr/local/bin/kubectl delete pod x"
blk "sudo kubectl drain node-1"
blk "kubectl cordon node-1"
blk "kubectl scale deploy x --replicas=0"
blk "kubectl -n x scale deploy y --replicas 0"
blk "kubectl rollout undo deploy/x"
blk "ssh mac 'kubectl delete pod x'"
blk "echo \$(kubectl delete pod x)"
blk "kubectl replace --force -f x.yaml"
blk "kubectl -n x replace -f x.yaml --force"
blk "eksctl delete cluster --name pro"
blk "eksctl --region eu-west-1 delete nodegroup --cluster pro --name ng"
blk "argocd app delete x"
blk "argocd cluster rm pro"
blk "flux delete kustomization x"
blk "flux uninstall"
alw "kubectl replace -f x.yaml"
alw "eksctl get cluster"
alw "argocd app sync x"
alw "argocd app list"
alw "flux reconcile kustomization x"
alw "kubectl get pods -n prod"
alw "kubectl -n prod describe deploy api"
alw "kubectl get pods | grep delete"
alw "kubectl logs job/delete-old-data"
alw "kubectl scale deploy x --replicas=3"
alw "kubectl rollout status deploy/x"

# permissions.deny / ask
denied "kubectl delete pod x"
denied "kubectl -n x delete pod y"
denied "kubectl drain node-1 --ignore-daemonsets"
denied "kubectl --context c drain node-1"
denied "eksctl delete cluster --name pro"
asked "kubectl apply -f x.yaml"
asked "kubectl -n x apply -f y.yaml"
unruled "kubectl get pods -A"

# ro-guard: kubectl and its tools only through bin/ro
guarded "kubectl get pods"
guarded "eksctl get cluster"
guarded "argocd app list"
guarded "flux get all"
guarded "k9s -n x"
guarded "kubectx pro"
guarded "kubens x"
guarded "ro aws eks list-clusters --profile P; kubectl delete ns x"
guarded "bin/ro aws eks list-clusters --profile P; kubectl delete ns x"
guarded "bash -c 'kubectl apply -f x'"

# Credential files (credential-files, credential-readers): reading, copying or sending is blocked; using is not
credblk "cat ~/.kube/config"
credblk "cp ~/.kube/config /tmp/k"
credblk "kubectl cp ~/.kube/config ns/pod:/tmp/config"
credread "~/.kube/config"
readdenied "~/.kube/config"
credok "kubectl --kubeconfig ~/.kube/config get pods --context x"
credok "KUBECONFIG=~/.kube/config kubectl get pods"
credok "kubectl cp ns/pod:/var/log/app.log ./app.log"

# Commands that print a secret (secret-commands): shown is blocked, used is not
credblk "kubectl config view --raw"
credblk "kubectl config view --raw=true --minify"
credblk "kubectl config view --flatten > k.yaml"
credblk "kubectl --context c config view --raw"
credblk "kubectl create token default -n x"
credblk "kubectl get secret app -o yaml"
credblk "kubectl get secrets -A -o json"
credblk "kubectl get secret/app -oyaml"
credblk "kubectl get secret app --output=json"
credblk "kubectl get secret app -o jsonpath='{.data.password}' | base64 -d"
credblk "kubectl get configmap,secret -n x -o yaml"
credblk "kubectl get secret app -o yaml > app-secret.yaml"
credblk "kubectl get --raw /api/v1/namespaces/x/secrets/app"
credblk 'echo "$(kubectl get secret app -o json)" > s.json'
credok "kubectl get secrets"
credok "kubectl get secrets -A"
credok "kubectl describe secret app"
credok "kubectl config view"
credok "kubectl config view --minify"
credok "kubectl get pods -o yaml"
credok "kubectl get secret app -o yaml | kubectl apply -n other -f -"
credok 'TOKEN=$(kubectl create token default)'
credok "kubectl create secret generic app --from-literal=a=b"

pack_done "kubernetes pack"
