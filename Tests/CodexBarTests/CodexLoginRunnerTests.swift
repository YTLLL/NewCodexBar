import Foundation
import Testing
@testable import CodexBar

struct CodexLoginRunnerTests {
    @Test
    func `login runner returns timeout before hung codex exits`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-login-runner-\(UUID().uuidString)", isDirectory: true)
        let binDir = root.appendingPathComponent("bin", isDirectory: true)
        let homeDir = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let codex = binDir.appendingPathComponent("codex")
        let script = """
        #!/usr/bin/python3
        import time

        print("login-started", flush=True)
        time.sleep(5)
        print("login-finished", flush=True)
        """
        try script.write(to: codex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)

        let start = Date()
        let result = await CodexLoginRunner.run(
            homePath: homeDir.path,
            timeout: 0.2,
            environment: ["PATH": binDir.path],
            loginPATH: nil)
        let elapsed = Date().timeIntervalSince(start)

        #expect(result.outcome == .timedOut)
        #expect(result.output.contains("login-finished") == false)
        #expect(elapsed < 2.0, "Timeout should return promptly, took \(elapsed)s")
    }

    @Test
    func `cancelling login runner terminates hung codex promptly`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-login-runner-\(UUID().uuidString)", isDirectory: true)
        let binDir = root.appendingPathComponent("bin", isDirectory: true)
        let homeDir = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let codex = binDir.appendingPathComponent("codex")
        let script = """
        #!/usr/bin/python3
        import time

        print("login-started", flush=True)
        time.sleep(30)
        """
        try script.write(to: codex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)

        let start = Date()
        let task = Task {
            await CodexLoginRunner.run(
                homePath: homeDir.path,
                timeout: 60,
                environment: ["PATH": binDir.path],
                loginPATH: nil)
        }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let result = await task.value
        let elapsed = Date().timeIntervalSince(start)

        #expect(result.outcome == .cancelled)
        #expect(elapsed < 3.0, "Cancellation should terminate codex promptly, took \(elapsed)s")
    }
}
