import Foundation
import Testing
@testable import SwiftGetX

@Suite("NotificationManager")
struct NotificationManagerTests {
    @Test("allows notifications only from app bundles")
    func allowsNotificationsOnlyFromAppBundles() {
        #expect(NotificationManager.canUseUserNotifications(
            bundleURL: URL(fileURLWithPath: "/Applications/SwiftGetX.app")
        ))
        #expect(!NotificationManager.canUseUserNotifications(
            bundleURL: URL(fileURLWithPath: "/Users/me/Library/Developer/Xcode/DerivedData/SwiftGetX/Build/Products/Debug")
        ))
        #expect(!NotificationManager.canUseUserNotifications(
            bundleURL: URL(fileURLWithPath: "/tmp/SwiftGetXTests.xctest")
        ))
    }
}
