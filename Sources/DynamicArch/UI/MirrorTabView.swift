import SwiftUI

struct MirrorTabView: View {
    var body: some View {
        MirrorView()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
