# Figma build tracker — PaceSync full design implementation

File: https://www.figma.com/design/cjIuRJnQorjutybWw2IZ9j/PaceSync-%E2%80%94-Design-Comparison
FileKey: `cjIuRJnQorjutybWw2IZ9j`

Purpose: pixel-perfect, fully tokenized implementation of the CURRENT app design
(source of truth: `PaceSync/DesignSystem/Theme.swift`, `Components.swift`, and the
`Views/Redesign/*` screens; sim reference screenshots at 402×874 pt).
Built stage-by-stage so a fresh session can resume — each stage records the
Figma node/collection IDs it created.

Conventions decided (do not re-litigate on resume):
- Leave Page 1 (old "Design Comparison" content, TimeBar/* collections, Inter styles) untouched.
- New pages: `PS 1 · Foundations`, `PS 2 · Components`, `PS 3 · Screens`.
- New collections: `PaceSync / Color` (Light+Dark), `PaceSync / Primitives` (Base).
- Text styles `PS/*` in **SF Pro** (LargeTitle 22 SB, Title 17 SB, Headline 15 SB,
  Body 15 R, Callout 13 R, Caption 12 R, Label 10.5 SB).
- Screen frames: 402×874 (matches sim screenshots), dark-mode variants via
  explicit variable mode on duplicated frames.
- Apple components from community library **iOS and iPadOS 26**
  (libraryKey `lk-a5b98decf0…8a17` from get_libraries): status bar, home indicator,
  tab bar, toggle, segmented control. If import-by-key fails, add the library to
  the file in Figma UI first.
- Credit discipline: fewest/biggest use_figma calls; inline `await node.screenshot()`
  instead of separate get_screenshot calls; STOP on rate-limit error, commit this
  tracker, report exact resume point.

## New feature to design (user request 2026-07-07)
Plan naming: name auto-generated from the plan/PDF at import, user can override.
- Add Training sheet: after file attach/parse, "Plan name" field pre-filled with
  generated name + sparkle "auto" glyph; tap to edit.
- Plans page rows show the name; rename stays in plan-settings menu (detail view).

## Stages

- [x] A. Variables — DONE 2026-07-07.
      Color coll `VariableCollectionId:67:2` (Light `67:0`, Dark `67:1`); Prims `VariableCollectionId:67:24`.
      Vars 67:3–67:23 (colors in Theme.swift order: canvas,surface,surfaceRaised,hairline,ink,ink2,ink3,
      accent,accentSoft,onAccent,warning,error,chipFill,control,cat easy/long/tempo/intervals/hills/strength/rest);
      prims 67:25–67:34 (radius card/row/control/chip, space s1–s6).
- [x] B. Text styles + pages — DONE 2026-07-07. SF Pro ("Semibold" style string).
      PS/LargeTitle→Label created. Pages: Foundations `67:42`, Components `67:43`, Screens `67:44`.
- [x] C. Core components — DONE 2026-07-07 on page 67:43:
      CategoryDot `69:2`, CompletionCheckbox set `69:8` (Done=Off/On),
      SectionHeader `69:9`, Button set `69:15` (Kind=Primary/Secondary), Toast `69:16`,
      TodayWorkoutRow set `70:44` (Sync=NotSynced/Synced/Done),
      WorkoutRow set `70:86` (State=NotSynced/Synced/Done/Rest),
      WeekDay set `71:22` (State=Done/Pending/Rest/Today), WeekStrip `71:23`, ProgressRing `71:45`.
      Card containers are built per-screen (variable-bound frames), not a slot component.
- [~] D. Apple kit — BLOCKED: `importComponentByKeyAsync` returns "Not permitted to
      upsert from library" because the iOS 26 community library is NOT ADDED to the file.
      USER ACTION: in Figma, Assets panel → Libraries (book icon) → search
      "iOS and iPadOS 26" → Add to file. Then swap: per-screen node named
      "Tab bar (placeholder — swap for iOS 26 kit …)" + add "Status bar - iPhone"
      (key 51ddb19de206b67eae2d554b1d20c018feb754f4) at y=0 of each screen, and
      Home Indicator set key 7aafe068eb8261b9aa743403f83769ae78800a38,
      Tab Bar - iPhone set key 1a05576da751e45de479836ff1f59971cedc2606.
- [~] E. Screens on page 67:44 (light, 402×874) — 5 of 9 DONE 2026-07-07:
      Home `73:2` (content 73:7), Plans `79:7` (content 79:12, ProgressCard 79:15),
      Add Training `82:13` (content 82:17 — includes NEW auto plan-name row w/ sparkle),
      Workout Detail `83:13` (content 83:17), Settings `84:13` (content 84:15).
      REMAINING: Full Plan (List), Full Plan (Calendar), Edit Workout, Edit Segment.
- [ ] F. Dark-mode duplicates (set explicit Dark mode `67:1` of collection 67:2 on
      duplicated frames) + swap Apple chrome + user visual pass.

## CRITICAL BUILD CONSTRAINT discovered 2026-07-07
SF Pro is a LOCAL font → the MCP's server-side renderer can't re-render it:
1. `setProperties` on TEXT props fails ("font that isn't available") — component TEXT
   props exist on the row sets but are unusable from MCP. (They still work fine for
   humans in the Figma app.)
2. Editing text INSIDE instances silently reverts. Pattern that works:
   `variant.createInstance().detachInstance()` then edit text on the detached copy.
3. MCP screenshots render STALE text — do not trust them for copy; verify by
   reading `.characters` back. The user's Figma app renders correctly.

## Progress log
- 2026-07-07: Tracker created. File inspected (1 page, old content mapped).
  SF Pro confirmed available. No local components. Old TimeBar collections left as-is.
- 2026-07-07 (later): Stages A–C done; 5 screens built (~25 MCP calls, no rate limit hit).
  Next session: remaining 4 screens, dark duplicates, Apple chrome swap after user
  enables the iOS 26 library.
