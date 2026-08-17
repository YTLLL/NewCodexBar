import CodexBarCore
import Foundation
import Observation

enum ManagedCodexAccountCoordinatorError: Error, Equatable {
    case authenticationInProgress
}

@MainActor
@Observable
final class ManagedCodexAccountCoordinator {
    let service: ManagedCodexAccountService
    private(set) var isAuthenticatingManagedAccount: Bool = false
    private(set) var authenticatingManagedAccountID: UUID?
    private(set) var isRemovingManagedAccount: Bool = false
    private(set) var removingManagedAccountID: UUID?
    @ObservationIgnored private var authenticationTask: Task<ManagedCodexAccount, Error>?
    @ObservationIgnored private var authenticationOperationID: UUID?
    var onManagedAccountsDidChange: (@MainActor () -> Void)?

    var hasConflictingManagedAccountOperationInFlight: Bool {
        self.isAuthenticatingManagedAccount || self.isRemovingManagedAccount
    }

    init(service: ManagedCodexAccountService = ManagedCodexAccountService()) {
        self.service = service
    }

    func authenticateManagedAccount(
        existingAccountID: UUID? = nil,
        timeout: TimeInterval = 120,
        replacingInProgress: Bool = false)
        async throws -> ManagedCodexAccount
    {
        if self.isAuthenticatingManagedAccount, replacingInProgress == false {
            throw ManagedCodexAccountCoordinatorError.authenticationInProgress
        }
        guard self.isRemovingManagedAccount == false else {
            throw ManagedCodexAccountCoordinatorError.authenticationInProgress
        }

        if replacingInProgress {
            self.authenticationTask?.cancel()
        }

        let operationID = UUID()
        self.isAuthenticatingManagedAccount = true
        self.authenticatingManagedAccountID = existingAccountID
        self.authenticationOperationID = operationID

        let authenticationTask = Task {
            try await self.service.authenticateManagedAccount(
                existingAccountID: existingAccountID,
                timeout: timeout)
        }
        self.authenticationTask = authenticationTask

        do {
            let account = try await authenticationTask.value
            try Task.checkCancellation()
            guard self.authenticationOperationID == operationID else {
                throw CancellationError()
            }
            self.finishAuthentication(operationID: operationID)
            self.onManagedAccountsDidChange?()
            return account
        } catch {
            self.finishAuthentication(operationID: operationID)
            throw error
        }
    }

    func removeManagedAccount(id: UUID) async throws {
        self.isRemovingManagedAccount = true
        self.removingManagedAccountID = id
        defer {
            self.isRemovingManagedAccount = false
            self.removingManagedAccountID = nil
        }

        try await self.service.removeManagedAccount(id: id)
        self.onManagedAccountsDidChange?()
    }

    private func finishAuthentication(operationID: UUID) {
        guard self.authenticationOperationID == operationID else { return }
        self.authenticationTask = nil
        self.authenticationOperationID = nil
        self.isAuthenticatingManagedAccount = false
        self.authenticatingManagedAccountID = nil
    }
}
