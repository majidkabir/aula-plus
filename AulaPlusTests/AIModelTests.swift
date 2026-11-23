import XCTest
@testable import AulaPlus

/// Private Cloud Compute crashes the app without Apple's entitlement, so it must stay off until we have it.
final class AIModelTests: XCTestCase {
    func testCloudModelIsOffWithoutEntitlement() {
        XCTAssertFalse(AIModel.hasEntitlement)
        XCTAssertFalse(AIModel.cloud)
        XCTAssertFalse(AIModel.cloudSupported)
    }
}
