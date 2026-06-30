// ClaudeParserService.swift
// Two-phase parsing pipeline:
//   Phase 1 — structural extraction: identifies each week/day and copies its raw workout text
//   Phase 2 — segment parsing: given one day's raw text, returns its structured segments
//
// Separating the concerns means Claude has a single focused job in each call,
// which dramatically improves accuracy for complex workouts.
// Both phases are cached independently — re-uploads only re-parse days whose text changed.

import Foundation

class ClaudeParserService {

    // Requests go to the PaceSync proxy, which attaches the real Anthropic key
    // server-side. The app never contains the Anthropic key.
    private let apiURL = URL(string: Secrets.proxyURL)!

    /// Max Claude calls in flight at once. Bounds bursts so individual calls stay fast
    /// and well under the serverless proxy's ~30s timeout (and avoids self-inflicted rate limits).
    private let maxConcurrentCalls = 4

    // MARK: - Public Entry Point

    func parseTrainingPlan(
        from text: String,
        title: String,
        progressCallback: ((Double, String) -> Void)? = nil
    ) async throws -> TrainingPlan {

        let processedText = looksLikeSingleWorkout(text)
            ? "Week 1, Wednesday:\n\(text)"
            : text

        let chunks = splitIntoWeeks(processedText)
        print("📦 [ClaudeParser] \(chunks.count) chunk(s)")

        progressCallback?(0.0, "Extracting schedule…")

        // ── Phase 1: extract day structures, ~one week per call, bounded concurrency ──
        var rawStructures: [DayStructureDTO] = []
        for batch in chunks.chunked(into: maxConcurrentCalls) {
            let batchResults = try await withThrowingTaskGroup(
                of: [DayStructureDTO].self
            ) { group in
                for chunk in batch {
                    group.addTask { [self] in try await self.extractDayStructures(from: chunk) }
                }
                var all: [[DayStructureDTO]] = []
                for try await b in group { all.append(b) }
                return all.flatMap { $0 }
            }
            rawStructures.append(contentsOf: batchResults)
        }

        let structures = deduplicateStructures(rawStructures)
        print("📋 [ClaudeParser] Phase 1: \(structures.count) day(s) extracted")
        progressCallback?(0.25, "Parsing workouts…")

        // ── Phase 2: parse segments for every non-rest day concurrently ──────────
        let restDays: [WorkoutDay] = structures
            .filter { isRestDay($0.rawText) }
            .map { makeWorkoutDay(from: $0, segments: []) }

        let workoutStructures = structures.filter { !isRestDay($0.rawText) }
        let total = workoutStructures.count

        var parsedWorkoutDays: [WorkoutDay] = []
        var done = 0
        for batch in workoutStructures.chunked(into: maxConcurrentCalls) {
            let batchDays = try await withThrowingTaskGroup(
                of: WorkoutDay.self
            ) { group in
                for dto in batch {
                    group.addTask { [self] in
                        let segs = try await self.parseSegments(from: dto.rawText)
                        return self.makeWorkoutDay(from: dto, segments: segs)
                    }
                }
                var days: [WorkoutDay] = []
                for try await day in group { days.append(day) }
                return days
            }
            parsedWorkoutDays.append(contentsOf: batchDays)
            done += batchDays.count
            progressCallback?(
                0.25 + 0.75 * Double(done) / Double(max(total, 1)),
                "Parsed \(done) of \(total) workouts…"
            )
        }

        progressCallback?(1.0, "Done!")
        return assemblePlan(from: restDays + parsedWorkoutDays, title: title)
    }

    // MARK: - Phase 1: Structure Extraction

    private func extractDayStructures(from chunk: String) async throws -> [DayStructureDTO] {
        let json = try await callClaudeWithCache(chunk, prefix: "p1", maxTokens: 4000, prompt: buildPhase1Prompt)
        return try decodeDayStructures(from: json)
    }

    private func buildPhase1Prompt(for text: String) -> String {
        """
        You are a running coach assistant. Extract the training schedule structure from the text \
        below. The text may come from a table-format PDF (columns = days Mon–Sun, rows = weeks).

        For EACH day you identify, output one JSON object:
        {
          "week": 1,
          "dayOfWeek": "monday",
          "title": "Easy Run w/ Strides",
          "notes": "optional coach commentary",
          "isRaceDay": false,
          "rawText": "complete verbatim workout description for this day"
        }

        EXTRACTION RULES:
        - Output exactly 7 entries per complete week (monday through sunday)
        - dayOfWeek: lowercase only
        - rawText: copy the EXACT source text for this day's workout. For rest days use "Rest"
        - title: brief descriptive name ("Rest Day", "Easy Run", "Track Intervals", "Long Run w/ Tempo")
        - notes: coach tips / context accompanying the workout — omit if none
        - isRaceDay: true ONLY for the marathon / race day itself
        - Each chunk may contain 2–5 complete weeks — extract ALL of them, do not stop early
        - If text starts mid-sentence it is a continuation from a page break — assign by context
        - Ignore unit conversion tables (Miles / Kilometers)

        TABLE BOUNDARY RULES (table-format PDFs):
        - Cells read left-to-right: Mon → Tue → Wed → Thu → Fri → Sat → Sun per week row
        - A new day starts with a fresh mileage statement ("8-12 mi", "3 mi easy") or "Rest"
        - "Optional uphill TM", "Full strength routine" are NOTES appended inside a cell — \
        they do NOT begin a new day
        - The next mileage or "Rest" after those notes belongs to the NEXT day

        Return ONLY a JSON array starting with [ and ending with ].

        Training plan text:
        \(text)
        """
    }

    private nonisolated func decodeDayStructures(from jsonString: String) throws -> [DayStructureDTO] {
        let cleaned = extractJSONArray(from: jsonString)
        guard let data = cleaned.data(using: .utf8) else {
            throw parserError("Could not encode Phase 1 response", code: -2)
        }
        do {
            return try JSONDecoder().decode([DayStructureDTO].self, from: data)
        } catch {
            print("📋 [ClaudeParser] Phase 1 decode error: \(error)\nPreview: \(cleaned.prefix(300))")
            throw parserError("Could not extract schedule structure. Please try again.", code: -3)
        }
    }

    // MARK: - Phase 2: Segment Parsing

    private func parseSegments(from rawText: String) async throws -> [WorkoutSegment] {
        guard !isRestDay(rawText) else { return [] }
        let json = try await callClaudeWithCache(rawText, prefix: "p2", maxTokens: 1500, prompt: buildPhase2Prompt)
        return (try? decodeSegments(from: json)) ?? []
    }

    private func buildPhase2Prompt(for rawText: String) -> String {
        """
        Parse the following single workout description into a JSON array of training segments.
        Return ONLY the flat segments array — no day wrapper, no week field.
        If this is a rest day, return [].

        Workout: \(rawText)

        Segment schema:
        {
          "type": "warmup|cooldown|easy|interval|tempo|hills|rest",
          "durationSeconds": 600,
          "distanceMiles": 1.5,
          "distanceMeters": 800,
          "reps": 4,
          "effort": "easy|marathon|threshold|tenK|fiveK|threeK",
          "setIndex": 1
        }

        GENERAL RULES:
        - Segments appear in the ORDER they are described in the text — never reorder them
        - For ranges ("8-10 miles", "4-5 x"), always use the LOWER bound
        - distanceMiles for road/trail; distanceMeters for track distances given in meters
        - durationSeconds ONLY when a time is explicitly stated ("30 min", "5 min easy")
        - Never set durationSeconds to 0 — omit entirely if not applicable
        - effort is optional — omit if not specified
        - For easy runs with distance RANGES ("6-8 miles easy"), omit distanceMiles (open workout)

        EFFORT MAPPINGS:
        - easy / jog / recovery / float → easy
        - marathon / MP / marathon pace → marathon
        - threshold / tempo / T-pace / LT / 1-hour effort → threshold
        - 10K effort / 10k pace → tenK
        - 5K effort / 5k pace → fiveK
        - 3K effort / 3k pace / mile pace / fast / hard / faster → threeK

        EFFORT + DISTANCE ORDERING — critical:
        - Honour the literal order described. "2 miles at M effort plus 1 mile faster" →
          first segment 2mi@marathon, second segment 1mi@threshold (NOT reversed)
        - "800/400/200 at 10K/5K/3K" → 800m=tenK, 400m=fiveK, 200m=threeK (parallel mapping)

        DISTANCE RULES:
        - Bare numbers without units (800, 400, 200, 1600) = METERS → distanceMeters
        - "800m", "400m" → distanceMeters: 800, 400
        - NEVER convert track distances to time
        - Recovery segments in track workouts also use distanceMeters ("400 easy" → distanceMeters: 400)

        INTERVAL SETS:
        1. Simple "N x distance" with one recovery: reps:N, no setIndex
           4 x 800 with 400 easy → {"type":"interval","distanceMeters":800,"reps":4}, \
        {"type":"rest","distanceMeters":400}

        2. Complex "N x d1/d2/d3 with multiple recoveries": ALL segments share one setIndex; \
        put reps:N on each interval segment
           "4 x 800/400/200 at 10K/5K/3K with 400/200/400 easy":
           {"type":"interval","distanceMeters":800,"effort":"tenK","reps":4,"setIndex":1},
           {"type":"rest","distanceMeters":400,"effort":"easy","setIndex":1},
           {"type":"interval","distanceMeters":400,"effort":"fiveK","reps":4,"setIndex":1},
           {"type":"rest","distanceMeters":200,"effort":"easy","setIndex":1},
           {"type":"interval","distanceMeters":200,"effort":"threeK","reps":4,"setIndex":1},
           {"type":"rest","distanceMeters":400,"effort":"easy","setIndex":1}

        3. Never expand reps into separate segment pairs
        4. Open recovery ("jog back", "run down") → rest with no distance/duration
        5. Multiple distinct complex sets → increment setIndex (setIndex:1, setIndex:2…)

        GRADUATED SETS ("5/4/3/2/1 miles at M effort with 1 mile float recovery"):
        Each distance = separate interval, same setIndex:
        {"type":"interval","distanceMiles":5,"effort":"marathon","setIndex":1},
        {"type":"rest","distanceMiles":1,"effort":"easy","setIndex":1},
        {"type":"interval","distanceMiles":4,"effort":"marathon","setIndex":1},
        {"type":"rest","distanceMiles":1,"effort":"easy","setIndex":1}, … and so on

        Return ONLY the JSON array starting with [ and ending with ].
        """
    }

    private nonisolated func decodeSegments(from jsonString: String) throws -> [WorkoutSegment] {
        let cleaned = extractJSONArray(from: jsonString)
        guard let data = cleaned.data(using: .utf8) else {
            throw parserError("Could not encode Phase 2 response", code: -2)
        }
        let dtos = try JSONDecoder().decode([WorkoutSegmentDTO].self, from: data)
        return dtos.map { seg in
            let segs = WorkoutSegment(
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
            print("🏃 [ClaudeParser] Seg: \(seg.type) distM=\(seg.distanceMeters ?? -1) distMi=\(seg.distanceMiles ?? -1) dur=\(seg.durationSeconds ?? -1) reps=\(seg.reps ?? -1) effort=\(seg.effort ?? "-")")
            return segs
        }
    }

    // MARK: - Helpers

    private nonisolated func makeWorkoutDay(from dto: DayStructureDTO, segments: [WorkoutSegment]) -> WorkoutDay {
        WorkoutDay(
            id: UUID(),
            week: dto.week,
            dayOfWeek: DayOfWeek(rawValue: dto.dayOfWeek.lowercased()) ?? .monday,
            title: dto.title,
            notes: dto.notes,
            segments: segments,
            isRaceDay: dto.isRaceDay ?? false
        )
    }

    private func isRestDay(_ rawText: String) -> Bool {
        let t = rawText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t == "rest" || t.isEmpty
    }

    /// When multiple chunks produce the same (week, dayOfWeek), keep the one with more rawText.
    private func deduplicateStructures(_ structures: [DayStructureDTO]) -> [DayStructureDTO] {
        var best: [String: DayStructureDTO] = [:]
        for s in structures {
            let key = "\(s.week)-\(s.dayOfWeek.lowercased())"
            if let existing = best[key] {
                if s.rawText.count > existing.rawText.count { best[key] = s }
            } else {
                best[key] = s
            }
        }
        return Array(best.values)
    }

    /// Strips markdown fences and extracts the outermost [...] from a Claude response.
    private nonisolated func extractJSONArray(from response: String) -> String {
        var s = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            let lines = s.components(separatedBy: "\n")
            s = lines.dropFirst().dropLast().joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !s.hasPrefix("["),
           let start = s.firstIndex(of: "["),
           let end   = s.lastIndex(of: "]") {
            s = String(s[start...end])
        }
        return s
    }

    private nonisolated func parserError(_ message: String, code: Int) -> NSError {
        NSError(domain: "ClaudeParser", code: code,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    // MARK: - Single Workout Detection

    private func looksLikeSingleWorkout(_ text: String) -> Bool {
        let hasWeek = text.range(of: #"(?i)\bweek\s*\d"#, options: .regularExpression) != nil
        let hasDay  = text.range(
            of: #"(?i)\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun)\b"#,
            options: .regularExpression) != nil
        let single = !hasWeek && !hasDay
        if single { print("📦 [ClaudeParser] Single workout — wrapping as Week 1 Wednesday") }
        return single
    }

    // MARK: - Page Merging

    private func mergeOrphanedPageStarts(_ pages: [String]) -> [String] {
        var merged: [String] = []
        for page in pages {
            let startsNewWeek = page.range(
                of: #"(?i)^week\s+\d"#, options: .regularExpression) != nil
            if !startsNewWeek && !merged.isEmpty {
                merged[merged.count - 1] += "\n\n" + page
                print("📦 [ClaudeParser] Merged orphaned page into previous chunk")
            } else {
                merged.append(page)
            }
        }
        return merged
    }

    // MARK: - Chunking

    private func splitIntoWeeks(_ text: String) -> [String] {
        // Chunk by WEEK so each Claude call covers at most one week — keeping every call
        // small and well under the serverless proxy's ~30s timeout. Legacy page-break
        // sentinels are normalised away first; a week that was split across pages gets
        // reunited because we split on week markers, not page boundaries. The leading
        // [#>\-\*\s]* allows markdown headings/bullets (e.g. "## Week 1", "- Week 1").
        let normalized = text.replacingOccurrences(of: "=== PAGE BREAK ===", with: "\n")
        guard let regex = try? NSRegularExpression(
            pattern: #"(?im)^[#>\-\*\s]*week\s+\d+"#
        ) else { return [normalized] }
        let ns = normalized as NSString
        let matches = regex.matches(in: normalized, range: NSRange(location: 0, length: ns.length))
        guard matches.count > 1 else { return [normalized] }
        return matches.enumerated().map { i, m in
            let start = m.range.location
            let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            return ns.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Cache-aware Claude Call

    private func callClaudeWithCache(
        _ text: String,
        prefix: String,
        maxTokens: Int,
        prompt: (String) -> String
    ) async throws -> String {
        let cacheKey = "\(prefix):\(text)"
        if let cached = PlanParseCache.shared.cachedJSON(for: cacheKey) {
            print("✅ [ClaudeParser] Cache hit (\(prefix))")
            return cached
        }
        print("🌐 [ClaudeParser] Cache miss (\(prefix)) — calling Claude")
        let json = try await callClaude(with: prompt(text), maxTokens: maxTokens)
        PlanParseCache.shared.store(json: json, for: cacheKey)
        return json
    }

    // MARK: - API Call

    private func callClaude(with prompt: String, maxTokens: Int) async throws -> String {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The proxy validates this token, then attaches the Anthropic key +
        // anthropic-version header itself before forwarding to Anthropic.
        request.setValue(Secrets.appToken, forHTTPHeaderField: "x-app-token")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Retry transient failures — transport errors (dropped connection / timeout on
        // cellular) AND gateway/rate-limit/overload statuses. 504 is the serverless proxy
        // timeout; 429 is rate limiting (honour Retry-After when present).
        let retryableStatuses: Set<Int> = [408, 429, 500, 502, 503, 504, 529]
        let maxAttempts = 5
        var lastError: Error = parserError("Unknown error", code: -1)

        for attempt in 1...maxAttempts {
            let data: Data
            let urlResponse: URLResponse
            do {
                (data, urlResponse) = try await URLSession.shared.data(for: request)
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: backoffNanos(attempt))
                    continue
                }
                throw error
            }

            guard let http = urlResponse as? HTTPURLResponse else {
                throw parserError("Invalid response from server", code: -1)
            }

            if http.statusCode != 200 {
                if let errBody = try? JSONDecoder().decode(ClaudeErrorResponse.self, from: data) {
                    lastError = parserError(errBody.error.message, code: http.statusCode)
                } else {
                    lastError = parserError("API error (HTTP \(http.statusCode))", code: http.statusCode)
                }
                if retryableStatuses.contains(http.statusCode), attempt < maxAttempts {
                    let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                    let delay = retryAfter.map { UInt64($0 * 1_000_000_000) } ?? backoffNanos(attempt)
                    try await Task.sleep(nanoseconds: delay)
                    continue
                }
                throw lastError
            }

            let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)
            guard let text = response.content.first(where: { $0.type == "text" })?.text else {
                throw parserError("Empty response from Claude", code: -1)
            }
            return text
        }
        throw lastError
    }

    /// Exponential backoff (2^attempt seconds) in nanoseconds.
    private func backoffNanos(_ attempt: Int) -> UInt64 {
        UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
    }

    // MARK: - Assembly

    private func assemblePlan(from days: [WorkoutDay], title: String) -> TrainingPlan {
        // Safety dedup — should be a no-op after deduplicateStructures, but kept as guard
        var best: [String: WorkoutDay] = [:]
        for day in days {
            let key = "\(day.week)-\(day.dayOfWeek.rawValue)"
            if let existing = best[key] {
                let score    = day.segments.count * 10 + (day.notes != nil ? 1 : 0)
                let exScore  = existing.segments.count * 10 + (existing.notes != nil ? 1 : 0)
                if score > exScore { best[key] = day }
            } else {
                best[key] = day
            }
        }
        let unique = Array(best.values)
        let grouped = Dictionary(grouping: unique) { $0.week }
        let sortedWeeks = grouped.keys.sorted().map { week -> [WorkoutDay] in
            let order = DayOfWeek.allCases
            return (grouped[week] ?? []).sorted {
                (order.firstIndex(of: $0.dayOfWeek) ?? 0) < (order.firstIndex(of: $1.dayOfWeek) ?? 0)
            }
        }
        print("🗓️ [ClaudeParser] '\(title)': \(sortedWeeks.count) week(s), \(unique.count) day(s)")
        for (i, week) in sortedWeeks.enumerated() {
            let s = week.map { "\($0.dayOfWeek.rawValue): \($0.title)" }.joined(separator: ", ")
            print("  Week \(i + 1): \(s)")
        }
        return TrainingPlan(id: UUID(), title: title, weeks: sortedWeeks)
    }
}

// MARK: - DTOs

private struct DayStructureDTO: Decodable {
    let week: Int
    let dayOfWeek: String
    let title: String
    let notes: String?
    let isRaceDay: Bool?
    let rawText: String
}

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

private struct WorkoutSegmentDTO: Decodable {
    let type: String
    let durationSeconds: Int?
    let distanceMiles: Double?
    let distanceMeters: Double?
    let reps: Int?
    let restDurationSeconds: Int?
    let effort: String?
    let setIndex: Int?
}

private extension Array {
    /// Splits into consecutive sub-arrays of at most `size` elements (used to bound
    /// how many Claude calls run concurrently).
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
