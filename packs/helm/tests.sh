#!/usr/bin/env bash
# shellcheck disable=SC2088  # '~/…' is passed to the helpers as the agent types it
# Tests for the helm pack: bin/ro reads, destructive commands, deny/ask rules and ro-guard. Runs nothing real.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=tests/lib/pack-test.sh
. "$ROOT/tests/lib/pack-test.sh"

# bin/ro: list/status/history/get metadata, --kube-context mandatory
ro_ok helm list -A --kube-context c
ro_ok helm get metadata r -n n --kube-context c
ro_no helm get values r --kube-context c
ro_ok helm status r -n n --kube-context c
ro_no helm status r --kube-context c -o json
ro_no helm status r --kube-context c -oyaml
ro_no helm status r --kube-context c --output=json
ro_ok helm list -A -o json --kube-context c
RO_CONTEXTS=c ro_no helm list --kube-context c --kube-context d
ro_no helm upgrade r x --kube-context c
ro_no helm list -A

# block-destructive-platform
blk "helm -n x uninstall y"
blk "bash -c \"helm uninstall x\""
blk "helm delete x"
blk "helm del x"
blk "helm un x"
blk "helmfile -e pro apply"
blk "helmfile destroy"
blk "helmfile -e x delete"
blk "helmfile -e pro sync"
blk "helm rollback x 1"
blk "helm -n y rollback x"
alw "helm status rollback-job"
alw "helm -n x list"
alw "helm history x"
alw "helm upgrade x ./chart"
alw "helmfile -e pro diff"

# permissions.deny / ask
denied "helm uninstall x"
denied "helm -n y uninstall x"
asked "helm upgrade x ./chart"
asked "helm -n y upgrade x ./chart"
asked "helm install x ./chart"
asked "helm -n y install x ./chart"
unruled "helm list -A"

# ro-guard: helm and helmfile only through bin/ro
guarded "helm list -A"
guarded "helmfile diff"
guarded "timeout 10 helm upgrade x y"

# Credential files (credential-files): reading, copying or sending is blocked; using is not
credblk "cat ~/.config/helm/registry/config.json"
credblk "cat ~/.config/helm/repositories.yaml"
credblk "cat ~/Library/Preferences/helm/registry/config.json"
credread "~/.config/helm/registry/config.json"
readdenied "~/.config/helm/registry/config.json"
readdenied "~/Library/Preferences/helm/repositories.yaml"
credok "helm repo list"
credok "helm --registry-config ~/.config/helm/registry/config.json pull oci://r/c"

pack_done "helm pack"
