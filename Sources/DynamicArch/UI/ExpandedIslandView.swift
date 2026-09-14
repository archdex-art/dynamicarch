import SwiftUI

/// The open panel: header, tab content, and the drop overlay.
struct ExpandedIslandView: View {
    let model: IslandModel
    let morph: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            IslandHeader(model: model)
                .frame(height: (model.metrics?.restingSize.height ?? 32))

            ZStack {
                if let call = CallCenter.shared.call {
                    CallTakeoverView(call: call)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)
                        .transition(Motion.contentSwap)
                } else {
                    tabContent
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                        .padding(.top, 2)
                }

                if model.shortcutsPickerVisible {
                    ShortcutsPicker(model: model)
                        .padding(Metrics.small)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else if model.dropTargeted || (model.dragInFlight && model.tab == .shelf) {
                    ShelfDropOverlay(targeted: model.dropTargeted)
                        .padding(10)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        let slide = Motion.sectionSlide(direction: model.tabDirection)
        switch model.tab {
        case .home:
            HomeTabView(model: model, morph: morph).transition(slide)
        case .timer:
            TimerTabView(model: model).transition(slide)
        case .shelf:
            ShelfTabView(model: model).transition(slide)
        case .apps:
            AppsTabView(model: model).transition(slide)
        case .clipboard:
            ClipboardTabView().transition(slide)
        case .calendar:
            CalendarTabView().transition(slide)
        case .mirror:
            MirrorTabView().transition(slide)
        }
    }
}

/// Header sits in the strip that is level with the notch, so the camera housing
/// visually becomes part of the UI instead of a hole punched through it.
struct IslandHeader: View {
    let model: IslandModel

    var body: some View {
        let resting = model.metrics?.restingSize.width ?? 190

        HStack(spacing: 0) {
            HStack(spacing: 10) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(context.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
                if let battery = PowerStore.shared.snapshot {
                    BatteryPill(snapshot: battery)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, 16)

            Spacer(minLength: resting)

            HStack(spacing: 6) {
                Spacer(minLength: 0)
                TabRail(model: model)
                IslandButton(size: 22, tint: Palette.secondaryText) {
                    SettingsWindowController.shared.show()
                } label: {
                    Image(systemName: "gearshape.fill")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.trailing, 12)
        }
    }
}

struct TabRail: View {
    let model: IslandModel
    @Namespace private var indicator

    private var tabs: [IslandTab] { model.availableTabs }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                let selected = model.tab == tab
                Image(systemName: tab.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selected ? Palette.primaryText : Palette.tertiaryText)
                    .frame(width: 24, height: 20)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Palette.controlFill)
                                .matchedGeometryEffect(id: "tab", in: indicator)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { model.select(tab: tab) }
                    .help(tab.title)
            }
        }
    }
}

struct BatteryPill: View {
    let snapshot: PowerStore.Snapshot

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: snapshot.symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(snapshot.tint)
                .contentTransition(.symbolEffect(.replace))
            Text("\(Int(snapshot.level * 100))%")
                .font(Typography.caption)
                .foregroundStyle(Palette.secondaryText)
                .contentTransition(.numericText())
        }
        .animation(Motion.content, value: snapshot.level)
    }
}
