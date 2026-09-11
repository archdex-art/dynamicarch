import SwiftUI

struct CalendarTabView: View {
    private var calendar: CalendarStore { CalendarStore.shared }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(Typography.title)
                        .foregroundStyle(Palette.primaryText)
                }

                if !calendar.accessGranted {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Calendar access is off")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                        Button("Grant Access") { calendar.requestAccess() }
                            .buttonStyle(.borderless)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.accent)
                    }
                } else if calendar.events.isEmpty {
                    Text("Nothing scheduled")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.tertiaryText)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(calendar.events) { event in
                                EventRow(event: event)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            WeatherPanel()
                .frame(width: 150)
        }
    }
}

struct EventRow: View {
    let event: CalendarStore.Event

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(event.color)
                .frame(width: 3, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)
                Text(event.timeDescription)
                    .font(Typography.caption)
                    .foregroundStyle(event.isNow ? Palette.positive : Palette.tertiaryText)
            }
            Spacer(minLength: 0)
        }
    }
}

struct WeatherPanel: View {
    private var weather: WeatherStore { WeatherStore.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let snapshot = weather.snapshot {
                HStack(spacing: 8) {
                    Image(systemName: snapshot.symbolName)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white, Palette.accent)
                        .symbolRenderingMode(.palette)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(Int(snapshot.temperature.rounded()))°")
                            .font(Typography.headline)
                            .foregroundStyle(Palette.primaryText)
                        Text(snapshot.summary)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
                Text(snapshot.place)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.tertiaryText)
                Text("H \(Int(snapshot.high.rounded()))°  L \(Int(snapshot.low.rounded()))°")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.tertiaryText)
            } else if weather.needsAuthorization {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Local weather needs your location")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                    Button("Enable Weather") { weather.requestAccess() }
                        .buttonStyle(.borderless)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.accent)
                }
            } else {
                Text("Weather unavailable")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.tertiaryText)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WeatherGlance: View {
    private var weather: WeatherStore { WeatherStore.shared }

    var body: some View {
        VStack(spacing: 2) {
            if let snapshot = weather.snapshot {
                Image(systemName: snapshot.symbolName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Palette.primaryText)
                Text("\(Int(snapshot.temperature.rounded()))°")
                    .font(Typography.title)
                    .foregroundStyle(Palette.primaryText)
            } else {
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                Text("Today")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }
}
