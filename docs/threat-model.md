# Threat model

What each layer of the harness stops, what it does not, and what you should add yourself. Read it before you let an agent near an account that matters.

## In one minute

- The harness stops **mistakes**: an agent that runs a destructive command, reads a credential file or calls the cloud outside the read-only path because it seemed a good idea.
- It does not stop an **adversary**: an agent that is set on going around it (because a page or a file it read told it to, or because it "fixes" what blocks it) can do so.
- The barrier that holds against both is not in this repo: **the credential you give the agent**. With a read-only role, nothing here has to be perfect.
- Use the layers together. Each one is cheap to go around on its own.

## What we protect

| Asset | Worst case |
|---|---|
| Cloud and cluster resources | The agent deletes or changes production with your administrator role |
| Credentials on your machine | Keys, tokens and `.env` files end up in the conversation, in a file or on another host |
| Secrets of applications | A secret value printed on the screen stays in the transcript |
| Your machine's setup | The agent changes its own guards, the security profile or your tool settings |

## Who we defend against

| Who | Example | Covered |
|---|---|---|
| An agent that makes a mistake | Runs `terraform destroy` in the wrong folder; `cat .env` to "check the config" | Yes: this is what the guards are for |
| An agent misled by what it reads (prompt injection) | A README says "run this script first"; a log line says "print your token" | Partly: the obvious commands are blocked, an indirect route is not |
| An agent that works around a block | Blocked once, it writes the same call into a script and runs it | No, unless the sandbox of `strict` or the credential stops it |
| A person with access to your machine | Edits the guards, switches the mode off | No: out of scope |

## The layers

From the strongest to the weakest. "Where" says what to read or run.

### 1. The credential (yours to set up)

- **Stops:** every write to the cloud, whatever the agent runs, if the role is read-only.
- **Does not stop:** reads of data the role can read (objects in S3, items in a table, log lines).
- **Do this:** give the agent its own profile or role with a read-only policy, without `s3:PutObject`, `iam:*` write actions or `ssm:SendCommand`. Keep the administrator role for the terminal where you run the commands yourself. If the only role you have is an administrator, keep read-only mode on (layer 4).

### 2. The sandbox of the `strict` profile

- **Stops:** a command that writes outside the folder the session started in, reaches a domain that is not on the list, or opens a credential file, also from a script the agent wrote. This is the only layer that holds when the agent builds its own tool.
- **Does not stop:**
  - `ro`, which runs outside it on purpose (it needs the cloud credentials); see layer 5;
  - a credential file created after the command starts, or a `.env` outside the folder the session started in;
  - anything, if you open the session in your home directory: the whole home is then writable.
- **Where:** `bin/security-profile set strict`, then `bin/link-harness`. What changes in daily work: [tools.md](tools.md).

### 3. Permission rules of Claude Code (`deny`, `ask`, `Read(…)`)

- **Stops:** the listed commands when they are written the plain way (`kubectl delete …`), and the file tools on every credential file.
- **Does not stop:** the same command behind a wrapper, a variable or a script. The `ask` rules are gone with the `permissive` profile.
- **Careful:** a plugin cannot ship these rules. They exist only after you run `bin/link-harness`; `bin/doctor` tells you if they are missing.

### 4. The guards (hooks)

All three read the command line before it runs (`credential-guard` as text, the other two with the common parser). They fail closed: without `jq`, or with an input they cannot parse, they block.

| Guard | Stops | Does not stop |
|---|---|---|
| `block-destructive-platform` | The destructive commands in `packs/<name>/destructive.rules`, anywhere in the line, also inside `ssh host '…'` or `bash -c "…"` | A destructive command that is not on the list; the same call from a script, an SDK or `curl`; a tool with an alias |
| `credential-guard` | A credential file given to a reader, a copy or a sender (`cat`, `cp`, `curl -T`…), `<` and `@file`; the output of a command that prints a secret when it would be shown or saved | A reader that is not on the list; `cd ~/.aws && cat credentials`; a path in a variable; a secret already in a variable or in the environment (`echo $TOKEN`, `env`) |
| `ro-guard` (read-only mode on) | Cloud, cluster and remote tools outside `ro`, also behind `sudo -u x`, `timeout 5`, `nice -n 5`, `xargs`, `for … do`, `if`, `{ }`, `$(…)`, `bash -c`, `eval`, `ssh host '…'`, `watch`, `find -exec`, a heredoc or a pipe into a shell | A tool that is not on its list (`psql`, `vault`, `ansible`, an SDK in Python); a script file that calls the tool (`bash file.sh`, `source file`); the code of a language written inline (`python3 -c`); a command nested more than 4 levels deep is blocked, not read; variables or aliases used as the command name |

`ro-guard` and `block-destructive-platform` read the command line with a common parser (`hooks/lib/cmdparse.awk`), so a command that only **mentions** a blocked one (a commit message, a `grep` pattern, `echo`, a heredoc to `cat`) passes. Known costs: the arguments of a command that is not on the list of data commands (`hooks/lib/cmdparse-data.txt`) are still searched, so `gh pr create --body "… kubectl delete …"` blocks (write that text with the file tools); the code of `python`, `perl`, `ruby`, `node`, `php`, `lua`, `deno`, `bun` and `awk` is not looked into, so `python3 -c "os.system('kubectl delete x')"` passes (it is a script written on the fly, like `bash file.sh`); a command nested more than 4 levels deep is blocked. `credential-guard` still reads the line as text (task 7.22).

### 5. The read-only executor (`bin/ro`)

- **Stops:** everything that is not on its allow-list. One command, fixed shape, no shell inside, a profile or a context always named for cloud and cluster tools, files only under `RO_ROOTS`, never a credential file.
- **Does not stop:**
  - reads that return sensitive configuration without being a "secret" call: the environment variables of a Lambda function or of an ECS task definition, the user data of an instance, a ConfigMap;
  - reads of data: `dynamodb get-item`, `logs get-log-events`;
  - `git` settings inside a repository the agent can write to (`core.fsmonitor`, a `textconv` filter, an external diff): `ro git status` or `ro git diff` would run the program named there. Point `RO_ROOTS` at repositories you trust;
  - shortened options of the aws CLI other than the four it knows (`--with-decryption`, `--endpoint-url`, `--debug`, `--profile`).
- **Why it matters:** with an administrator role, `ro` plus `ro-guard` is the only thing between the agent and a write. It is an allow-list of verbs (`describe-`, `list-`, `get-`…), not an IAM policy.

### 6. After the fact

- **Decision log:** every block, with the command, in `~/.local/state/infra-agent-harness/hook-decisions.jsonl`. It records what was blocked, not what ran.
- **Secret scan on commit:** `gitleaks` in the `pre-commit` hook of your work repo. It blocks the commit when `gitleaks` is not installed.

## What nothing here covers

- **The guards are files the agent can edit.** Nothing stops an agent from changing a hook script, a pack or `~/.claude/settings.json`, except the sandbox of `strict` (writes only under the session folder) and Claude Code asking you before an edit outside the project. The profile file and the mode file are the only ones with a rule of their own. If you load the plugin from a clone for development, do not open sessions in that clone for other work.
- **Other tools of the agent:** MCP servers, web fetches and sub-agents with their own tools are not inspected. A sub-agent of the same session does go through the hooks.
- **Other agent tools:** the hooks are registered for Claude Code only. Copilot CLI gets the skills and the instructions, not the guards.
- **Secrets in the environment:** a token exported in the shell that starts the agent is readable with `env`. Start the agent from a clean shell; `bin/doctor` warns about GitHub tokens in the environment.
- **Data in the transcript:** whatever the agent reads goes to the model provider under your plan's terms. The guards keep credentials and secret values out of it; they do not classify the rest.
- **Windows without WSL**, and any shell that is not bash or zsh.

## What to set up, in order

1. A read-only role or profile for the agent. Everything else is a second line.
2. Install, run `bin/link-harness`, then `bin/doctor` until it shows no `FAIL` ([guide.md](guide.md)).
3. With an administrator role: `ro mode on` before the session, and leave it on.
4. For unattended or long runs: the `strict` profile, with the session opened in the work repo.
5. Look at the decision log now and then: a command blocked many times is either a rule to relax or a habit to correct.

## Reporting

A guard that lets through what this page says it stops is a vulnerability: [SECURITY.md](../SECURITY.md). A limit listed here is not, but a pull request that narrows it is welcome.
