# Native Codex CLI and shared history

CodexBar's shell integration adds `--no-daemon` once to recognized interactive `codex`, `codex resume`, and
`codex fork` launches. It never sets, clears, or overrides `CODEX_HOME`, and never calls `codexbar codex-home`.
Native Codex therefore uses its default shared `~/.codex` home unless **you** explicitly set `CODEX_HOME`.
Managed account homes retain separate credentials for login and remote quota probes, not shell routing.

Selecting the displayed usage account only changes CodexBar's remote quota view. To change the CLI account,
use **Activate Selected Account for Codex CLI…** (System in Settings). Existing promotion preserves displaced
authentication and atomically replaces shared `auth.json`. Promotion refuses a non-shared app environment or
an explicitly configured non-file credential store (`keyring`, `auto`, `ephemeral`); it never changes storage
policy or writes Keychain. Command-line credential-storage overrides are outside CodexBar's control.

After a real auth replacement, CodexBar selects `.liveSystem` and refreshes account-scoped usage. It does not
inspect, start, stop, restart, or repair the shared daemon. Usage refresh retains account-scoped OAuth requests
and the existing dedicated stdio app-server rate-limit/account RPC fallback; that separate query process is
not the shared daemon. Its read-only launch uses `-s read-only -a on-request app-server`, not the obsolete
`untrusted` approval value. Display-only selection, failed promotion, and converged no-op promotion do not show
the system-switch success notice. The existing Settings notice/menu alert explains that an old background
server may still hold the previous account and how to explicitly bypass it for a new interactive CLI.

## Start or resume with the selected System account

Only terminals that have loaded the **updated** shell integration get automatic injection. In those shells:

```bash
codex
codex resume --all
codex resume <SESSION_ID>
codex fork --last
codex -c model_reasoning_effort=high -m <MODEL> resume <SESSION_ID>
```

All receive one leading `--no-daemon`, unless it is already explicitly present. Common separated
`-c`/`--config` and `-m`/`--model` value options, plus `--config=value`/`--model=value`, are recognized before
or after resume/fork. Recognized no-value options are `--no-alt-screen`, `--search`, `--oss`, and (for
resume/fork) `--all`, `--last`, `--include-non-interactive`. Values and quoted arguments remain intact.

Management/non-interactive commands (`exec`, `app-server`, `agents`, `queue`, `remote-control`, `login`, `mcp`,
`help`, etc.), help/version flags, unknown options/commands, missing option values, compact `-c...`/`-m...`,
bare root prompts, and `--` forms pass through **unchanged**. This is deliberately conservative, not a
complete native CLI parser. For an unrecognized interactive form, explicitly add `--no-daemon` yourself.

Absolute-path launches, `command codex`, Go `exec.Command`, IDE processes, and other tools that invoke the
binary directly do not go through a shell function. Use explicit native `--no-daemon` for those interactive
launches to bypass even an already-running shared background server. For example:

```bash
cd ~/Documents/dreamOS
env -u CODEX_HOME /opt/homebrew/bin/codex --no-daemon
env -u CODEX_HOME /opt/homebrew/bin/codex resume --no-daemon 01a11aa8-e0f0-73f0-a4a6-07e0107dd7ee
env -u CODEX_HOME /opt/homebrew/bin/codex resume --all --no-daemon
```

The absolute path bypasses shell functions/aliases; `env -u CODEX_HOME` selects the default shared home.
Check `/status` in the new CLI to confirm its actual account. Resume requires the original session history
to already be present in the shared home; switching credentials does not migrate history.

Without the updated integration, bare `codex` and `codex resume` can still reuse an old daemon or report a
feature/config mismatch. Installing new source does not update a function already loaded by an old shell.
`features.daemon_auto_start = false` is not a substitute for explicitly bypassing an existing socket.
Do not inject `--no-daemon` into every subcommand: agents/queue require the shared daemon, while exec and
standalone app-server have different lifecycles. This change does not alter cc-connect or their launch commands.

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

## In-place shell integration upgrade

The packaged App's startup installer reuses `~/.codexbar/codexbar-codex-routing.sh` and the original source
block in `~/.zshrc` and an already-existing `~/.bashrc`. The legacy name/markers are retained solely to
upgrade in place; the script contains **no account Home routing**. Only the single complete owned block is
replaced, with unrelated text and existing shell-file permissions preserved:

```text
# >>> codexbar codex account routing >>>
# <<< codexbar codex account routing <<<
```

With no markers, the installer appends one block (creating `.zshrc` if absent; it does not create `.bashrc`).
Missing, duplicate, reversed, inline, or malformed markers reject the whole preflight before **any** write,
including script replacement. Symlink/non-regular configuration/script files and a symlinked support
directory are refused instead of followed. Repeated installs leave unchanged file contents and mtimes alone.
Writes are atomic per file, not a multi-file transaction. No PATH change, binary shim, or native CLI patch
is installed; cc-connect, cc-switch, and third-party launch commands are not changed.

After separately installing/running the new App, open a new terminal or explicitly source the updated file
in the shell you want to change. Existing Codex processes keep running; existing shells keep their old
function until reloaded. Bash login shells must already source `.bashrc`; custom `ZDOTDIR`/other shells
need their own explicit source setup. The App does not edit other profile files. Check `type -a codex`
(a shell function is now expected) and `printenv CODEX_HOME`; do not infer correctness from `which` alone.
Loading this integration does not repair a custom `CODEX_HOME` inherited from elsewhere.

## Validation boundary

Synthetic homes and existing stubs cover auth promotion/preservation, quota refresh, fail-closed credential
guards, no-op/failed/display-only behavior, success-notice eligibility, and local-cache/remote-home separation.
The daemon helper and its restart-specific tests have been removed, not retained as unreachable code.
A real two-account `/status` and cross-account `resume` check requires separate approval, backup, and native
CLI compatibility validation. Source checks are not a substitute for in-flight task protection acceptance.
Never merge SQLite databases or resume a real managed thread as part of routine testing.

See the [2026-10-09 no-restart validation record](codex-live-session-no-restart-validation-2026-10-09.md).
The follow-up [shell/RPC validation record](codex-shell-rpc-validation-2026-10-09.md) covers conservative
argument injection, original-wrapper upgrade, marker protection, and native CLI argument parsing.

References: upstream [#4006](https://github.com/steipete/CodexBar/pull/4006) and
[#4018](https://github.com/steipete/CodexBar/pull/4018).
