import AppKit

/// Runs the user's own Shortcuts from the island. Enumerated through the
/// `shortcuts` CLI that ships with macOS, so there is nothing to configure.
@MainActor
@Observable
final class ShortcutsStore {
    static let shared = ShortcutsStore()

    private(set) var names: [String] = []
    private(set) var pinned: [String] = UserDefaults.standard.stringArray(forKey: "pinnedShortcuts") ?? []
    private(set) var isRunning: String?

    private init() {}

    func refresh() {
        Task.detached(priority: .utility) {
            let output = Self.run(["list"])
            let list = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            await MainActor.run { [weak self] in self?.names = list }
        }
    }

    func pin(_ name: String) {
        guard !pinned.contains(name) else { return }
        pinned.append(name)
        if pinned.count > 4 { pinned.removeFirst() }
        UserDefaults.standard.set(pinned, forKey: "pinnedShortcuts")
    }

    func unpin(_ name: String) {
        pinned.removeAll { $0 == name }
        UserDefaults.standard.set(pinned, forKey: "pinnedShortcuts")
    }

    func run(_ name: String) {
        isRunning = name
        Task.detached(priority: .userInitiated) {
            _ = Self.run(["run", name])
            await MainActor.run { [weak self] in
                self?.isRunning = nil
                Haptics.success()
            }
        }
    }

    /// Menu used by the home tile, built on demand so it always reflects the
    /// current Shortcuts library.
    func presentMenu() {
        if names.isEmpty { refresh() }
        let menu = NSMenu()
        for name in pinned {
            let item = menu.addItem(withTitle: name, action: #selector(MenuTarget.run(_:)), keyEquivalent: "")
            item.target = MenuTarget.shared
            item.representedObject = name
        }
        if !pinned.isEmpty { menu.addItem(.separator()) }
        let all = NSMenu()
        for name in names.prefix(80) {
            let item = all.addItem(withTitle: name, action: #selector(MenuTarget.run(_:)), keyEquivalent: "")
            item.target = MenuTarget.shared
            item.representedObject = name
        }
        let allItem = menu.addItem(withTitle: "All Shortcuts", action: nil, keyEquivalent: "")
        allItem.submenu = all
        // Menu tracking runs its own event loop; hold the island open for as
        // long as the menu is up, or it collapses under the user's cursor.
        IslandModel.shared.interactionLock += 1
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        IslandModel.shared.interactionLock = max(0, IslandModel.shared.interactionLock - 1)
    }

    @MainActor
    final class MenuTarget: NSObject {
        static let shared = MenuTarget()
        @objc func run(_ sender: NSMenuItem) {
            guard let name = sender.representedObject as? String else { return }
            ShortcutsStore.shared.run(name)
        }
    }

    private nonisolated static func run(_ arguments: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
