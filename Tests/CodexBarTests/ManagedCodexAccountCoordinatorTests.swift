import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct ManagedCodexAccountCoordinatorTests {
    @Test
    func `add account login link remains valid for ten minutes by default`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let loginResult = CodexLoginRunner.Result(outcome: .timedOut, output: "timed out")
        let runner = TimeoutRecordingManagedCodexLoginRunner(result: loginResult)
        let service = ManagedCodexAccountService(
            store: InMemoryManagedCodexAccountStoreForCoordinatorTests(
                accounts: ManagedCodexAccountSet(version: 1, accounts: [])),
            homeFactory: CoordinatorTestManagedCodexHomeFactory(root: root),
            loginRunner: runner,
            identityReader: CoordinatorStubManagedCodexIdentityReader(email: "user@example.com"))
        let coordinator = ManagedCodexAccountCoordinator(service: service)

        await #expect(throws: ManagedCodexAccountServiceError.self) {
            try await coordinator.authenticateManagedAccount()
        }
        #expect(await runner.recordedTimeout() == 10 * 60)
    }

    @Test
    func `coordinator exposes in flight state and rejects overlapping managed authentication`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let existingAccountID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-111111111111"))
        let runner = BlockingManagedCodexLoginRunner()
        let service = ManagedCodexAccountService(
            store: InMemoryManagedCodexAccountStoreForCoordinatorTests(
                accounts: ManagedCodexAccountSet(version: 1, accounts: [])),
            homeFactory: CoordinatorTestManagedCodexHomeFactory(root: root),
            loginRunner: runner,
            identityReader: CoordinatorStubManagedCodexIdentityReader(email: "user@example.com"))
        let coordinator = ManagedCodexAccountCoordinator(service: service)

        let authTask = Task { try await coordinator.authenticateManagedAccount(existingAccountID: existingAccountID) }
        await runner.waitUntilStarted()

        #expect(coordinator.isAuthenticatingManagedAccount)
        #expect(coordinator.authenticatingManagedAccountID == existingAccountID)

        await #expect(throws: ManagedCodexAccountCoordinatorError.authenticationInProgress) {
            try await coordinator.authenticateManagedAccount()
        }

        await runner.resume()
        let account = try await authTask.value

        #expect(account.email == "user@example.com")
        #expect(coordinator.isAuthenticatingManagedAccount == false)
        #expect(coordinator.authenticatingManagedAccountID == nil)
    }

    @Test
    func `coordinator clears in flight state after managed login timeout`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let loginResult = CodexLoginRunner.Result(outcome: .timedOut, output: "timed out")
        let existingAccountID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-222222222222"))
        let service = ManagedCodexAccountService(
            store: InMemoryManagedCodexAccountStoreForCoordinatorTests(
                accounts: ManagedCodexAccountSet(version: 1, accounts: [])),
            homeFactory: CoordinatorTestManagedCodexHomeFactory(root: root),
            loginRunner: TimedOutManagedCodexLoginRunner(result: loginResult),
            identityReader: CoordinatorStubManagedCodexIdentityReader(email: "user@example.com"))
        let coordinator = ManagedCodexAccountCoordinator(service: service)

        do {
            _ = try await coordinator.authenticateManagedAccount(existingAccountID: existingAccountID, timeout: 0.2)
            Issue.record("Expected managed login timeout to throw")
        } catch let error as ManagedCodexAccountServiceError {
            #expect(error == .loginFailed(loginResult))
        } catch {
            Issue.record("Expected ManagedCodexAccountServiceError.loginFailed, got \(error)")
        }

        #expect(coordinator.isAuthenticatingManagedAccount == false)
        #expect(coordinator.authenticatingManagedAccountID == nil)
    }

    @Test
    func `coordinator replaces an in flight add account login`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = ReplacingManagedCodexLoginRunner()
        let service = ManagedCodexAccountService(
            store: InMemoryManagedCodexAccountStoreForCoordinatorTests(
                accounts: ManagedCodexAccountSet(version: 1, accounts: [])),
            homeFactory: CoordinatorTestManagedCodexHomeFactory(root: root),
            loginRunner: runner,
            identityReader: CoordinatorStubManagedCodexIdentityReader(email: "replacement@example.com"))
        let coordinator = ManagedCodexAccountCoordinator(service: service)

        let firstLogin = Task { try await coordinator.authenticateManagedAccount() }
        await runner.waitUntilFirstLoginStarted()
        let replacement = try await coordinator.authenticateManagedAccount(replacingInProgress: true)

        await #expect(throws: CancellationError.self) {
            try await firstLogin.value
        }
        #expect(replacement.email == "replacement@example.com")
        #expect(await runner.invocationCount() == 2)
        #expect(coordinator.isAuthenticatingManagedAccount == false)
    }
}

private actor BlockingManagedCodexLoginRunner: ManagedCodexLoginRunning {
    private var waiters: [CheckedContinuation<CodexLoginRunner.Result, Never>] = []
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var didStart = false

    func run(homePath _: String, timeout _: TimeInterval) async -> CodexLoginRunner.Result {
        self.didStart = true
        self.startedWaiters.forEach { $0.resume() }
        self.startedWaiters.removeAll()
        return await withCheckedContinuation { continuation in
            self.waiters.append(continuation)
        }
    }

    func waitUntilStarted() async {
        if self.didStart { return }
        await withCheckedContinuation { continuation in
            self.startedWaiters.append(continuation)
        }
    }

    func resume() {
        let result = CodexLoginRunner.Result(outcome: .success, output: "ok")
        self.waiters.forEach { $0.resume(returning: result) }
        self.waiters.removeAll()
    }
}

private struct TimedOutManagedCodexLoginRunner: ManagedCodexLoginRunning {
    let result: CodexLoginRunner.Result

    func run(homePath _: String, timeout _: TimeInterval) async -> CodexLoginRunner.Result {
        self.result
    }
}

private actor TimeoutRecordingManagedCodexLoginRunner: ManagedCodexLoginRunning {
    let result: CodexLoginRunner.Result
    private var timeout: TimeInterval?

    init(result: CodexLoginRunner.Result) {
        self.result = result
    }

    func run(homePath _: String, timeout: TimeInterval) async -> CodexLoginRunner.Result {
        self.timeout = timeout
        return self.result
    }

    func recordedTimeout() -> TimeInterval? {
        self.timeout
    }
}

private actor ReplacingManagedCodexLoginRunner: ManagedCodexLoginRunning {
    private var count = 0
    private var hasStartedFirstLogin = false
    private var firstLoginStartedWaiters: [CheckedContinuation<Void, Never>] = []

    func run(homePath _: String, timeout _: TimeInterval) async -> CodexLoginRunner.Result {
        self.count += 1
        if self.count == 1 {
            self.hasStartedFirstLogin = true
            self.firstLoginStartedWaiters.forEach { $0.resume() }
            self.firstLoginStartedWaiters.removeAll()
            try? await Task.sleep(for: .seconds(30))
        }
        return CodexLoginRunner.Result(outcome: .success, output: "ok")
    }

    func waitUntilFirstLoginStarted() async {
        if self.hasStartedFirstLogin { return }
        await withCheckedContinuation { continuation in
            self.firstLoginStartedWaiters.append(continuation)
        }
    }

    func invocationCount() -> Int {
        self.count
    }
}

private final class InMemoryManagedCodexAccountStoreForCoordinatorTests: ManagedCodexAccountStoring,
@unchecked Sendable {
    var snapshot: ManagedCodexAccountSet

    init(accounts: ManagedCodexAccountSet) {
        self.snapshot = accounts
    }

    func loadAccounts() throws -> ManagedCodexAccountSet {
        self.snapshot
    }

    func storeAccounts(_ accounts: ManagedCodexAccountSet) throws {
        self.snapshot = accounts
    }

    func ensureFileExists() throws -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
}

private final class CoordinatorTestManagedCodexHomeFactory: ManagedCodexHomeProducing, @unchecked Sendable {
    let root: URL

    init(root: URL) {
        self.root = root
    }

    func makeHomeURL() -> URL {
        self.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func validateManagedHomeForDeletion(_ url: URL) throws {
        try ManagedCodexHomeFactory(root: self.root).validateManagedHomeForDeletion(url)
    }
}

private final class CoordinatorStubManagedCodexIdentityReader: ManagedCodexIdentityReading, @unchecked Sendable {
    let email: String

    init(email: String) {
        self.email = email
    }

    func loadAccountIdentity(homePath _: String) throws -> CodexAuthBackedAccount {
        CodexAuthBackedAccount(
            identity: CodexIdentityResolver.resolve(accountId: nil, email: self.email),
            email: self.email,
            plan: "Pro")
    }
}
