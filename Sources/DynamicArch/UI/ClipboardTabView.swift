import SwiftUI

struct ClipboardTabView: View {
    private var store: ClipboardStore { ClipboardStore.shared }

    var body: some View {
        VStack(spacing: 6) {
            if store.entries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                    Text("Nothing copied yet")
                        .font(Typography.title)
                        .foregroundStyle(Palette.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(store.entries) { entry in
                            ClipboardRow(entry: entry)
                        }
                    }
                }
                HStack {
                    Text("\(store.entries.count) items")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.tertiaryText)
                    Spacer()
                    IslandButton(size: 22, tint: Palette.danger) { store.clear() } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }
}

struct ClipboardRow: View {
    let entry: ClipboardStore.Entry
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            if case .image(let image) = entry.payload {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 26, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: entry.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 20)
            }

            Text(entry.preview)
                .font(Typography.caption)
                .foregroundStyle(Palette.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if hovering {
                IslandButton(size: 18, tint: Palette.secondaryText) { ClipboardStore.shared.remove(entry) } label: {
                    Image(systemName: "xmark")
                }
            } else if let source = entry.sourceApp {
                Text(source)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.tertiaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Palette.controlFill : .clear)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { ClipboardStore.shared.copy(entry) }
    }
}
