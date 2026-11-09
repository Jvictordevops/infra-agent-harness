#!/usr/bin/env bash
# Tests for the settings merge of bin/link-harness, in a throwaway HOME. Touches nothing real.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"   # physical path: macOS temp dirs sit behind the /var -> /private/var link
trap 'rm -rf "$TMP"' EXIT
export IAH_PROFILE_FILE="$TMP/profile"   # not the machine's profile; no file = standard
S="$TMP/.claude/settings.json"
fail=0
check() { if jq -e "$1" "$S" >/dev/null; then :; else echo "FAIL: $2"; fail=1; fi; }
run() { HOME="$TMP" LINK_HARNESS_WINDOWS=0 "$ROOT/bin/link-harness" --quiet; }
backups() { find "$TMP/.claude" -name 'settings.json.bak-*' | wc -l | tr -d ' '; }

# 1. No settings yet
run
check '.permissions.deny | index("Bash(kubectl * delete *)")' "deny rules installed"
check '.permissions.ask | index("Bash(git push --force*)")' "ask rules installed"
check '[.hooks.PreToolUse[].hooks[].command] | length == 3' "three hooks registered"
check '[.hooks.PreToolUse[] | select(.matcher == "Bash|Read|Grep") | .hooks[].command | select(endswith("/credential-guard.sh"))] | length == 1' "credential-guard registered for Bash, Read and Grep"
check '.permissions.deny | index("Read(~/.ssh/id_ed25519)") and index("Read(//**/.env)")' "Read deny rules of the core credential files installed"
check '.permissions.deny | index("Read(~/.aws/credentials)") and index("Read(~/.kube/config)")' "Read deny rules of the pack credential files installed"
check "[.hooks.PreToolUse[].hooks[].command] | all(startswith(\"$ROOT/hooks/\"))" "hook paths point to the repo"

# 2. Existing settings: keep everything, no duplicates
cat > "$S" <<EOF
{ "permissions": { "additionalDirectories": ["~/code"], "deny": ["Bash(kubectl delete *)", "Read(./.env)"] },
  "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [
    { "type": "command", "command": "/home/x/other-tool/hooks/block-git-write.sh" },
    { "type": "command", "command": "/home/x/infra-agent-harness/hooks/block-destructive-platform/block-destructive-platform.sh" } ] } ] },
  "model": "opus" }
EOF
sleep 1; run
check '.permissions.additionalDirectories == ["~/code"]' "additionalDirectories kept"
check '.model == "opus"' "other keys kept"
check '.permissions.deny | index("Read(./.env)")' "own deny rule kept"
check '[.permissions.deny[] | select(. == "Bash(kubectl delete *)")] | length == 1' "no duplicate deny rule"
check '[.hooks.PreToolUse[].hooks[].command | select(endswith("block-destructive-platform.sh"))] | length == 1' "block-destructive not duplicated"
check '[.hooks.PreToolUse[].hooks[].command | select(endswith("ro-guard.sh"))] | length == 1' "ro-guard added"
check '[.hooks.PreToolUse[].hooks[].command | select(endswith("block-git-write.sh"))] | length == 1' "other hook kept"
[ "$(backups)" = 1 ] || { echo "FAIL: one backup expected, got $(backups)"; fail=1; }

# 3. Idempotent
before="$(cat "$S")"; sleep 1; run
[ "$(cat "$S")" = "$before" ] || { echo "FAIL: second run changed the file"; fail=1; }
[ "$(backups)" = 1 ] || { echo "FAIL: second run made a backup"; fail=1; }

# 4. Non-plugin mode (IAH_PLUGIN=0): skills are linked into ~/.claude/skills
first="$(basename "$(find "$ROOT/skills" -mindepth 1 -maxdepth 1 -type d | head -1)")"
IAH_PLUGIN=0 run
[ -L "$TMP/.claude/skills/$first" ] || { echo "FAIL: manual mode did not link skills"; fail=1; }

# 5. Plugin mode (IAH_PLUGIN=1): own skill links removed, unrelated ones kept, hooksPath -> stable link
mkdir -p "$TMP/other-skill" "$TMP/work"; ln -s "$TMP/other-skill" "$TMP/.claude/skills/mine"
git init -q "$TMP/work"
export IAH_STABLE_LINK="$TMP/share/current"
(cd "$TMP/work" && IAH_PLUGIN=1 HOME="$TMP" LINK_HARNESS_WINDOWS=0 "$ROOT/bin/link-harness" --quiet)
[ ! -e "$TMP/.claude/skills/$first" ] || { echo "FAIL: plugin mode kept the skill link"; fail=1; }
[ -L "$TMP/.claude/skills/mine" ] || { echo "FAIL: plugin mode removed an unrelated link"; fail=1; }
[ "$(git -C "$TMP/work" config core.hooksPath)" = "$IAH_STABLE_LINK/bin/hooks" ] || { echo "FAIL: hooksPath not set to the stable link"; fail=1; }
[ -L "$TMP/.copilot/skills/$first" ] || { echo "FAIL: plugin mode: no Copilot skill link"; fail=1; }
git -C "$TMP/work" config core.hooksPath /opt/custom/hooks
(cd "$TMP/work" && IAH_PLUGIN=1 HOME="$TMP" LINK_HARNESS_WINDOWS=0 "$ROOT/bin/link-harness" --quiet 2>/dev/null)
[ "$(git -C "$TMP/work" config core.hooksPath)" = /opt/custom/hooks ] || { echo "FAIL: custom hooksPath overwritten"; fail=1; }
git -C "$TMP/work" config core.hooksPath "/home/x/.claude/plugins/cache/m/infra-agent-harness/0.1.0/bin/hooks"
(cd "$TMP/work" && IAH_PLUGIN=1 HOME="$TMP" LINK_HARNESS_WINDOWS=0 "$ROOT/bin/link-harness" --quiet)
[ "$(git -C "$TMP/work" config core.hooksPath)" = "$IAH_STABLE_LINK/bin/hooks" ] || { echo "FAIL: plugin cache hooksPath not replaced"; fail=1; }

# 6. Plugin mode, fresh settings: deny/ask rules only, never hooks (the plugin registers the guards)
SL="$IAH_STABLE_LINK"; mkdir -p "$SL/skills"
prun() { (cd "$TMP/work" && IAH_PLUGIN=1 HOME="$TMP" LINK_HARNESS_WINDOWS=0 "$ROOT/bin/link-harness" "$@" 2>&1); }
rm -f "$TMP/.claude/settings.json"
prun --quiet >/dev/null
check '.permissions.deny | index("Bash(kubectl * delete *)")' "plugin mode: deny rules installed"
check '.permissions.ask | index("Bash(git push --force*)")' "plugin mode: ask rules installed"
check '(.hooks // {}) | has("PreToolUse") | not' "plugin mode: hooks added to a fresh settings.json"

# 7. Plugin mode: stable-link guard entries removed (with backup), foreign ones kept with a message
ROG="$SL/hooks/ro-guard/ro-guard.sh"; BDP="$SL/hooks/block-destructive-platform/block-destructive-platform.sh"
CRG="$SL/hooks/credential-guard/credential-guard.sh"
FOREIGN="/home/x/other-harness/hooks/ro-guard/ro-guard.sh"
cat > "$S" <<EOF
{ "permissions": { "deny": ["Bash(kubectl delete *)"] },
  "hooks": { "PreToolUse": [
    { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$ROG" }, { "type": "command", "command": "$BDP" } ] },
    { "matcher": "Bash|Read|Grep", "hooks": [ { "type": "command", "command": "$CRG" } ] },
    { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$FOREIGN" }, { "type": "command", "command": "/home/x/other-tool/hooks/block-git-write.sh" } ] } ],
    "SessionStart": [ { "hooks": [ { "type": "command", "command": "/home/x/start.sh" } ] } ] },
  "model": "opus" }
EOF
cp "$S" "$TMP/settings.before"
b0="$(backups)"
out="$(prun --dry-run)"
cmp -s "$S" "$TMP/settings.before" || { echo "FAIL: plugin mode --dry-run changed settings.json"; fail=1; }
[ "$(backups)" = "$b0" ] || { echo "FAIL: plugin mode --dry-run made a backup"; fail=1; }
grep -qF "would: remove hook $ROG from settings.json (the plugin registers it)" <<<"$out" || { echo "FAIL: dry-run does not list the ro-guard removal"; fail=1; }
grep -qF "would: remove hook $BDP from settings.json (the plugin registers it)" <<<"$out" || { echo "FAIL: dry-run does not list the block-destructive removal"; fail=1; }
grep -qF "would: remove hook $CRG from settings.json (the plugin registers it)" <<<"$out" || { echo "FAIL: dry-run does not list the credential-guard removal"; fail=1; }
sleep 1
out="$(prun)"
grep -qF "kept hook $FOREIGN in settings.json (not this harness; the guard will run twice: the plugin also registers it)" <<<"$out" || { echo "FAIL: no message for the foreign guard entry"; fail=1; }
[ "$(backups)" = "$((b0 + 1))" ] || { echo "FAIL: removal made no backup"; fail=1; }
check "[.hooks.PreToolUse[].hooks[].command] | index(\"$ROG\") == null and index(\"$BDP\") == null and index(\"$CRG\") == null" "stable-link guard entries not removed"
check "[.hooks.PreToolUse[].hooks[].command] | index(\"$FOREIGN\") != null" "foreign guard entry removed"
check '[.hooks.PreToolUse[].hooks[].command] | index("/home/x/other-tool/hooks/block-git-write.sh") != null' "other hook removed"
check '(.hooks.PreToolUse | length) == 1' "emptied PreToolUse group kept"
check '.hooks.SessionStart | length == 1' "SessionStart hook lost"
check '.model == "opus" and (.permissions.ask | index("Bash(git push --force*)"))' "other keys / ask rules lost"
before="$(cat "$S")"; sleep 1; prun --quiet >/dev/null
[ "$(cat "$S")" = "$before" ] || { echo "FAIL: plugin mode second run changed the file"; fail=1; }
# only our entries: the whole PreToolUse key disappears when it becomes empty
cat > "$S" <<EOF
{ "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$ROG" }, { "type": "command", "command": "$BDP" } ] } ] } }
EOF
prun --quiet >/dev/null
check '(.hooks // {}) | has("PreToolUse") | not' "empty PreToolUse key left behind"

# 8. Manual mode still adds the hooks
rm -f "$S"
(cd "$TMP/work" && IAH_PLUGIN=0 HOME="$TMP" LINK_HARNESS_WINDOWS=0 "$ROOT/bin/link-harness" --quiet >/dev/null 2>&1)
check '[.hooks.PreToolUse[].hooks[].command] | length == 3' "manual mode: hooks not registered"

# 9. Security profile: permissive removes the ask rules of the packs (listed), keeps the core asks, the user's own
#    asks and every deny rule; standard adds them back.
PACK_ASKS='["Bash(terraform apply *)", "Bash(tofu apply *)", "Bash(terragrunt * apply *)", "Bash(kubectl apply *)", "Bash(helm upgrade *)", "Bash(helm * install *)"]'
nopack="(.permissions.ask // []) as \$a | $PACK_ASKS | all(. as \$r | \$a | index([\$r]) | not)"
allpack="(.permissions.ask // []) as \$a | $PACK_ASKS | all(. as \$r | \$a | index([\$r]))"
check "$allpack" "standard: ask rules of the packs installed"
jq '.permissions.ask += ["Bash(npm publish *)"]' "$S" > "$TMP/s.json" && mv "$TMP/s.json" "$S"
deny_before="$(jq -c '.permissions.deny' "$S")"
printf 'profile=permissive\npacks=none\n' > "$IAH_PROFILE_FILE"
cp "$S" "$TMP/settings.before"; b0="$(backups)"
out="$(IAH_PLUGIN=0 HOME="$TMP" LINK_HARNESS_WINDOWS=0 "$ROOT/bin/link-harness" --dry-run 2>&1)"
cmp -s "$S" "$TMP/settings.before" || { echo "FAIL: permissive --dry-run changed settings.json"; fail=1; }
grep -qF "would: remove ask rule Bash(terraform apply *) from settings.json (security profile permissive)" <<<"$out" || { echo "FAIL: dry-run does not list the ask rules it would remove"; fail=1; }
sleep 1
out="$(IAH_PLUGIN=0 HOME="$TMP" LINK_HARNESS_WINDOWS=0 "$ROOT/bin/link-harness" 2>&1)"
grep -qF "removing ask rule Bash(kubectl apply *) from settings.json (security profile permissive)" <<<"$out" || { echo "FAIL: permissive does not list the ask rules it removes"; fail=1; }
[ "$(backups)" = "$((b0 + 1))" ] || { echo "FAIL: permissive made no backup"; fail=1; }
check "$nopack" "permissive: ask rules of the packs left in settings.json"
check '.permissions.ask | index(["Bash(git push --force*)"]) and index(["Bash(git reset --hard*)"])' "permissive: core ask rules (git) removed"
check '.permissions.ask | index(["Bash(npm publish *)"])' "permissive: the user's own ask rule removed"
[ "$(jq -c '.permissions.deny' "$S")" = "$deny_before" ] || { echo "FAIL: permissive changed the deny rules"; fail=1; }
before="$(cat "$S")"; sleep 1
out="$(IAH_PLUGIN=0 HOME="$TMP" LINK_HARNESS_WINDOWS=0 "$ROOT/bin/link-harness" 2>&1)"
[ "$(cat "$S")" = "$before" ] || { echo "FAIL: permissive second run changed the file"; fail=1; }
! grep -q "removing ask rule" <<<"$out" || { echo "FAIL: permissive second run lists removals"; fail=1; }
printf 'profile=standard\n' > "$IAH_PROFILE_FILE"
run
check "$allpack" "back to standard: ask rules of the packs not added again"
check '.permissions.ask | index(["Bash(npm publish *)"])' "back to standard: the user's own ask rule lost"
[ "$(jq -c '.permissions.deny' "$S")" = "$deny_before" ] || { echo "FAIL: back to standard changed the deny rules"; fail=1; }
# plugin mode follows the profile too
printf 'profile=permissive\n' > "$IAH_PROFILE_FILE"
prun --quiet >/dev/null
check "$nopack" "plugin mode, permissive: ask rules of the packs left in settings.json"
rm -f "$IAH_PROFILE_FILE"

# 10. Sandbox: strict turns it on with the core and chosen-pack domains, ro outside it and every credential file
#     denied inside it; a pack not chosen takes its domains back; standard takes back what strict added (named)
#     and keeps the user's own sandbox entries.
lh() { IAH_PLUGIN=0 HOME="$TMP" LINK_HARNESS_WINDOWS=0 "$ROOT/bin/link-harness" "$@" 2>&1; }
has() { grep -qF "$1" <<<"$out" || { echo "FAIL: $2"; fail=1; }; }
jq '.sandbox = {"network": {"allowedDomains": ["pypi.org"]}, "excludedCommands": ["docker compose *"]}' "$S" > "$TMP/s.json" && mv "$TMP/s.json" "$S"
printf 'profile=strict\n' > "$IAH_PROFILE_FILE"
cp "$S" "$TMP/settings.before"
out="$(lh --dry-run)"
cmp -s "$S" "$TMP/settings.before" || { echo "FAIL: strict --dry-run changed settings.json"; fail=1; }
has "would: enable the sandbox (security profile strict)" "strict --dry-run does not say it would enable the sandbox"
sleep 1; out="$(lh)"
has "enabling the sandbox (security profile strict)" "strict does not say it enables the sandbox"
ncred="$(bash -c '. "$1/bin/lib/packs.sh"; . "$1/bin/lib/profile.sh"; packs_sandbox "$1" strict' _ "$ROOT" | jq '.creds | length')"
[ "$(grep -c 'sandbox (security profile strict)' <<<"$out")" = 1 ] || { echo "FAIL: strict names the sandbox more than once: $out"; fail=1; }
has "enabling the sandbox (security profile strict): 6 allowed domain(s), $ncred credential file(s) denied inside it, outside it: docker compose *, ro *, bin/ro *" "strict: the sandbox message does not count domains, files and commands"
check '.sandbox.enabled == true and .sandbox.failIfUnavailable == true and .sandbox.allowUnsandboxedCommands == false' "strict: sandbox on, failIfUnavailable, no unsandboxed retry"
check '.sandbox.excludedCommands | index(["ro *"]) and index(["bin/ro *"]) and index(["docker compose *"])' "strict: ro outside the sandbox, the user's command kept"
check '.sandbox.network.allowedDomains | index(["github.com"]) and index(["registry.terraform.io"]) and index(["pypi.org"])' "strict: core, pack and user domains"
check '.sandbox.network.strictAllowlist == true' "strict: a domain not listed must be refused (strictAllowlist)"
check '.sandbox.credentials.files | index([{"path": "~/.aws/credentials", "mode": "deny"}]) and index([{"path": "**/.env", "mode": "deny"}]) and index([{"path": "~/.ssh/id_ed25519", "mode": "deny"}])' "strict: credential files denied inside the sandbox"
check '[.sandbox.credentials.files[].path] | all(startswith("/") | not)' "strict: an absolute credential path (the Linux sandbox skips a leading glob)"
before="$(cat "$S")"; out="$(lh)"
[ "$(cat "$S")" = "$before" ] || { echo "FAIL: strict second run changed the file"; fail=1; }
! grep -q "sandbox" <<<"$out" || { echo "FAIL: strict second run names sandbox changes"; fail=1; }
printf 'profile=strict\npacks=aws\n' > "$IAH_PROFILE_FILE"
out="$(lh)"
has "removing allowed domain registry.terraform.io from the sandbox (its pack is not chosen)" "strict, packs=aws: the terraform domains not named"
check '.sandbox.network.allowedDomains | (index(["registry.terraform.io"]) | not) and index(["github.com"]) and index(["pypi.org"])' "strict, packs=aws: terraform domains left, or core/user ones lost"
check '.sandbox.credentials.files | index([{"path": "~/.terraformrc", "mode": "deny"}])' "strict, packs=aws: credential files of a pack not chosen dropped (they are the floor)"
printf 'profile=standard\n' > "$IAH_PROFILE_FILE"
sleep 1; out="$(lh)"
has "disabling the sandbox (security profile standard" "standard does not say it disables the sandbox"
has "removing ro * from the commands outside the sandbox (security profile standard)" "standard does not name the commands it takes back"
check '.sandbox | (has("enabled") or has("failIfUnavailable") or has("allowUnsandboxedCommands") or has("credentials")) | not' "standard: strict flags or credential files left"
check '.sandbox.network == {"allowedDomains": ["pypi.org"]} and .sandbox.excludedCommands == ["docker compose *"]' "standard: the user's sandbox entries lost, or harness entries left (strictAllowlist included)"
jq 'del(.sandbox)' "$S" > "$TMP/s.json" && mv "$TMP/s.json" "$S"
printf 'profile=strict\n' > "$IAH_PROFILE_FILE"; lh >/dev/null
printf 'profile=permissive\n' > "$IAH_PROFILE_FILE"; lh >/dev/null
check 'has("sandbox") | not' "permissive: an empty sandbox block left behind"
printf 'profile=strict\n' > "$IAH_PROFILE_FILE"
prun --quiet >/dev/null
check '.sandbox.enabled == true and (.sandbox.excludedCommands | index(["ro *"]))' "plugin mode, strict: sandbox not merged"
rm -f "$IAH_PROFILE_FILE"

if [ "$fail" = 0 ]; then echo "link-harness settings: all tests passed"; else echo "link-harness settings: tests FAILED"; exit 1; fi
