import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let model: IslandModel
    private var item: NSStatusItem?

    init(model: IslandModel) {
        self.model = model
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "DynamicArch")
        item.button?.image?.isTemplate = true
        item.menu = buildMenu()
        self.item = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(withTitle: "Open Island", action: #selector(openIsland), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())

        let shelf = menu.addItem(withTitle: "Clear Shelf", action: #selector(clearShelf), keyEquivalent: "")
        shelf.target = self

        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self

        let login = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = LaunchAtLogin.isEnabled ? .on : .off

        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit DynamicArch", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTitle: "Launch at Login")?.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func openIsland() { model.open() }
    @objc private func clearShelf() { ShelfStore.shared.removeAll() }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func toggleLaunchAtLogin() { LaunchAtLogin.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}
