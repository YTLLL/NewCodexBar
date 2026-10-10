# System account switching without daemon restart — 2026-10-09

Historical record for `c0c41075`. The subsequent
[shell/RPC follow-up](codex-shell-rpc-validation-2026-10-09.md) fixes the RPC approval argument and restores
conservative interactive-only shell flag injection, without restoring daemon restart or account Home routing.

Base: `aaf3979b768d1b482d92cc636a2608b63905aad5`, verified against the fetched remote before editing.
Delivery branch: `fix/native-codex-shared-home-20261008`. No merge, release, app deployment, shell cleanup,
real account switch, history migration, database edits, daemon repair, or task termination in this delivery.
The unrelated untracked root `main` file is preserved.

## Implementation and call-chain review

- Removed the daemon dependency/call from `CodexAccountPromotionService`, `daemonRestartNote` from the
  result/coordinator, and the entire daemon helper and its restart-specific tests. Removed the now-unused
  Darwin PID/argv helpers from `CodexHomeScope`; its shared/managed environment routing remains unchanged.
- Kept shared-home/file-store validation, displaced-account preservation, atomic auth replacement,
  `.liveSystem` selection, and account-scoped usage refresh. Keyring/auto/ephemeral still fail closed.
- Both existing Settings notices and menu alerts use the same stateless coordinator notice eligibility:
  actual `.promoted`, mutated auth, and `.liveSystem`. No notice for display-only/no-op/failure. Updated
  English, Simplified Chinese, and Traditional Chinese; no timer, persistent state, or new UI framework.
- Reviewed `refreshCodexAccountScopedState` through usage, credits, optional dashboard, provider registry,
  OAuth strategy, and `UsageFetcher.loadLatestCLIAccountSnapshot`. The RPC fallback spawns its own stdio
  `codex ... app-server` for account/rate-limit queries, then shuts down that query process. It does not
  issue shared daemon version/restart/stop/start. `ProviderRegistry` and local-cost routing are unchanged.
- No changes to global `SubprocessRunner`, native Codex binaries, cc-connect, user configs, authentication,
  session histories, SQLite, native updates, or runtime process management.

## Automated validation

Tests use `CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1`, `CODEXBAR_TEST_CODEX_FILE_ISOLATION=1`, and
`CODEXBAR_TEST_SESSION_FILE_ISOLATION=1` with synthetic homes.

- `swift build`: passed (17.22 seconds); existing missing-module-cache linker warnings remain.
- Focused `swift test --filter`: **155 Swift Testing tests in 14 suites plus 21 XCTest tests passed**.
  Filter: `CodexAccountPromotion(Service|Preparation|Planning|Execution)Tests|CodexSystemPromotionUITests|CodexAccountScopedRefresh(Tests|CreditsTests|DashboardCleanupTests)|CodexManagedRoutingTests|CodexHistoryOwnershipTests|CodexAccountsSectionStateTests|CodexAccountsSettingsSectionTests|CodexVisibleAccountTests|CodexActiveSourceConfigTests|ProviderRegistryTests|CLIEntryTests|CLIArgumentParsingTests`.
- Additional `swift test --skip-build --filter 'UsageStoreCachedTokenHydrationTests|CostUsageFetcherTests'`:
  **14 tests in 2 suites passed**, including shared cost-cache/isolated remote-usage coverage.
- Total across those non-overlapping focused runs: **190 tests passed**. No full-suite rerun this delivery.
- `make check`: passed; SwiftFormat clean and SwiftLint **0 violations in 1017 files**.
- `git diff --check`: passed. `plutil -lint`: all three edited localization resources passed.
- Fresh debug `CodexBarCLI --help`: passed; no obsolete `codex-home` command exposed.

Raw local logs: `/tmp/newcodexbar-no-restart-focused-20261009.log`,
`/tmp/newcodexbar-no-restart-local-cost-20261009.log`, `/tmp/newcodexbar-no-restart-check-20261009.log`.

The previous full-suite run was **not green**: 3343 tests/392 suites/99 issues; a baseline comparison found
96 matching issues in 209 tests/15 suites, with three additional PathBuilder timing issues not recurring
in the focused repeat. See the [historical record](codex-shared-home-validation-2026-10-08.md). Do not
interpret focused success in this delivery as a claim that the full suite passes.

## Read-only checks and live acceptance boundary

- Installed native CLI **0.160.0** help exposes `--no-daemon` for both new and resumed interactive sessions
  and says it bypasses even an already-running shared background server. Manual native checks only read
  help/version; no real session is launched, account switched, or model request sent. Keychain access is
  suppressed and synthetic credentials are used.
- Important existing compatibility observation: some synthetic refresh tests still spawn the native
  RPC child. Its unchanged `UsageFetcher.swift` default arguments include `-a untrusted`; local Codex
  0.160.0 rejects that value during argument parsing (help lists `on-request` and `never`). These children
  exit before an account RPC completes; the passing stub/model assertions do **not** validate real CLI
  quota fetching. This is a separate existing fallback compatibility defect, not repaired or hidden here.
  No shared daemon lifecycle subcommand or paid model turn is involved. Investigate the RPC launch flags
  separately with a synthetic CLI runner before claiming real usage-query compatibility.
- Source search confirms removal of the daemon helper/old restart note, no shared daemon lifecycle calls,
  and no reintroduced shell routing. User instructions for native absolute-path commands and explicit
  per-launch `--no-daemon` are in [shared-home guidance](codex-shared-home.md).
- Real Jerr/Serena switching, new-session `/status`, cross-account resume, active daemon PID/socket
  continuity, in-flight task protection, cc-connect behavior, and visual notice acceptance are **not
  exercised**. The installed/running app is not updated by this source-only change.
- The QA skill's optional `$autoreview` is unavailable. Manual diff/call-chain review is recorded; no
  independent automated review or real provider-matrix probe is claimed.

## Prior incident evidence, not new-version runtime proof

The earlier local diagnosis recorded an auth-file update at 20:00:48, daemon graceful restart drain at
20:00:49 (two running assistant turns), and CodexBar's restart subprocess timeout at 20:01:18.984
(approximately 30 seconds). Later inspection found daemon PID 91633 defunct and the control socket absent;
the Jerr CLI PID 33875 had been launched without `--no-daemon`. These observations establish the drain,
timeout, and missing backend; they are not a live acceptance test of this change or proof of every native
replacement-process detail. No recovery operation is performed here.

## Remaining risks

Shared `auth.json` can race with concurrent OAuth refresh/writeback. An old daemon may retain old identity;
new `--no-daemon` CLIs should verify `/status`. Bare native CLI launches can still reuse a daemon, and
`features.daemon_auto_start = false` alone cannot exclude an existing socket. Native daemon updates/manual
maintenance can still interrupt work. Third-party providers may separately write shared auth/config; that
is outside this fix. No guarantee of absolute isolation or zero interruption is made.
