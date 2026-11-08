# evidence module

Optional module of infra-agent-harness. It gives you:

- an **evidence store** and a **clipboard** shared between your own machines, served on your local network (TLS + token, nothing goes to the internet or to git);
- **encrypted archives** of a work's evidence when you close the work;
- **pluggable secrets backends** (`file` by default, `bitwarden` included, your own in a few lines).

Enable it per work repo in `.harness.conf` (comma list, spaces allowed), then relink from the work repo (`<harness>` is where you cloned infra-agent-harness):

```bash
echo 'modules=evidence' >> .harness.conf     # or: modules=evidence, other
<harness>/bin/link-harness                   # installs cpush / cpull (+ cpush.cmd / cpull.cmd on WSL)
<harness>/bin/doctor                         # evidence checks appear once the module is active
```

`link-harness` finds the active modules in the work repo of the current directory, or in `$IAH_REPO`; the git hooks and `doctor` pass it along. Run from anywhere else, it installs no module.

## Architecture

```
 server host                              other machines (clients)
+--------------------------------+       +------------------------------+
| clip-server (Docker or Podman) |<-TLS->| bin/evidence  sync / archive |
|  server/server.py              | token | cpush / cpull  (bin/clip)    |
|  - clipboard: 1 slot, memory   |  LAN  | client config: url, crt, tok |
|  - evidence store: disk        |       +------------------------------+
+--------------------------------+
      |                                   secrets backend (key backup,
      v                                   `clip --remote` clipboard):
 archive_dir (encrypted .enc)             file | bitwarden | your own
```

- Evidence travels as one `tar.zst` package per folder `evidence/<date>.<slug>/` (folders are immutable once uploaded).
- Server-side packages are checked by sha256 on download.

## Setup

Per-machine settings: `~/.config/infra-agent-harness/evidence.conf` (override the path with `IAH_EVIDENCE_CONF`). Lines `key=value`; parsed as data, nothing is executed; `~/` is expanded.

| Key | Default | Meaning |
|---|---|---|
| `server_host` | none (required for `init` and `clip-server`) | Name clients use to reach the server; also the certificate name |
| `server_port` | `443` | Published port of the server |
| `archive_dir` | `~/evidence-archive` | Where encrypted archives are written |
| `key_fingerprint` | unset | First 12 hex of sha256 of the key file; checked by `key-restore` and `bin/doctor` |
| `secrets_backend` | `file` | `file`, `bitwarden`, or any `backends/<name>.sh` |

Other paths (env overrides): key `~/.config/infra-agent-harness/evidence.key` (`EVIDENCE_KEY`), client config dir `~/.config/infra-agent-harness/clip/` (`EVIDENCE_CLIENT_CONF`), server data `~/.local/share/infra-agent-harness/evidence-store` (`CLIP_SERVER_DATA`).

### Server host

```bash
printf 'server_host=myserver.lan\nserver_port=443\n' > ~/.config/infra-agent-harness/evidence.conf
bin/clip-server up        # creates cert (10 years) + token if missing, starts the container; idempotent
bin/clip-server status    # container, health, keep-awake (WSL), URL
bin/clip-server logs
bin/clip-server down
```

- Engine: `docker` first, then `podman`; force with `CONTAINER_ENGINE=docker|podman`.
- Open the port (inbound TCP) in the host firewall for your private network only.
- Rootless Podman cannot bind port 443: set `server_port=8443` (any port above 1024) and re-run `up`.
- Container: read-only, all capabilities dropped, uid 65534, 64 MB.

### Other machines

From the server host (needs SSH access to that machine):

```bash
bin/clip-server share <ssh-host>     # copies server.crt, token and url to ~/.config/infra-agent-harness/clip/
```

### WSL server host

- Windows firewall: inbound TCP rule for the port, **Private** profile, both the Windows and the Hyper-V rules.
- WSL stops when idle, and the container with it. Run once, yourself: `bin/clip-server keep-awake` (a hidden `sleep infinity` started at logon; remove the generated `wsl-keepalive.vbs` from the Windows Startup folder to undo).
- `bin/link-harness` writes `cpush.cmd` / `cpull.cmd` into `%USERPROFILE%\bin` (and adds it to the user PATH) so the clipboard works from Windows terminals. `LINK_HARNESS_WINDOWS=0` skips this.

## Evidence

Put only filtered data that backs a fact in `evidence/<date>.<slug>/` inside the work. Never secrets, never raw dumps. Loose files directly in `evidence/` are not shared (a warning is printed).

```bash
bin/evidence init    <work-dir>   # sets `evidence_store: <server_host>` in the work README frontmatter; commit it
bin/evidence sync    <work-dir>   # upload folders the store lacks, download the ones missing here
bin/evidence status  <work-dir>   # local folders, store packages, key present/MISSING
bin/evidence archive <work-dir>   # on close: sync, encrypt, verify, delete from store and locally
bin/evidence restore <archive.enc> <dir>
```

- The work README needs `id:` and `company:` in its frontmatter.
- **Store unreachable** (other network, VPN blocking the LAN, host asleep): `sync` prints `store not reachable ... pending; run sync again later` and exits 0. Nothing is lost; repeat later.
- `archive` needs the store and the key. It writes `<archive_dir>/<company>.<id>.<date>.tar.zst.enc`, decrypts it again to compare file counts, and only then deletes the work from the store and the local `evidence/`, and sets `evidence_archive:` in the README. If the check fails nothing is deleted.
- A folder over **2 GB compressed** is kept local only (a warning says so; note it in your record). The server enforces the same limit.
- After archiving, `sync` on a closed work does nothing. Other machines keep whatever local copy they had until you delete it.

## The key

The archive key is a random file, never printed.

```bash
bin/evidence key-new        # first machine only; refuses to overwrite
bin/evidence key-backup     # stores it base64 in the secrets backend as `evidence-key`
bin/evidence key-restore    # other machines: fetch it back from the backend
bin/evidence key-import     # alternative: base64 on stdin
```

- Then pin it: `key_fingerprint=<12 hex>` in `evidence.conf`. `key-restore` discards a key that does not match; `bin/doctor` fails on a mismatch and fixes permissions to 600.
- Get the fingerprint with `sha256sum ~/.config/infra-agent-harness/evidence.key | cut -c1-12`.
- Lose the key and the archives are unrecoverable: keep a backup outside the machine.

## Secrets backends

A backend is an executable `backends/<name>.sh`; the name matches `[a-z0-9-]+`.

| Command | Behaviour |
|---|---|
| `get <name>` | secret on stdout; **exit 1 if missing** |
| `put <name>` | secret from stdin, replaces the old one |
| `status` | optional, one line |
| `lock` | optional (the `file` backend exits 3: nothing to lock) |

Select with `secrets_backend=<name>` in `evidence.conf`. Names used by the module: `evidence-key`, `clipboard`.

- **`file`** (default): one file per secret in `~/.config/infra-agent-harness/secrets` (dir 700, files 600).
- **`bitwarden`**: needs `bw` and `jq`. Each secret is a secure note named `iah-<name>` (`IAH_BW_PREFIX` changes the prefix), max 9000 characters. Set up once:

  ```bash
  bw config server <your server url>   # only for a non-default server
  bw login
  ```

  Unlocking asks for the master password and caches the session for `CLIP_SESSION_TTL_MIN` minutes (default 480) in a 600 file; `lock` forgets it.

### Writing your own (untested examples)

Save as `backends/<name>.sh`, `chmod +x`, then `secrets_backend=<name>`. Both examples below are **untested**.

```bash
#!/usr/bin/env bash
# backends/pass.sh  (untested)
set -euo pipefail
p="iah/${2:?name}"
case "${1:-}" in
  get)    pass show "$p" 2>/dev/null || exit 1 ;;
  put)    pass insert -m -f "$p" >/dev/null ;;
  status) echo "pass: $(pass ls >/dev/null 2>&1 && echo ok || echo unavailable)" ;;
  *)      exit 2 ;;
esac
```

```bash
#!/usr/bin/env bash
# backends/op.sh  (untested; 1Password CLI, item type "Secure Note")
set -euo pipefail
t="iah-${2:?name}"
case "${1:-}" in
  get) op item get "$t" --fields notesPlain 2>/dev/null || exit 1 ;;
  put) v="$(cat)"
       if op item get "$t" >/dev/null 2>&1; then op item edit "$t" "notesPlain=$v" >/dev/null
       else op item create --category "Secure Note" --title "$t" "notesPlain=$v" >/dev/null; fi ;;
  status) op whoami >/dev/null 2>&1 && echo "op: signed in" || echo "op: signed out" ;;
  *) exit 2 ;;
esac
```

## Clipboard

```bash
cpush            # copy something, then send it
cpull            # on the other machine: paste it into your local clipboard
cpush --remote   # through the secrets backend instead of the LAN server
cpull --remote
clip status      # server URL, health, backend status
```

- One slot. The server returns it **and empties it** on `cpull`; `--remote` pulls also blank the backend secret.
- LAN mode keeps the text in server memory only. `--remote` works away from home or behind a VPN (use an end-to-end encrypted backend such as `bitwarden`).
- Max 1,000,000 bytes on the server. Only the size is printed, never the content.
- Local clipboard tool: `pbcopy`/`pbpaste` (macOS), PowerShell (WSL), `wl-copy`/`wl-paste` or `xclip` (Linux).
- Server unreachable: the error suggests `--remote`.

## Day to day, reboots, problems

- After a reboot of the server host the container restarts by itself (`restart: unless-stopped`) once the engine is up; on WSL that needs `keep-awake`. Check with `bin/clip-server status`.
- Server certificate or token regenerated (state deleted): run `clip-server share <ssh-host>` again for each client.

| Symptom | Likely cause | Do |
|---|---|---|
| `server not reachable` on `cpush` | host asleep or off, other network, VPN blocking the LAN, firewall | wake the host; away from home use `--remote` |
| `store not reachable ... pending` | same | repeat `sync` later |
| `nothing to paste` | nothing sent, or already collected | `cpush` again on the other side |
| `no key at ...` | key missing | `key-restore` or `key-import` |
| doctor: fingerprint does NOT match | different key on this machine | `key-import` the right one |
| Podman: cannot bind 443 | rootless | `server_port=8443` |

Reinstall a machine: clone the repo, set `evidence.conf`, `bin/link-harness`, `bin/evidence key-restore` (or `key-import`), `clip-server share` from the server host (or `clip-server up` if it is the server), then `bin/doctor`.

Secrets live in: the key file (`evidence.key`, 600), the client token (`clip/token`, 700 dir), the server-side cert and token (`~/.config/infra-agent-harness/clip-server`), and the secrets backend. The token and certificate can be regenerated; the key cannot, so back it up.

## Security notes

- **Network**: LAN only by design, TLS (self-signed EC certificate pinned by clients through `--cacert`) plus a shared token header. Do not publish the port to the internet. Anyone with the token on your LAN can read and write the clipboard and the store.
- **At rest**: the evidence store (and the archives) sit unencrypted-by-the-module on the server host disk; use full-disk encryption there. Clients keep evidence in plain files too.
- **Archive cipher**: `openssl enc -aes-256-cbc -pbkdf2 -iter 200000`, password derived from the sha256 of the whole key file. **CBC has no integrity protection: a modified archive is not detected before decryption, and corruption may surface only as unpack errors. Confidentiality depends entirely on the key.** Keep the archive dir somewhere you trust and verify provenance yourself.
- The archive contents are checked by file count after encrypting, not authenticated.
- `bin/evidence` and the backends never print the key or secrets, except `get` on stdout.
- **Not tested**: Podman as engine, macOS as server host or client in this module's tests, the `bitwarden` backend beyond syntax and clean failure without `bw`, the `pass` and `op` examples above.

## Tests

Throwaway HOME, server on the loopback interface and key; nothing real is touched.

```bash
bash modules/evidence/tests/backends.sh        # file backend (get/put, modes 700/600, name validation); bitwarden syntax and clean failure without bw
bash modules/evidence/tests/evidence-e2e.sh    # real server.py with two simulated machines: clipboard, init/sync/archive/restore, keys
```

They print `OK` / `FAIL` lines and exit non-zero on failure. Python 3, openssl, curl, zstd, tar and jq are needed (`bin/doctor` checks them).
