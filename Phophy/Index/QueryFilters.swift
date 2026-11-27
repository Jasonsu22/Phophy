import Foundation

/// The place and time a search names, taken out of its words.
///
/// "food in Shanghai 2024" is three things: a place (Shanghai), a time
/// (2024) and what to look for (food). Place and time are facts recorded
/// with each photo, so they are applied as filters; only the rest is
/// matched by meaning. Without this, "Shanghai" was matched by look, and
/// any city street came back.
nonisolated struct QueryFilters: Sendable {
    var from: Date?
    var to: Date?
    var place: String?
    /// What is left to search for; may be empty.
    var text: String

    var isEmpty: Bool { from == nil && to == nil && place == nil }

    /// `places`: lowercased place names that photos were actually taken at.
    static func parse(_ query: String, places: Set<String>, now: Date = .now, calendar: Calendar = .current) -> QueryFilters {
        var filters = QueryFilters(text: "")
        var words = query.lowercased()
            .components(separatedBy: CharacterSet(charactersIn: " ,，.。?？!！;；:：\"“”'‘’()（）\n\t"))
            .filter { !$0.isEmpty }

        func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }
        func add(_ component: Calendar.Component, _ value: Int, to date: Date) -> Date {
            calendar.date(byAdding: component, value: value, to: date) ?? date
        }
        func start(of component: Calendar.Component, _ date: Date) -> Date {
            calendar.dateInterval(of: component, for: date)?.start ?? date
        }
        func set(_ from: Date, _ to: Date) { filters.from = from; filters.to = to }
        /// Removes the phrase (as whole words) if present.
        func take(_ phrase: String) -> Bool {
            let parts = phrase.split(separator: " ").map(String.init)
            guard !parts.isEmpty, words.count >= parts.count else { return false }
            for i in 0...(words.count - parts.count) where Array(words[i..<i + parts.count]) == parts {
                words.removeSubrange(i..<i + parts.count)
                return true
            }
            return false
        }
        /// Removes the phrase wherever it appears, for languages without spaces.
        func takeInside(_ phrase: String) -> Bool {
            for i in words.indices where words[i].contains(phrase) {
                words[i] = words[i].replacingOccurrences(of: phrase, with: "")
                if words[i].isEmpty { words.remove(at: i) }
                return true
            }
            return false
        }

        // Relative times.
        let today = startOfDay(now)
        if take("yesterday") || takeInside("昨天") {
            set(add(.day, -1, to: today), today)
        } else if take("today") || takeInside("今天") {
            set(today, add(.day, 1, to: today))
        } else if take("last week") || takeInside("上周") || takeInside("上星期") {
            let thisWeek = start(of: .weekOfYear, now)
            set(add(.weekOfYear, -1, to: thisWeek), thisWeek)
        } else if take("this week") || takeInside("这周") || takeInside("本周") {
            set(start(of: .weekOfYear, now), add(.day, 1, to: today))
        } else if take("last month") || takeInside("上个月") {
            let thisMonth = start(of: .month, now)
            set(add(.month, -1, to: thisMonth), thisMonth)
        } else if take("this month") || takeInside("这个月") || takeInside("本月") {
            set(start(of: .month, now), add(.day, 1, to: today))
        } else if take("last year") || takeInside("去年") {
            let thisYear = start(of: .year, now)
            set(add(.year, -1, to: thisYear), thisYear)
        } else if take("this year") || takeInside("今年") {
            set(start(of: .year, now), add(.day, 1, to: today))
        }

        // A year, a month, a season.
        let thisYear = calendar.component(.year, from: now)
        var year: Int?
        if let i = words.firstIndex(where: { word in
            let digits = word.hasSuffix("年") ? String(word.dropLast()) : word
            guard digits.count == 4, let y = Int(digits) else { return false }
            return (1990...thisYear).contains(y)
        }) {
            year = Int(words[i].prefix(4))
            words.remove(at: i)
        }
        let monthNames = ["january", "february", "march", "april", "may", "june", "july", "august",
                          "september", "october", "november", "december"]
        let shortNames = ["jan", "feb", "mar", "apr", "", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        var month: Int?
        if filters.from == nil {
            if let i = words.firstIndex(where: { monthNames.contains($0) || (shortNames.contains($0) && !$0.isEmpty) }) {
                month = (monthNames.firstIndex(of: words[i]) ?? shortNames.firstIndex(of: words[i])!) + 1
                words.remove(at: i)
            } else if let i = words.firstIndex(where: { $0.hasSuffix("月") && (1...12).contains(Int($0.dropLast()) ?? 0) }) {
                month = Int(words[i].dropLast())
                words.remove(at: i)
            }
        }
        // Months each season starts in (northern hemisphere), and how long it is.
        let seasons: [(names: [String], startMonth: Int)] = [
            (["spring", "春天"], 3), (["summer", "夏天"], 6), (["autumn", "fall", "秋天"], 9), (["winter", "冬天"], 12),
        ]
        var season: Int?
        if filters.from == nil, month == nil {
            for entry in seasons {
                if entry.names.contains(where: { take($0) || ($0.unicodeScalars.first!.value > 0x2E80 && takeInside($0)) }) {
                    season = entry.startMonth
                    break
                }
            }
        }
        func date(_ year: Int, _ month: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? now
        }
        if let month {
            // No year given: the most recent such month.
            var y = year ?? thisYear
            if year == nil, date(y, month) > now { y -= 1 }
            set(date(y, month), add(.month, 1, to: date(y, month)))
        } else if let season {
            var y = year ?? thisYear
            if year == nil, date(y, season) > now { y -= 1 }
            set(date(y, season), add(.month, 3, to: date(y, season)))
        } else if let year, filters.from == nil {
            set(date(year, 1), date(year + 1, 1))
        }

        // A place photos were taken at: the longest run of words that names one.
        search: for length in stride(from: min(4, words.count), through: 1, by: -1) {
            guard words.count >= length else { continue }
            for i in 0...(words.count - length) {
                let phrase = words[i..<i + length].joined(separator: " ")
                if places.contains(phrase) {
                    filters.place = phrase
                    words.removeSubrange(i..<i + length)
                    break search
                }
            }
        }

        // Words that only connect the rest.
        if !filters.isEmpty {
            let filler: Set<String> = ["in", "at", "from", "on", "of", "during", "taken", "photos", "photo", "pictures",
                                       "picture", "pics", "images", "my", "the", "trip", "to", "around", "near",
                                       "的", "照片", "在", "拍的", "图片"]
            words.removeAll { filler.contains($0) }
        }
        filters.text = words.joined(separator: " ")
        return filters
    }
}
