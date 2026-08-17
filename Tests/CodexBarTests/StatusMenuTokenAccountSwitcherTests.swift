import AppKit
import CodexBarCore
import Foundation
import XCTest
@testable import CodexBar

@MainActor
final class StatusMenuTokenAccountSwitcherTests: XCTestCase {
    private func disableMenuCardsForTesting() {
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.setMenuRefreshEnabledForTesting(false)
    }

    private func makeStatusBarForTesting() -> NSStatusBar {
        let env = ProcessInfo.processInfo.environment
        if env["GITHUB_ACTIONS"] == "true" || env["CI"] == "true" {
            return .system
        }
        return NSStatusBar()
    }

    private func makeSettings() -> SettingsStore {
        let suite = "StatusMenuTokenAccountSwitcherTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore())
        settings.providerDetectionCompleted = true
        return settings
    }

    private func enableOnlyClaude(_ settings: SettingsStore) {
        self.enableOnly(.claude, settings)
    }

    private func enableOnly(_ enabledProvider: UsageProvider, _ settings: SettingsStore) {
        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: provider == enabledProvider)
        }
    }

    private func representedIDs(in menu: NSMenu) -> [String] {
        menu.items.compactMap { $0.representedObject as? String }
    }

    /// Finds the native token account submenu for a provider by matching the "{displayName} Account" title.
    private func findTokenAccountSubmenu(in menu: NSMenu, displayName: String) -> NSMenu? {
        menu.items.first { $0.title == "\(displayName) Account" && $0.submenu != nil }?.submenu
    }

    /// Simulates selecting a native token account submenu item by sending its action to its target.
    private func selectNativeTokenAccountItem(
        in submenu: NSMenu,
        at index: Int,
        file: StaticString = #filePath,
        line: UInt = #line) throws
    {
        XCTAssertTrue(
            index < submenu.items.count,
            "Token account submenu has fewer than \(index + 1) items",
            file: file,
            line: line)
        let item = submenu.items[index]
        XCTAssertNotNil(item.action, "Token account item has no action", file: file, line: line)
        XCTAssertNotNil(item.target, "Token account item has no target", file: file, line: line)
        NSApplication.shared.sendAction(item.action!, to: item.target, from: item)
    }

    private func installBlockingClaudeProvider(on store: UsageStore, blocker: BlockingTokenAccountFetchStrategy) {
        let baseSpec = store.providerSpecs[.claude]!
        store.providerSpecs[.claude] = Self.makeClaudeProviderSpec(baseSpec: baseSpec) {
            try await blocker.awaitResult()
        }
    }

    private static func makeClaudeProviderSpec(
        baseSpec: ProviderSpec,
        loader: @escaping @Sendable () async throws -> UsageSnapshot) -> ProviderSpec
    {
        let baseDescriptor = baseSpec.descriptor
        let strategy = StatusMenuTokenAccountFetchStrategy(loader: loader)
        let descriptor = ProviderDescriptor(
            id: .claude,
            metadata: baseDescriptor.metadata,
            branding: baseDescriptor.branding,
            tokenCost: baseDescriptor.tokenCost,
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .cli, .oauth],
                pipeline: ProviderFetchPipeline { _ in [strategy] }),
            cli: baseDescriptor.cli)
        return ProviderSpec(
            style: baseSpec.style,
            isEnabled: baseSpec.isEnabled,
            descriptor: descriptor,
            makeFetchContext: baseSpec.makeFetchContext)
    }

    private func snapshot(percent: Double = 12) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: percent,
                windowMinutes: 300,
                resetsAt: Date().addingTimeInterval(300),
                resetDescription: nil),
            secondary: nil,
            updatedAt: Date(),
            identity: ProviderIdentitySnapshot(
                providerID: .claude,
                accountEmail: "claude@example.com",
                accountOrganization: nil,
                loginMethod: "OAuth"))
    }

    func test_tokenAccountMenuSelectionRefreshesProviderWhileGlobalRefreshIsActive() async throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        self.enableOnlyClaude(settings)
        settings.addTokenAccount(provider: .claude, label: "Primary", token: "Bearer sk-ant-oat-primary")
        settings.addTokenAccount(provider: .claude, label: "Secondary", token: "Bearer sk-ant-oat-secondary")
        settings.setActiveTokenAccountIndex(0, for: .claude)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let blocker = BlockingTokenAccountFetchStrategy()
        self.installBlockingClaudeProvider(on: store, blocker: blocker)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let refreshTask = Task { @MainActor in
            await store.refresh()
        }
        await blocker.waitUntilStarted(count: 1)
        XCTAssertTrue(store.isRefreshing)

        let menu = controller.makeMenu()
        defer { withExtendedLifetime(menu) {} }
        controller.menuWillOpen(menu)

        // Native token account submenu replaces hosted TokenAccountSwitcherView
        let tokenSubmenu = try XCTUnwrap(self.findTokenAccountSubmenu(in: menu, displayName: "Claude"))
        XCTAssertFalse(tokenSubmenu.items.isEmpty, "Token submenu should contain account items")
        try self.selectNativeTokenAccountItem(in: tokenSubmenu, at: 1)

        await blocker.waitUntilStarted(count: 2)
        XCTAssertEqual(settings.tokenAccountsData(for: .claude)?.clampedActiveIndex(), 1)

        await blocker.resumeAll(with: .success(self.snapshot(percent: 17)))
        await refreshTask.value
        let startedCallCount = await blocker.startedCallCount()
        XCTAssertGreaterThanOrEqual(startedCallCount, 2)
    }

    func test_multiAccountSegmentedLayoutShowsCopilotSwitcher() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.multiAccountMenuLayout = .segmented
        self.enableOnly(.copilot, settings)
        settings.addTokenAccount(provider: .copilot, label: "Primary", token: "gh_primary")
        settings.addTokenAccount(provider: .copilot, label: "Secondary", token: "gh_secondary")
        settings.setActiveTokenAccountIndex(0, for: .copilot)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu(for: .copilot)
        controller.menuWillOpen(menu)

        // Native submenu replaces hosted TokenAccountSwitcherView — no hosted view should exist
        XCTAssertNil(menu.items.compactMap { $0.view as? TokenAccountSwitcherView }.first)
        let tokenSubmenu = try XCTUnwrap(self.findTokenAccountSubmenu(in: menu, displayName: "Copilot"))
        XCTAssertEqual(tokenSubmenu.items.count, 2)
        XCTAssertEqual(tokenSubmenu.items[0].state, .on, "First account should be active")
        XCTAssertEqual(tokenSubmenu.items[1].state, .off)
    }

    func test_multiAccountStackedLayoutShowsCopilotCards() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.multiAccountMenuLayout = .stacked
        self.enableOnly(.copilot, settings)
        settings.addTokenAccount(provider: .copilot, label: "Primary", token: "gh_primary")
        settings.addTokenAccount(provider: .copilot, label: "Secondary", token: "gh_secondary")
        let accounts = settings.tokenAccounts(for: .copilot)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        store.accountSnapshots[.copilot] = accounts.enumerated().map { index, account in
            TokenAccountUsageSnapshot(
                account: account,
                snapshot: self.snapshot(percent: Double(10 + index)),
                error: nil,
                sourceLabel: "test")
        }
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu(for: .copilot)
        controller.menuWillOpen(menu)

        // Native submenu replaces hosted menu cards for both segmented and stacked layouts
        XCTAssertNil(menu.items.compactMap { $0.view as? TokenAccountSwitcherView }.first)
        let tokenSubmenu = try XCTUnwrap(self.findTokenAccountSubmenu(in: menu, displayName: "Copilot"))
        XCTAssertEqual(tokenSubmenu.items.count, 2)
        XCTAssertEqual(tokenSubmenu.items[0].title, "Primary")
        XCTAssertEqual(tokenSubmenu.items[1].title, "Secondary")
    }

    func test_multiAccountStackedRefreshStartsAccountFetchesConcurrently() async {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.multiAccountMenuLayout = .stacked
        self.enableOnlyClaude(settings)
        settings.addTokenAccount(provider: .claude, label: "Primary", token: "Bearer sk-ant-oat-primary")
        settings.addTokenAccount(provider: .claude, label: "Secondary", token: "Bearer sk-ant-oat-secondary")

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let blocker = BlockingTokenAccountFetchStrategy()
        self.installBlockingClaudeProvider(on: store, blocker: blocker)

        let refreshTask = Task { @MainActor in
            await store.refreshProvider(.claude)
        }

        await blocker.waitUntilStarted(count: 2)
        let startedBeforeResume = await blocker.startedCallCount()
        XCTAssertEqual(startedBeforeResume, 2)

        await blocker.resumeAll(with: .success(self.snapshot(percent: 17)))
        await refreshTask.value
        XCTAssertEqual(store.accountSnapshots[.claude]?.count, 2)
    }

    func test_multiAccountStackedLayoutIgnoresStaleSnapshotsAndKeepsMenuCapped() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        settings.multiAccountMenuLayout = .stacked
        self.enableOnly(.copilot, settings)
        for index in 0..<8 {
            settings.addTokenAccount(provider: .copilot, label: "Account \(index)", token: "gh_\(index)")
        }
        settings.setActiveTokenAccountIndex(7, for: .copilot)
        let accounts = settings.tokenAccounts(for: .copilot)
        let staleAccounts = (0..<2).map { index in
            ProviderTokenAccount(
                id: UUID(),
                label: "Removed \(index)",
                token: "stale_\(index)",
                addedAt: TimeInterval(index),
                lastUsed: nil)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let staleSnapshots = staleAccounts.enumerated().map { index, account in
            TokenAccountUsageSnapshot(
                account: account,
                snapshot: self.snapshot(percent: Double(70 + index)),
                error: nil,
                sourceLabel: "stale")
        }
        let currentSnapshots = accounts.enumerated().map { index, account in
            TokenAccountUsageSnapshot(
                account: account,
                snapshot: self.snapshot(percent: Double(10 + index)),
                error: nil,
                sourceLabel: "current")
        }
        store.accountSnapshots[.copilot] = staleSnapshots + currentSnapshots
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu(for: .copilot)
        controller.menuWillOpen(menu)

        XCTAssertNil(menu.items.compactMap { $0.view as? TokenAccountSwitcherView }.first)
        // Native submenu shows all current accounts (stale snapshots don't create extra items)
        let tokenSubmenu = try XCTUnwrap(self.findTokenAccountSubmenu(in: menu, displayName: "Copilot"))
        XCTAssertEqual(tokenSubmenu.items.count, 8, "All 8 current accounts should be in the submenu")
        // Active account (index 7) has .on state
        XCTAssertEqual(tokenSubmenu.items[7].state, .on)
    }

    func test_tokenAccountSwitchDefersOpenMenuRebuildUntilAfterSwitcherAction() async throws {
        self.disableMenuCardsForTesting()
        StatusItemController.setMenuRefreshEnabledForTesting(true)
        defer { StatusItemController.setMenuRefreshEnabledForTesting(false) }

        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .claude
        settings.multiAccountMenuLayout = .segmented
        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            settings.setProviderEnabled(
                provider: provider,
                metadata: metadata,
                enabled: provider == .claude || provider == .codex)
        }
        settings.addTokenAccount(provider: .claude, label: "Primary", token: "Bearer sk-ant-oat-primary")
        settings.addTokenAccount(provider: .claude, label: "Secondary", token: "Bearer sk-ant-oat-secondary")
        settings.setActiveTokenAccountIndex(0, for: .claude)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let blocker = BlockingTokenAccountFetchStrategy()
        self.installBlockingClaudeProvider(on: store, blocker: blocker)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)

        // Native token submenu replaces hosted TokenAccountSwitcherView
        let tokenSubmenu = try XCTUnwrap(self.findTokenAccountSubmenu(in: menu, displayName: "Claude"))
        XCTAssertFalse(tokenSubmenu.items.isEmpty)

        var rebuildCount = 0
        controller._test_openMenuRebuildObserver = { _ in
            rebuildCount += 1
        }
        defer { controller._test_openMenuRebuildObserver = nil }

        // Submenu selection triggers the native selector; parent menu rebuild is not scheduled
        // because sender.menu (submenu) is not tracked in openMenus
        try self.selectNativeTokenAccountItem(in: tokenSubmenu, at: 1)

        // Selection immediately updates the active index
        XCTAssertEqual(settings.tokenAccountsData(for: .claude)?.clampedActiveIndex(), 1)
        // Parent menu is not rebuilt on submenu selection
        XCTAssertEqual(rebuildCount, 0)

        await blocker.waitUntilStarted(count: 1)
        await blocker.resumeAll(with: .success(self.snapshot(percent: 17)))
    }
}

private struct StatusMenuTokenAccountFetchStrategy: ProviderFetchStrategy {
    let loader: @Sendable () async throws -> UsageSnapshot

    var id: String {
        "status-menu-token-account-test"
    }

    var kind: ProviderFetchKind {
        .cli
    }

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        true
    }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        let snapshot = try await self.loader()
        return self.makeResult(usage: snapshot, sourceLabel: "status-menu-token-account-test")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}

private actor BlockingTokenAccountFetchStrategy {
    private var waiters: [CheckedContinuation<Result<UsageSnapshot, Error>, Never>] = []
    private var startedWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var resolvedResult: Result<UsageSnapshot, Error>?
    private var startedCount = 0

    func awaitResult() async throws -> UsageSnapshot {
        if let resolvedResult {
            self.startedCount += 1
            self.resumeStartedWaiters()
            return try resolvedResult.get()
        }
        let result = await withCheckedContinuation { continuation in
            self.waiters.append(continuation)
            self.startedCount += 1
            self.resumeStartedWaiters()
        }
        return try result.get()
    }

    func waitUntilStarted(count: Int) async {
        if self.startedCount >= count { return }
        await withCheckedContinuation { continuation in
            self.startedWaiters.append((count: count, continuation: continuation))
        }
    }

    func startedCallCount() -> Int {
        self.startedCount
    }

    func resumeAll(with result: Result<UsageSnapshot, Error>) {
        self.resolvedResult = result
        self.waiters.forEach { $0.resume(returning: result) }
        self.waiters.removeAll()
    }

    private func resumeStartedWaiters() {
        let ready = self.startedWaiters.filter { self.startedCount >= $0.count }
        self.startedWaiters.removeAll { self.startedCount >= $0.count }
        ready.forEach { $0.continuation.resume() }
    }
}
