import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
struct CodexCLIShellIntegrationTests {
    @Test(arguments: ["/bin/zsh", "/bin/bash"])
    func `new shells inject only recognized interactive launches`(shell: String) async throws {
        let fixture = try CodexShellTestHome()
        defer { fixture.cleanUp() }
        try CodexCLIShellIntegrationInstaller.install(homeURL: fixture.root)
        let interactive: [[String]] = [
            [], ["resume"], ["resume", "session-id"], ["resume", "--all"], ["fork", "--last"],
            ["fork", "session-id", "a quoted prompt with ' and $ and spaces"],
            ["-c", "model_reasoning_effort=high"], ["-m", "test-model"],
            ["-c", "model='test'", "-m", "test-model", "resume", "session-id"],
            ["-m", "test-model", "fork", "--last"], ["--config=x=y", "--model=test", "resume"],
            ["resume", "-m", "test-model", "session-id"], ["--no-alt-screen"],
            ["-m", "exec"], ["-c", "label='--no-daemon'", "resume"],
        ]
        let explicit: [[String]] = [
            ["--no-daemon"], ["--no-daemon", "resume", "session-id"],
            ["resume", "--no-daemon", "session-id"], ["-c", "x=y", "--no-daemon", "fork", "--last"],
            ["app-server", "daemon", "restart"], ["queue", "session-id", "--no-daemon"],
        ]
        let management = [
            "exec", "e", "app-server", "agents", "queue", "remote-control", "login", "logout", "mcp", "help",
            "review", "plugin", "app", "completion", "update", "doctor", "sandbox", "debug", "apply", "archive",
            "delete", "migrate-rollouts", "unarchive", "cloud", "exec-server",
        ]
        let ambiguous: [[String]] = [
            ["unknown-command"], ["a bare prompt"], ["--unknown", "resume"], ["-c"], ["-m"],
            ["-c", "--no-daemon"], ["--config="], ["--model="], ["-cfoo=bar", "resume"],
            ["--resume", "session-id"], ["--", "resume"], ["--all"], ["--remote", "unix://"],
            ["resume", "--unknown"], ["fork", "-m"], ["resume", "id", "prompt", "extra"],
            ["--help"], ["--version"], ["resume", "--help"], ["-m", "test", "fork", "--version"],
        ]
        for args in interactive {
            try await fixture.expectInvocation(shell: shell, args: args, expected: ["--no-daemon"] + args)
        }
        for args in explicit + ambiguous {
            try await fixture.expectInvocation(shell: shell, args: args, expected: args)
        }
        for command in management {
            for prefix in [[], ["-c", "x=y", "-m", "test"]] {
                let args = prefix + [command, "argument with spaces"]
                try await fixture.expectInvocation(shell: shell, args: args, expected: args)
            }
        }
    }

    @Test(arguments: ["/bin/zsh", "/bin/bash"])
    func `wrapper leaves unset empty and custom CODEX_HOME unchanged`(shell: String) async throws {
        let fixture = try CodexShellTestHome()
        defer { fixture.cleanUp() }
        try CodexCLIShellIntegrationInstaller.install(homeURL: fixture.root)
        for value: String? in [nil, "", "/tmp/custom home '$HOME"] {
            try await fixture.expectInvocation(
                shell: shell,
                args: ["resume", "--last"],
                expected: ["--no-daemon", "resume", "--last"],
                codexHome: value)
        }
        let script = CodexCLIShellIntegration.script()
        #expect(!script.contains("CODEX_HOME="))
        #expect(!script.contains("codex-home"))
        #expect(!script.contains("restart"))
    }

    @Test(arguments: ["/bin/zsh", "/bin/bash"])
    func `wrapper propagates native exit status`(shell: String) async throws {
        let fixture = try CodexShellTestHome()
        defer { fixture.cleanUp() }
        try CodexCLIShellIntegrationInstaller.install(homeURL: fixture.root)
        do {
            _ = try await fixture.run(shell: shell, args: [], exitStatus: "37")
            Issue.record("Expected the fake CLI exit code to propagate")
        } catch let SubprocessRunnerError.nonZeroExit(code, _) {
            #expect(code == 37)
        }
    }
}

struct CodexShellTestHome {
    let root: URL
    let bin: URL
    let pathValue: String

    init() throws {
        self.root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-shell-home '\(UUID())", isDirectory: true)
        self.bin = self.root.appendingPathComponent("bin", isDirectory: true)
        self.pathValue = self.bin.path + ":/usr/bin:/bin"
        try FileManager.default.createDirectory(at: self.bin, withIntermediateDirectories: true)
        for name in [".zshrc", ".bashrc"] {
            try Data("# user prefix\n# user suffix\n".utf8).write(to: self.root.appendingPathComponent(name))
        }
        let fake = self.bin.appendingPathComponent("codex")
        try Data("""
        #!/bin/sh
        printf '%s\\0' "${CODEX_HOME+x}" "${CODEX_HOME-}" "$PATH" "$@"
        exit "${CODEXBAR_TEST_EXIT_STATUS:-0}"
        """.utf8).write(to: fake)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: self.root)
    }

    func run(shell: String, args: [String], codexHome: String? = "test-home", exitStatus: String = "0")
        async throws -> SubprocessResult
    {
        var environment = [
            "HOME": self.root.path, "ZDOTDIR": self.root.path, "PATH": self.pathValue, "TERM": "dumb",
            "CODEXBAR_TEST_EXIT_STATUS": exitStatus,
        ]
        environment["CODEX_HOME"] = codexHome
        let command = """
        codex "$@"
        codexbar_test_status=$?
        printf '%s\\0' "${CODEX_HOME+x}" "${CODEX_HOME-}" "$PATH"
        exit "$codexbar_test_status"
        """
        let startup = shell == "/bin/zsh" ? ["-d", "-i"] :
            ["--noprofile", "--rcfile", self.root.appendingPathComponent(".bashrc").path, "-i"]
        return try await SubprocessRunner.run(
            binary: shell,
            arguments: startup + ["-c", command, "codexbar-test"] + args,
            environment: environment,
            timeout: 5,
            currentDirectoryURL: self.root,
            label: "fake-codex-shell")
    }

    func expectInvocation(shell: String, args: [String], expected: [String], codexHome: String? = "test-home")
        async throws
    {
        let result = try await self.run(shell: shell, args: args, codexHome: codexHome)
        let fields = result.stdout.split(separator: "\0", omittingEmptySubsequences: false).dropLast().map(String.init)
        let environmentFields = [codexHome == nil ? "" : "x", codexHome ?? "", self.pathValue]
        #expect(fields == environmentFields + expected + environmentFields, "\(shell) argv: \(args)")
    }
}
