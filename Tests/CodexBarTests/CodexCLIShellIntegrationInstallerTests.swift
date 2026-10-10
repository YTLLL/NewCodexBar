import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct CodexCLIShellIntegrationInstallerTests {
    @Test
    func `old wrapper upgrades in place and repeated installation does not rewrite files`() async throws {
        let fixture = try CodexShellTestHome()
        defer { fixture.cleanUp() }
        let scriptURL = try self.writeLegacyScript(fixture)
        let block = """
        \(CodexCLIShellIntegration.startMarker)
        # Old managed source block
        . "$HOME/.codexbar/\(CodexCLIShellIntegration.fileName)"
        \(CodexCLIShellIntegration.endMarker)
        """
        let shellURLs = [".zshrc", ".bashrc"].map { fixture.root.appendingPathComponent($0) }
        for url in shellURLs {
            try Data("# user prefix\n\(block)\n# user suffix\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
        }
        #expect(try CodexCLIShellIntegrationInstaller.install(homeURL: fixture.root) == [".zshrc", ".bashrc"])
        for url in shellURLs {
            let contents = try String(contentsOf: url, encoding: .utf8)
            #expect(contents == "# user prefix\n\(CodexCLIShellIntegration.sourceBlock())\n# user suffix\n")
            #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o640)
        }
        #expect(try String(contentsOf: scriptURL, encoding: .utf8) == CodexCLIShellIntegration.script())
        let date = Date(timeIntervalSince1970: 12345)
        let allURLs = shellURLs + [scriptURL]
        let before = try allURLs.map { try Data(contentsOf: $0) }
        for url in allURLs {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        try CodexCLIShellIntegrationInstaller.install(homeURL: fixture.root)
        #expect(try allURLs.map { try Data(contentsOf: $0) } == before)
        for url in allURLs {
            #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date == date)
        }
        for shell in ["/bin/zsh", "/bin/bash"] {
            try await fixture.expectInvocation(shell: shell, args: [], expected: ["--no-daemon"])
            try await fixture.expectInvocation(shell: shell, args: ["exec", "test"], expected: ["exec", "test"])
        }
    }

    @Test(arguments: ["start-only", "end-only", "reversed", "duplicate", "extra-start", "inline", "indented"])
    func `abnormal markers reject the entire installation before any write`(kind: String) throws {
        let fixture = try CodexShellTestHome()
        defer { fixture.cleanUp() }
        let scriptURL = try self.writeLegacyScript(fixture)
        let start = CodexCLIShellIntegration.startMarker
        let end = CodexCLIShellIntegration.endMarker
        let malformed = switch kind {
        case "start-only": start
        case "end-only": end
        case "reversed": "\(end)\n\(start)"
        case "duplicate": "\(start)\n\(end)\n\(start)\n\(end)"
        case "extra-start": "\(start)\n\(start)\n\(end)"
        case "inline": "prefix \(start)\n\(end)"
        default: " \(start)\n\(end)"
        }
        // Put the failure second to prove the first shell and script are not written prematurely.
        try Data(malformed.utf8).write(to: fixture.root.appendingPathComponent(".bashrc"))
        let urls = [
            fixture.root.appendingPathComponent(".zshrc"),
            fixture.root.appendingPathComponent(".bashrc"),
            scriptURL,
        ]
        let before = try urls.map { try Data(contentsOf: $0) }
        #expect(throws: CodexCLIShellIntegrationInstaller.InstallationError.invalidMarkers(".bashrc")) {
            try CodexCLIShellIntegrationInstaller.install(homeURL: fixture.root)
        }
        #expect(try urls.map { try Data(contentsOf: $0) } == before)
    }

    @Test(arguments: [".zshrc", ".bashrc", ".codexbar", ".codexbar/codexbar-codex-routing.sh"])
    func `symlinks are refused without changing their destination`(name: String) throws {
        let fixture = try CodexShellTestHome()
        defer { fixture.cleanUp() }
        let destination = fixture.root.appendingPathComponent("untouched")
        try Data("user content".utf8).write(to: destination)
        let url = fixture.root.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        if name.contains("/") {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: destination)
        #expect(throws: CodexCLIShellIntegrationInstaller.InstallationError.unsupportedFile(url.lastPathComponent)) {
            try CodexCLIShellIntegrationInstaller.install(homeURL: fixture.root)
        }
        #expect(try String(contentsOf: destination, encoding: .utf8) == "user content")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: url.path) == destination.path)
    }

    @Test
    func `missing bashrc stays missing and new zshrc is installed once`() throws {
        let fixture = try CodexShellTestHome()
        defer { fixture.cleanUp() }
        for name in [".zshrc", ".bashrc"] {
            try FileManager.default.removeItem(at: fixture.root.appendingPathComponent(name))
        }
        #expect(try CodexCLIShellIntegrationInstaller.install(homeURL: fixture.root) == [".zshrc"])
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(".bashrc").path))
        #expect(try String(contentsOf: fixture.root.appendingPathComponent(".zshrc"), encoding: .utf8) ==
            CodexCLIShellIntegration.sourceBlock() + "\n")
        try CodexCLIShellIntegrationInstaller.install(homeURL: fixture.root)
        #expect(try String(contentsOf: fixture.root.appendingPathComponent(".zshrc"), encoding: .utf8) ==
            CodexCLIShellIntegration.sourceBlock() + "\n")
    }

    @Test
    func `packaged app startup entry installs into the supplied temporary home`() throws {
        let fixture = try CodexShellTestHome()
        defer { fixture.cleanUp() }
        let app = fixture.root.appendingPathComponent("NewCodexBar.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let helpers = contents.appendingPathComponent("Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "test.codexbar.shell", "CFBundlePackageType": "APPL"],
            format: .xml,
            options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        let helper = helpers.appendingPathComponent("CodexBarCLI")
        try Data("#!/bin/sh\nexit 99\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let bundle = try #require(Bundle(url: app))
        #expect(CodexCLIShellIntegrationInstaller.installFromCurrentApp(bundle: bundle, homeURL: fixture.root) ==
            [".zshrc", ".bashrc"])
        let script = fixture.root.appendingPathComponent(".codexbar/\(CodexCLIShellIntegration.fileName)")
        #expect(try String(contentsOf: script, encoding: .utf8) == CodexCLIShellIntegration.script())
    }

    @Test
    func `startup installer does not run from test bundle`() throws {
        let fixture = try CodexShellTestHome()
        defer { fixture.cleanUp() }
        #expect(CodexCLIShellIntegrationInstaller.installFromCurrentApp(homeURL: fixture.root) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(".codexbar").path))
    }

    private func writeLegacyScript(_ fixture: CodexShellTestHome) throws -> URL {
        let directory = fixture.root.appendingPathComponent(".codexbar", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(CodexCLIShellIntegration.fileName)
        try Data("""
        # CodexBar routes new interactive Codex CLI processes through the selected account home.
        codex() { CODEX_HOME="old-isolated-home" command codex --no-daemon "$@"; }
        """.utf8).write(to: url)
        return url
    }
}
