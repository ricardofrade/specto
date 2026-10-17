import AVFoundation
import SwiftUI
import Core
import Library
import Playback
import PlaybackUI
import DesignSystem

/// Background audio, Now Playing, audio mode, SponsorBlock and DeArrow: every platform.
extension AppEnvironment {
    func startSystemIntegration() {
        NowPlayingController.configureAudioSession()
        nowPlaying = NowPlayingController(session: session) { url in
            await ImagePipeline.shared.image(url, pixelSize: CGSize(width: 600, height: 600))
        }
        #if os(iOS)
        observeAudioRoute()
        followEngineForPictureInPicture()
        #endif
    }

    // MARK: Background

    /// Background without PiP: keep audio, stop decoding video. Back to the foreground: resume.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background where !isPictureInPictureActive:
            session.setVideoEnabled(false)
        case .active:
            session.setVideoEnabled(true)
            #if os(iOS)
            systemPictureInPicture.stop()
            #endif
            Task { await syncNow() }
        default:
            break
        }
    }

    private var isPictureInPictureActive: Bool {
        #if os(iOS)
        pictureInPicture.isActive || systemPictureInPicture.isActive || systemPictureInPicture.isStarting
        #else
        false
        #endif
    }

    // MARK: Audio mode

    func switchMode(to mode: PlaybackMode) async {
        guard let page = currentPage, let request = try? plan(page, mode: mode, startAt: session.position) else { return }
        await session.switchMode(to: mode, using: request)
    }

    // MARK: SponsorBlock and DeArrow

    func loadSkipSegments(for id: VideoID) {
        guard AppSettings.shared.skipsSponsors else { return }
        let community = self.community
        Task {
            let categories: Set<SkipSegment.Category> = [.sponsor, .selfpromo, .interaction]
            if let segments = try? await community.skipSegments(for: id, categories: categories) {
                session.setSkipSegments(segments, for: id)
            }
        }
    }

    func refreshBranding() {
        guard AppSettings.shared.brandedTitles || AppSettings.shared.brandedThumbnails else { return }
        let store = BrandingStore(database), community = self.community
        Task.detached(priority: .utility) {
            guard let ids = try? store.videosNeedingLookup(), !ids.isEmpty,
                  let branding = try? await community.branding(for: ids) else { return }
            try? store.save(branding, lookedUp: ids)
        }
    }

    /// What to tell the viewer when a video can't play.
    static func message(for error: Error) -> String {
        switch error {
        case SourceError.unavailable(let reason):
            reason ?? String(localized: "This video isn't available.")
        case SourceError.blockedUpstream:
            String(localized: "Your instances are being blocked by YouTube right now. Try again later.")
        case SourceError.unsupported:
            String(localized: "None of your instances can play videos.")
        case let error as PlaybackError:
            switch error {
            case .unsupportedFormat(let detail): detail
            default: String(localized: "Playback failed.")
            }
        default:
            String(localized: "Couldn't load this video.")
        }
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
