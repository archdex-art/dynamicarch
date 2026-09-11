import SwiftUI
import UniformTypeIdentifiers

/// Full shelf: a horizontal tray of staged items you can drag back out
/// individually or all at once.
struct ShelfTabView: View {
    let model: IslandModel
    private var store: ShelfStore { ShelfStore.shared }

    var body: some View {
        VStack(spacing: 8) {
            if store.isEmpty {
                ShelfEmptyState()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.items) { item in
                            ShelfItemCell(item: item)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                ShelfToolbar(model: model)
            }
        }
        .animation(Motion.content, value: store.items)
    }
}

struct ShelfEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)
                .symbolEffect(.bounce, options: .repeat(.periodic(delay: 3)))
            Text("Drop files, images, or text here")
                .font(Typography.title)
                .foregroundStyle(Palette.secondaryText)
            Text("They stay for \(Preferences.shared.shelfRetentionHours) h and follow you across spaces")
                .font(Typography.caption)
                .foregroundStyle(Palette.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.4, dash: [6, 5]))
                .foregroundStyle(.white.opacity(0.14))
        }
    }
}

struct ShelfItemCell: View {
    let item: ShelfItem
    @State private var hovering = false
    private var store: ShelfStore { ShelfStore.shared }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.controlFill)
                if let thumbnail = store.thumbnail(for: item) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                }

                if hovering {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.black.opacity(0.45))
                    HStack(spacing: 8) {
                        IslandButton(size: 22, tint: .white) { ShelfActions.quickLook([item], startingAt: 0) } label: {
                            Image(systemName: "eye.fill")
                        }
                        IslandButton(size: 22, tint: .white) { store.remove(item) } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
            }
            .frame(width: 64, height: 64)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(hovering ? 0.22 : 0.08), lineWidth: 0.8)
            }
            .scaleEffect(hovering ? 1.04 : 1)
            .animation(Motion.press, value: hovering)

            Text(item.name)
                .font(Typography.caption)
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 68)
        }
        .onHover { hovering = $0 }
        .help("\(item.name) · \(item.sizeDescription)")
        // Drag straight back out into any app: the file exists on disk, so a
        // plain file-URL provider is all Finder, Mail, and upload fields need.
        .onDrag {
            Haptics.tap()
            let provider = NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
            provider.suggestedName = item.name
            return provider
        } preview: {
            ShelfDragPreview(item: item)
        }
        .contextMenu { ShelfItemMenu(item: item) }
    }
}

struct ShelfDragPreview: View {
    let item: ShelfItem
    private var store: ShelfStore { ShelfStore.shared }

    var body: some View {
        Group {
            if let thumbnail = store.thumbnail(for: item) {
                Image(nsImage: thumbnail).resizable().scaledToFit()
            } else {
                Image(systemName: item.symbolName).font(.system(size: 28))
            }
        }
        .frame(width: 64, height: 64)
    }
}

struct ShelfItemMenu: View {
    let item: ShelfItem

    var body: some View {
        Button("Open") { ShelfActions.open(item) }
        Button("Quick Look") { ShelfActions.quickLook([item], startingAt: 0) }
        Button("Reveal in Finder") { ShelfActions.reveal(item) }
        Divider()
        Button("Copy") { ShelfActions.copyToPasteboard([item]) }
        Button("AirDrop…") { ShelfActions.airDrop([item], relativeTo: nil) }
        Button("Save a Copy…") { ShelfActions.saveCopy([item]) }
        if !FileConverter.conversions(for: item).isEmpty {
            Menu("Convert") {
                ForEach(FileConverter.conversions(for: item)) { conversion in
                    Button(conversion.title) { FileConverter.run(conversion, on: item) }
                }
            }
        }
        Divider()
        Button("Remove", role: .destructive) { ShelfStore.shared.remove(item) }
    }
}

struct ShelfToolbar: View {
    let model: IslandModel
    private var store: ShelfStore { ShelfStore.shared }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(store.items.count) item\(store.items.count == 1 ? "" : "s")")
                .font(Typography.caption)
                .foregroundStyle(Palette.tertiaryText)

            Spacer()

            // One handle that drags the entire stack, the way Finder does.
            MultiFileDragHandle(urls: store.items.map(\.url))
                .frame(width: 96, height: 24)

            IslandButton(size: 24, tint: Palette.secondaryText) {
                ShelfActions.airDrop(store.items, relativeTo: nil)
            } label: { Image(systemName: "airplayaudio") }
                .help("AirDrop everything")

            IslandButton(size: 24, tint: Palette.secondaryText) {
                ShelfActions.copyToPasteboard(store.items)
            } label: { Image(systemName: "doc.on.doc") }
                .help("Copy all")

            IslandButton(size: 24, tint: Palette.danger) {
                store.removeAll()
            } label: { Image(systemName: "trash") }
                .help("Clear shelf")
        }
    }
}

/// Compact shelf strip shown on the home tab.
struct ShelfMiniColumn: View {
    let model: IslandModel
    private var store: ShelfStore { ShelfStore.shared }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Shelf").font(Typography.caption).foregroundStyle(Palette.tertiaryText)
                Spacer()
                if !store.isEmpty {
                    Text("\(store.items.count)")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.controlFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                            .foregroundStyle(.white.opacity(store.isEmpty ? 0.16 : 0.06))
                    }

                if store.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Drop")
                            .font(Typography.caption)
                    }
                    .foregroundStyle(Palette.tertiaryText)
                } else {
                    ShelfStackPreview(items: Array(store.items.prefix(3)))
                }
            }
            .frame(maxHeight: .infinity)
            .onTapGesture { withAnimation(Motion.content) { model.tab = .shelf } }
        }
    }
}

struct ShelfStackPreview: View {
    let items: [ShelfItem]
    private var store: ShelfStore { ShelfStore.shared }

    var body: some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Group {
                    if let thumbnail = store.thumbnail(for: item) {
                        Image(nsImage: thumbnail).resizable().scaledToFill()
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.12))
                            Image(systemName: item.symbolName).font(.system(size: 16))
                                .foregroundStyle(Palette.secondaryText)
                        }
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .rotationEffect(.degrees(Double(index) * 6 - 6))
                .offset(x: CGFloat(index) * 6 - 6, y: CGFloat(index) * -3)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            }
        }
    }
}

struct ShelfDropOverlay: View {
    let targeted: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(targeted ? 0.55 : 0.35))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: targeted ? 2.4 : 1.6, dash: [8, 6]))
                .foregroundStyle(targeted ? Palette.accent : .white.opacity(0.35))
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(targeted ? Palette.accent : Palette.secondaryText)
                    .scaleEffect(targeted ? 1.12 : 1)
                Text(targeted ? "Release to stage" : "Drop to stage")
                    .font(Typography.title)
                    .foregroundStyle(Palette.primaryText)
            }
        }
        .animation(Motion.content, value: targeted)
    }
}
