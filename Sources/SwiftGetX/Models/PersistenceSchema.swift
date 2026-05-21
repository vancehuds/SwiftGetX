import SwiftData

enum SwiftGetXSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [DownloadTask.self, AppSettingsRecord.self] }
}

enum SwiftGetXMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SwiftGetXSchemaV2.self] }
    static var stages: [MigrationStage] { [] }
}

enum SwiftGetXPersistence {
    static let currentSchemaVersion = "2.0.0"

    static var currentSchema: Schema {
        Schema(versionedSchema: SwiftGetXSchemaV2.self)
    }

    static func makeModelContainer(
        configurations: ModelConfiguration...
    ) throws -> ModelContainer {
        try ModelContainer(
            for: currentSchema,
            migrationPlan: SwiftGetXMigrationPlan.self,
            configurations: configurations
        )
    }
}
