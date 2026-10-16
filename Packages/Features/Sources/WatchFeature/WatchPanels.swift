import SwiftUI
import Core
import Library
import Playback
import DesignSystem

/// A chapter with its start pre-formatted.
public struct ChapterRow: Identifiable, Hashable, Sendable {
    public let id: Int
    public let title: String
    public let start: Duration
    public let startText: String

    static func rows(_ chapters: [Chapter]) -> [ChapterRow] {
        chapters.enumerated().map { index, chapter in
            ChapterRow(id: index, title: chapter.title, start: chapter.start, startText: RowFormatter.clock(chapter.start))
        }
    }
}

/// A comment with counts pre-formatted.
struct CommentRow: Identifiable, Hashable, Sendable {
    let id: String
    let author: String
    let text: String
    let meta: String
    let isPinned: Bool

    init(_ comment: Comment) {
        id = comment.id
        author = comment.authorName
        text = comment.text
        isPinned = comment.isPinned
        var parts: [String] = []
        if let likes = comment.likeCount, likes > 0 {
            parts.append(Self.inflected(AttributedString(localized: "^[\(likes) like](inflect: true)")))
        }
        if let published = comment.publishedText, !published.isEmpty { parts.append(published) }
        if comment.replyCount > 0 {
            parts.append(Self.inflected(AttributedString(localized: "^[\(comment.replyCount) reply](inflect: true)")))
        }
        meta = parts.joined(separator: " · ")
    }

    /// Foundation's automatic grammar agreement ("1 like", "2 likes"), per language.
    private static func inflected(_ text: AttributedString) -> String {
        String(text.inflected().characters)
    }
}

/// Comments for one video, loaded on first view and paged on scroll.
@Observable
public final class CommentsModel {
    private(set) var rows: [CommentRow] = []
    private(set) var isLoading = false
    private(set) var failed = false
    @ObservationIgnored private let videoID: VideoID
    @ObservationIgnored private let load: @Sendable (VideoID, String?) async throws -> Page<Comment>
    @ObservationIgnored private var cursor: String?
    @ObservationIgnored private var started = false

    public init(videoID: VideoID, load: @escaping @Sendable (VideoID, String?) async throws -> Page<Comment>) {
        self.videoID = videoID
        self.load = load
    }

    func start() async {
        guard !started else { return }
        started = true
        await next()
    }

    func loadMoreIfNeeded(after id: String) async {
        guard id == rows.last?.id, cursor != nil else { return }
        await next()
    }

    private func next() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await load(videoID, cursor)
            let known = Set(rows.map(\.id))
            rows += page.items.filter { !known.contains($0.id) }.map(CommentRow.init)
            cursor = page.nextCursor
        } catch {
            failed = rows.isEmpty
        }
    }
}

/// Details, comments and chapters as tabs, for the band and side-panel layouts.
struct WatchTabs<Details: View>: View {
    enum Tab: Hashable { case details, comments, chapters }

    let content: WatchContent
    let comments: CommentsModel?
    let session: PlaybackSession
    @ViewBuilder let details: Details
    @State private var tab = Tab.details

    var body: some View {
        VStack(spacing: 0) {
            Picker(selection: $tab) {
                Text("Details").tag(Tab.details)
                if comments != nil { Text("Comments").tag(Tab.comments) }
                if !content.chapters.isEmpty { Text("Chapters").tag(Tab.chapters) }
            } label: {
                Text("Section")
            }
            .pickerStyle(.segmented)
            .padding(Tokens.Spacing.m)
            switch tab {
            case .details: ScrollView { details }
            case .comments: if let comments { CommentsList(model: comments) }
            case .chapters: ChaptersList(chapters: content.chapters, session: session)
            }
        }
    }
}

struct CommentsList: View {
    let model: CommentsModel

    var body: some View {
        List {
            ForEach(model.rows) { row in
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    HStack(spacing: Tokens.Spacing.xs) {
                        if row.isPinned {
                            Image(systemName: "pin.fill").font(Tokens.Typography.caption)
                                .accessibilityLabel(Text("Pinned"))
                        }
                        Text(row.author).font(Tokens.Typography.caption.weight(.semibold))
                    }
                    Text(row.text).font(Tokens.Typography.body)
                    if !row.meta.isEmpty {
                        Text(row.meta).font(Tokens.Typography.caption).foregroundStyle(Tokens.Colors.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .task { await model.loadMoreIfNeeded(after: row.id) }
            }
            if model.isLoading { ProgressView().frame(maxWidth: .infinity) }
            if model.failed {
                Text("Comments couldn't be loaded.").foregroundStyle(Tokens.Colors.textSecondary)
            }
        }
        .listStyle(.plain)
        .task { await model.start() }
    }
}

struct ChaptersList: View {
    let chapters: [ChapterRow]
    let session: PlaybackSession

    var body: some View {
        List(chapters) { chapter in
            Button {
                Task { await session.seek(to: chapter.start, precise: false) }
            } label: {
                HStack {
                    Text(chapter.startText).font(Tokens.Typography.timecode).foregroundStyle(Tokens.Colors.textSecondary)
                    Text(chapter.title).font(Tokens.Typography.body)
                }
            }
            .accessibilityHint(Text("Jumps to this chapter"))
        }
        .listStyle(.plain)
    }
}
