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

- [ ] A. Variables — `PaceSync / Color` (Light+Dark) + `PaceSync / Primitives`
      IDs: (fill in)
- [ ] B. Text styles PS/* in SF Pro + new pages created
      IDs: (fill in)
- [ ] C. Core components on `PS 2 · Components`: PSCard, SectionHeader, CategoryDot,
      CompletionCheckbox, PSPrimaryButton, PSSecondaryButton, WorkoutRow,
      TodayWorkoutRow, WeekStrip, ProgressRing, Toast capsule
      IDs: (fill in)
- [ ] D. Apple kit instances wired (status bar, tab bar, home indicator, toggle,
      segmented control) — or noted fallback
- [ ] E. Screens on `PS 3 · Screens` (light): Home, Plans (+ naming), Workout Detail,
      Add Training, Settings, Full Plan (List), Full Plan (Calendar), Edit Workout,
      Edit Segment
- [ ] F. Dark-mode duplicates + final validation pass (per-section screenshots)

## Progress log
- 2026-07-07: Tracker created. File inspected (1 page, old content mapped).
  SF Pro confirmed available. No local components. Old TimeBar collections left as-is.
