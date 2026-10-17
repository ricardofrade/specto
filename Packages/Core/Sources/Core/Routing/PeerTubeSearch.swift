/// Where content comes from: YouTube (through Piped, Invidious or YT Zero) or PeerTube.
public enum ContentNetwork: String, Sendable, Hashable, CaseIterable {
    case youTube
    case peerTube
}

public extension VideoID { var network: ContentNetwork { isPeerTube ? .peerTube : .youTube } }
public extension ChannelID { var network: ContentNetwork { isPeerTube ? .peerTube : .youTube } }

/// Search across every PeerTube server the person added, as one list: PeerTube is many
/// servers, and each indexes different videos (ADR 0018).
///
/// Every server gets the same offset cursor (PeerTube pages by `start`). Results interleave,
/// one from each server in turn, so no server buries the others; a video, channel or playlist
/// that several servers know (federation) appears once, from the earliest server in the
/// person's order. A server that fails is left out; only all failing is an error.
public enum PeerTubeSearch {
    public static func search(_ sources: [any VideoSource], query: String, filter: SearchFilter,
                              cursor: String?) async throws -> Page<SearchResult> {
        guard !sources.isEmpty else { throw SourceError.unsupported(.search) }
        let pages = await withTaskGroup(of: (Int, Result<Page<SearchResult>, Error>).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    do { return (index, .success(try await source.search(query, filter: filter, cursor: cursor))) }
                    catch { return (index, .failure(error)) }
                }
            }
            var pages = [Result<Page<SearchResult>, Error>?](repeating: nil, count: sources.count)
            for await (index, result) in group { pages[index] = result }
            return pages.compactMap { $0 }
        }
        let found = pages.compactMap { try? $0.get() }
        if found.isEmpty, case .failure(let error)? = pages.first { throw error }
        return Page(items: merged(found.map(\.items)), nextCursor: found.lazy.compactMap(\.nextCursor).first)
    }

    /// One from each list in turn, skipping what's already in.
    static func merged(_ lists: [[SearchResult]]) -> [SearchResult] {
        var seen = Set<String>()
        var out: [SearchResult] = []
        let longest = lists.map(\.count).max() ?? 0
        for position in 0..<longest {
            for list in lists where position < list.count {
                let item = list[position]
                if seen.insert(key(item)).inserted { out.append(item) }
            }
        }
        return out
    }

    /// The same video on two servers has one UUID; a channel, one `name@host` handle.
    private static func key(_ result: SearchResult) -> String {
        switch result {
        case .video(let video): "v:" + (video.id.peerTube?.uuid ?? video.id.rawValue)
        case .channel(let channel): "c:" + (channel.id.peerTube?.handle ?? channel.id.rawValue)
        case .playlist(let playlist): "p:" + (playlist.id.peerTube?.uuid ?? playlist.id.rawValue)
        }
    }
}
