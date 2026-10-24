import Testing
import ZivletActions
import ZivletCore
import ZivletNotchCore
import ZivletRuntime

@testable import ZivletUI

#if DEBUG
    /// The states the owner reviews before merge (OWN-UI-1) that the first preview set left out (19b §5), and the
    /// fast progress input of the idle-CPU rows.
    @Suite("Island preview: every state of 19b §5 (DEBUG)")
    struct IslandPreviewStatesTests {
        private static func board(_ preview: IslandPreview) throws -> NotchHUDBoard {
            let start = try preview.snapshots().reduce(NotchHUDBoard()) { $0.updating($1, display: 1, now: .zero) }
            return preview.action.map { start.updating($0, display: 1, now: .zero) } ?? start
        }

        @Test func severalJobsShowTheCountAndOneRing() throws {
            let tab = try #require(try Self.board(.jobs).tab(on: 1))
            #expect(tab.count == "3 jobs" && !tab.failed && IslandPreview.jobs.opens == false)
            guard case .fraction = tab.ring else {
                Issue.record("expected the combined ring")
                return
            }
        }

        @Test func theFailedTabShowsTheTriangleOnceItsToastIsOver() throws {
            let board = try Self.board(.failedTab).expiring(now: .seconds(5))
            #expect(board.tab(on: 1)?.failed == true && board.request(on: 1)?.resting == .collapsed)
        }

        @Test func theDoneTabShowsTheCheckMark() throws {
            let tab = try #require(try Self.board(.doneTab).tab(on: 1))
            #expect(tab.ring == .done && !tab.failed && tab.count == "2 jobs")
        }

        @Test func theActionCardHasMoreLinesThanItShows() throws {
            let card = try #require(IslandPreview.actionCard.action?.card)
            #expect(card.lines.count > ActionContent.maxLines && IslandPreview.actionCard.opens)
            #expect(NotchActionCard.lines(try #require(IslandPreview.actionCard.action)).last == "and 3 more")
        }

        @Test func theFailureWithDetailsOpensWithItsDetailsShown() throws {
            let failed = try IslandPreview.failureDetails.first()
            #expect(ResultCardModel(failed).details != nil)
            #expect(IslandPreview.failureDetails.opens && IslandPreview.failureDetails.showsDetails)
            #expect(!IslandPreview.failure.showsDetails)
        }

        @Test func theUnknownLengthCardAndTheManyFilesCardOpen() throws {
            #expect(
                try IslandPreview.indeterminateCard.first().isIndeterminate && IslandPreview.indeterminateCard.opens)
            let many = ResultCardModel(try IslandPreview.resultFiles.first())
            #expect(many.outputs.count == 3 && !many.notes.isEmpty && IslandPreview.resultFiles.opens)
        }

        /// 2 % a tick at 10 Hz: the ring moves about 17 of its 84 steps a second, so the 250 ms floor holds steps back
        /// (the slow row, 0.2 % a tick, never reaches it).
        @Test func fastProgressOutrunsTheFloor() throws {
            #expect(IslandPreview.fastProgress.tick == .milliseconds(100))
            let start = try IslandPreview.fastProgress.first()
            let later = try IslandPreview.fastProgress.advanced(start, step: 1)
            let stepsPerSecond = (later.fraction - start.fraction) * Double(NotchHUDBoard.ringSteps) * 10
            #expect(stepsPerSecond > 4)
        }
    }
#endif
