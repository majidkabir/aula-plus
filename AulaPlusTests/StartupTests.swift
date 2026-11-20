import XCTest
@testable import AulaPlus

/// Singletons that the app touches at start must not re-enter their own initializers (that crashed build 38).
@MainActor
final class StartupTests: XCTestCase {
    func testSharedObjectsInitialiseAndWriteWidgetSnapshot() {
        _ = ParentTaskFinder.shared
        _ = ThemeStore.shared
        _ = DataStore.shared
        WidgetWriter.update()
        XCTAssertNotNil(ParentTaskFinder.shared.open)
    }
}
