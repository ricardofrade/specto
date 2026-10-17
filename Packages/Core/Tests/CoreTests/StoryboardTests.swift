import Foundation
import Testing
@testable import Core

struct StoryboardTests {
    private let board = Storyboard(pages: [URL(string: "https://proxy.example/M0.jpg")!, URL(string: "https://proxy.example/M1.jpg")!],
                                   frameWidth: 160, frameHeight: 90, columns: 5, rows: 5, frameCount: 30,
                                   intervalMilliseconds: 10_000)

    @Test func findsTheFrameOnItsPage() throws {
        let first = try #require(board.frame(at: .seconds(0)))
        #expect(first == Storyboard.Frame(page: board.pages[0], x: 0, y: 0))
        let seventh = try #require(board.frame(at: .seconds(65)))      // Index 6: row 1, column 1.
        #expect(seventh == Storyboard.Frame(page: board.pages[0], x: 160, y: 90))
        let secondPage = try #require(board.frame(at: .seconds(255)))  // Index 25: page 1, first frame.
        #expect(secondPage == Storyboard.Frame(page: board.pages[1], x: 0, y: 0))
        #expect(board.frame(at: .seconds(10_000))?.page == board.pages[1])   // Clamped to the last frame.
    }

    @Test func picksTheSmallestBoardThatIsBigEnough() {
        let small = Storyboard(pages: board.pages, frameWidth: 80, frameHeight: 45, columns: 10, rows: 10,
                               frameCount: 30, intervalMilliseconds: 10_000)
        #expect([small, board].best(forFrameWidth: 120) == board)
        #expect([small, board].best(forFrameWidth: 400) == board)
        #expect([small, board].best(forFrameWidth: 60) == small)
    }
}
