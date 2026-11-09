#!/usr/bin/env bash
# Tests for the helm pack: bin/ro reads, destructive commands, deny/ask rules and ro-guard. Runs nothing real.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=tests/lib/pack-test.sh
. "$ROOT/tests/lib/pack-test.sh"

# bin/ro: list/status/history/get metadata, --kube-context mandatory
ro_ok helm list -A --kube-context c
ro_ok helm get metadata r -n n --kube-context c
ro_no helm get values r --kube-context c
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

pack_done "helm pack"
