import SwiftUI
import UIKit
import WidgetKit

/// Continue Watching on the Home Screen, in StandBy and on the Lock Screen. Reads the snapshot
/// the app keeps in the App Group (falling back to the latest uploads); tapping opens the video.
struct ContinueWatchingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ContinueWatching", provider: Provider()) { entry in
            ContinueWatchingView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text("Continue Watching"))
        .description(Text("Pick up where you left off."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let items: [HomeSnapshot.Item]
    /// False when there's nothing in progress and the latest uploads stand in.
    let isContinue: Bool
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, items: [HomeSnapshot.Item(id: "x", title: String(localized: "A video you're watching"),
                                                    imageURL: nil, progress: 0.4)], isContinue: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(load())
    }

    /// The app reloads widgets when its library changes; hourly is only a backstop.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .after(.now.addingTimeInterval(3600))))
    }

    private func load() -> Entry {
        let snapshot = HomeSnapshot.read()
        let inProgress = snapshot?.continueWatching ?? []
        return Entry(date: .now, items: inProgress.isEmpty ? snapshot?.latest ?? [] : inProgress, isContinue: !inProgress.isEmpty)
    }
}

struct ContinueWatchingView: View {
    let entry: Entry
    /// Set for previews and render tests; widgets read the system's family.
    var familyOverride: WidgetFamily?
    @Environment(\.widgetFamily) private var systemFamily
    private var family: WidgetFamily { familyOverride ?? systemFamily }

    var body: some View {
        if entry.items.isEmpty {
            Text("Videos you watch show up here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else {
            switch family {
            case .systemSmall: small(entry.items[0])
            case .systemMedium: list(count: 2)
            case .systemLarge: list(count: 4)
            case .accessoryRectangular: rectangular(entry.items[0])
            default: small(entry.items[0])
            }
        }
    }

    private var heading: Text {
        entry.isContinue ? Text("Continue Watching") : Text("Latest")
    }

    private func small(_ item: HomeSnapshot.Item) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Thumbnail(item: item)
            Text(verbatim: item.title).font(.caption.weight(.semibold)).lineLimit(2)
        }
        .widgetURL(HomeSnapshot.playURL(for: item.id))
    }

    private func list(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(entry.items.prefix(count), id: \.id) { item in
                Link(destination: HomeSnapshot.playURL(for: item.id) ?? URL(fileURLWithPath: "/")) {
                    HStack(spacing: 10) {
                        Thumbnail(item: item).frame(width: count > 2 ? 104 : 120)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: item.title).font(.footnote.weight(.semibold)).lineLimit(2)
                                .foregroundStyle(.primary)
                            if let channel = item.channelName {
                                Text(verbatim: channel).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .tint(.primary)     // Plain labels, not link-coloured text.
            }
            Spacer(minLength: 0)
        }
    }

    private func rectangular(_ item: HomeSnapshot.Item) -> some View {
        VStack(alignment: .leading) {
            heading.font(.headline).widgetAccentable()
            Text(verbatim: item.title).font(.caption).lineLimit(2)
        }
        .widgetURL(HomeSnapshot.playURL(for: item.id))
    }
}

/// The thumbnail the app saved into the App Group, with a progress bar.
private struct Thumbnail: View {
    let item: HomeSnapshot.Item

    var body: some View {
        Color.secondary.opacity(0.2)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let name = item.imageFile, let url = HomeSnapshot.directory?.appending(path: name),
                   let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .overlay(alignment: .bottom) {
                if let progress = item.progress {
                    Rectangle().fill(.red).frame(height: 3).scaleEffect(x: progress, y: 1, anchor: .leading)
                }
            }
            .clipShape(.rect(cornerRadius: 8))
    }
}
