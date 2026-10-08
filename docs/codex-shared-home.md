# Native Codex CLI and shared history

Ordinary `codex`, `codex resume`, and `codex resume --all` use the native CLI and its default `~/.codex` home
(unless you explicitly set `CODEX_HOME`). CodexBar no longer installs a `codex()` function, rewrites arguments,
or adds `--no-daemon`. Managed account homes retain separate credentials for login and remote quota probes.

Selecting the displayed usage account only changes CodexBar's remote quota view. To change the CLI account,
use **Activate Selected Account for Codex CLI…** (System in Settings). Existing promotion preserves displaced
authentication and atomically replaces shared `auth.json`. Promotion refuses a non-shared app environment or
an explicitly configured non-file credential store (`keyring`, `auto`, `ephemeral`); it never changes storage
policy or writes Keychain. Command-line credential-storage overrides are outside CodexBar's control.

After a real auth replacement, CodexBar checks `app-server-daemon/daemon.pid` and `app-server.pid`, native
`codex app-server --listen unix://` argv, and `daemon version` status/backend/control socket. Socket comparisons
resolve symlinks on both sides. Only a verified daemon for the shared home receives `daemon restart`.
No verified process means no CLI call. Detection has a 10-second timeout; restart has a 30-second timeout and
is drained despite caller cancellation. A failure leaves the successful auth switch in place and shows a
manual recovery note. Switch System accounts when no tasks are running: a daemon restart can interrupt work.

Local token/cost is labelled **This Mac** and reads the shared session pool across accounts. It is not per-account
attribution. The old managed-home JSONL and SQLite files remain untouched; migration is a separate task.

## One-time cleanup for installations of the old shell wrapper

Updating the source or app does not remove a function already sourced by an existing shell. With explicit user
approval, first back up each affected shell file and remove only its single, complete block bounded by:

```text
# >>> codexbar codex account routing >>>
# <<< codexbar codex account routing <<<
```

Check `~/.zshrc` and `~/.bashrc`. If a marker is missing or duplicated, stop and inspect manually. Do not remove
unrelated shell code. The generated `~/.codexbar/codexbar-codex-routing.sh` can be backed up and removed only
after confirming its provenance; otherwise leave it and remove only the managed source reference.
CodexBar does not run this cleanup on startup.

Open a new terminal, check `type -a codex` resolves the real CLI, and compare `command codex --help` with
`codex --help`. Inspect `printenv CODEX_HOME`; locate any remaining user-defined setting before changing it.

## Validation boundary

Synthetic homes and injected runners cover promotion, PID/socket checks, cancellation, failure notes,
display-only selection, and local-cache/remote-home separation. A real two-account `/status` and cross-account
`resume` check requires a separately approved quiet period, backup, and native CLI compatibility validation.
Source checks are not a substitute for that runtime acceptance. Never merge SQLite databases or resume an old
managed thread as part of testing this change.

References: upstream [#4006](https://github.com/steipete/CodexBar/pull/4006) and
[#4018](https://github.com/steipete/CodexBar/pull/4018).
