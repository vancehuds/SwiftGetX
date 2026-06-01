import AppKit
import SwiftData
import Testing
@testable import SwiftGetX

@Suite("AppKit support")
@MainActor
struct AppKitSupportTests {
    @Test("task list data source filters tasks and syncs table selection")
    func taskListDataSourceFiltersAndSyncsTableSelection() throws {
        let container = try SwiftGetXPersistence.makeTemporaryModelContainer()
        let settings = AppSettings()
        let coordinator = DownloadCoordinator(runsEngines: false)
        coordinator.attach(modelContext: container.mainContext, settings: settings)

        let queued = DownloadTask(
            name: "Queued",
            source: "https://example.com/queued.zip",
            kind: .http,
            status: .queued,
            savePath: "/tmp/queued.zip"
        )
        let running = DownloadTask(
            name: "Running",
            source: "https://example.com/running.zip",
            kind: .http,
            status: .running,
            savePath: "/tmp/running.zip"
        )
        container.mainContext.insert(queued)
        container.mainContext.insert(running)
        try container.mainContext.save()

        coordinator.selectFilter(.running)
        let dataSource = TaskListDataSource(coordinator: coordinator)
        dataSource.reload()

        #expect(dataSource.tasks.map(\.name) == ["Running"])

        let tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        tableView.dataSource = dataSource
        tableView.delegate = dataSource
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        dataSource.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification, object: tableView))

        #expect(coordinator.selectedTaskID == running.id)
        #expect(coordinator.selectedTaskIDs == [running.id])
    }
}
