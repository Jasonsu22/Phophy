import Foundation
import GRDB

/// What the index knows about one photo.
nonisolated struct IndexedInfo: Sendable {
    let text: String
    let labels: [String]
}

/// The on-device index: one row per photo with its recognized text, Vision
/// labels and MobileCLIP embedding, plus a full-text table for word search.
/// Lives in Application Support; safe to delete, it is rebuilt from the library.
nonisolated final class IndexStore: Sendable {
    static let shared: IndexStore = {
        do {
            return try IndexStore()
        } catch {
            fatalError("Could not open the photo index: \(error)")
        }
    }()

    private let db: DatabaseQueue

    init() throws {
        let folder = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        db = try DatabaseQueue(path: folder.appendingPathComponent("index.sqlite").path)

        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE asset (
                    local_id TEXT PRIMARY KEY NOT NULL,
                    modified REAL,
                    ocr TEXT NOT NULL DEFAULT '',
                    labels TEXT NOT NULL DEFAULT '',
                    embedding BLOB,
                    embedding_model TEXT,
                    indexed_at REAL NOT NULL
                );
                CREATE VIRTUAL TABLE asset_fts USING fts5(
                    local_id UNINDEXED, ocr, labels, tokenize='trigram'
                );
                """)
        }
        try migrator.migrate(db)
    }

    // MARK: Writing

    func save(
        localID: String, modified: Date?, text: String, labels: [String],
        embedding: [Float]?, embeddingModel: String?
    ) throws {
        let labelText = labels.joined(separator: ", ")
        let blob = embedding.map { vector in
            vector.withUnsafeBufferPointer { Data(buffer: $0) }
        }
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO asset
                        (local_id, modified, ocr, labels, embedding, embedding_model, indexed_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    localID, modified?.timeIntervalSince1970, text, labelText,
                    blob, embeddingModel, Date().timeIntervalSince1970,
                ]
            )
            try db.execute(sql: "DELETE FROM asset_fts WHERE local_id = ?", arguments: [localID])
            try db.execute(
                sql: "INSERT INTO asset_fts (local_id, ocr, labels) VALUES (?, ?, ?)",
                arguments: [localID, text, labelText]
            )
        }
    }

    func remove(localIDs: [String]) throws {
        guard !localIDs.isEmpty else { return }
        try db.write { db in
            for id in localIDs {
                try db.execute(sql: "DELETE FROM asset WHERE local_id = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM asset_fts WHERE local_id = ?", arguments: [id])
            }
        }
    }

    // MARK: Reading

    /// IDs that are fully indexed. When an embedding model is in use, a photo
    /// only counts if it was embedded with that same model.
    func indexedIDs(embeddingModel: String?) throws -> Set<String> {
        try db.read { db in
            if let embeddingModel {
                return try Set(String.fetchAll(
                    db, sql: "SELECT local_id FROM asset WHERE embedding_model = ?",
                    arguments: [embeddingModel]
                ))
            }
            return try Set(String.fetchAll(db, sql: "SELECT local_id FROM asset"))
        }
    }

    func allIDs() throws -> Set<String> {
        try db.read { db in try Set(String.fetchAll(db, sql: "SELECT local_id FROM asset")) }
    }

    func info(for localID: String) throws -> IndexedInfo? {
        try db.read { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT ocr, labels FROM asset WHERE local_id = ?", arguments: [localID]
            ) else { return nil }
            let labels: String = row["labels"]
            return IndexedInfo(
                text: row["ocr"],
                labels: labels.isEmpty ? [] : labels.components(separatedBy: ", ")
            )
        }
    }

    /// Photos whose recognized text or labels contain every word of the query.
    func textMatches(_ query: String, limit: Int = 200) throws -> [String] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }

        return try db.read { db in
            // The trigram index cannot match words shorter than 3 characters.
            if terms.allSatisfy({ $0.count >= 3 }) {
                let match = terms
                    .map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
                    .joined(separator: " AND ")
                return try String.fetchAll(
                    db,
                    sql: "SELECT local_id FROM asset_fts WHERE asset_fts MATCH ? ORDER BY rank LIMIT ?",
                    arguments: [match, limit]
                )
            }
            let clause = terms
                .map { _ in "(ocr LIKE ? ESCAPE '\\' OR labels LIKE ? ESCAPE '\\')" }
                .joined(separator: " AND ")
            var arguments: [String] = []
            for term in terms {
                let escaped = term
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                arguments += ["%\(escaped)%", "%\(escaped)%"]
            }
            return try String.fetchAll(
                db,
                sql: "SELECT local_id FROM asset WHERE \(clause) ORDER BY indexed_at DESC LIMIT \(limit)",
                arguments: StatementArguments(arguments)
            )
        }
    }

    /// How many characters of text were recognized in each photo.
    func textLengths() throws -> [String: Int] {
        try db.read { db in
            var lengths: [String: Int] = [:]
            let rows = try Row.fetchCursor(db, sql: "SELECT local_id, length(ocr) AS n FROM asset")
            while let row = try rows.next() {
                lengths[row["local_id"]] = row["n"]
            }
            return lengths
        }
    }

    /// Every stored embedding for one model, as IDs plus one flat row-major matrix.
    func embeddings(model: String) throws -> (ids: [String], matrix: [Float], dimension: Int) {
        try db.read { db in
            var ids: [String] = []
            var matrix: [Float] = []
            var dimension = 0
            let rows = try Row.fetchCursor(
                db,
                sql: "SELECT local_id, embedding FROM asset WHERE embedding_model = ? AND embedding IS NOT NULL",
                arguments: [model]
            )
            while let row = try rows.next() {
                let data: Data = row["embedding"]
                let count = data.count / MemoryLayout<Float>.size
                if dimension == 0 { dimension = count }
                guard count == dimension, count > 0 else { continue }
                ids.append(row["local_id"])
                data.withUnsafeBytes { matrix.append(contentsOf: $0.bindMemory(to: Float.self)) }
            }
            return (ids, matrix, dimension)
        }
    }
}
