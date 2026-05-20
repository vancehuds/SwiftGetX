import Foundation
import SwiftData
import Testing
@testable import SwiftGetX

@Suite("DownloadCoordinator")
@MainActor
struct DownloadCoordinatorTests {
    @Test("toolbar speed limit persists through AppSettings")
    func toolbarSpeedLimitPersistsThroughAppSettings() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: DownloadTask.self,
            AppSettingsRecord.self,
            configurations: configuration
        )
        let settings = AppSettings()
        let coordinator = DownloadCoordinator()
        coordinator.attach(modelContext: container.mainContext, settings: settings)

        coordinator.setSpeedLimit(
            downloadBytesPerSecond: 5_000_000,
            uploadBytesPerSecond: 512_000,
            persistsToSettings: true
        )

        let descriptor = FetchDescriptor<AppSettingsRecord>(
            predicate: #Predicate { $0.id == "default" }
        )
        let record = try #require(container.mainContext.fetch(descriptor).first)

        #expect(settings.globalDownloadLimitBytes == 5_000_000)
        #expect(settings.globalUploadLimitBytes == 512_000)
        #expect(record.globalDownloadLimitBytes == 5_000_000)
        #expect(record.globalUploadLimitBytes == 512_000)
        #expect(coordinator.downloadLimitBytes == 5_000_000)
        #expect(coordinator.uploadLimitBytes == 512_000)
    }
}
