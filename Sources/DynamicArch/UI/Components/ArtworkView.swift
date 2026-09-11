import SwiftUI

/// Album art with a graceful empty state and a soft accent glow.
///
/// The layout size comes from a flexible shape and the image rides in an
/// overlay: putting the image itself in the layout path lets non-square art -
/// a 16:9 video thumbnail, say - report its own aspect ratio, clip at that
/// size, and then spill outside the frame the caller asked for.
struct ArtworkView: View {
    let image: NSImage?
    var accent: Color = Palette.accent
    var cornerRadius: CGFloat = 10

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        LinearGradient(colors: [accent.opacity(0.55), accent.opacity(0.15)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "music.note")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            // Clip after the frame is established, never before it.
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.6)
            }
            .shadow(color: accent.opacity(0.35), radius: 6, y: 2)
    }
}
