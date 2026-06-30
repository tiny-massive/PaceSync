# PaceSync — Project Roadmap

_Last updated: 2026-06-29. Source: full multi-agent codebase audit + owner direction._

PaceSync is a SwiftUI iOS app that ingests a running training plan (PDF / text / Markdown),
uses the Claude API to parse it into structured weeks → days → segments, and schedules the
workouts to Apple Watch via WorkoutKit (and, soon, syncs them to the local Calendar).
~3,000 lines, 22 Swift files, single-plan model. Bundle id `studio.schoolwork.pacesync`.

**Overall health at audit time: 52/100.** Strong parsing pipeline; foundation (security,
persistence, state identity) below shippable bar. Stabilize the base, then land features on top.

---

## Decisions locked (2026-06-29)

1. **API key → backend proxy now.** No client-embedded key. Proxy holds the key server-side, gated
   by a shared app token (per-user auth later). _Scaffolded in `proxy/` (Netlify Function)._
2. **Calendar sync → in addition to Watch.** Both "Send to Watch" and "Sync to Calendar" coexist.
   Goal: when a user uploads a plan, each upcoming training activity shows up in their calendar.
3. **Figma plan → Organization / Enterprise.** Code Connect available, on top of a token layer.
4. **Design direction → align to the `TimeBar` macOS app** (sibling project in this workspace).
   That means: **light + dark adaptive** (not dark-only), **Inter** typography with **tabular
   digits**, restrained colour (one accent + Apple system green/red for actions; colour otherwise
   only as small category markers), soft surfaces + hairlines, progress **rings**. See its design
   DNA in `../TimeBar/Sources/TimeBar/Theme.swift`; its Figma file: figma.com/design/8u3mc7jtRDc997KL6ZFW0M.
5. **Ingest pipeline → dates first.** Reframe to **PDF → Markdown → dated skeleton → workouts**:
   - Convert any upload to clean **Markdown** first. For PDFs, send the *actual PDF* to Claude
     (Anthropic native PDF input) rather than PDFKit text extraction — this is the real fix for the
     date-scrambling bug (PDFKit reads table cells out of order; Claude sees the rendered layout).
   - Build the **dated skeleton** next: deterministically map each week/day → real calendar date
     (anchored to race date), independent of workout content. Get the dates *right* in isolation.
   - **Then** parse each day's workout content onto its already-correct date.
   - Caching stays as **timeout resilience** (full PDFs were timing out — caching saved partial
     progress; it was never meant to "refactor"). Re-parse gets a `forceRefresh` to bypass it.
6. **Units → display-only, at the very end.** No mid-pipeline conversion, no canonical-unit
   refactor. A value enters in its source unit (mile in → mile stored as mile); if the user's
   preference is km, convert **only at display time**, rounded for readability. (This reverses the
   earlier "convert everything to km up front" idea — simpler, and close to today's behaviour.)

Still open: **what "simplify the app" means** (which flows feel heavy); **which signing team**
is correct (see Phase 1); proxy host confirmed (**Netlify**).

## What PaceSync automates — the SWAP manual workflow

A SWAP-podcast Patreon comment describes the manual flow runners do today. PaceSync exists to
collapse the whole thing into a single upload:

1. Open the plan PDF in Google Docs → save as **Markdown** (cleaner than reading the PDF directly).
2. Paste into an LLM; give **current + peak weekly mileage**; ask to convert to **km**.
3. Ask it to generate a PDF.
4. Bonus: ask for a **`.ics`** file and open it in a calendar app → daily plan in your calendar.

What this confirms / adds:
- **PDF → Markdown first is right** (decision #5). Their Google-Docs trick exists *because* raw PDF
  text is error-prone — exactly the date-scrambling we hit. Our native-PDF-to-Claude reaches the
  same clean Markdown automatically, no Google Docs detour.
- **`.ics` export is a wanted output**, not just live Calendar sync (Phase 5).
- **Personalization (candidate / backlog):** let users enter current + peak weekly mileage so the
  plan *scales to their level*. Real demand from SWAP runners; revisit after the core flow lands.

---

## 🔴 Release blockers

1. **API key compiled into the binary** (`Secrets.swift`). Rotate + move to the proxy. _(in progress)_
2. **No HealthKit capability** — WorkoutKit can't run in a signed build. ✅ **Done 2026-06-29:**
   `PaceSync.entitlements` created (HealthKit) + `CODE_SIGN_ENTITLEMENTS` + usage strings wired into
   both configs; project builds clean. _Remaining: enable the HealthKit capability on the App ID
   (Xcode does this on first signed build), and verify a workout actually lands on the Watch._
3. **Scheduling state in-memory only** — shows "unscheduled" after relaunch. (Phase 2.)
4. **Two signing teams** (`N5235GZ26C` project-level vs `2Z7F922CV2` target-level — the target one
   signs). Reconcile to one. _Owner to confirm which is the distribution team._
5. **Deployment target was iOS 26.2** → ✅ **lowered to 17.0 (2026-06-29)**; builds clean.

## 🟠 Foundation debt (before any model/ingest rework)

- Re-parse returns cached results (add `forceRefresh`) and mints new UUIDs (preserve identity by
  `(week, dayOfWeek)`).
- No `schemaVersion`; `load()` silently drops the plan on decode failure; non-atomic writes.
- Scheduling verified by `displayName == title` → false positives on repeated titles.
- Zero tests. Parse resilience uneven (Phase 1 aborts on one bad chunk; 429/500 not retried).

**Root cause:** no single source of truth for identity/state. Fix once → collapses four bugs.

---

## Phased plan

### Phase 1 — Stop the bleeding (security + release blockers) — _in progress_
**Done (2026-06-29):** deployment target → 17.0; HealthKit entitlement + usage strings wired
(builds clean); backend proxy scaffolded in `proxy/`.
**Remaining:** deploy the proxy with the new key as a secret → flip `ClaudeParserService` to the
proxy + delete `Secrets.swift` → revoke the old key. Reconcile the signing team. Enable HealthKit
capability on the App ID and verify Watch scheduling end-to-end on device. Handle `.denied`
WorkoutKit auth with an explanatory alert.

### Phase 2 — Foundation: identity, state, persistence
Identity-preserving + cache-bypassing re-parse. Scheduling abstraction keyed on stable `(day id,
date)` encoded in workout metadata, persisted and reconciled against WorkoutKit at launch.
`schemaVersion` + explicit migrations + atomic writes; preserve raw JSON + surface an error instead
of dropping the plan. Minimal test target. Harden parse pipeline (per-chunk resilience, 429/500
retries honoring `retry-after`, bounded concurrency, `max_tokens` truncation detection).

### Phase 3 — Ingest rework: dates-first pipeline + Markdown upload
Convert uploads to clean Markdown first (native-PDF-to-Claude for PDFs). Build the deterministic
**dated skeleton** (week/day → calendar date) before parsing workout content, so dates can't get
mis-associated. Add markdown `UTType` to the picker; relax the week-split / single-workout regexes
for markdown headings (`## Week 1`). Test a real exported `.md` plan end-to-end. (See decision #5.)
_Candidate (backlog):_ let users enter current + peak weekly mileage so the plan scales to their
level — SWAP runners do this by hand today.

### Phase 4 — Design system → TimeBar-aligned redesign → simplify
Build a SwiftUI `Theme` (semantic Colors / Spacing / Typography / Radius) backed by Asset-Catalog
colorsets — modeled on TimeBar's tokens (light+dark, Inter, tabular digits, restrained colour,
rings). Kill duplication (one `SegmentType` colour helper, one race-day helper; extract
`CardContainer` / `StatBadge` / `SectionHeader` / `PrimaryButton`). Refactor navigation to a typed
route enum (home of "simplify"). Accessibility labels. Build the PaceSync Figma file with a semantic
variable collection mirroring the Swift tokens; reconcile via `get_variable_defs`; then Code Connect
component → SwiftUI mapping. **Units (decision #6) land here** as a trivial display-layer tweak:
default display to km, round for readability — no model change.

### Phase 5 — Local calendar (EventKit) sync — _in addition to Watch_
`EventKitService` (one `EKEventStore`); reuse `SavedPlan.date(forWeekIndex:day:)` for every event
date; all-day `EKEvent` per workout; dedicated "PaceSync" calendar; persist `[dayID: eventID]` for
idempotent update/delete on re-parse (relies on Phase 2 stable IDs). Calendar usage strings in both
configs. "Sync to Calendar" surfaced in the (redesigned) plan card alongside "Send to Watch".
**Confirmed:** export a standard **`.ics`** the user can import into any calendar app (the
SWAP-podcast workflow's payoff: MD → calendar file → daily plan in your calendar).

**Why this order:** can't redesign on a still-changing model (3 before 4); can't change persistence
formats without a migration that won't wipe users (2 before 3); calendar sync last so it reuses
stable identity + date math instead of a second fragile state mirror.
