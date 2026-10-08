import CodexBarCore
import Foundation

/// Adapted from upstream CodexBar #4006 / #4018, without its promotion framework refactor.
@MainActor
struct CodexAppServerDaemon {
    private struct PIDRecord: Decodable { let pid: Int32 }
    private struct Version: Decodable {
        let status: String
        let backend: String?
        let socketPath: String?
    }

    static var recoveryNote: String {
        L("Account switched; restart the Codex background server manually when no tasks are running.")
    }

    var isAppServerProcess: (Int32) -> Bool = CodexHomeScope.isAppServerProcess
    var run: (String, [String: String]) async throws -> String = Self.runCommand

    func restartIfRunning(homeURL: URL, environment: [String: String]) async -> String? {
        let home = homeURL.resolvingSymlinksInPath().standardizedFileURL
        guard ["daemon.pid", "app-server.pid"].contains(where: { name in
            let url = home.appendingPathComponent("app-server-daemon/\(name)")
            guard let data = try? Data(contentsOf: url),
                  let record = try? JSONDecoder().decode(PIDRecord.self, from: data)
            else { return false }
            return record.pid > 0 && self.isAppServerProcess(record.pid)
        }) else { return nil }

        let env = CodexHomeScope.scopedEnvironment(base: environment, codexHome: home.path)
        let log = CodexBarLog.logger("codex-account-promotion")
        var phase = "detect"
        do {
            let output = try await self.run("version", env)
            let version = try JSONDecoder().decode(Version.self, from: Data(output.utf8))
            if version.status == "stopped" { return nil }
            guard version.status == "running", version.backend == "pid",
                  let socketPath = version.socketPath, (socketPath as NSString).isAbsolutePath,
                  URL(fileURLWithPath: socketPath).resolvingSymlinksInPath().standardizedFileURL ==
                  home.appendingPathComponent("app-server-control/app-server-control.sock")
                  .resolvingSymlinksInPath().standardizedFileURL
            else { return Self.recoveryNote }
            phase = "restart"
            _ = try await self.run("restart", env)
            return nil
        } catch {
            log.warning("Codex daemon refresh failed", metadata: ["phase": phase])
            return Self.recoveryNote
        }
    }

    private static func runCommand(_ command: String, environment: [String: String]) async throws -> String {
        var env = environment
        let loginPATH = LoginShellPathCache.shared.current
        env["PATH"] = PathBuilder.effectivePATH(purposes: [.rpc, .nodeTooling], env: env, loginPATH: loginPATH)
        guard let binary = BinaryLocator.resolveCodexBinary(env: env, loginPATH: loginPATH) else {
            throw SubprocessRunnerError.binaryNotFound("codex")
        }
        let arguments = ["app-server", "daemon", command]
        if command == "restart" {
            return try await self.runRestartToCompletion(binary: binary, arguments: arguments, environment: env)
        }
        let result = try await SubprocessRunner.run(
            binary: binary, arguments: arguments, environment: env, timeout: 10, label: "codex-daemon-version")
        return result.stdout
    }

    /// An unstructured task drains the launched mutation despite caller cancellation, with a bounded CLI wait.
    static func runRestartToCompletion(
        binary: String, arguments: [String], environment: [String: String], timeout: TimeInterval = 30) async throws
        -> String
    {
        try await Task {
            let result = try await SubprocessRunner.run(
                binary: binary,
                arguments: arguments,
                environment: environment,
                timeout: timeout,
                label: "codex-daemon-restart")
            return result.stdout
        }.value
    }
}
