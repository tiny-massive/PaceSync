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

---

## Phase 6 — App Store launch (added 2026-07-13)

_Status going in: Phases 1–5 are functionally done (proxy live + rate-limited, tokens rotated,
history scrubbed, multi-plan library, triple backup, calendar sync, redesign shipped, 12 unit
tests, TestFlight build 1.1(5) live). Requirements below were verified against Apple primary
sources on 2026-07-13 (multi-agent research + adversarial verification)._

### Done 2026-07-13
- **PrivacyInfo.xcprivacy** added (UserDefaults CA92.1 + User Content collection declaration).
  Blocking-enforced by Apple since May 2024 (ITMS-91053) — was missing.
- **Version unified to 2.0 (build 6)** (configs had 1.0/1.1 split; Settings hardcoded "2.0" —
  now reads the bundle).

### Step 1 — AI-consent flow (code, ~1 h) — REQUIRED
Guideline 5.1.2(i) (since Nov 13 2025): *"clearly disclose where personal data will be shared
with third parties, including with third-party AI, and obtain explicit permission before doing
so."* Reviewer-corroborated expectation (Apple dev-forum staff replies): disclose **what** is
sent, **to whom**, and get permission **before** sending. Build: one-time sheet before the first
parse — "PaceSync sends your plan text to Anthropic (Claude) to turn it into workouts. Nothing
else leaves your phone." → Continue / Cancel, persisted flag; also gates single-workout parse.
Plus a Settings row linking the privacy policy (5.1.1(i) requires the policy link **inside the
app** too — doubly required because of HealthKit).

### Step 2 — Privacy policy + support pages (code + deploy)
Serve `GET /privacy` and `/support` from the existing Cloudflare worker (no new infra).
Policy must name Anthropic (≈30-day API retention), state HealthKit data never leaves the
device and is never sent to the AI (true today — keep it true), calendar usage, no accounts /
analytics / tracking, contact email. These URLs go in App Store Connect (privacy policy URL is
a required field; support URL required per version).

### Step 3 — Screenshots (local, no cost)
One 6.9" portrait set satisfies everything (1320×2868 or 1290×2796; 1–10 images; smaller sizes
auto-scale; no iPad set for an iPhone-only app). Boot an iPhone 16/17 Pro Max simulator with the
seeded sample plan; capture Home, Plans, Workout Detail, Add Training, Full Plan (calendar),
Settings — light + a dark shot or two.

### Step 4 — Listing copy (draft for owner edit)
Name "PaceSync" (≤30 chars, already held) · subtitle ≤30 chars (e.g. "Your plan, on your wrist")
· description ≤4000 · keywords 100 bytes · promo text ≤170 (editable post-review). Category:
Health & Fitness (primary), Sports (secondary).

### Step 5 — Archive 2.0 (6) → TestFlight → device sanity pass (owner, guided)
Verify: consent sheet on first parse, fresh-install restore-from-iCloud, Watch sync, calendar
event, policy link opens.

### Step 6 — App Store Connect forms (owner, exact answers provided)
- **App Privacy label:** collects **User Content** ("Other User Content" — plan text), purpose
  App Functionality, **not linked** to identity, **no tracking**. Must match the manifest (it
  does). Declaring "Data Not Collected" while calling an LLM API is a known rejection.
- **Age rating (new 2026 questionnaire, mandatory):** honest answer on "Health or Wellness
  Topics" (exercise/self-care) → expect **9+**. No user-to-user chat/UGC → those are "No".
- **Review notes:** paste a small sample plan text so the reviewer can parse without hunting for
  a PDF; explain HealthKit read = auto-ticking completed runs; note no account is needed.
- Content rights, copyright ("© 2026 Schoolwork Studio"), export compliance already declared.

### Step 7 — Submit
Apple: 90% of submissions reviewed in <24 h. Rejection risks pre-mitigated: 5.1.2(i) consent
(Step 1), label/manifest mismatch (Step 6), HealthKit-without-policy (Steps 1–2).

### Post-launch guardrails
Anthropic console spend cap; Cloudflare caps already live (200/IP/day, 5 000/day global);
crashes via Xcode Organizer. Optional hardening: hash the IP in the worker's rate-limit KV key.
Backlog unchanged: COROS (API application), pace-range parser upgrade, one-off editing.
