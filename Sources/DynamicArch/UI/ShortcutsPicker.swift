import SwiftUI

/// Runs and pins Shortcuts from inside the island.
///
/// This replaces an `NSMenu` popped from a background app, which never
/// reliably took the click and gave no way to see or fix an empty library.
struct ShortcutsPicker: View {
    let model: IslandModel
    private var store: ShortcutsStore { ShortcutsStore.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            HStack(spacing: Metrics.small) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.warning)
                Text("Shortcuts")
                    .font(Typography.title)
                    .foregroundStyle(Palette.primaryText)
                if store.isLoading {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                IslandButton(size: 22, tint: Palette.secondaryText) {
                    model.dismissShortcutsPicker()
                } label: {
                    Image(systemName: "xmark")
                }
            }

            if store.hasShortcuts {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(store.names, id: \.self) { name in
                            ShortcutRow(name: name)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: Metrics.small) {
                    Text("No shortcuts found")
                        .font(Typography.compact)
                        .foregroundStyle(Palette.primaryText)
                    Text("Create one in the Shortcuts app and it will appear here straight away.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Metrics.small) {
                        Button("Open Shortcuts") { store.openShortcutsApp() }
                            .buttonStyle(CapsuleButtonStyle(tint: Palette.accent, foreground: .white))
                        Button("Reload") { store.refresh() }
                            .buttonStyle(CapsuleButtonStyle(tint: Palette.controlFill,
                                                            foreground: Palette.primaryText))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Metrics.medium)
        .background {
            RoundedRectangle(cornerRadius: Metrics.medium, style: .continuous)
                .fill(Palette.confirmationBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.medium, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        }
        .onAppear { store.refresh() }
    }
}

private struct ShortcutRow: View {
    let name: String
    @State private var hovering = false
    private var store: ShortcutsStore { ShortcutsStore.shared }

    private var isPinned: Bool { store.pinned.contains(name) }

    var body: some View {
        HStack(spacing: Metrics.small) {
            Image(systemName: store.isRunning == name ? "hourglass" : "bolt.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(store.isRunning == name ? Palette.accent : Palette.warning)
                .frame(width: 16)
            Text(name)
                .font(Typography.caption)
                .foregroundStyle(Palette.primaryText)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isPinned ? Palette.accent : Palette.tertiaryText)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Palette.controlFill))
                .contentShape(Circle())
                .onTapGesture { isPinned ? store.unpin(name) : store.pin(name) }
                .opacity(hovering || isPinned ? 1 : 0)
                .help(isPinned ? "Unpin" : "Pin")
        }
        .padding(.horizontal, Metrics.small)
        .padding(.vertical, Metrics.tight)
        .background {
            RoundedRectangle(cornerRadius: Metrics.small, style: .continuous)
                .fill(hovering ? Palette.controlFill : .clear)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { store.run(name) }
    }
}
