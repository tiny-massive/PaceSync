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

        let chunks = splitIntoWeeks(text)
        let total  = chunks.count

        print("📦 [ClaudeParser] Split into \(total) chunk(s)")

        // Single-chunk fallback — no week headers found, parse as one call
        if total <= 1 {
            progressCallback?(0.1, "Parsing plan…")
            let json = try await callClaudeWithCache(text)
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

    // MARK: - Week Chunking

    /// Splits plan text on "Week N" / "WEEK N" boundaries.
    /// Returns [text] unchanged if no week headers are detected (≤1 match).
    private func splitIntoWeeks(_ text: String) -> [String] {
        // Matches "Week 1", "WEEK 12:", "Week 3 of 16", "WEEK ONE" etc. at line start
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

    private func decodeDays(from jsonString: String) throws -> [WorkoutDay] {
        print("🏃 [ClaudeParser] Raw JSON:\n\(jsonString)")
        var cleaned = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.components(separatedBy: "\n").dropFirst().dropLast().joined(separator: "\n")
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw NSError(domain: "ClaudeParser", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not encode response"])
        }

        let dtos = try JSONDecoder().decode([WorkoutDayDTO].self, from: data)

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
        let grouped = Dictionary(grouping: days) { $0.week }
        let sortedWeeks = grouped.keys.sorted().map { week in
            let order = DayOfWeek.allCases
            return (grouped[week] ?? []).sorted {
                (order.firstIndex(of: $0.dayOfWeek) ?? 0) < (order.firstIndex(of: $1.dayOfWeek) ?? 0)
            }
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
