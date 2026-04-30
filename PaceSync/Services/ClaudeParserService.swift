// ClaudeParserService.swift
// Sends training plan text to the Claude API and parses the JSON response.
// Splits multi-week plans into per-week chunks, parses them concurrently, and
// caches each chunk so re-uploads cost zero tokens for unchanged weeks.

import Foundation

class ClaudeParserService {

    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!

    // MARK: - Public Entry Point

    /// Parses a training plan, splitting it into per-week chunks when possible.
    /// - Parameters:
    ///   - text: The full plan text (from PDF, paste, etc.)
    ///   - title: Used as the plan title in the returned TrainingPlan.
    ///   - progressCallback: Called on the calling actor after each week is parsed.
    ///     Receives a 0…1 fraction and a human-readable phase string.
    func parseTrainingPlan(
        from text: String,
        title: String,
        progressCallback: ((Double, String) -> Void)? = nil
    ) async throws -> TrainingPlan {

        // If the text has no week or day-of-week markers, it's a single pasted workout.
        // Wrap it so Claude gets unambiguous structure rather than guessing at day boundaries.
        let processedText = looksLikeSingleWorkout(text)
            ? "Week 1, Wednesday:\n\(text)"
            : text

        let chunks = splitIntoWeeks(processedText)
        let total  = chunks.count

        print("📦 [ClaudeParser] Split into \(total) chunk(s)")

        // Single-chunk fallback — no week headers found, parse as one call
        if total <= 1 {
            progressCallback?(0.1, "Parsing plan…")
            let json = try await callClaudeWithCache(processedText)
            progressCallback?(1.0, "Done!")
            return assemblePlan(from: try decodeDays(from: json), title: title)
        }

        // Multi-chunk: parse up to 3 weeks concurrently for speed
        var allDaysByIndex: [(index: Int, days: [WorkoutDay])] = []

        allDaysByIndex = try await withThrowingTaskGroup(of: (Int, [WorkoutDay]).self) { group in
            for (index, chunk) in chunks.enumerated() {
                group.addTask { [self] in
                    let json = try await self.callClaudeWithCache(chunk)
                    return (index, try self.decodeDays(from: json))
                }
            }

            var results: [(Int, [WorkoutDay])] = []
            for try await (index, days) in group {
                results.append((index, days))
                progressCallback?(
                    Double(results.count) / Double(total),
                    "Parsed \(results.count) of \(total) weeks…"
                )
            }
            return results
        }

        // Reassemble in original week order
        let allDays = allDaysByIndex
            .sorted { $0.index < $1.index }
            .flatMap { $0.days }

        return assemblePlan(from: allDays, title: title)
    }

    // MARK: - Single Workout Detection

    /// Returns true when the text has no week numbers or day-of-week labels —
    /// i.e. the user pasted a single workout session rather than a full plan.
    private func looksLikeSingleWorkout(_ text: String) -> Bool {
        let hasWeekMarker = text.range(
            of: #"(?i)\bweek\s*\d"#, options: .regularExpression) != nil
        let hasDayMarker = text.range(
            of: #"(?i)\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun)\b"#,
            options: .regularExpression) != nil
        let result = !hasWeekMarker && !hasDayMarker
        if result { print("📦 [ClaudeParser] Single workout detected — wrapping as Week 1 Wednesday") }
        return result
    }

    /// Merges pages that begin mid-sentence into the previous page.
    /// A page "starts mid-sentence" when its first non-whitespace content is NOT a
    /// "Week N" label — meaning it's the continuation of a table cell cut off at a
    /// page boundary. Merging gives Claude the complete cell content in one chunk.
    private func mergeOrphanedPageStarts(_ pages: [String]) -> [String] {
        var merged: [String] = []
        for page in pages {
            let startsNewWeek = page.range(
                of: #"(?i)^week\s+\d"#, options: .regularExpression) != nil
            if !startsNewWeek && !merged.isEmpty {
                // Continuation — glue onto the previous chunk
                merged[merged.count - 1] += "\n\n" + page
                print("📦 [ClaudeParser] Merged orphaned page continuation into previous chunk")
            } else {
                merged.append(page)
            }
        }
        return merged
    }

    // MARK: - Week Chunking

    /// Splits plan text into chunks for parallel parsing.
    /// Prefers page-based splitting (from PDFs) over week-header splitting,
    /// because table-format PDFs produce scrambled text that confuses week-header detection.
    private func splitIntoWeeks(_ text: String) -> [String] {
        // Page-based splitting: PDFImporter inserts "=== PAGE BREAK ===" markers.
        // Each page is a self-contained unit — much more reliable for grid/table PDFs.
        let pageBreak = "\n\n=== PAGE BREAK ===\n\n"
        if text.contains(pageBreak) {
            let rawPages = text.components(separatedBy: pageBreak)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if rawPages.count > 1 {
                // Merge any page that starts mid-sentence (i.e. no "Week N" near the top).
                // This handles table cells that are split across a page boundary —
                // e.g. Week 9 Wednesday's cell spans pages 3→4 in this plan.
                let chunks = mergeOrphanedPageStarts(rawPages)
                print("📦 [ClaudeParser] Page-based split: \(rawPages.count) page(s) → \(chunks.count) chunk(s)")
                return chunks
            }
        }

        // Week-header splitting: for plain-text plans with "Week N" headers.
        guard let regex = try? NSRegularExpression(
            pattern: #"(?m)^week\s+\d+"#,
            options: .caseInsensitive
        ) else { return [text] }

        let nsText  = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        guard matches.count > 1 else { return [text] }

        return matches.enumerated().map { i, match in
            let start = match.range.location
            let end   = i + 1 < matches.count ? matches[i + 1].range.location : nsText.length
            return nsText
                .substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Cache-aware Claude Call

    private func callClaudeWithCache(_ chunk: String) async throws -> String {
        if let cached = PlanParseCache.shared.cachedJSON(for: chunk) {
            print("✅ [ClaudeParser] Cache hit")
            return cached
        }
        print("🌐 [ClaudeParser] Cache miss — calling Claude")
        let json = try await callClaude(with: buildPrompt(for: chunk))
        PlanParseCache.shared.store(json: json, for: chunk)
        return json
    }

    // MARK: - Prompt

    private func buildPrompt(for text: String) -> String {
        """
        You are a running coach assistant. Parse the following training plan text and return ONLY a JSON array — no markdown, no explanation, just raw JSON.

        Each element represents one workout day with this exact structure:
        {
          "week": 1,
          "dayOfWeek": "monday",
          "title": "Easy Run",
          "notes": "Optional coach note",
          "isRaceDay": false,
          "segments": [
            {
              "type": "warmup|cooldown|easy|interval|tempo|hills|rest",
              "durationSeconds": 600,
              "distanceMiles": 1.5,
              "distanceMeters": 800,
              "reps": 4,
              "effort": "easy|marathon|threshold|tenK|fiveK|threeK"
            }
          ]
        }

        COLUMN-FORMAT PLANS: Training plans often use a table where columns are days (Mon–Sun) and rows are weeks. PDFKit extracts these column by column, so the text you receive is already in reading order: first all of Week N's Monday text, then Tuesday, etc. Each chunk may contain 2–5 complete weeks. Parse ALL weeks and ALL days you see — do not stop after the first week.

        If the text starts mid-sentence (e.g. "seconds easy recovery..."), it is the continuation of a Wednesday or Thursday workout from the previous page that was cut off. Use context clues (nearby week/day structure) to assign it to the correct week and day.

        Ignore any unit conversion tables (Miles/Kilometers reference tables) — these are not workout data.

        SINGLE WORKOUT INPUT: If the input contains no week numbers and no day-of-week labels, treat the ENTIRE input as one single workout day (week: 1, dayOfWeek: "wednesday"). Comma-separated steps and line breaks within a workout description are SEGMENTS of that one day — NOT separate days. For example:
        "3 mi easy warmup, 5 miles tempo, 6 x 45 sec fast, 2 mi cooldown" → ONE day with four segments (warmup, tempo, intervals, cooldown).

        GENERAL RULES:
        - dayOfWeek must be lowercase: monday, tuesday, wednesday, thursday, friday, saturday, sunday
        - Set isRaceDay: true on the single day that is explicitly the race (e.g. "Race Day", "Marathon", "5K Race"). Omit or set false for all other days. Races can fall on any day of the week — friday, saturday, or sunday are all common.
        - Include every training day in the provided text
        - For ranges (e.g. "8-10 miles", "4-5 x"), use the lower bound
        - Use distanceMiles for road/trail distances (miles or km), distanceMeters for track distances specified in meters
        - Use durationSeconds only when the workout explicitly states a time (e.g. "30 min easy")
        - Never set durationSeconds to 0 — omit it entirely if not applicable
        - effort is optional; omit if not specified
        - Rest days: use an empty segments array []
        - For easy runs with distance RANGES (e.g. "6-8 miles easy", "4-5 mi"), omit distanceMiles entirely — leave segments with NO distance and NO duration so the workout goal is "open" (the runner decides how far to go)
        - Return ONLY the JSON array, starting with [ and ending with ]

        TITLE RULES — make titles descriptive:
        - Use specific titles that reflect the workout content, NOT generic names
        - Examples: "Track Intervals", "Tempo Run", "Long Run", "Easy Recovery", "Hill Repeats", "Rest Day", "Race Pace Long Run", "Speed Work", "Progression Run"
        - If the workout has intervals, name it after the primary interval type (e.g. "Track Intervals", "800m Repeats")
        - If it's a long run with pace work, say so (e.g. "Long Run w/ Marathon Pace")
        - If it's a pure easy/recovery run, use "Easy Run" or "Recovery Run"
        - Rest days should be titled "Rest Day"

        GRADUATED DISTANCE SETS in long runs:
        - Patterns like "5/4/3/2/1 miles at M effort" or "3-2-1 mi at tempo" are graduated sets
        - Each distance is a separate interval segment, all sharing the SAME setIndex
        - Example: "5/4/3/2/1 at marathon pace with 1 min easy between":
          {type:interval, distanceMiles:5, effort:marathon, setIndex:1},
          {type:rest, durationSeconds:60, effort:easy, setIndex:1},
          {type:interval, distanceMiles:4, effort:marathon, setIndex:1},
          {type:rest, durationSeconds:60, effort:easy, setIndex:1},
          ... and so on for 3, 2, 1

        EFFORT MAPPINGS:
        - easy/jog/recovery pace/float/float recovery → easy
        - marathon/MP/marathon pace → marathon
        - threshold/tempo/T-pace/LT/1-hour effort/hour effort → threshold
        - 10K effort/10k pace → tenK
        - 5K effort/5k pace → fiveK
        - 3K effort/3k pace/mile pace/fast/hard → threeK

        EFFORT ORDERING — critical:
        - When distances and efforts are listed in parallel order (e.g. "800/400/200 at 10K/5K/3K"), the FIRST distance maps to the FIRST effort, SECOND to SECOND, THIRD to THIRD.
        - "800/400/200 at 10K/5K/3K" → 800m=tenK, 400m=fiveK, 200m=threeK
        - "800/400/200 fast" with hint "(10k/5k/3k effort on each set)" → 800m=tenK, 400m=fiveK, 200m=threeK
        - Never assign the same effort to all distances in a graduated set; always respect the ordering.

        DISTANCE RULES — critical:
        - Track distances without units (e.g. 800, 400, 200, 1600, 1200) are always METERS — use distanceMeters
        - "800m", "400m", "200m" → distanceMeters: 800 / 400 / 200
        - Mile/km distances → distanceMiles (convert km: divide by 1.60934)
        - NEVER convert track distances to time. Do NOT approximate "800m ≈ 4 min" — always use distanceMeters: 800
        - durationSeconds is ONLY for workouts explicitly stated as time-based (e.g. "30 min easy", "5 min tempo")
        - Recovery/rest segments in track workouts ALSO use distanceMeters (e.g. "400 easy" → distanceMeters: 400)
        - When in doubt between distanceMeters and durationSeconds, prefer distanceMeters for any track workout

        INTERVAL SETS — grouping rules:
        1. Simple set "N x distance" with one recovery: use reps:N, NO setIndex needed.
           {"type":"interval","distanceMeters":800,"reps":4}, {"type":"rest","distanceMeters":400}

        2. Complex set "N x d1/d2/d3 with multiple recoveries": ALL segments in the set share
           the SAME setIndex integer. Also put reps:N on every interval segment in the group.
           setIndex values start at 1 and increment for each distinct complex set in the workout.

           "4 x 800/400/200 at 10K/5K/3K with 400 easy/200 easy/400 easy recovery":
           {"type":"interval","distanceMeters":800,"effort":"tenK","reps":4,"setIndex":1},
           {"type":"rest","distanceMeters":400,"effort":"easy","setIndex":1},
           {"type":"interval","distanceMeters":400,"effort":"fiveK","reps":4,"setIndex":1},
           {"type":"rest","distanceMeters":200,"effort":"easy","setIndex":1},
           {"type":"interval","distanceMeters":200,"effort":"threeK","reps":4,"setIndex":1},
           {"type":"rest","distanceMeters":400,"effort":"easy","setIndex":1}

        3. Never expand reps into separate segment pairs.
        4. Open/unstructured recovery (e.g. "jog back", "run down") → rest segment with no distances/durations.
        5. Each distinct complex set uses its own setIndex (e.g. first set = setIndex:1, second = setIndex:2).

        EXAMPLE — "3 mi easy warm-up, 4 x 800/400/200 fast with 400 easy/200 easy/400 easy (10k/5k/3k effort), 4 x 200 fast/200 easy, 2 mi easy cooldown":
        [
          {"week":1,"dayOfWeek":"tuesday","title":"Track Workout","segments":[
            {"type":"warmup","distanceMiles":3.0,"effort":"easy"},
            {"type":"interval","distanceMeters":800,"effort":"tenK","reps":4,"setIndex":1},
            {"type":"rest","distanceMeters":400,"effort":"easy","setIndex":1},
            {"type":"interval","distanceMeters":400,"effort":"fiveK","reps":4,"setIndex":1},
            {"type":"rest","distanceMeters":200,"effort":"easy","setIndex":1},
            {"type":"interval","distanceMeters":200,"effort":"threeK","reps":4,"setIndex":1},
            {"type":"rest","distanceMeters":400,"effort":"easy","setIndex":1},
            {"type":"interval","distanceMeters":200,"effort":"threeK","reps":4},
            {"type":"rest","distanceMeters":200,"effort":"easy"},
            {"type":"cooldown","distanceMiles":2.0,"effort":"easy"}
          ]}
        ]

        Training plan:
        \(text)
        """
    }

    // MARK: - API Call

    private func callClaude(with prompt: String) async throws -> String {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Secrets.anthropicAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 16000,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var lastError: Error = NSError(domain: "ClaudeParser", code: -1,
                                       userInfo: [NSLocalizedDescriptionKey: "Unknown error"])
        for attempt in 1...5 {
            let (data, urlResponse) = try await URLSession.shared.data(for: request)

            if let http = urlResponse as? HTTPURLResponse, http.statusCode != 200 {
                let isOverloaded = http.statusCode == 529 || http.statusCode == 503
                if let errBody = try? JSONDecoder().decode(ClaudeErrorResponse.self, from: data) {
                    lastError = NSError(domain: "ClaudeParser", code: http.statusCode,
                                        userInfo: [NSLocalizedDescriptionKey: errBody.error.message])
                } else {
                    lastError = NSError(domain: "ClaudeParser", code: http.statusCode,
                                        userInfo: [NSLocalizedDescriptionKey: "API error (HTTP \(http.statusCode))"])
                }
                if isOverloaded && attempt < 5 {
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    try await Task.sleep(nanoseconds: delay)
                    continue
                }
                throw lastError
            }

            let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)
            guard let text = response.content.first(where: { $0.type == "text" })?.text else {
                throw NSError(domain: "ClaudeParser", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Empty response from Claude"])
            }
            return text
        }
        throw lastError
    }

    // MARK: - Decode

    private nonisolated func decodeDays(from jsonString: String) throws -> [WorkoutDay] {
        print("🏃 [ClaudeParser] Raw JSON:\n\(jsonString)")
        var cleaned = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences (``` or ```json ... ```)
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            cleaned = lines.dropFirst().dropLast().joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // If the response has surrounding prose or an object wrapper, extract the
        // outermost JSON array by finding the first '[' and last ']'.
        if !cleaned.hasPrefix("[") {
            if let start = cleaned.firstIndex(of: "["),
               let end = cleaned.lastIndex(of: "]") {
                cleaned = String(cleaned[start...end])
            }
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw NSError(domain: "ClaudeParser", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not encode response"])
        }

        let dtos: [WorkoutDayDTO]
        do {
            dtos = try JSONDecoder().decode([WorkoutDayDTO].self, from: data)
        } catch {
            let preview = String(cleaned.prefix(300))
            print("🏃 [ClaudeParser] Decode error: \(error)\nResponse preview: \(preview)")
            throw NSError(domain: "ClaudeParser", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "Could not parse the training plan. Please try again or paste the plan as text."
            ])
        }

        return dtos.map { dto in
            let segments = dto.segments.map { seg in
                WorkoutSegment(
                    id: UUID(),
                    type: SegmentType(rawValue: seg.type) ?? .easy,
                    durationSeconds: (seg.durationSeconds ?? 0) > 0 ? seg.durationSeconds : nil,
                    distanceMiles: seg.distanceMeters == nil ? seg.distanceMiles : nil,
                    distanceMeters: seg.distanceMeters,
                    reps: seg.reps,
                    restDurationSeconds: seg.restDurationSeconds,
                    effort: seg.effort.flatMap { EffortLevel(rawValue: $0) },
                    setIndex: seg.setIndex
                )
            }
            for seg in segments {
                print("🏃 [ClaudeParser] Segment: \(seg.type.rawValue) distMeters=\(seg.distanceMeters ?? -1) distMiles=\(seg.distanceMiles ?? -1) durSec=\(seg.durationSeconds ?? -1) reps=\(seg.reps ?? -1) setIndex=\(seg.setIndex ?? -1)")
            }
            return WorkoutDay(
                id: UUID(),
                week: dto.week,
                dayOfWeek: DayOfWeek(rawValue: dto.dayOfWeek.lowercased()) ?? .monday,
                title: dto.title,
                notes: dto.notes,
                segments: segments,
                isRaceDay: dto.isRaceDay ?? false
            )
        }
    }

    private func assemblePlan(from days: [WorkoutDay], title: String) -> TrainingPlan {
        // Deduplicate: when two chunks both produce a day for the same (week, dayOfWeek),
        // keep the most detailed one (most segments; break ties with notes presence).
        var best: [String: WorkoutDay] = [:]
        for day in days {
            let key = "\(day.week)-\(day.dayOfWeek.rawValue)"
            if let existing = best[key] {
                let newScore = day.segments.count * 10 + (day.notes != nil ? 1 : 0)
                let oldScore = existing.segments.count * 10 + (existing.notes != nil ? 1 : 0)
                if newScore > oldScore { best[key] = day }
            } else {
                best[key] = day
            }
        }
        let uniqueDays = Array(best.values)

        let grouped = Dictionary(grouping: uniqueDays) { $0.week }
        let sortedWeeks = grouped.keys.sorted().map { week in
            let order = DayOfWeek.allCases
            return (grouped[week] ?? []).sorted {
                (order.firstIndex(of: $0.dayOfWeek) ?? 0) < (order.firstIndex(of: $1.dayOfWeek) ?? 0)
            }
        }
        print("🗓️ [ClaudeParser] Assembled plan '\(title)': \(sortedWeeks.count) week(s), \(uniqueDays.count) day(s) (deduped from \(days.count))")
        for (i, week) in sortedWeeks.enumerated() {
            let summary = week.map { "\($0.dayOfWeek.rawValue): \($0.title)" }.joined(separator: ", ")
            print("  Week \(i + 1): \(summary)")
        }
        return TrainingPlan(id: UUID(), title: title, weeks: sortedWeeks)
    }
}

// MARK: - DTOs

private struct ClaudeResponse: Decodable {
    let content: [ContentBlock]
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
}

private struct ClaudeErrorResponse: Decodable {
    let error: ErrorDetail
    struct ErrorDetail: Decodable {
        let type: String
        let message: String
    }
}

private struct WorkoutDayDTO: Decodable {
    let week: Int
    let dayOfWeek: String
    let title: String
    let notes: String?
    let isRaceDay: Bool?
    let segments: [WorkoutSegmentDTO]
}

private struct WorkoutSegmentDTO: Decodable {
    let type: String
    let durationSeconds: Int?
    let distanceMiles: Double?
    let distanceMeters: Double?
    let reps: Int?
    let restDurationSeconds: Int?
    let effort: String?
    let setIndex: Int?           // non-nil when segment belongs to a multi-step group

    /// Resolved distance in miles — prefers distanceMeters (converted) over distanceMiles.
    var resolvedDistanceMiles: Double? {
        if let m = distanceMeters { return m / 1609.344 }
        return distanceMiles
    }
}
