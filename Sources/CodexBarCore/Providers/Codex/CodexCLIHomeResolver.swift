import Foundation

public enum CodexCLIHomeResolutionError: Error, Equatable, LocalizedError, Sendable {
    case managedAccountNotFound(UUID)
    case managedAccountHomeMissing(UUID, String)

    public var errorDescription: String? {
        switch self {
        case let .managedAccountNotFound(id):
            "The selected managed Codex account is unavailable (\(id.uuidString))."
        case let .managedAccountHomeMissing(id, path):
            "The selected managed Codex home is unavailable for \(id.uuidString): \(path)"
        }
    }
}

public struct CodexCLIHomeResolution: Equatable, Sendable {
    public let source: CodexActiveSource
    public let homeURL: URL

    public init(source: CodexActiveSource, homeURL: URL) {
        self.source = source
        self.homeURL = homeURL
    }
}

/// Resolves the home that a user-launched Codex CLI process should use.
///
/// This is intentionally evaluated for every launch. A running Codex process has already captured its
/// environment and must not be migrated when the selected account changes.
public enum CodexCLIHomeResolver {
    public static func resolve(
        configStore: CodexBarConfigStore = CodexBarConfigStore(),
        managedAccountStore: any ManagedCodexAccountStoring = FileManagedCodexAccountStore(),
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default) throws -> CodexCLIHomeResolution
    {
        let source = try configStore.load()?
            .providerConfig(for: .codex)?
            .codexActiveSource ?? .liveSystem

        return try self.resolve(
            source: source,
            managedAccountStore: managedAccountStore,
            env: env,
            fileManager: fileManager)
    }

    public static func resolve(
        source: CodexActiveSource,
        managedAccountStore: any ManagedCodexAccountStoring = FileManagedCodexAccountStore(),
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default) throws -> CodexCLIHomeResolution
    {
        switch source {
        case .liveSystem:
            return CodexCLIHomeResolution(
                source: .liveSystem,
                homeURL: CodexHomeScope.ambientHomeURL(env: env, fileManager: fileManager))

        case let .managedAccount(id):
            let accounts = try managedAccountStore.loadAccounts()
            guard let account = accounts.account(id: id) else {
                throw CodexCLIHomeResolutionError.managedAccountNotFound(id)
            }

            let path = account.managedHomePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, fileManager.fileExists(atPath: path) else {
                throw CodexCLIHomeResolutionError.managedAccountHomeMissing(id, path)
            }

            return CodexCLIHomeResolution(
                source: .managedAccount(id: id),
                homeURL: URL(fileURLWithPath: path, isDirectory: true))
        }
    }
}
