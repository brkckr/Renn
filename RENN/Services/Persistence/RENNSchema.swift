import Foundation
import SwiftData

/// Local-only SwiftData schema, version 1 (05 V07). CloudKit is disabled.
///
/// Domain values that already validate themselves on decode (recipe, sources) are stored
/// as JSON blobs, so the domain types stay the single authority for their invariants and
/// schema changes to them are versioned by `Recipe.version`/optional fields.
enum RENNSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [ProjectEntity.self, LookPreferencesEntity.self]
    }

    @Model
    final class ProjectEntity {
        @Attribute(.unique) var id: UUID
        var schemaVersion: Int
        var createdAt: Date
        var updatedAt: Date
        var displayName: String
        var sourceMode: String
        var readiness: String
        var recipeRevision: Int
        var recipeJSON: Data
        var sourcesJSON: Data
        var lastOutputID: UUID?

        init(
            id: UUID, schemaVersion: Int, createdAt: Date, updatedAt: Date, displayName: String,
            sourceMode: String, readiness: String, recipeRevision: Int, recipeJSON: Data,
            sourcesJSON: Data, lastOutputID: UUID?
        ) {
            self.id = id
            self.schemaVersion = schemaVersion
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.displayName = displayName
            self.sourceMode = sourceMode
            self.readiness = readiness
            self.recipeRevision = recipeRevision
            self.recipeJSON = recipeJSON
            self.sourcesJSON = sourcesJSON
            self.lastOutputID = lastOutputID
        }
    }

    /// Single row holding favorites and the ordered last-four-distinct Look IDs.
    @Model
    final class LookPreferencesEntity {
        @Attribute(.unique) var key: String
        var favoriteIDs: [String]
        var recentIDs: [String]

        init(key: String, favoriteIDs: [String], recentIDs: [String]) {
            self.key = key
            self.favoriteIDs = favoriteIDs
            self.recentIDs = recentIDs
        }
    }
}

typealias ProjectEntity = RENNSchemaV1.ProjectEntity
typealias LookPreferencesEntity = RENNSchemaV1.LookPreferencesEntity

/// Explicit migration plan. No stages yet: V1 is the first shipped schema. Future versions
/// add a `VersionedSchema` and a stage here; the store is never wiped on failure (05 V08).
enum RENNMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [RENNSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum PersistenceController {
    /// `Application Support/RENN/Metadata/RENN.store`
    static func defaultStoreURL() throws -> URL {
        let directory = URL.applicationSupportDirectory
            .appendingPathComponent("RENN", isDirectory: true)
            .appendingPathComponent("Metadata", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("RENN.store")
    }

    static func makeContainer(storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: RENNSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: RENNMigrationPlan.self, configurations: configuration)
    }

    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: RENNSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: RENNMigrationPlan.self, configurations: configuration)
    }
}
