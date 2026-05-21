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

@Suite("SystemBehaviorController")
@MainActor
struct SystemBehaviorControllerTests {
    @Test("manages login items only from app bundles")
    func managesLoginItemsOnlyFromAppBundles() {
        #expect(SystemBehaviorController.canManageLoginItem(
            bundleURL: URL(fileURLWithPath: "/Applications/SwiftGetX.app")
        ))
        #expect(!SystemBehaviorController.canManageLoginItem(
            bundleURL: URL(fileURLWithPath: "/tmp/SwiftGetXTests.xctest")
        ))
    }
}
