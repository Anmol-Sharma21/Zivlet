import Testing
import ZivletIPC

@Suite("Each side requires the other's team, or its signing identifier when ad-hoc (D-M6-7)")
struct PeerPolicyTests {
    @Test func aBuildWithATeamRequiresTheSameTeamAndTheIdentifier() {
        let own = SigningIdentity(teamID: "ABCDE12345", identifier: WorkerPeerPolicy.appIdentifier)
        #expect(
            WorkerPeerPolicy.requirement(own: own, peer: WorkerPeerPolicy.workerIdentifier)
                == .sameTeam(identifier: "app.zivlet.Zivlet.Worker"))
    }

    @Test func anAdHocBuildRequiresTheSigningIdentifier() {
        let own = SigningIdentity(teamID: nil, identifier: WorkerPeerPolicy.workerIdentifier)
        #expect(
            WorkerPeerPolicy.requirement(own: own, peer: WorkerPeerPolicy.appIdentifier)
                == .signingIdentifier("app.zivlet.Zivlet"))
    }

    @Test(arguments: ["abcde12345", "ABC", "ABCDE12345X", "\"; true"])
    func aMalformedTeamFallsBackToTheIdentifier(_ team: String) {
        let own = SigningIdentity(teamID: team, identifier: nil)
        #expect(WorkerPeerPolicy.requirement(own: own, peer: "x") == .signingIdentifier("x"))
    }

    @Test func theRunningCodeHasAnIdentity() {
        let own = SigningIdentity.current()
        #expect(own.teamID.map { !$0.isEmpty } ?? true)
    }

    @Test func theIdentifiersAreTheBundleIdentifiers() {
        #expect(WorkerPeerPolicy.appIdentifier == "app.zivlet.Zivlet")
        #expect(WorkerPeerPolicy.workerIdentifier == "app.zivlet.Zivlet.Worker")
        #expect(WorkerPeerPolicy.workerServiceName == WorkerPeerPolicy.workerIdentifier)
    }
}
