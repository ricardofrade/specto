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
                        .opacity(row.isHiddenFromHome ? 0.5 : 1)
                    VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                        Text(row.name).font(.body).lineLimit(1)
                        if row.isHiddenFromHome {
                            Label { Text("Hidden from Home") } icon: { Image(systemName: "rectangle.slash") }
                                .font(Tokens.Typography.caption)
                                .foregroundStyle(Tokens.Colors.textSecondary)
                        } else if row.mutesNotifications {
                            Label { Text("Notifications off") } icon: { Image(systemName: "bell.slash") }
                                .font(Tokens.Typography.caption)
                                .foregroundStyle(Tokens.Colors.textSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("channels.row")
            .swipeActions {
                Button(role: .destructive) { onUnsubscribe(row.channel) } label: { Text("Unsubscribe") }
            }
            .swipeActions(edge: .leading) {
                Button { model.toggleHidden(row) } label: {
                    if row.isHiddenFromHome {
                        Label { Text("Show on Home") } icon: { Image(systemName: "rectangle") }
                    } else {
                        Label { Text("Hide from Home") } icon: { Image(systemName: "rectangle.slash") }
                    }
                }
                .tint(.indigo)
                Button { model.toggleNotifications(row) } label: { notificationsLabel(row) }
                    .tint(.orange)
            }
            .contextMenu {
                Button { model.toggleNotifications(row) } label: { notificationsLabel(row) }
                Button { model.toggleHidden(row) } label: {
                    if row.isHiddenFromHome {
                        Label { Text("Show on Home") } icon: { Image(systemName: "rectangle") }
                    } else {
                        Label { Text("Hide from Home") } icon: { Image(systemName: "rectangle.slash") }
                    }
                }
                Button(role: .destructive) { onUnsubscribe(row.channel) } label: {
                    Label { Text("Unsubscribe") } icon: { Image(systemName: "person.badge.minus") }
                }
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

    @ViewBuilder
    private func notificationsLabel(_ row: ChannelRow) -> some View {
        if row.mutesNotifications {
            Label { Text("Turn On Notifications") } icon: { Image(systemName: "bell") }
        } else {
            Label { Text("Turn Off Notifications") } icon: { Image(systemName: "bell.slash") }
        }
    }
}
#endif
