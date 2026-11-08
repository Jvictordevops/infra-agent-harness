# two-machine module

Optional module of infra-agent-harness. It lets two machines of yours (or two agent sessions) share one work with a clear split: one session designs and reviews (**architect**), the other one runs things on its side of the fence (**executor**). The only channel between them is git.

Typical use: the executor machine has what the architect lacks (VPN, cloud CLI, a cluster, another tool) and the architect keeps the plan.

## Enable

```bash
echo 'modules=two-machine' >> .harness.conf     # or: modules=two-machine,evidence
<harness>/bin/link-harness                      # links the role skill with the rest
<harness>/bin/doctor                            # two-machine checks appear once the module is active
```

The `role` skill refuses to work if `two-machine` is not in `modules=` of the work repo. Do this on both machines.

## Roles

- **Roles belong to the session, not the tool.** You say "you are the architect" or "you are the executor of X" and the `role` skill applies. Any tool may take either role on the same work.
- **Machine name:** `$IAH_MACHINE`, else the short hostname. The harness has no fixed machine names.
- **Who writes what:**

| Role | Writes | Never writes |
|---|---|---|
| Architect | README, ROADMAP, briefs, decision records | evidence of the executor |
| Executor | new records, `evidence/` | README, ROADMAP, committed records |

Records are new files, so the two machines do not conflict in git.

## Brief and result

- **Brief** = a record by the architect (`RECORD/<date>.brief-<slug>.done.md`, with its task line). Under *Proposal / Result* it says what to do, the constraints (read-only, accounts, environments), which evidence to bring back and when it is done. It is the only "prompt in a file" the method allows.
- **Result** = a record by the executor with the same task id, a self-contained *Facts* section (key data written out, not only links) and a confidence line. The architect reviews it against the evidence and, with your OK, strikes the task.

## Delegated task marker

In the current ROADMAP revision a delegated task is an in-progress item with the executor word and a link to the brief:

```markdown
- **2.3** [~] Inventory of the node groups. Read-only, list sizes and versions. ⇢ executor → [brief](../RECORD/2030-01-02.brief-node-groups.done.md)
```

The word is the vocabulary key `VOC_EXECUTOR` of the repo language (`executor` in `en`, `ejecutor` in `es`). After review the architect strikes the item and removes the marker.

## A delegated task, step by step

1. **Architect machine:** "you are the architect of X". The skill checks the module, syncs (`git pull --rebase`), loads the work.
2. "Delegate 2.3": the skill writes the brief, marks the ROADMAP item `[~]` with the executor marker, adds it to README *In progress*, runs `bin/check-work --changed`, commits and pushes. It tells you what to say on the other machine.
3. **Executor machine:** "you are the executor of X". Same start: check, pull, load. It lists the items with the marker that have no result record yet.
4. The executor reads the brief and runs it inside the constraints. Evidence goes to `evidence/<date>.<slug>/`, filtered, the command next to its result, no secrets.
5. It writes the result record (same task id), runs `bin/check-work --changed`, commits, pulls, pushes. It tells you what to say on the architect machine.
6. **Architect machine:** "what has the executor done?". It reads the result and the evidence it cites, summarizes, proposes, and waits for your OK. With OK it strikes the item; otherwise it writes a new brief that links the previous one.

## Read-only executor

When the brief says read-only (or the cloud role is admin anyway), switch the guard on in the executor machine: `bin/ro mode on`. Every access to clouds, clusters or another machine then goes through `bin/ro`, sub-agents included (see `docs/tools.md`).

- `bin/ro aws … --profile P`, `bin/ro kubectl … --context C`: one allow-listed read-only command, no shell inside.
- `bin/ro --host <ssh-alias> <command>`: runs it on another machine over SSH. The command is validated here and **again on the remote machine** with its own copy of `bin/ro` (its own paths and limits). The remote copy is `~/infra-agent-harness/bin/ro` unless `RO_REMOTE_BIN` says otherwise. Keep the remote harness up to date.
- Per-task limits: `RO_PROFILES=…`, `RO_CONTEXTS=…`. The brief names the allowed ones.

An agent does not start another autonomous agent on the remote machine over SSH: you open the executor session there.

## SSH: closed by default

SSH into a machine is only for installing and maintaining the harness and for `bin/ro --host`. Keep it **closed** and open it only when needed:

- keys only (no passwords), no root, only your user, no full-disk access;
- open it when you ask for it, close it when done;
- if the address of the machine changes, update `HostName` of its alias in `~/.ssh/config`.

### macOS

On the Mac, turn on System Settings > General > Sharing > Remote Login (only your user). Then, with the **public** key of the other machine:

```bash
modules/two-machine/bin/setup-ssh-access --pubkey-file ~/id_ed25519.pub     # or --pubkey 'ssh-ed25519 AAAA… name', or pipe it with `--pubkey-file -`
modules/two-machine/bin/setup-ssh-access --check                              # report only, changes nothing
modules/two-machine/bin/setup-ssh-access --pubkey-file ~/k.pub --cpush       # also send the summary with cpush (evidence module)
```

- Adds the key to `~/.ssh/authorized_keys` (once), writes the drop-in `/etc/ssh/sshd_config.d/100-infra-agent-harness.conf` (asks for sudo, validates with `sshd -t`, reverts if invalid) and checks that Remote Login is on. Idempotent.
- Prints a summary (user and host name to put in the other machine's `~/.ssh/config`). Nothing is sent anywhere unless you pass `--cpush`.
- To close: turn Remote Login off again.

### Linux (manual, untested)

Not tested on a real machine yet. With the public key of the other machine:

```bash
cat other-machine.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\nAllowUsers %s\n' "$USER" \
  | sudo tee /etc/ssh/sshd_config.d/100-infra-agent-harness.conf
sudo sshd -t && sudo systemctl reload sshd      # the unit is "ssh" on Debian/Ubuntu
```

If `sshd -t` fails, remove the drop-in before reloading. Check first that `/etc/ssh/sshd_config` has `Include /etc/ssh/sshd_config.d/*.conf`. Stop the service when you do not need it.

## Evidence

- **With the `evidence` module** (`modules=two-machine,evidence`): the work is marked `evidence_store:` by the evidence command's `init`; the `role` skill runs `sync` when a role starts (and the executor again when it finishes) and `archive` when the work closes. See `modules/evidence/README.md`.
- **Without it:** evidence stays on the machine that made it and is **never in git**. The result record must carry the key data in *Facts*, because the architect will not see the files. The executor says so in its reply.

## Checks and tests

- `bin/doctor` with the module active: machine name, `ssh` present, `RO_REMOTE_BIN`, `role` skill linked. No network calls.
- `modules/two-machine/tests/setup-ssh-access.sh`: argument parsing and `--check` in a throwaway HOME; never touches the real `~/.ssh` or sshd.
