#!/usr/bin/env bash
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

pack_done "kubernetes pack"
