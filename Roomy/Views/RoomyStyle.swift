import SwiftUI

/// Shared visual language for Roomy: cards, section headers, media badges.
/// System colors only, so everything adapts to light/dark mode.
enum RoomyStyle {
    static let corner: CGFloat = 16
    static let cardPadding: CGFloat = 14
}

/// Frosted card container used for rows and content blocks.
struct RoomyCard: ViewModifier {
    var padding: CGFloat = RoomyStyle.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(RoomyStyle.corner)
    }
}

extension View {
    func roomyCard(padding: CGFloat = RoomyStyle.cardPadding) -> some View {
        modifier(RoomyCard(padding: padding))
    }
}

/// Big primary call-to-action button.
struct RoomyPrimaryButton: ViewModifier {
    var isEnabled = true

    func body(content: Content) -> some View {
        content
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(isEnabled ? Color.accentColor : Color.gray.opacity(0.4))
            .foregroundStyle(.white)
            .cornerRadius(RoomyStyle.corner)
    }
}

extension View {
    func roomyPrimaryButton(isEnabled: Bool = true) -> some View {
        modifier(RoomyPrimaryButton(isEnabled: isEnabled))
    }
}

/// Small pill badge for photo/video/live media kinds.
struct MediaBadge: View {
    let item: LibraryItem

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.55))
        .foregroundStyle(.white)
        .cornerRadius(8)
        .accessibilityHidden(true)
    }

    private var icon: String {
        if item.isVideo { return "video.fill" }
        if item.isLivePhoto { return "livephoto" }
        return "photo.fill"
    }

    private var label: String {
        if item.isVideo { return FormatHelpers.duration(item.duration) }
        if item.isLivePhoto { return "Live" }
        return FormatHelpers.bytes(item.originalBytes)
    }
}

/// Gradient hero tile used as the app mark.
struct RoomyAppMark: View {
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            Image(systemName: "photo.stack.fill")
                .font(.system(size: size * 0.42))
                .foregroundStyle(.white)
                .accessibilityHidden(true)
        }
        .shadow(color: Color.accentColor.opacity(0.35), radius: size * 0.18, y: size * 0.08)
    }
}
