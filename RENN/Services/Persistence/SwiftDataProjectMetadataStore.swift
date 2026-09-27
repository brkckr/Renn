import Foundation
import SwiftData
import RENNDomain

/// SwiftData metadata authority for `ProjectLibrary`. Model objects never leave this actor;
/// only `ProjectRecord` snapshots cross the boundary (04 A05).
@ModelActor
actor SwiftDataProjectMetadataStore: ProjectMetadataStoring {
    enum StoreError: Error {
        case duplicate
        case missing
        case corruptRecord
    }

    /// Throws if any row cannot be decoded: `ProjectLibrary` then treats metadata as
    /// unavailable and deletes nothing, instead of mistaking the row's files for orphans.
    func allRecords() throws -> [ProjectRecord] {
        try modelContext.fetch(FetchDescriptor<ProjectEntity>()).map(Self.record)
    }

    func record(_ id: ProjectID) throws -> ProjectRecord? {
        try entity(id).map(Self.record)
    }

    func insert(_ record: ProjectRecord) throws {
        guard try entity(record.id) == nil else { throw StoreError.duplicate }
        let encoded = try Self.encode(record)
        modelContext.insert(ProjectEntity(
            id: record.id.rawValue, schemaVersion: record.schemaVersion, createdAt: record.createdAt,
            updatedAt: record.updatedAt, displayName: record.name.value, sourceMode: record.sourceMode.rawValue,
            readiness: record.readiness.rawValue, recipeRevision: record.recipeRevision,
            recipeJSON: encoded.recipe, sourcesJSON: encoded.sources, outputsJSON: encoded.outputs,
            lastOutputID: record.lastOutputID?.rawValue))
        try modelContext.save()
    }

    func update(_ record: ProjectRecord) throws {
        guard let entity = try entity(record.id) else { throw StoreError.missing }
        let encoded = try Self.encode(record)
        entity.schemaVersion = record.schemaVersion
        entity.updatedAt = record.updatedAt
        entity.displayName = record.name.value
        entity.sourceMode = record.sourceMode.rawValue
        entity.readiness = record.readiness.rawValue
        entity.recipeRevision = record.recipeRevision
        entity.recipeJSON = encoded.recipe
        entity.sourcesJSON = encoded.sources
        entity.outputsJSON = encoded.outputs
        entity.lastOutputID = record.lastOutputID?.rawValue
        try modelContext.save()
    }

    func remove(_ id: ProjectID) throws {
        guard let entity = try entity(id) else { return }
        modelContext.delete(entity)
        try modelContext.save()
    }

    private func entity(_ id: ProjectID) throws -> ProjectEntity? {
        let target = id.rawValue
        var descriptor = FetchDescriptor<ProjectEntity>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func encode(_ record: ProjectRecord) throws -> (recipe: Data, sources: Data, outputs: Data) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try encoder.encode(record.recipe), try encoder.encode(record.sources), try encoder.encode(record.outputs))
    }

    private static func record(_ entity: ProjectEntity) throws -> ProjectRecord {
        let decoder = JSONDecoder()
        guard entity.schemaVersion <= ProjectRecord.currentSchemaVersion,
              let name = try? ProjectName(entity.displayName),
              let sourceMode = ProjectSummary.SourceMode(rawValue: entity.sourceMode),
              let readiness = ProjectSummary.Readiness(rawValue: entity.readiness),
              let recipe = try? decoder.decode(Recipe.self, from: entity.recipeJSON),
              let sources = try? decoder.decode([SourceReference].self, from: entity.sourcesJSON),
              let outputs = try? decoder.decode([OutputRecord].self, from: entity.outputsJSON)
        else { throw StoreError.corruptRecord }
        return ProjectRecord(
            id: ProjectID(entity.id), schemaVersion: entity.schemaVersion, createdAt: entity.createdAt,
            updatedAt: entity.updatedAt, name: name, sourceMode: sourceMode, readiness: readiness,
            sources: sources, recipeRevision: entity.recipeRevision, recipe: recipe,
            lastOutputID: entity.lastOutputID.map { OutputID($0) },
            outputs: outputs)
    }
}

/// Used when the metadata store cannot be opened: every read fails, so `ProjectLibrary`
/// reports `metadataUnavailable` and never deletes files (05 V08).
struct UnavailableProjectMetadataStore: ProjectMetadataStoring {
    struct Unavailable: Error {}
    func allRecords() async throws -> [ProjectRecord] { throw Unavailable() }
    func record(_ id: ProjectID) async throws -> ProjectRecord? { throw Unavailable() }
    func insert(_ record: ProjectRecord) async throws { throw Unavailable() }
    func update(_ record: ProjectRecord) async throws { throw Unavailable() }
    func remove(_ id: ProjectID) async throws { throw Unavailable() }
}
