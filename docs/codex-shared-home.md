# Native Codex CLI and shared history

Ordinary `codex`, `codex resume`, and `codex resume --all` use the native CLI and its default `~/.codex` home
(unless you explicitly set `CODEX_HOME`). CodexBar no longer installs a `codex()` function, rewrites arguments,
or adds `--no-daemon`. Managed account homes retain separate credentials for login and remote quota probes.

Selecting the displayed usage account only changes CodexBar's remote quota view. To change the CLI account,
use **Activate Selected Account for Codex CLI…** (System in Settings). Existing promotion preserves displaced
authentication and atomically replaces shared `auth.json`. Promotion refuses a non-shared app environment or
an explicitly configured non-file credential store (`keyring`, `auto`, `ephemeral`); it never changes storage
policy or writes Keychain. Command-line credential-storage overrides are outside CodexBar's control.

After a real auth replacement, CodexBar selects `.liveSystem` and refreshes account-scoped usage. It does not
inspect, start, stop, restart, or repair the shared daemon. Usage refresh retains account-scoped OAuth requests
and the existing dedicated stdio app-server rate-limit/account RPC fallback; that separate query process is
not the shared daemon. Display-only selection, failed promotion, and converged no-op promotion do not show
the system-switch success notice. The existing Settings notice/menu alert explains that an old background
server may still hold the previous account and how to explicitly bypass it for a new interactive CLI.

## Start or resume with the selected System account

Use the native CLI with `--no-daemon` on **each interactive launch** to bypass even an already-running shared
background server. For example:

```bash
cd ~/Documents/dreamOS
env -u CODEX_HOME /opt/homebrew/bin/codex --no-daemon
env -u CODEX_HOME /opt/homebrew/bin/codex resume --no-daemon 01a11aa8-e0f0-73f0-a4a6-07e0107dd7ee
env -u CODEX_HOME /opt/homebrew/bin/codex resume --all --no-daemon
```

The absolute path bypasses shell functions/aliases; `env -u CODEX_HOME` selects the default shared home.
Check `/status` in the new CLI to confirm its actual account. Resume requires the original session history
to already be present in the shared home; switching credentials does not migrate history.

Bare `codex` and `codex resume` can still reuse an old daemon or report a feature/config mismatch.
`features.daemon_auto_start = false` is not a substitute for explicitly bypassing an existing socket.
CodexBar does not automatically add flags to terminal, IDE, or third-party launches. Do not inject
`--no-daemon` into every subcommand: agents/queue require the shared daemon, while exec and standalone
app-server have different lifecycles. This change does not alter cc-connect or their launch commands.

## Limits and already-disconnected sessions

Removing CodexBar's restart prevents its account switch from intentionally draining the shared background
server. It does **not** guarantee uninterrupted work or strict account isolation: the old server may cache
old credentials, and concurrent OAuth refreshes may race with or write back to shared `auth.json`.
Native Codex updates, other applications, and manual maintenance can still restart a daemon. CodexBar does
not disable native updates, add a file watcher/lock service, or automatically recover a dead daemon.

An already-disconnected CLI is not repaired by installing this change. Save unsent input and confirm what
work was persisted before manually exiting or retrying; do not blindly repeat potentially completed tool
actions. Once no process is writing that session, resume it explicitly with `--no-daemon`. Any repair of
shared daemon/queue/remote-control features is a separate operation for a quiet period, not part of switching.

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

Synthetic homes and existing stubs cover auth promotion/preservation, quota refresh, fail-closed credential
guards, no-op/failed/display-only behavior, success-notice eligibility, and local-cache/remote-home separation.
The daemon helper and its restart-specific tests have been removed, not retained as unreachable code.
A real two-account `/status` and cross-account `resume` check requires separate approval, backup, and native
CLI compatibility validation. Source checks are not a substitute for in-flight task protection acceptance.
Never merge SQLite databases or resume a real managed thread as part of routine testing.

See the [2026-10-09 no-restart validation record](codex-live-session-no-restart-validation-2026-10-09.md).

References: upstream [#4006](https://github.com/steipete/CodexBar/pull/4006) and
[#4018](https://github.com/steipete/CodexBar/pull/4018).
