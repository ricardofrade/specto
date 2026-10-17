import Foundation
import Core

/// The audio tracks a viewer can pick for a video: the original first, then dubs by name.
/// One option per language, whichever codecs carry it (`FormatSelector` picks the stream).
public struct AudioTrackOption: Hashable, Sendable, Identifiable {
    /// Primary language code ("es"); nil is the original track.
    public let language: String?
    /// "Español", or "English (original)": pre-formatted for menus.
    public let label: String
    public var id: String { language ?? "original" }
}

public enum AudioTracks {
    /// Empty when there's nothing to choose (one language, or no language tags).
    public static func options(in streams: [AudioStream], locale: Locale = .current) -> [AudioTrackOption] {
        let original = streams.first(where: \.isOriginal)?.language.map(primary)
        var dubs = Set<String>()
        for stream in streams where !stream.isOriginal {
            if let language = stream.language.map(primary), language != original { dubs.insert(language) }
        }
        guard !dubs.isEmpty else { return [] }
        let originalName = original.flatMap { locale.localizedString(forLanguageCode: $0) }
        let originalLabel = originalName.map { String(localized: "\($0) (original)") } ?? String(localized: "Original")
        let others = dubs.map { AudioTrackOption(language: $0, label: name($0, locale: locale)) }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        return [AudioTrackOption(language: nil, label: originalLabel)] + others
    }

    /// The option for a remembered language, if this video has it; otherwise the original.
    public static func selected(_ language: String?, in options: [AudioTrackOption]) -> String? {
        guard let language else { return nil }
        let code = primary(language)
        return options.contains { $0.language == code } ? code : nil
    }

    static func primary(_ code: String) -> String {
        (code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? code).lowercased()
    }

    private static func name(_ code: String, locale: Locale) -> String {
        (locale.localizedString(forLanguageCode: code) ?? code).capitalized(with: locale)
    }
}
