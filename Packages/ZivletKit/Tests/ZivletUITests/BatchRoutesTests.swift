import CoreGraphics
import Testing
import ZivletCore

@testable import ZivletUI

@Suite("Batch routes (D-M5a-2, D-M5a-8)")
struct BatchRoutesTests {
    let notch = BatchRoutes.Route.notch
    let card = BatchRoutes.Route.nearDrop

    @Test func twoQuickDropsWithDifferentPlacementsKeepTheirOwnRoutes() {
        let a = BatchID()
        let b = BatchID()
        var routes = BatchRoutes(defaultRoute: notch)
            .enqueuing(point: CGPoint(x: 10, y: 10), at: .seconds(1), route: notch)
            .enqueuing(point: CGPoint(x: 50, y: 50), at: .seconds(2), route: card)  // setting changed in between
        let first: BatchRoutes.Claim
        (routes, first) = routes.claiming(a)
        let second: BatchRoutes.Claim
        (routes, second) = routes.claiming(b)
        #expect(first == BatchRoutes.Claim(route: notch, point: CGPoint(x: 10, y: 10), isNew: true))
        #expect(second == BatchRoutes.Claim(route: card, point: CGPoint(x: 50, y: 50), isNew: true))
        #expect(routes.route(of: a) == notch && routes.route(of: b) == card)
    }

    @Test func aRetryFromEitherPresenterKeepsTheSourceRoute() {
        let a = BatchID()
        let c = BatchID()
        let p = CGPoint(x: 300, y: 200)
        var routes = BatchRoutes(defaultRoute: notch).enqueuing(point: nil, at: .seconds(1), route: card)
        (routes, _) = routes.claiming(a)
        routes = routes.retrying(a, anchor: p, at: .seconds(5))
        let claim: BatchRoutes.Claim
        (routes, claim) = routes.claiming(c)
        #expect(claim == BatchRoutes.Claim(route: card, point: p, isNew: true))
    }

    @Test func aRetryOfAForgottenBatchTakesTheDefaultRoute() {
        let c = BatchID()
        var routes = BatchRoutes(defaultRoute: card).retrying(BatchID(), anchor: nil, at: .seconds(1))
        let claim: BatchRoutes.Claim
        (routes, claim) = routes.claiming(c)
        #expect(claim.route == card && claim.point == nil)
    }

    @Test func aBatchNobodyPreparedTakesTheDefaultRoute() {
        let (routes, claim) = BatchRoutes(defaultRoute: notch).claiming(BatchID())
        #expect(claim == BatchRoutes.Claim(route: notch, point: nil, isNew: true))
        #expect(routes.pendingCount == 0)
    }

    @Test func aLaterSnapshotNeverConsumesAPendingRoute() {
        let a = BatchID()
        var routes = BatchRoutes(defaultRoute: notch).enqueuing(point: nil, at: .seconds(1), route: card)
        (routes, _) = routes.claiming(a)
        routes = routes.enqueuing(point: CGPoint(x: 1, y: 1), at: .seconds(2), route: notch)
        let again: BatchRoutes.Claim
        (routes, again) = routes.claiming(a)
        #expect(again == BatchRoutes.Claim(route: card, point: nil, isNew: false))
        #expect(routes.route(of: a) == card && routes.pendingCount == 1)
    }

    @Test func aClosedBatchIsForgottenAndTheDefaultCanChange() {
        let a = BatchID()
        var routes = BatchRoutes(defaultRoute: notch)
        (routes, _) = routes.claiming(a)
        routes = routes.forgetting(a).withDefaultRoute(card)
        #expect(routes.route(of: a) == nil && routes.defaultRoute == card)
    }
}
