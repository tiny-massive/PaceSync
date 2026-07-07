# COROS export — scoping (researched & verified 2026-07-07)

Goal: the same "sync workout to watch" experience PaceSync has for Apple Watch
(WorkoutKit), but targeting COROS. Every claim below was verified against primary
sources (COROS help center, the COROS API application form, platform forums) on
2026-07-07.

## The landscape

**There is no file route.** COROS accepts no structured-workout file imports
(.FIT workout, .ZWO, JSON) anywhere — Training Hub's "Import Data" is for
*completed activities* only. Planned workouts reach a COROS watch exclusively
through partner integrations built on COROS's private API. So "export a file the
user opens" — the trick that works for Garmin — is off the table.

**How partner delivery works:** an approved app appears as a named training plan
source in the COROS app (e.g. "PaceSync Training Plan" under Profile → Training
Plan Library). The user adds it to their COROS calendar once; workouts then flow
to the watch automatically. Push model (per the Intervals.icu developer): POST
the whole plan, a rolling window of ~7 days of workouts, re-posted on change.
Known limitation: deleting a workout on our side can't delete it from COROS.

## Route A — official COROS Training API (the real solution)

- OAuth2 partner API at open.coros.com. Private docs, application-only access
  via a Google Form linked from COROS support article 17085887816340
  ("Submitting an API Application").
- The form explicitly offers **"Structured Workouts"** as a requestable API
  function and has a **0–150 active users** bucket + personal/non-commercial
  designation — small apps are contemplated. No published pricing.
- The form wants: contact emails, company/app name + URL, 100-char description,
  **authorized callback domain**, a **workout-data receiving endpoint URL** and
  **service status-check URL** → we need small server pieces; the existing
  Cloudflare worker can host all three.
- Lead time is the risk: no published criteria/timeline; the one dated anecdote
  (Intervals.icu, 2022–23, pre-dating the current form) took ~6 months.
- Dev work once approved: "Connect COROS" OAuth flow in Settings
  (ASWebAuthenticationSession + worker-side token exchange), a
  `CorosExportService` next to `WorkoutKitService`, a segment→step mapper,
  push-on-change of the next 7 days. Estimate ~1–2 weeks.

## Route B — Intervals.icu bridge (shippable now, no approval)

Intervals.icu has an **open, self-serve, free-at-small-scale API** (documented
API-key auth per athlete; `POST /api/v1/athlete/{id}/events` creates planned
workouts) and its own approved COROS partner sync.

Chain: PaceSync → Intervals.icu API → COROS calendar → watch.

- User setup (once): create Intervals.icu account → connect COROS in its
  settings → add "Intervals.icu Training Plan" in the COROS app → paste their
  Intervals.icu API key into PaceSync.
- Dev: days, not weeks — REST calls + a mapper to Intervals.icu's workout format.
- Verified caveats: COROS receives only a ~7-day rolling window, refreshed on
  change or ~every 8 h; steps mixing pace+HR+power targets degrade to ONE
  driving metric on COROS; three-account chain is clunky for casual users.
- Good fit as a "COROS (beta, via Intervals.icu)" power-user feature while
  Route A's application is pending.

## Route C — COROS MCP (watch this)

COROS's official MCP server (launched May 2026) is **read-only today**, but
COROS publicly commits (help article updated 2026-07-07): *"We plan to release
an update before September 2026 that will allow you to write training plans and
workouts directly into the COROS app via AI."* If that ships with a usable auth
model, it becomes the first non-partner programmatic write path. Re-check
support article 50841795180948 in September.

## Dead ends (verified)

- **TrainingPeaks**: partner API closed to new partners ("not accepting any new
  API partners at this time"), commercial-only, no personal use.
- **Final Surge**: no open API; bespoke commercial arrangement only.
- **Terra / aggregators**: COROS data flows out (webhooks) but nothing writes in.

## Model fit (PaceSync ↔ COROS structured workouts)

Verified COROS capabilities: distance / time / open / training-load steps;
pace min–max ranges, % threshold pace, HR zones/BPM, power, cadence;
warmup/cooldown/interval/rest step types; **single-level repeats only** (nested
groups get flattened); **no per-step text** (name/description at workout level
only); supported on all COROS watches.

Mapping from `WorkoutSegment`:

| PaceSync | COROS |
|---|---|
| type warmup/cooldown/easy/tempo/interval/hills/rest | step type (hills → interval) |
| durationSeconds / distanceMiles / distanceMeters | time / distance step target |
| open easy runs (no distance/duration) | "Open" step — supported |
| reps + restDurationSeconds | single-level repeat group — matches, we never nest |
| effort / pace text in notes | needs parsing into numeric pace ranges (parser schema addition), else send unset intensity |
| day.notes (coach text) | workout-level description only — per-step notes are lost |

## Recommendation

1. **Submit the COROS API application now** — it's a Google Form, the wait is
   the bottleneck, and the worker already gives us the endpoints it asks for.
2. Decide whether Route B is worth shipping as a beta for COROS users in the
   meantime (small dev cost, real but tolerable fidelity caveats).
3. Re-check the MCP write release around September 2026.
4. Independently useful: extend the Claude parser to emit numeric pace-range
   targets per segment — improves Apple Watch sync too and is required for
   good COROS fidelity.
