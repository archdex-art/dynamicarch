import SwiftUI

/// Scrolls text horizontally when, and only when, it does not fit.
///
/// The text lives in an *overlay* over a flexible, zero-intrinsic-width shape:
/// a plain `Text` with `fixedSize` would report the full string width up the
/// layout chain and shove its neighbours off the panel.
struct MarqueeText: View {
    let text: String
    var font: Font = Typography.title
    var color: Color = Palette.primaryText
    var height: CGFloat = 17
    var speed: Double = 26

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflow: CGFloat { max(0, textWidth - containerWidth) }

    var body: some View {
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(x: offset)
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { textWidth = proxy.size.width }
                                .onChange(of: proxy.size.width) { _, new in textWidth = new }
                        }
                    }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { containerWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, new in containerWidth = new }
                }
            }
            .clipped()
            // Fade the trailing edge so long titles dissolve instead of being
            // chopped mid-glyph.
            .mask {
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: overflow > 1 ? 0.90 : 1),
                    .init(color: .black.opacity(overflow > 1 ? 0 : 1), location: 1)
                ], startPoint: .leading, endPoint: .trailing)
            }
            .task(id: "\(text)|\(textWidth)|\(containerWidth)") { await animate() }
    }

    private func animate() async {
        offset = 0
        guard overflow > 1, containerWidth > 1 else { return }
        let duration = Double(overflow) / speed
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: duration)) { offset = -overflow }
            try? await Task.sleep(for: .seconds(duration + 1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.45)) { offset = 0 }
        }
    }
}
