# Go-to-market plan (compiled 2026-10-01, research-verified)

Product: **Racebound** (code name PaceSync internally): any training
plan — PDF, text, or a typed sentence — becomes structured workouts in the native
Apple Watch Workout app, anchored to race day, ticked off automatically from Health.
No account. App is launch-ready at 2.0 (6); a build is believed to be in App Store
Connect from July.

## The market verdict (3 research passes, sourced in repo history)
- **Demand is real**: years of forum threads asking exactly this; people buy Garmins
  to get it; Apple Watch is Strava's #1 recording device; Runna reached ~90k paying
  members → Strava acquisition (market proof).
- **Position**: nobody on Apple Watch does the full bundle (whole-plan PDF → native
  Workout app + calendar + auto-completion). Single-workout NL parsing has two tiny
  competitors (Workout Writer, Fitsmith). Closest threat: "Type to Run" (Garmin-first,
  AW beta open) and Garmin-side PlanToWatch — speed to market matters.
- **Positioning sentence**: "Turn any training plan — PDF, book page, or a sentence —
  into your Apple Watch's built-in Workout app. Scheduled, synced, ticked off
  automatically. Pay once, no subscription."

## Pricing (decided)
- **Free download → 1 full plan parse + a couple of one-off workouts free → one-time
  unlock $12.99** (launch-intro $9.99 for two weeks). No subscription — that IS the
  marketing message ("one month of Runna costs more than this app forever").
- Evidence: hard paywall ≈12% conversion vs ≈2% soft freemium; WorkOutDoors $8.99
  one-off = niche floor; Runna $119.99/yr = anchor; one-time IAP beat subs in 2026
  indie modeling. COGS $0.50–3/user lifetime, →$0 with on-device Foundation Models.
- Engineering: DONE 2026-10-05 — PurchaseManager (StoreKit 2) + PaywallSheet + gates on all parse entry points; free tier = 1 plan import + 3 one-offs, counted only on successful saves; re-import free; Racebound.storekit test config in the shared scheme.
- Enroll in **Apple Small Business Program** (15% commission) if not already.
- Later, only if telemetry demands: consumable parse-packs; tip jar (WorkOutDoors pattern).

## Naming (DECIDED 2026-10-05: **Racebound** — register racebound.app immediately)
PaceSync is dead publicly: "PaceSync: Music For Your Run" live in H&F + Dentsu
"Pace Sync" mark + pacesync.com ransom-parked. Vetted-clean finalists (as of 10-01,
.app free to register same-day): **Racebound** (recommended; race-day anchor, zero
collisions), **Taperline**, **Planbound**. "PlanSync" checked 10-01: both domains
taken, generic "-sync" plumbing word, search-collides with planner apps — weak.
Factors that matter: same-category clearance; distinctive/suggestive over descriptive
(keywords go in the SUBTITLE, brand in the title); runner-coded vocabulary; spellable
from hearing; domains/handles free; not locked to one platform or feature.
Before committing: manual USPTO TESS check (Class 9/41/42); register .app same day.

## Launch sequence (from name decision; "W" = week)
**W1 — ship prep**
- Choose name → register .app → rename display name/listing/site copy (bundle ID unchanged)
- Build the IAP paywall + free-tier gating; bump to 2.1
- **Submit App Store featuring nomination immediately** (ASC → Featuring → Nominations;
  6–8 wk editorial lead). Story: on-device AI + native WorkoutKit + no account — the
  exact narrative Apple's Sept-2025 newsroom promoted. Timing hooks: NYC Marathon
  (early Nov), spring-marathon training (Jan).
- TestFlight external group: run-club friends + r/AppleWatch beta volunteers
**W2 — assets + press**
- Static one-pager site live on the .app domain (Cloudflare; hero video, 3 proof
  features, price, FAQ, privacy/support). Press-kit page (icon, screenshots, videos,
  blurb, contact).
- Record 3 explainer videos (shot list below)
- Pitch: 9to5Mac Indie App Spotlight — michaelb@9to5mac.com, Tue–Thu AM PT, TestFlight
  ok, follow up after 1 wk. the5krunner — via /faq review-request route; explicit ask.
  iOS Dev Weekly. (DC Rainmaker: long shot, send anyway — this is his readers' pain.)
- Fill ASC forms from APPSTORE.md (update name/price/screenshots) → submit for review
**W3 — launch week**
- Release. Reddit maker posts (read each sub's current rules first; disclose; story-first
  "my coach's PDF wouldn't go on my watch"; App Store promo codes in comments):
  r/AppleWatch, r/running, r/Marathon_Training, r/SideProject. Product Hunt same week
  (checkbox, not strategy). Press embargo lifts.
- Apple Search Ads: exact-match only — "training plan apple watch", "structured workout
  watch", "couch to 5k apple watch", competitor terms (runna, workoutdoors, watchletic,
  intervals). ~$10–15/day; benchmark CPT ~$1.50–3. Treat as keyword research too.
**W4+ — compounding**
- Coach partnerships (the Watchletic-proven channel): coaches who sell PDF plans get
  bulk promo codes / referral arrangement; pitch 10 coaches.
- Nano-runfluencer experiments: $50–300/post, "PDF → watch in 30s" reels; kill or scale.
- 3–4 "launchable" updates across year 1 (each = fresh press/Reddit/featuring moment):
  on-device parsing (iOS 26+, kills COGS + "never leaves your phone" headline),
  COROS/Garmin export, race-week features, .ics export.

## Website (decided: static one-pager, Cloudflare, custom .app domain)
Sections: hero (15s video autoplay: type workout → it's on the watch) · "How it works"
in 3 steps · the anti-subscription price card · plan-PDF demo video · FAQ (privacy:
on-device Health, what's sent to AI) · footer links to /privacy + /support (already
live on the worker). I build + deploy; owner buys domain.

## Explainer videos (3 × 15–30 s, sim-recorded, captions, no voiceover needed)
1. **The sentence**: type "6 × 800m at 5K pace, 90s jog" → Create → workout on the
   (simulated) watch Workout app. Caption: "Describe it. Sync it. Run it."
2. **The plan**: PDF in → weeks appear dated → one tap → whole block on the watch +
   calendar. Caption: "Your coach's plan. Your watch. One upload."
3. **The loop**: run completes on watch → plan ticks itself + week strip fills + race
   countdown. Caption: "It even marks your runs done."
Raw sim footage I can record; final polish (device frames, music) = CapCut/Descript pass.

## Targets & expectations (sourced)
- Well-executed launch: **$5k–20k year one** (~500–2,000 unlocks net ~$8.50–11);
  featuring/press spike upside $20k–60k; quiet launch $500–3k (the statistical mode —
  distribution is the work).
- Metrics that matter: downloads/wk, trial→unlock conversion (target ≥10%), proceeds,
  review velocity (prompt after first successful sync), keyword ranks.

## Risks
- Type to Run's Apple Watch release replicates the bundle → ship this month.
- Name on ice blocks W1 — decide within days, not weeks.
- July ASC build may be stale/expired → re-archive is 5 minutes; verify ASC state first.
- Seasonality: marathon-training waves (Jan, Apr, Sep) are the demand peaks.

## Owner to-dos (can't be done for you)
1. Verify ASC state: is 2.0 (6) there? App record fields editable?
2. Decide the name (or green-light Racebound) → buy the .app domain (~$15/yr).
3. Check/enroll Apple Small Business Program.
4. Approve the $12.99/$9.99-intro price.
