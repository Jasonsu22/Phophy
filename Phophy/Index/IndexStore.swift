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
        migrator.registerMigration("v2-digests") { db in
            try db.execute(sql: """
                CREATE TABLE digest (
                    session_key TEXT PRIMARY KEY NOT NULL,
                    json BLOB NOT NULL,
                    created_at REAL NOT NULL
                );
                """)
        }
        migrator.registerMigration("v3-metadata-places") { db in
            try db.execute(sql: """
                ALTER TABLE asset ADD COLUMN index_version INTEGER NOT NULL DEFAULT 1;
                CREATE TABLE photo_meta (
                    local_id TEXT PRIMARY KEY NOT NULL,
                    taken REAL,
                    lat REAL,
                    lon REAL,
                    place_key TEXT,
                    media TEXT NOT NULL DEFAULT 'photo'
                );
                CREATE INDEX photo_meta_taken ON photo_meta(taken);
                CREATE INDEX photo_meta_place ON photo_meta(place_key);
                CREATE TABLE place (
                    key TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL DEFAULT '',
                    city TEXT NOT NULL DEFAULT '',
                    region TEXT NOT NULL DEFAULT '',
                    context TEXT NOT NULL DEFAULT '',
                    looked_up REAL NOT NULL
                );
                """)
        }
        try migrator.migrate(db)
    }

    /// Bumped when indexing gets better, so older entries are redone.
    /// 2: text read from a 2,048 px copy; embedding covers the whole photo.
    static let indexVersion = 2

    // MARK: Metadata and places

    nonisolated struct PhotoMeta: Sendable {
        let localID: String
        let taken: Date?
        let latitude: Double?
        let longitude: Double?
        let media: String
    }

    /// Photos within about a kilometre share a key, so each area's name is
    /// looked up once.
    static func placeKey(latitude: Double, longitude: Double) -> String {
        "\(Int((latitude * 100).rounded(.down))),\(Int((longitude * 100).rounded(.down)))"
    }

    /// Replaces the metadata of every photo in one transaction.
    func replaceMetadata(_ rows: [PhotoMeta]) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM photo_meta")
            let statement = try db.makeStatement(sql: """
                INSERT INTO photo_meta (local_id, taken, lat, lon, place_key, media) VALUES (?, ?, ?, ?, ?, ?)
                """)
            for row in rows {
                var key: String?
                if let lat = row.latitude, let lon = row.longitude { key = Self.placeKey(latitude: lat, longitude: lon) }
                try statement.execute(arguments: [
                    row.localID, row.taken?.timeIntervalSince1970, row.latitude, row.longitude, key, row.media,
                ])
            }
        }
    }

    /// Areas with photos but no name yet, busiest first, with a point in each.
    func unnamedPlaces() throws -> [(key: String, latitude: Double, longitude: Double)] {
        try db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT place_key, AVG(lat) AS lat, AVG(lon) AS lon, COUNT(*) AS n FROM photo_meta
                WHERE place_key IS NOT NULL AND place_key NOT IN (SELECT key FROM place)
                GROUP BY place_key ORDER BY n DESC
                """).map { ($0["place_key"], $0["lat"], $0["lon"]) }
        }
    }

    func savePlace(key: String, name: String, city: String, region: String, context: String) throws {
        try db.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO place (key, name, city, region, context, looked_up) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [key, name, city, region, context, Date().timeIntervalSince1970]
            )
        }
    }

    /// A readable place for each photo that has one, e.g. "Central, Hong Kong".
    func placeLabels(for ids: [String]) throws -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        return try db.read { db in
            var labels: [String: String] = [:]
            let marks = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let rows = try Row.fetchAll(db, sql: """
                SELECT m.local_id, p.name, p.context FROM photo_meta m JOIN place p ON p.key = m.place_key
                WHERE m.local_id IN (\(marks))
                """, arguments: StatementArguments(ids))
            for row in rows {
                let name: String = row["name"], context: String = row["context"]
                labels[row["local_id"]] = Self.placeLabel(name: name, context: context)
            }
            return labels
        }
    }

    private static func placeLabel(name: String, context: String) -> String {
        if name.isEmpty { return context }
        if context.isEmpty || name == context || context.contains(name) { return context.isEmpty ? name : context }
        return "\(name), \(context)"
    }

    nonisolated struct PlaceSummary: Sendable {
        let label: String
        let count: Int
        let first: Date?
        let last: Date?
    }

    /// Named places with how many photos were taken there, most first.
    func places(matching term: String?, limit: Int = 25) throws -> [PlaceSummary] {
        try db.read { db in
            var sql = """
                SELECT p.name, p.context, COUNT(*) AS n, MIN(m.taken) AS first, MAX(m.taken) AS last
                FROM photo_meta m JOIN place p ON p.key = m.place_key
                """
            var arguments: [String] = []
            if let term, !term.isEmpty {
                sql += " WHERE p.name LIKE ? OR p.city LIKE ? OR p.region LIKE ? OR p.context LIKE ?"
                arguments = Array(repeating: "%\(term)%", count: 4)
            }
            sql += " GROUP BY p.name, p.context ORDER BY n DESC LIMIT \(limit)"
            return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments)).map { row in
                let first: Double? = row["first"], last: Double? = row["last"]
                return PlaceSummary(
                    label: Self.placeLabel(name: row["name"], context: row["context"]),
                    count: row["n"],
                    first: first.map { Date(timeIntervalSince1970: $0) },
                    last: last.map { Date(timeIntervalSince1970: $0) }
                )
            }
        }
    }

    nonisolated struct Coverage: Sendable {
        let photos: Int
        let withLocation: Int
        let placesNamed: Int
        let placesPending: Int
    }

    func coverage() throws -> Coverage {
        try db.read { db in
            Coverage(
                photos: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_meta") ?? 0,
                withLocation: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_meta WHERE place_key IS NOT NULL") ?? 0,
                placesNamed: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_meta m JOIN place p ON p.key = m.place_key") ?? 0,
                placesPending: try Int.fetchOne(db, sql: """
                    SELECT COUNT(DISTINCT place_key) FROM photo_meta
                    WHERE place_key IS NOT NULL AND place_key NOT IN (SELECT key FROM place)
                    """) ?? 0
            )
        }
    }

    /// Photos matching the filters, newest first. Covers the whole library,
    /// indexed or not. `place` matches a place name, city, country or area.
    func filteredIDs(from: Date?, to: Date?, place: String?, media: String?) throws -> [String] {
        try db.read { db in
            var clauses: [String] = []
            var arguments: [DatabaseValueConvertible?] = []
            if let from { clauses.append("taken >= ?"); arguments.append(from.timeIntervalSince1970) }
            if let to { clauses.append("taken < ?"); arguments.append(to.timeIntervalSince1970) }
            if let media { clauses.append("media = ?"); arguments.append(media) }
            if let place, !place.isEmpty {
                clauses.append("""
                    place_key IN (SELECT key FROM place WHERE name LIKE ? OR city LIKE ? OR region LIKE ? OR context LIKE ?)
                    """)
                arguments += Array(repeating: "%\(place)%", count: 4)
            }
            let condition = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
            return try String.fetchAll(
                db, sql: "SELECT local_id FROM photo_meta \(condition) ORDER BY taken DESC",
                arguments: StatementArguments(arguments)
            )
        }
    }

    // MARK: Lecture digests

    /// Saved digests, keyed by lecture session. Kept so a digest is only
    /// ever paid for once.
    func saveDigest(_ json: Data, for sessionKey: String) throws {
        try db.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO digest (session_key, json, created_at) VALUES (?, ?, ?)",
                arguments: [sessionKey, json, Date().timeIntervalSince1970]
            )
        }
    }

    func allDigests() throws -> [String: Data] {
        try db.read { db in
            var digests: [String: Data] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT session_key, json FROM digest") {
                digests[row["session_key"]] = row["json"]
            }
            return digests
        }
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
                        (local_id, modified, ocr, labels, embedding, embedding_model, indexed_at, index_version)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    localID, modified?.timeIntervalSince1970, text, labelText,
                    blob, embeddingModel, Date().timeIntervalSince1970, Self.indexVersion,
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
                try db.execute(sql: "DELETE FROM photo_meta WHERE local_id = ?", arguments: [id])
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
                    db, sql: "SELECT local_id FROM asset WHERE embedding_model = ? AND index_version >= ?",
                    arguments: [embeddingModel, Self.indexVersion]
                ))
            }
            return try Set(String.fetchAll(
                db, sql: "SELECT local_id FROM asset WHERE index_version >= ?", arguments: [Self.indexVersion]
            ))
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

    /// The text recognized in every photo that has some.
    func allTexts() throws -> [String: String] {
        try db.read { db in
            var texts: [String: String] = [:]
            let rows = try Row.fetchCursor(db, sql: "SELECT local_id, ocr FROM asset WHERE ocr != ''")
            while let row = try rows.next() {
                texts[row["local_id"]] = row["ocr"]
            }
            return texts
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
