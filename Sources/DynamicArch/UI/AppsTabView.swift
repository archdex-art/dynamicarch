import AppKit
import SwiftUI

/// The running-apps manager: what is running, what it costs, and one tap to
/// get rid of it. Quitting is graceful; force quit is deliberate and confirmed.
struct AppsTabView: View {
    let model: IslandModel
    private var store: AppsStore { AppsStore.shared }

    @State private var confirming: AppsStore.Entry?
    @State private var confirmingQuitAll = false

    var body: some View {
        VStack(spacing: 6) {
            header

            if store.visibleEntries.isEmpty {
                Text("No apps running")
                    .font(Typography.title)
                    .foregroundStyle(Palette.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        ForEach(store.visibleEntries) { entry in
                            AppRow(entry: entry, confirming: $confirming)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                // Fade the cut-off row instead of slicing it in half.
                .mask {
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.88),
                        .init(color: .black.opacity(0), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
            }

            footer
        }
        .overlay {
            if let entry = confirming {
                ForceQuitConfirmation(entry: entry) { confirmed in
                    if confirmed { store.forceQuit(entry) }
                    withAnimation(Motion.content) { confirming = nil }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if confirmingQuitAll {
                QuitAllConfirmation(count: store.bulkQuitCandidates.count) { confirmed in
                    if confirmed { store.quitAll() }
                    withAnimation(Motion.content) { confirmingQuitAll = false }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .onAppear { store.beginLiveSampling() }
        .onDisappear {
            store.endLiveSampling()
            confirming = nil
            confirmingQuitAll = false
        }
        .animation(Motion.content, value: store.visibleEntries.map(\.id))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("\(store.visibleEntries.count) apps")
                .font(Typography.compact)
                .foregroundStyle(Palette.primaryText)
            Text(ByteCountFormatter.string(fromByteCount: store.totalMemory, countStyle: .memory))
                .font(Typography.caption)
                .foregroundStyle(Palette.secondaryText)
                .contentTransition(.numericText())

            Spacer()

            Toggle(isOn: Binding(
                get: { store.showsBackgroundApps },
                set: { store.showsBackgroundApps = $0 }
            )) {
                Text("Background")
                    .font(Typography.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Palette.accent)
            .foregroundStyle(Palette.secondaryText)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let message = store.lastActionMessage {
                Text(message)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.tertiaryText)
                    .lineLimit(1)
                    .transition(.opacity)
            }
            Spacer()
            Button {
                withAnimation(Motion.content) { confirmingQuitAll = true }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "xmark.circle.fill")
                    Text("Quit All")
                }
                .font(Typography.compact)
                .foregroundStyle(Palette.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Palette.controlFill))
            }
            .buttonStyle(.plain)
            .disabled(store.isQuitting)
        }
    }
}

private struct AppRow: View {
    let entry: AppsStore.Entry
    @Binding var confirming: AppsStore.Entry?

    @State private var hovering = false
    private var store: AppsStore { AppsStore.shared }

    private var isProtected: Bool { store.isProtected(entry) }
    private var isCritical: Bool { store.isCritical(entry) }
    private var isHung: Bool { entry.isResponding == false }

    var body: some View {
        HStack(spacing: 9) {
            if let icon = entry.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 19, height: 19)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 13))
                    .frame(width: 19, height: 19)
                    .foregroundStyle(Palette.secondaryText)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text(entry.name)
                        .font(Typography.compact)
                        .foregroundStyle(Palette.primaryText)
                        .lineLimit(1)
                    if entry.isActive {
                        Circle().fill(Palette.positive).frame(width: 4, height: 4)
                    }
                    if isProtected {
                        Image(systemName: isCritical ? "lock.fill" : "shield.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(isCritical ? Palette.tertiaryText : Palette.accent)
                    }
                }
                if isHung {
                    Text("Not responding")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.danger)
                } else if entry.isAccessory {
                    Text("Background")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.tertiaryText)
                }
            }

            Spacer(minLength: 4)

            // Usage always visible, actions always in the same place. Swapping
            // the two on hover moved the buttons under a still cursor, which
            // made it easy to hit force quit on the wrong app.
            HStack(spacing: 10) {
                Text(entry.cpuDescription)
                    .font(Typography.mono)
                    .foregroundStyle(entry.cpu > 60 ? Palette.warning : Palette.tertiaryText)
                    .frame(width: 34, alignment: .trailing)
                Text(entry.memoryDescription)
                    .font(Typography.mono)
                    .foregroundStyle(entry.memory > 2_000_000_000 ? Palette.warning : Palette.secondaryText)
                    .frame(width: 62, alignment: .trailing)
            }
            .contentTransition(.numericText())
            .opacity(hovering ? 0.35 : 1)

            HStack(spacing: 5) {
                RowButton(symbol: isProtected ? "shield.slash" : "shield",
                          tint: Palette.secondaryText,
                          help: isProtected ? "Unprotect" : "Protect from bulk quit",
                          enabled: !isCritical) {
                    store.toggleProtection(entry)
                }
                RowButton(symbol: "arrow.up.left.square",
                          tint: Palette.secondaryText,
                          help: "Bring to front",
                          enabled: true) {
                    store.activate(entry)
                }
                RowButton(symbol: "xmark",
                          tint: Palette.primaryText,
                          help: "Quit (asks to save)",
                          enabled: !isCritical) {
                    store.quit(entry)
                }
                RowButton(symbol: "bolt.fill",
                          tint: isProtected ? Palette.tertiaryText : Palette.danger,
                          help: isCritical ? "Required by macOS" : (isProtected ? "Protected" : "Force quit"),
                          enabled: !isCritical && !isProtected) {
                    withAnimation(Motion.content) { confirming = entry }
                }
            }
            // Reserved space always; only interactive on the hovered row, so a
            // stray click cannot reach a neighbour's controls.
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHung ? Palette.danger.opacity(0.14) : (hovering ? Palette.controlFill : .clear))
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Double click brings the app forward; a single click does nothing, so
        // clicking around the list is never destructive.
        .onTapGesture(count: 2) { store.activate(entry) }
        .animation(Motion.press, value: hovering)
    }
}

private struct RowButton: View {
    let symbol: String
    let tint: Color
    let help: String
    let enabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(enabled ? tint : Palette.tertiaryText)
            .frame(width: 25, height: 25)
            .background(Circle().fill(hovering && enabled ? Palette.controlFillHover : Palette.controlFill))
            .contentShape(Circle())
            .onHover { hovering = enabled && $0 }
            .onTapGesture {
                guard enabled else { return }
                Haptics.tap()
                action()
            }
            .help(help)
            .opacity(enabled ? 1 : 0.45)
    }
}

/// Force quit always confirms, and says plainly what is at risk. An app that is
/// still responding is the dangerous case: it has unsaved work and no chance to
/// save it.
private struct ForceQuitConfirmation: View {
    let entry: AppsStore.Entry
    let completion: (Bool) -> Void

    private var isHealthy: Bool { entry.isResponding != false }

    var body: some View {
        ConfirmationCard(
            symbol: isHealthy ? "exclamationmark.triangle.fill" : "bolt.fill",
            tint: isHealthy ? Palette.warning : Palette.danger,
            title: "Force quit \(entry.name)?",
            message: isHealthy
                ? "It is still responding. Unsaved work will be lost - quitting normally lets it save first."
                : "It stopped responding, so unsaved work is probably already gone.",
            confirmTitle: "Force Quit",
            confirmTint: Palette.danger,
            completion: completion
        )
    }
}

private struct QuitAllConfirmation: View {
    let count: Int
    let completion: (Bool) -> Void

    var body: some View {
        ConfirmationCard(
            symbol: "xmark.circle.fill",
            tint: Palette.warning,
            title: "Quit \(count) app\(count == 1 ? "" : "s")?",
            message: "Each app quits normally and can still ask you to save. Protected and system apps are skipped.",
            confirmTitle: "Quit All",
            confirmTint: Palette.accent,
            completion: completion
        )
    }
}

private struct ConfirmationCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    let confirmTitle: String
    let confirmTint: Color
    let completion: (Bool) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Typography.title)
                        .foregroundStyle(Palette.primaryText)
                    Text(message)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { completion(false) }
                    .buttonStyle(CapsuleButtonStyle(tint: Palette.controlFill, foreground: Palette.primaryText))
                Button(confirmTitle) { completion(true) }
                    .buttonStyle(CapsuleButtonStyle(tint: confirmTint, foreground: .white))
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.confirmationBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        }
        .padding(.horizontal, 10)
    }
}

struct CapsuleButtonStyle: ButtonStyle {
    let tint: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.compact)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.7 : 1)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}
