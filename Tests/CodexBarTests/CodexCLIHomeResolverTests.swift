import CodexBarCore
import Foundation
import Testing

struct CodexCLIHomeResolverTests {
    @Test
    func `live system keeps ambient home`() throws {
        let root = try self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let configStore = CodexBarConfigStore(fileURL: root.appendingPathComponent("config.json"))
        try configStore.save(CodexBarConfig(providers: [
            ProviderConfig(id: .codex, codexActiveSource: .liveSystem),
        ]))

        let result = try CodexCLIHomeResolver.resolve(
            configStore: configStore,
            managedAccountStore: FileManagedCodexAccountStore(
                fileURL: root.appendingPathComponent("managed-accounts.json")),
            env: ["CODEX_HOME": "/tmp/ambient-codex-home"])

        #expect(result.source == .liveSystem)
        #expect(result.homeURL.path == "/tmp/ambient-codex-home")
    }

    @Test
    func `managed source resolves its isolated home`() throws {
        let root = try self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let accountID = UUID()
        let managedHome = root.appendingPathComponent("managed-home", isDirectory: true)
        try FileManager.default.createDirectory(at: managedHome, withIntermediateDirectories: true)

        let accountStore = FileManagedCodexAccountStore(
            fileURL: root.appendingPathComponent("managed-accounts.json"))
        try accountStore.storeAccounts(ManagedCodexAccountSet(
            version: FileManagedCodexAccountStore.currentVersion,
            accounts: [ManagedCodexAccount(
                id: accountID,
                email: "managed@example.com",
                managedHomePath: managedHome.path,
                createdAt: 1,
                updatedAt: 1,
                lastAuthenticatedAt: nil)]))

        let configStore = CodexBarConfigStore(fileURL: root.appendingPathComponent("config.json"))
        try configStore.save(CodexBarConfig(providers: [
            ProviderConfig(id: .codex, codexActiveSource: .managedAccount(id: accountID)),
        ]))

        let result = try CodexCLIHomeResolver.resolve(
            configStore: configStore,
            managedAccountStore: accountStore,
            env: ["CODEX_HOME": "/tmp/ambient-codex-home"])

        #expect(result.source == .managedAccount(id: accountID))
        #expect(result.homeURL.path == managedHome.path)
    }

    @Test
    func `missing managed account fails closed`() throws {
        let root = try self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let accountID = UUID()
        let configStore = CodexBarConfigStore(fileURL: root.appendingPathComponent("config.json"))
        try configStore.save(CodexBarConfig(providers: [
            ProviderConfig(id: .codex, codexActiveSource: .managedAccount(id: accountID)),
        ]))
        let accountStore = FileManagedCodexAccountStore(
            fileURL: root.appendingPathComponent("managed-accounts.json"))
        try accountStore.storeAccounts(ManagedCodexAccountSet(
            version: FileManagedCodexAccountStore.currentVersion,
            accounts: [ManagedCodexAccount(
                id: UUID(),
                email: "other@example.com",
                managedHomePath: root.path,
                createdAt: 1,
                updatedAt: 1,
                lastAuthenticatedAt: nil)]))

        do {
            _ = try CodexCLIHomeResolver.resolve(
                configStore: configStore,
                managedAccountStore: accountStore)
            Issue.record("Expected a missing managed account to fail closed")
        } catch let error as CodexCLIHomeResolutionError {
            #expect(error == .managedAccountNotFound(accountID))
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test
    func `shell integration routes resume and disables shared daemon by default`() {
        let script = CodexCLIShellIntegration.script(helperPath: "/tmp/CodexBar.app/Contents/Helpers/CodexBarCLI")

        #expect(script.contains("codex-home"))
        #expect(script.contains("set -- resume \"$@\""))
        #expect(script.contains("CODEX_HOME=\"$codexbar_home\" command codex --no-daemon \"$@\""))
        #expect(script.contains("Existing Codex processes keep the environment they started with."))
        #expect(CodexCLIShellIntegration.sourceBlock().contains(CodexCLIShellIntegration.startMarker))
        #expect(CodexCLIShellIntegration.sourceBlock().contains(CodexCLIShellIntegration.endMarker))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-cli-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
