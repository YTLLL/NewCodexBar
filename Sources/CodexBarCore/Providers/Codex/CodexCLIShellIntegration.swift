import Foundation

public enum CodexCLIShellIntegration {
    // Retain the old locations/markers to replace account-home routing in place.
    public static let fileName = "codexbar-codex-routing.sh"
    public static let startMarker = "# >>> codexbar codex account routing >>>"
    public static let endMarker = "# <<< codexbar codex account routing <<<"

    public static func script() -> String {
        """
        # CodexBar bypasses the shared daemon for recognized interactive CLI launches only.
        # Never route account homes; unknown forms and management commands pass through unchanged.
        codex() {
            local codexbar_mode=start
            local codexbar_needs_value=0
            local codexbar_has_no_daemon=0
            local codexbar_inject=1
            local codexbar_positionals=0
            local codexbar_arg
            for codexbar_arg in "$@"; do
                if [ "$codexbar_needs_value" -eq 1 ]; then
                    case "$codexbar_arg" in
                        ''|-*) codexbar_inject=0; break ;;
                    esac
                    codexbar_needs_value=0
                    continue
                fi
                case "$codexbar_arg" in
                    --no-daemon) codexbar_has_no_daemon=1 ;;
                    -c|--config|-m|--model) codexbar_needs_value=1 ;;
                    --config=?*|--model=?*|--no-alt-screen|--search|--oss) ;;
                    -h|--help|-V|--version) codexbar_inject=0; break ;;
                    --all|--last|--include-non-interactive)
                        if [ "$codexbar_mode" = start ]; then
                            codexbar_inject=0; break
                        fi
                        ;;
                    *)
                        if [ "$codexbar_mode" = start ]; then
                            case "$codexbar_arg" in
                                resume|fork) codexbar_mode="$codexbar_arg" ;;
                                *) codexbar_inject=0; break ;;
                            esac
                        else
                            case "$codexbar_arg" in
                                -*) codexbar_inject=0; break ;;
                                *) codexbar_positionals=$((codexbar_positionals + 1)) ;;
                            esac
                            if [ "$codexbar_positionals" -gt 2 ]; then
                                codexbar_inject=0; break
                            fi
                        fi
                        ;;
                esac
            done
            if [ "$codexbar_inject" -eq 1 ] && [ "$codexbar_needs_value" -eq 0 ] &&
                [ "$codexbar_has_no_daemon" -eq 0 ]; then
                command codex --no-daemon "$@"
            else
                command codex "$@"
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
}
