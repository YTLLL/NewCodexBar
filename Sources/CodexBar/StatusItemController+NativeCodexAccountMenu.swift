import AppKit
import CodexBarCore

extension StatusItemController {
    func appendNativeCodexAccountSubmenu(to menu: NSMenu) {
        guard let display = self.codexAccountMenuDisplay(for: .codex) else { return }

        let accountMenuItem = NSMenuItem(title: "Codex Account", action: nil, keyEquivalent: "")
        let accountSubmenu = NSMenu(title: "Codex Account")
        accountMenuItem.submenu = accountSubmenu

        let activeID = display.activeVisibleAccountID
        let hasLive = display.accounts.contains(where: \.isLive)

        for account in display.accounts {
            let isDisplayed = account.id == activeID
            let isLiveSystem = account.isLive
            let displayedMarker = isDisplayed ? "\u{2713} " : "  "
            let liveMarker = isLiveSystem ? "\u{25CF} " : "  "
            let title = "\(displayedMarker)\(liveMarker)\(account.menuDisplayName)"

            let item = NSMenuItem(
                title: title,
                action: #selector(self.selectNativeCodexAccount(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = account
            item.state = isDisplayed ? .on : .off
            accountSubmenu.addItem(item)
        }

        accountSubmenu.addItem(.separator())

        let legendDisplayed = NSMenuItem(title: "\u{2713} Displayed usage account", action: nil, keyEquivalent: "")
        legendDisplayed.isEnabled = false
        accountSubmenu.addItem(legendDisplayed)

        if hasLive {
            let legendLive = NSMenuItem(title: "\u{25CF} Active Codex CLI account", action: nil, keyEquivalent: "")
            legendLive.isEnabled = false
            accountSubmenu.addItem(legendLive)
        } else {
            let legendUnknown = NSMenuItem(title: "Codex CLI Active Account: Unknown", action: nil, keyEquivalent: "")
            legendUnknown.isEnabled = false
            accountSubmenu.addItem(legendUnknown)
        }

        accountSubmenu.addItem(.separator())

        if let activeAccount = display.accounts.first(where: { $0.id == activeID }),
           let managedAccountID = activeAccount.storedAccountID
        {
            let activate = NSMenuItem(
                title: "Activate Selected Account for Codex CLI\u{2026}",
                action: #selector(self.requestCodexSystemPromotionFromMenu(_:)),
                keyEquivalent: "")
            activate.target = self
            activate.representedObject = managedAccountID.uuidString
            accountSubmenu.addItem(activate)
        }

        if self.removableManagedCodexAccounts().isEmpty == false {
            let removeAccount = NSMenuItem(
                title: "Remove Account\u{2026}",
                action: #selector(self.removeManagedCodexAccountFromMenu(_:)),
                keyEquivalent: "")
            removeAccount.target = self
            accountSubmenu.addItem(removeAccount)
        }

        let addAccount = NSMenuItem(
            title: "Add Account\u{2026}",
            action: #selector(self.addManagedCodexAccountFromMenu(_:)),
            keyEquivalent: "")
        addAccount.target = self
        accountSubmenu.addItem(addAccount)

        menu.addItem(accountMenuItem)
    }

    @objc private func selectNativeCodexAccount(_ sender: NSMenuItem) {
        guard let account = sender.representedObject as? CodexVisibleAccount else { return }
        _ = self.handleCodexVisibleAccountSelection(account, menu: sender.menu)
    }
}
