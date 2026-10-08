import CodexBarCore

extension CodexBarCLI {
    static func runCodexHome() {
        do {
            let resolution = try CodexCLIHomeResolver.resolve()
            print(resolution.homeURL.path)
            Self.platformExit(ExitCode.success.rawValue)
        } catch {
            writeStderr("Error: \(error.localizedDescription)\n")
            platformExit(ExitCode.failure.rawValue)
        }
    }
}
