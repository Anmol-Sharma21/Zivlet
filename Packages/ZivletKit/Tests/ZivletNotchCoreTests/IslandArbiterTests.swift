import Testing
import ZivletNotchCore

extension IslandRequest {
    /// Test helpers only: no tray or picker code exists in M5a (D-M5a-7).
    static func tray(_ resting: IslandSurface, display: UInt32 = 1) -> IslandRequest {
        IslandRequest(client: .tray, display: display, resting: resting, hoverSurface: .expanded)
    }

    static func picker(_ resting: IslandSurface, display: UInt32 = 1) -> IslandRequest {
        IslandRequest(client: .picker, display: display, resting: resting, hoverSurface: .expanded)
    }
}

@Suite("Island arbiter (P2-115: one island, several users)")
struct IslandArbiterTests {
    @Test func theHighestPriorityRequestWins() {
        let a = IslandArbiter().updating(.hud, .hud(.collapsed)).updating(.tray, .tray(.expanded))
        #expect(a.winner(on: 1)?.client == .tray)
        #expect(a.updating(.picker, .picker(.expanded)).winner(on: 1)?.client == .picker)
    }

    @Test func aWithdrawnHigherRequestHandsBackToTheLowerOne() {
        let a = IslandArbiter().updating(.hud, .hud(.toast)).updating(.tray, .tray(.expanded)).updating(.tray, nil)
        #expect(a.winner(on: 1) == .hud(.toast))
    }

    @Test func requestsAreKeptPerDisplay() {
        let a = IslandArbiter().updating(.hud, .hud(.collapsed, display: 2)).updating(.tray, .tray(.expanded))
        #expect(a.winner(on: 2)?.client == .hud && a.winner(on: 1)?.client == .tray)
    }

    @Test func noRequestsMeansNoWinner() { #expect(IslandArbiter().winner(on: 1) == nil) }

    @Test func aWithdrawalOnOneDisplayKeepsTheClientsOtherRequests() {
        let a = IslandArbiter().updating(.hud, .hud(.collapsed, display: 1)).updating(.hud, .hud(.toast, display: 2))
        let b = a.updating(.hud, on: 1, nil)
        #expect(b.winner(on: 1) == nil && b.winner(on: 2) == .hud(.toast, display: 2))
        #expect(a.updating(.hud, nil).displays.isEmpty)
    }

    @Test func aClientsNewRequestReplacesItsOldOneOnThatDisplay() {
        let a = IslandArbiter().updating(.hud, .hud(.collapsed)).updating(.hud, .hud(.toast))
        #expect(a.winner(on: 1) == .hud(.toast) && a.displays == [1])
    }

    @Test func aRequestFiledUnderAnotherClientIsRefused() {
        let a = IslandArbiter().updating(.tray, .hud(.collapsed))
        #expect(a.winner(on: 1) == nil)
    }
}
