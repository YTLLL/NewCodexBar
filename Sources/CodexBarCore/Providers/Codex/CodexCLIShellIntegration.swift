import Foundation

public enum CodexCLIShellIntegration {
    public static let fileName = "codexbar-codex-routing.sh"
    public static let startMarker = "# >>> codexbar codex account routing >>>"
    public static let endMarker = "# <<< codexbar codex account routing <<<"

    public static func script(
        helperPath: String = "/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI") -> String
    {
        let escapedHelperPath = self.shellDoubleQuoted(helperPath)
        return """
        # CodexBar routes new interactive Codex CLI processes through the selected account home.
        # Existing Codex processes keep the environment they started with.
        codex() {
            local codexbar_home=""
            if [ -x "\(escapedHelperPath)" ]; then
                codexbar_home="$("\(escapedHelperPath)" codex-home 2>/dev/null)" || return $?
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
        """
    }

    public static func sourceBlock() -> String {
        """
        \(self.startMarker)
        if [ -f "$HOME/.codexbar/\(self.fileName)" ]; then
            . "$HOME/.codexbar/\(self.fileName)"
        fi
        \(self.endMarker)
        """
    }

    private static func shellDoubleQuoted(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
    }
}
