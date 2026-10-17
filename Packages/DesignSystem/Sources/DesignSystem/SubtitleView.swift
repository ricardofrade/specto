import SwiftUI
import CoreText
import MediaAccessibility

/// The person's caption style from Settings → Accessibility → Subtitles & Captioning: font,
/// size, text and background colours and opacity, and the text edge. Read once per change of
/// those settings, never in `body`.
public struct CaptionStyle: Equatable, Sendable {
    public var foreground: Color
    public var background: Color
    /// Behind the whole caption block (often clear).
    public var window: Color
    /// The person's size relative to the default (1 = standard).
    public var scale: CGFloat
    public var fontName: String?
    public var edge: MACaptionAppearanceTextEdgeStyle

    public static let standard = CaptionStyle(foreground: .white, background: .black.opacity(0.7), window: .clear,
                                              scale: 1, fontName: nil, edge: .none)

    public static func current() -> CaptionStyle {
        let domain = MACaptionAppearanceDomain.user
        func color(_ copy: CGColor?, _ opacity: CGFloat) -> Color? {
            copy.map { Color(cgColor: $0).opacity(opacity) }
        }
        let foreground = color(MACaptionAppearanceCopyForegroundColor(domain, nil).takeRetainedValue(),
                               MACaptionAppearanceGetForegroundOpacity(domain, nil))
        let background = color(MACaptionAppearanceCopyBackgroundColor(domain, nil).takeRetainedValue(),
                               MACaptionAppearanceGetBackgroundOpacity(domain, nil))
        let window = color(MACaptionAppearanceCopyWindowColor(domain, nil).takeRetainedValue(),
                           MACaptionAppearanceGetWindowOpacity(domain, nil))
        let descriptor = MACaptionAppearanceCopyFontDescriptorForStyle(domain, nil, .default).takeRetainedValue()
        let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
        return CaptionStyle(foreground: foreground ?? standard.foreground, background: background ?? standard.background,
                            window: window ?? standard.window,
                            scale: max(0.5, min(MACaptionAppearanceGetRelativeCharacterSize(domain, nil), 2.5)),
                            // The system's default caption face reads as the platform font.
                            fontName: name.flatMap { $0.hasPrefix(".") ? nil : $0 },
                            edge: MACaptionAppearanceGetTextEdgeStyle(domain, nil))
    }

    func font(size: CGFloat) -> Font {
        let size = size * scale
        return fontName.map { .custom($0, fixedSize: size) } ?? .system(size: size, weight: .semibold)
    }
}

/// A subtitle line over the video, centred, in the person's caption style. The player gives the
/// base size (it knows how much room there is); the style scales it.
public struct SubtitleView: View {
    private let text: String?
    private let baseSize: CGFloat
    @State private var style = CaptionStyle.current()

    public init(_ text: String?, baseSize: CGFloat) {
        self.text = text
        self.baseSize = baseSize
    }

    public var body: some View {
        Group {
            if let text {
                Text(verbatim: text)
                    .font(style.font(size: baseSize))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(style.foreground)
                    .modifier(TextEdge(style: style.edge))
                    .padding(.horizontal, Tokens.Spacing.s)
                    .padding(.vertical, Tokens.Spacing.xs)
                    .background(style.background, in: .rect(cornerRadius: 6))
                    .padding(Tokens.Spacing.xxs)
                    .background(style.window, in: .rect(cornerRadius: 8))
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier("subtitle")
                    .allowsHitTesting(false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name(kMACaptionAppearanceSettingsChangedNotification as String))) { _ in
            style = .current()
        }
    }
}

/// Drop shadow, raised, depressed or uniform (outline) edges, as chosen in Settings.
private struct TextEdge: ViewModifier {
    let style: MACaptionAppearanceTextEdgeStyle

    func body(content: Content) -> some View {
        switch style {
        case .dropShadow: content.shadow(color: .black.opacity(0.9), radius: 1, x: 1, y: 1)
        case .raised: content.shadow(color: .black, radius: 0, x: -1, y: -1)
        case .depressed: content.shadow(color: .black, radius: 0, x: 1, y: 1)
        case .uniform:
            content.shadow(color: .black, radius: 0.6).shadow(color: .black, radius: 0.6)
        default: content
        }
    }
}
