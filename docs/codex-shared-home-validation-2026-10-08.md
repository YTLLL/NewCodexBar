# Shared-home implementation validation — 2026-10-08

Historical record for the original shared-home delivery, not the current behavior or machine state.
Its automatic daemon restart is removed by the
[2026-10-09 follow-up](codex-live-session-no-restart-validation-2026-10-09.md).
The shell, installed-app, and migration observations below describe the original inspection only; they
must not be used to infer that the wrapper still exists or that history is still unmigrated today.

Baseline: `origin/main@407457c9a9d5278406fe98a7a2976a5b2a2850e8`.
Delivery branch: `fix/native-codex-shared-home-20261008`; no merge, release, or app deployment.

## Implementation

- Reversed the standalone per-account CLI routing commit. Removed its resolver, shell integration/installer,
  `codex-home` command/help, installer additions, and four tests that only exercised that removed feature.
  The original CodexBar CLI symlink installer remains.
- Added a small daemon helper with injectable PID validation and CLI runner. It validates the native process,
  running PID backend, and home-scoped control socket with symlink resolution before restarting. A successful
  auth swap invokes it once; convergence, display selection, and failed swaps do not. Recovery notes preserve
  successful promotion and use existing menu alerts/settings notices.
- Added shared-home and file-credential guards before promotion. No Keychain reads or storage-policy changes.
- Local cost/cache scope stays ambient/shared; its hint explicitly identifies this Mac's cross-account history.
  `ProviderRegistry.swift` remote account routing and the native account menu's Displayed/System semantics
  remain unchanged. Fork bundle IDs, account storage, other providers, and update settings remain unchanged.

## Automated results

Test commands use `CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1`, `CODEXBAR_TEST_CODEX_FILE_ISOLATION=1`, and
`CODEXBAR_TEST_SESSION_FILE_ISOLATION=1`. Debug tests also disable real Keychain access by default.

- `swift build`: passed. Existing module-cache/linker warnings appeared; no build failure.
- Focused account/promotion/daemon/managed-routing/local-cache/menu-model run: **121 tests, 18 suites passed**.
- Final repeat including `PathBuilderTests`: **158 tests, 19 suites passed**.
- `make check`: passed, SwiftFormat clean and SwiftLint **0 violations**.
- `git diff --check`: passed.
- Full `swift test -q`: **3343 tests, 392 suites, 99 issues**. This was not a green full-suite result.
  A separate detached worktree at the exact baseline reran the affected existing suites: **209 tests,
  15 suites, 96 issues**. The 96 matching issues cover headless AppKit menu assumptions, app-group defaults,
  storage refresh timing, and account-info caching. The remaining 3 full-run issues were login-shell retry
  timing assertions in `PathBuilderTests`; they did not recur in the baseline run or final focused repeat.
  No unrelated baseline tests were removed or changed to hide failures.

## Local read-only checks and limits

- Native CLI: **0.160.0**, not 0.162.0. `codex app-server daemon --help` exposes `version` and `restart`.
- Freshly built CodexBar CLI help no longer exposes `codex-home`; source/installer searches found no remaining
  automatic wrapper injection. No real provider usage probe, daemon restart, or real session resume was run.
- Real Serena/Jerr `/status`, cross-account resume, CLI 0.162.0 compatibility, and visual notice acceptance
  remain unperformed. Synthetic tests are not a claim of real two-account acceptance.
- `.zshrc` still has the single paired routing block at lines 130–134. No user shell cleanup was performed,
  and no cleanup approval was requested during this source-only delivery. Existing shells/the installed app
  therefore continue using the previous installation until a separately approved deployment and cleanup.
- The installed `/Applications/CodexBar.app` process remained PID 60651 with embedded commit `c544364e`.
- Original Jerr managed home and its old session were not migrated, resumed, or modified. Before/after SHA-256
  values matched for all four files below, with paths unchanged:

| File in Jerr managed home | SHA-256 |
| --- | --- |
| `sessions/2026/10/08/rollout-2026-10-08T01-37-17-01a11aa8-e0f0-73f0-a4a6-07e0107dd7ee.jsonl` | `2e98e6dba1cd680cf10986346a7c78e4107e35fcb7cdc48aadc2f535d1ee9dd3` |
| `state_5.sqlite` | `162cecd26b4564e4de71d1b988ae300a4796d39d7ccec7aae8eda050401d5374` |
| `state_5.sqlite-wal` | `7fad93c966171a3e32c39063ae2beff0299e93a9e1227a84d5230511a509a9e1` |
| `state_5.sqlite-shm` | `d02025bdaa9c52cde0cb790436925b6e1de90a1b9fe0f2ca0f4dd404fec5f7fe` |

Manual review checked the post-auth restart boundary, PID/socket scoping, cancellation/timeout handling,
failure-note propagation, cost-cache separation, and the exact routing rollback. The optional `$autoreview`
skill mentioned by the QA skill is not installed in this environment; no independent automated review is claimed.
