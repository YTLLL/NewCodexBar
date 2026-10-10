# Conservative shell no-daemon integration and RPC compatibility — 2026-10-09

Before: `c0c410758760eb95863ad4b430ca8cfaffbf8f4e`.
Branch: `fix/native-codex-shared-home-20261008`, repository `YTLLL/NewCodexBar`.
Fetched remote HEAD matched the local baseline before editing. The unrelated untracked root `main` is preserved.
No merge, App installation/relaunch, real shell configuration changes, real account switches, session resume,
model requests, daemon lifecycle operations, history migration, or SQLite edits are performed here.

## Changes and review

- `UsageFetcher.swift`: only changes the default RPC argv to
  `-s read-only -a on-request app-server`. No sandbox relaxation, quota-flow change, credential routing change,
  or shared daemon use. A fake RPC executable captures actual process argv and `CODEX_HOME`, returns account
  and rate-limit responses, and verifies both launch flags and the preserved account-scoped Home.
- `CodexCLIShellIntegration.swift`: restores a shell function at the original generated file/marker locations,
  but not the old Home resolver. Conservative recognition adds one `--no-daemon` to interactive new/resume/fork
  invocations; explicit flags, management commands, help/version, unknown options/commands, incomplete value
  options, and ambiguous forms pass through unchanged. Common `-c`/`-m` and long equivalents are supported.
  No `CODEX_HOME` assignments, helper calls, global PATH changes, native binary modification, or shim.
- `CodexCLIShellIntegrationInstaller.swift` and `CodexbarApp.swift`: reuse the original packaged-App startup
  hook and in-place source block. Preflight all files, preserve unrelated text/permissions, refuse malformed
  markers/symlinks/non-regular files, and avoid rewriting identical files. Default targets remain `.zshrc`
  and an existing `.bashrc`; SwiftPM/test bundles do not install. Writes are per-file atomic, not a transaction.
- `CodexAccountPromotionCoordinator.swift` and en/zh-Hans/zh-Hant resources: keep the real-promotion-only success
  notice, now accurately distinguishing updated-shell automatic injection from direct binary launches.
- `docs/codex-shared-home.md`, this record, the historical validation note, and `CHANGELOG.md` are synchronized.
- `CodexAccountPromotionService`, provider routing, local-cost routing, global `SubprocessRunner`, and
  cc-connect/cc-switch are unchanged. Source search confirms no restored daemon helper or lifecycle command.
  The System-switch no-restart behavior from `c0c41075` is preserved.

## Automated results

Changed files (15):

```text
Sources/CodexBarCore/UsageFetcher.swift
Sources/CodexBarCore/Providers/Codex/CodexCLIShellIntegration.swift
Sources/CodexBar/CodexCLIShellIntegrationInstaller.swift
Sources/CodexBar/CodexbarApp.swift
Sources/CodexBar/CodexAccountPromotionCoordinator.swift
Sources/CodexBar/Resources/en.lproj/Localizable.strings
Sources/CodexBar/Resources/zh-Hans.lproj/Localizable.strings
Sources/CodexBar/Resources/zh-Hant.lproj/Localizable.strings
Tests/CodexBarTests/CodexUsageFetcherFallbackTests.swift
Tests/CodexBarTests/CodexCLIShellIntegrationTests.swift
Tests/CodexBarTests/CodexCLIShellIntegrationInstallerTests.swift
docs/codex-shared-home.md
docs/codex-live-session-no-restart-validation-2026-10-09.md
docs/codex-shell-rpc-validation-2026-10-09.md
CHANGELOG.md
```

QA uses synthetic stores/homes and fake CLIs, with `CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1`,
`CODEXBAR_TEST_CODEX_FILE_ISOLATION=1`, and `CODEXBAR_TEST_SESSION_FILE_ISOLATION=1`.

- Final `swift build`: **passed**, 5.39 seconds. Existing module-cache/linker warnings remain.
- Final focused `swift test --filter`: **110 Swift Testing tests in 11 suites plus 21 XCTest tests passed**
  (131 total). Filter:
  `CodexCLIShellIntegrationTests|CodexCLIShellIntegrationInstallerTests|CodexUsageFetcherFallbackTests|CodexAccountPromotion(Service|Preparation|Planning|Execution)Tests|CodexSystemPromotionUITests|CodexManagedRoutingTests|UsageStoreCachedTokenHydrationTests|CostUsageFetcherTests|CLIEntryTests`.
- Shell cases actually launch both `/bin/zsh` and `/bin/bash` against temporary `.zshrc`/`.bashrc`, with a fake
  Codex recording NUL-delimited argv/environment. Coverage includes interactive injection, explicit flag
  deduplication, management passthrough (including a **fake** `app-server daemon restart` invocation), option
  value preservation, quotes/spaces, ambiguous-form passthrough, native exit status, and before/after
  `CODEX_HOME`/PATH invariance. Both unset and empty `CODEX_HOME` remain distinct and unchanged.
- Installer cases cover old-wrapper upgrade in both shells, prefix/suffix and mode preservation, repeated
  install with unchanged mtimes, absent shell files, whole-preflight rejection for seven broken marker forms,
  symlink protection, test-bundle exclusion, and a fake packaged-bundle startup entry. Nothing is installed
  into the real home or Applications directory.
- `make check`: **passed**, SwiftFormat clean; SwiftLint **0 violations in 1021 files**. The first run found
  six multiline-argument formatting violations in the new tests; all were fixed before final validation.
- `git diff --check`: **passed**. `plutil -lint` passes for all three changed localization files.
- Full suite is **not rerun** and is not claimed green. Previous baseline/full-suite failures remain documented
  in the [historical shared-home record](codex-shared-home-validation-2026-10-08.md).
- The QA skill's optional `$autoreview` is unavailable. Manual diff/call-chain review is performed instead;
  no independent automated review or real provider-matrix probe is claimed.

Final logs: `/tmp/newcodexbar-shell-rpc-build-final-20261009.log`,
`/tmp/newcodexbar-shell-rpc-focused-final-20261009.log`, `/tmp/newcodexbar-shell-rpc-check-final-20261009.log`.

## Native CLI parameter parsing, without auth or model requests

The installed CLI **0.160.0** accepts the final argv plus `--help` with exit status **0**, in an empty temporary Home:

```bash
env -i HOME="$task_rpc_home" CODEX_HOME="$task_rpc_home/.codex" \
  PATH=/opt/homebrew/bin:/usr/bin:/bin \
  /opt/homebrew/bin/codex -s read-only -a on-request app-server --help
```

`task_rpc_home` is `/tmp/newcodexbar-rpc-parse.gfN5Yn`, created with `mktemp -d`; no credentials/config copied.
The initial `/usr/bin:/bin`-only environment could not locate the launcher's Node runtime; adding its existing
Homebrew directory to this **child process's** PATH allowed parsing. The user's PATH is not changed.
Only help/version are inspected: no app-server is started, no account/rate-limit RPC is sent to OpenAI,
and no paid model request/session is created. This is a parsing Gate, not real-account quota acceptance.

## User-owned live Gates, not performed

- Install/run the new packaged App, inspect the real marker block/script, then open a terminal that loads it.
  Existing shells are not reloaded by this delivery. Bash login shells must already load `.bashrc`; custom
  `ZDOTDIR`/other shell setup is not rewritten. Direct absolute-path/Go `exec.Command` calls bypass functions.
- Real Jerr/Serena System switching and `/status`, cross-account resume, and active-task continuity are to be
  exercised by the user. No guarantee of strict concurrent-account isolation or zero interruption is made.
- Existing daemon cached identity, shared `auth.json` OAuth-writeback races, native daemon updates, and
  third-party auth/config writes remain outside this patch. No daemon restart or repair is added.
