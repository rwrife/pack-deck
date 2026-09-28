import Testing
@testable import PackDeckKit

@Suite("Skeleton placeholder")
struct PlaceholderTests {
    @Test("domain namespace is reachable")
    func domainNamespace() {
        #expect(PackDeckKit.domain == "PackDeckKit")
    }

    @Test("milestone marker is set for M1")
    func milestoneMarker() {
        #expect(PackDeckKit.milestone == "M1-skeleton")
    }
}
