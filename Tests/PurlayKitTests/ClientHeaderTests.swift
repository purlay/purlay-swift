import Testing

@testable import PurlayKit

@Suite("the client header")
struct ClientHeaderTests {
    private let version = SemanticVersion(1, 2, 3)

    @Test("names macOS unless told otherwise")
    func defaultsToMacOS() {
        #expect(ClientHeader.value(appVersion: version, contractVersion: 1) == "macos/1.2.3 contract/1")
    }

    @Test("names the platform it runs on")
    func namesPlatform() {
        #expect(ClientHeader.value(appVersion: version, platform: .iOS, contractVersion: 1) == "ios/1.2.3 contract/1")
    }
}
