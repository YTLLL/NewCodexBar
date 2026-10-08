#!/usr/bin/env bash
set -euo pipefail

APP="/Applications/CodexBar.app"
HELPER="$APP/Contents/Helpers/CodexBarCLI"
TARGETS=("/usr/local/bin/codexbar" "/opt/homebrew/bin/codexbar")

if [[ ! -x "$HELPER" ]]; then
  echo "CodexBarCLI helper not found at $HELPER. Please reinstall CodexBar." >&2
  exit 1
fi

osascript - "$HELPER" <<'APPLESCRIPT'
on run argv
  set helperPath to item 1 of argv
  set installCommand to "set -euo pipefail" & linefeed & ¬
    "HELPER=" & quoted form of helperPath & linefeed & ¬
    "TARGETS=(\"/usr/local/bin/codexbar\" \"/opt/homebrew/bin/codexbar\")" & linefeed & ¬
    "for t in \"${TARGETS[@]}\"; do" & linefeed & ¬
    "  mkdir -p \"$(dirname \"$t\")\"" & linefeed & ¬
    "  ln -sf \"$HELPER\" \"$t\"" & linefeed & ¬
    "  echo \"Linked $t -> $HELPER\"" & linefeed & ¬
    "done"

  do shell script "bash -c " & quoted form of installCommand with administrator privileges
end run
APPLESCRIPT

echo "CodexBar CLI installed. Try: codexbar usage"

CODEXBAR_ROUTING_DIR="$HOME/.codexbar"
CODEXBAR_ROUTING_FILE="$CODEXBAR_ROUTING_DIR/codexbar-codex-routing.sh"
mkdir -p "$CODEXBAR_ROUTING_DIR"
cat > "$CODEXBAR_ROUTING_FILE" <<'SHELL'
# CodexBar routes new interactive Codex CLI processes through the selected account home.
# Existing Codex processes keep the environment they started with.
codex() {
    local codexbar_home=""
    if [ -x "/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI" ]; then
        codexbar_home="$("/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI" codex-home 2>/dev/null)" || return $?
    elif command -v codexbar >/dev/null 2>&1; then
        codexbar_home="$(command codexbar codex-home 2>/dev/null)" || return $?
    else
        command codex "$@"
        return $?
    fi

    if [ -z "$codexbar_home" ]; then
        echo "CodexBar: unable to resolve the active Codex home" >&2
        return 1
    fi

    # Codex CLI 0.157+ exposes resume as a subcommand. Keep the older
    # `codex --resume` spelling working for routed terminal sessions.
    if [ "${1:-}" = "--resume" ]; then
        shift
        set -- resume "$@"
    fi

    local codexbar_has_no_daemon=0
    local codexbar_arg
    for codexbar_arg in "$@"; do
        if [ "$codexbar_arg" = "--no-daemon" ]; then
            codexbar_has_no_daemon=1
            break
        fi
    done

    if [ "$codexbar_has_no_daemon" -eq 1 ]; then
        CODEX_HOME="$codexbar_home" command codex "$@"
    else
        CODEX_HOME="$codexbar_home" command codex --no-daemon "$@"
    fi
}
SHELL
chmod 644 "$CODEXBAR_ROUTING_FILE"

CODEXBAR_SHELL_RC="$HOME/.zshrc"
CODEXBAR_START_MARKER="# >>> codexbar codex account routing >>>"
CODEXBAR_END_MARKER="# <<< codexbar codex account routing <<<"
if [[ ! -f "$CODEXBAR_SHELL_RC" ]]; then
  touch "$CODEXBAR_SHELL_RC"
fi
if ! /usr/bin/grep -Fq "$CODEXBAR_START_MARKER" "$CODEXBAR_SHELL_RC"; then
  if [[ -s "$CODEXBAR_SHELL_RC" ]] && [[ "$(tail -c 1 "$CODEXBAR_SHELL_RC" | wc -l)" -eq 0 ]]; then
    printf '\n' >> "$CODEXBAR_SHELL_RC"
  fi
  printf '\n%s\nif [ -f "$HOME/.codexbar/codexbar-codex-routing.sh" ]; then\n  . "$HOME/.codexbar/codexbar-codex-routing.sh"\nfi\n%s\n' \
    "$CODEXBAR_START_MARKER" "$CODEXBAR_END_MARKER" >> "$CODEXBAR_SHELL_RC"
fi

echo "Codex CLI account routing installed for new shell sessions. Open a new shell or run: source ~/.zshrc"
