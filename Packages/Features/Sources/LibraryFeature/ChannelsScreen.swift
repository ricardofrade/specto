import SwiftUI
import Core
import DesignSystem

#if os(iOS)
/// Every subscribed channel: search, tap to open, swipe to unsubscribe. On iPad the sidebar
/// lists them too; this is the iPhone's way in (from Library).
public struct ChannelsScreen: View {
    /// Owned here: the navigation destination that builds this screen can run again at any time.
    @State private var model: ChannelsModel
    private let onOpen: (ChannelSummary) -> Void
    private let onUnsubscribe: (ChannelSummary) -> Void

    public init(model: ChannelsModel, onOpen: @escaping (ChannelSummary) -> Void,
                onUnsubscribe: @escaping (ChannelSummary) -> Void) {
        _model = State(initialValue: model)
        self.onOpen = onOpen
        self.onUnsubscribe = onUnsubscribe
    }

    public var body: some View {
        List(model.rows) { row in
            Button { onOpen(row.channel) } label: {
                HStack(spacing: Tokens.Spacing.m) {
                    AvatarView(row.avatar, size: 44)
                    Text(row.name).font(.body).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("channels.row")
            .swipeActions {
                Button(role: .destructive) { onUnsubscribe(row.channel) } label: { Text("Unsubscribe") }
            }
        }
        .listStyle(.plain)
        .overlay {
            if model.total == 0 {
                ContentUnavailableView {
                    Label { Text("No channels") } icon: { Image(systemName: "person.2") }
                } description: {
                    Text("Channels you subscribe to show up here.")
                }
            } else if model.rows.isEmpty {
                ContentUnavailableView.search(text: model.query)
            }
        }
        .searchable(text: Bindable(model).query, prompt: Text("Search channels"))
        .navigationTitle(Text("Channels"))
        .accessibilityIdentifier("channels.list")
        .task { await model.start() }
    }
}
#endif
