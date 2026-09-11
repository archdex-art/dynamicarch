import SwiftUI

/// Root of everything drawn inside the panel. The island is pinned to the top
/// centre; every other point of the stage stays empty so clicks fall through.
struct IslandRootView: View {
    let model: IslandModel
    @Namespace private var morph

    var body: some View {
        IslandContainer(model: model, morph: morph)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(.all)
            .environment(\.colorScheme, Palette.theme.isLight ? .light : .dark)
    }
}

struct IslandContainer: View {
    let model: IslandModel
    let morph: Namespace.ID

    private var layout: IslandLayout { model.layout }

    var body: some View {
        let accent = model.media.track?.accent ?? Palette.accent
        let isOpen = model.stage == .open

        ZStack(alignment: .top) {
            IslandSurface(topRadius: layout.topRadius,
                          bottomRadius: layout.bottomRadius,
                          accent: accent,
                          isOpen: isOpen,
                          isIdle: model.stage == .closed && model.compactPresentation == .none)

            content
                .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
                .clipShape(NotchShape(topRadius: layout.topRadius, bottomRadius: layout.bottomRadius))
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .contentShape(NotchShape(topRadius: layout.topRadius, bottomRadius: layout.bottomRadius))
        .onTapGesture { model.stage == .open ? () : model.open() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("DynamicArch island")
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .closed:
            CompactIslandView(model: model, morph: morph)
                .transition(Motion.compactSwap)
        case .peek:
            PeekIslandView(model: model, morph: morph)
                .transition(Motion.compactSwap)
        case .open:
            ExpandedIslandView(model: model, morph: morph)
                .transition(Motion.contentSwap)
        }
    }
}
