import Foundation
import GRDB

/// The keyword side of the index: concept tags, descriptions, and the
/// word-level BM25 table built from them (`doc_fts`).
nonisolated extension IndexStore {
    /// Bumped when the words stored per photo change shape, so every
    /// photo's keyword entry is rebuilt.
    nonisolated static let documentVersion = 1

    /// One photo's searchable text, as a describer or the assistant sees it.
    nonisolated struct Document: Sendable {
        var caption: String
        var keywords: String
        var tags: String
        var ocr: String
        var labels: String
        var describedBy: String?
    }

    // MARK: Concept tags

    func conceptVectors(model: String) throws -> (count: Int, dimension: Int, data: [Float])? {
        try db.read { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT count, dimension, data FROM concept_vector WHERE model = ?", arguments: [model]
            ) else { return nil }
            let data: Data = row["data"]
            let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            return (row["count"], row["dimension"], floats)
        }
    }

    func saveConceptVectors(model: String, count: Int, dimension: Int, data: [Float]) throws {
        let blob = data.withUnsafeBufferPointer { Data(buffer: $0) }
        try db.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO concept_vector (model, count, dimension, data) VALUES (?, ?, ?, ?)",
                arguments: [model, count, dimension, blob]
            )
        }
    }

    /// Photos whose tags are missing or older than `version`.
    func untaggedIDs(version: Int, model: String) throws -> [String] {
        try db.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT local_id FROM asset WHERE tag_version < ? AND embedding_model = ? AND embedding IS NOT NULL",
                arguments: [version, model]
            )
        }
    }

    func saveTags(_ tags: [String: String], version: Int) throws {
        try db.write { db in
            for (id, text) in tags {
                try db.execute(
                    sql: "UPDATE asset SET tags = ?, tag_version = ?, doc_version = 0 WHERE local_id = ?",
                    arguments: [text, version, id]
                )
            }
        }
    }

    // MARK: Descriptions

    func saveDescription(localID: String, caption: String, keywords: String, describedBy: String) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE asset SET caption = ?, keywords = ?, described_by = ?, doc_version = 0 WHERE local_id = ?",
                arguments: [caption, keywords, describedBy, localID]
            )
        }
    }

    func document(for localID: String) throws -> Document? {
        try db.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT caption, keywords, tags, ocr, labels, described_by FROM asset WHERE local_id = ?",
                arguments: [localID]
            ).map(Self.document(from:))
        }
    }

    func documents(for localIDs: [String]) throws -> [String: Document] {
        guard !localIDs.isEmpty else { return [:] }
        return try db.read { db in
            var result: [String: Document] = [:]
            for chunk in stride(from: 0, to: localIDs.count, by: 500).map({ Array(localIDs[$0..<min($0 + 500, localIDs.count)]) }) {
                let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT local_id, caption, keywords, tags, ocr, labels, described_by FROM asset WHERE local_id IN (\(marks))",
                    arguments: StatementArguments(chunk)
                )
                for row in rows { result[row["local_id"]] = Self.document(from: row) }
            }
            return result
        }
    }

    /// IDs that already have a description, and who wrote it.
    func describedIDs() throws -> [String: String] {
        try db.read { db in
            var result: [String: String] = [:]
            let rows = try Row.fetchCursor(db, sql: "SELECT local_id, described_by FROM asset WHERE described_by IS NOT NULL")
            while let row = try rows.next() { result[row["local_id"]] = row["described_by"] }
            return result
        }
    }

    func describedCount() throws -> Int {
        try db.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM asset WHERE described_by IS NOT NULL") ?? 0 }
    }

    /// Forgets every description written by `describer` (or all, if nil),
    /// so they're written again.
    func clearDescriptions(by describer: String? = nil) throws {
        try db.write { db in
            if let describer {
                try db.execute(sql: "UPDATE asset SET caption = '', keywords = '', described_by = NULL, doc_version = 0 WHERE described_by = ?", arguments: [describer])
            } else {
                try db.execute(sql: "UPDATE asset SET caption = '', keywords = '', described_by = NULL, doc_version = 0 WHERE described_by IS NOT NULL")
            }
        }
    }

    private static func document(from row: Row) -> Document {
        Document(
            caption: row["caption"], keywords: row["keywords"], tags: row["tags"],
            ocr: row["ocr"], labels: row["labels"], describedBy: row["described_by"]
        )
    }

    // MARK: Keyword table

    /// Rebuilds the keyword entry of every photo that changed. Returns how many.
    @discardableResult
    func refreshDocuments(limit: Int = 500) throws -> Int {
        let rows = try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT local_id, caption, keywords, tags, ocr, labels FROM asset WHERE doc_version < ? LIMIT ?",
                arguments: [Self.documentVersion, limit]
            )
        }
        guard !rows.isEmpty else { return 0 }
        // Normalizing (dictionary forms, Chinese word splitting) happens
        // outside the write transaction.
        let prepared: [(String, [String])] = rows.map { row in
            let fields: [String] = [row["caption"], row["keywords"], row["tags"], row["ocr"], row["labels"]]
            return (row["local_id"], fields.map(TextNormalizer.indexText))
        }
        try db.write { db in
            for (id, fields) in prepared {
                try db.execute(sql: "DELETE FROM doc_fts WHERE local_id = ?", arguments: [id])
                try db.execute(
                    sql: "INSERT INTO doc_fts (local_id, caption, keywords, tags, ocr, labels) VALUES (?, ?, ?, ?, ?, ?)",
                    arguments: StatementArguments([id] + fields)
                )
                try db.execute(sql: "UPDATE asset SET doc_version = ? WHERE local_id = ?", arguments: [Self.documentVersion, id])
            }
        }
        return rows.count
    }

    func pendingDocumentCount() throws -> Int {
        try db.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM asset WHERE doc_version < ?", arguments: [Self.documentVersion]) ?? 0
        }
    }

    /// Column weights for BM25: a description or keyword hit counts most,
    /// then tags and Vision labels, then text read from the photo.
    nonisolated struct Weights: Sendable {
        var caption = 3.0, keywords = 3.0, tags = 1.5, ocr = 1.0, labels = 1.5
    }

    /// Photos matching any of `terms` (already normalized), best BM25 first.
    /// Each entry of `terms` may hold alternatives ("dog OR puppy").
    func keywordMatches(_ terms: [[String]], weights: Weights = Weights(), limit: Int = 300) throws -> [(id: String, score: Double)] {
        let groups = terms.compactMap { alternatives -> String? in
            let quoted = alternatives.filter { !$0.isEmpty }.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            guard !quoted.isEmpty else { return nil }
            return quoted.count == 1 ? quoted[0] : "(" + quoted.joined(separator: " OR ") + ")"
        }
        guard !groups.isEmpty else { return [] }
        let match = groups.joined(separator: " OR ")
        return try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT local_id, bm25(doc_fts, 0, ?, ?, ?, ?, ?) AS score FROM doc_fts
                    WHERE doc_fts MATCH ? ORDER BY score LIMIT ?
                    """,
                arguments: [weights.caption, weights.keywords, weights.tags, weights.ocr, weights.labels, match, limit]
            )
            // FTS5's bm25() is negative: lower is better.
            return rows.map { ($0["local_id"], -($0["score"] as Double)) }
        }
    }

    /// Every word in the keyword table with how many photos contain it.
    func vocabulary() throws -> [String: Int] {
        try db.read { db in
            var words: [String: Int] = [:]
            let rows = try Row.fetchCursor(db, sql: "SELECT term, doc FROM doc_vocab")
            while let row = try rows.next() { words[row["term"]] = row["doc"] }
            return words
        }
    }
}
