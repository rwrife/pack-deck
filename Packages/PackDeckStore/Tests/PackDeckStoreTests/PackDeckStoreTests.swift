import Testing
@testable import PackDeckStore

@Suite("PackDeckStore skeleton tests")
struct PackDeckStoreTests {
    @Test("domain namespace is reachable")
    func domainNamespace() {
        #expect(PackDeckStore.domain == "PackDeckStore")
    }

    @Test("milestone marker is M1-skeleton")
    func milestoneMarker() {
        #expect(PackDeckStore.milestone == "M1-skeleton")
    }
}
