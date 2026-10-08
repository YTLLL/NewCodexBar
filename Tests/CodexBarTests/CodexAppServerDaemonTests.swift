import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@Suite(.serialized)
@MainActor
struct CodexAppServerDaemonTests {
    @Test(arguments: ["daemon.pid", "app-server.pid"])
    func `restart verifies scoped socket including symlinks`(pidName: String) async throws {
        let root = try self.makeHome()
        defer { try? FileManager.default.removeItem(at: root) }
        try self.writePID(home: root, name: pidName)
        let control = root.appendingPathComponent("app-server-control")
        try FileManager.default.createDirectory(at: control, withIntermediateDirectories: true)
        let realSocket = root.appendingPathComponent("real.sock")
        try Data().write(to: realSocket)
        try FileManager.default.createSymbolicLink(
            at: control.appendingPathComponent("app-server-control.sock"), withDestinationURL: realSocket)
        var calls: [String] = []
        let daemon = CodexAppServerDaemon(isAppServerProcess: { $0 == 42 }, run: { command, env in
            calls.append(command)
            #expect(env["CODEX_HOME"] == root.resolvingSymlinksInPath().path)
            if command == "version" { return try self.version(socket: realSocket.path) }
            return "{}"
        })
        #expect(await daemon.restartIfRunning(homeURL: root, environment: ["CODEX_HOME": "/other"]) == nil)
        #expect(calls == ["version", "restart"])
    }

    @Test(arguments: ["missing", "corrupt", "stale", "non-codex"])
    func `absent or unverified processes make no CLI calls`(kind: String) async throws {
        let root = try self.makeHome()
        defer { try? FileManager.default.removeItem(at: root) }
        if kind == "corrupt" {
            try Data("bad pid".utf8).write(to: root.appendingPathComponent("app-server-daemon/daemon.pid"))
        } else if kind != "missing" {
            try self.writePID(home: root)
        }
        var calls = 0
        let daemon = CodexAppServerDaemon(isAppServerProcess: { _ in false }, run: { _, _ in
            calls += 1
            return "{}"
        })
        #expect(await daemon.restartIfRunning(homeURL: root, environment: [:]) == nil)
        #expect(calls == 0)
    }

    @Test(arguments: ["stopped", "foreign-socket", "foreign-backend", "unsupported", "restart-failed"])
    func `unverified or failing daemon never undoes successful auth`(kind: String) async throws {
        let root = try self.makeHome()
        defer { try? FileManager.default.removeItem(at: root) }
        try self.writePID(home: root)
        var calls: [String] = []
        let daemon = CodexAppServerDaemon(isAppServerProcess: { _ in true }, run: { command, _ in
            calls.append(command)
            if kind == "unsupported" || (command == "restart" && kind == "restart-failed") {
                throw SubprocessRunnerError.nonZeroExit(code: 1, stderr: "synthetic failure")
            }
            return try self.version(
                status: kind == "stopped" ? "stopped" : "running",
                backend: kind == "foreign-backend" ? "launchd" : "pid",
                socket: kind == "foreign-socket" ? "/other/home/control.sock" :
                    root.appendingPathComponent("app-server-control/app-server-control.sock").path)
        })
        let note = await daemon.restartIfRunning(homeURL: root, environment: [:])
        #expect(note == (kind == "stopped" ? nil : CodexAppServerDaemon.recoveryNote))
        #expect(calls == (kind == "restart-failed" ? ["version", "restart"] : ["version"]))
    }

    @Test
    func `process predicate requires native app-server and paired unix listen argument`() {
        #expect(CodexHomeScope.isAppServer(arguments: ["/opt/bin/codex", "app-server", "--listen", "unix://"]))
        for arguments in [
            ["node", "codex", "app-server", "--listen", "unix://"],
            ["codex", "exec", "--listen", "unix://"],
            ["codex", "app-server", "--listen", "tcp://", "unix://"],
            ["codex", "app-server", "--listen"],
        ] {
            #expect(!CodexHomeScope.isAppServer(arguments: arguments))
        }
        #expect(!CodexHomeScope.isAppServerProcess(-1))
        var data = withUnsafeBytes(of: Int32(4)) { Data($0) }
        data.append(Data("/opt/bin/codex\0\0codex\0app-server\0--listen\0unix://\0SECRET=ignored\0".utf8))
        #expect(CodexHomeScope.appServerArguments(from: data) == ["codex", "app-server", "--listen", "unix://"])
        #expect(CodexHomeScope.appServerArguments(from: data.prefix(10)) == nil)
    }

    @Test
    func `restart command completes despite cancelled caller`() async throws {
        let task = Task {
            try await CodexAppServerDaemon.runRestartToCompletion(
                binary: "/bin/sh",
                arguments: ["-c", "sleep 0.1; printf complete"],
                environment: ["PATH": "/usr/bin:/bin"])
        }
        task.cancel()
        #expect(try await task.value == "complete")
        await #expect(throws: SubprocessRunnerError.self) {
            try await CodexAppServerDaemon.runRestartToCompletion(
                binary: "/bin/sleep", arguments: ["5"], environment: [:], timeout: 0.05)
        }
    }

    private func makeHome() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-daemon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("app-server-daemon"), withIntermediateDirectories: true)
        return root
    }

    private func writePID(home: URL, name: String = "daemon.pid") throws {
        try Data(#"{"pid":42}"#.utf8).write(to: home.appendingPathComponent("app-server-daemon/\(name)"))
    }

    private func version(status: String = "running", backend: String = "pid", socket: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [
            "status": status,
            "backend": backend,
            "socketPath": socket,
        ])
        return try #require(String(data: data, encoding: .utf8))
    }
}
