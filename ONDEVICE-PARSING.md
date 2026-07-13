# On-device plan parsing — research (verified July 2026)

**Verdict: very feasible, and well-timed. Prototype now (2–4 days), target production with
the iOS 27 wave (~Sept 2026). Skip third-party MLX/llama models.**

## The fit

Apple's **Foundation Models framework** (iOS 26+) runs the on-device ~3B Apple Intelligence
model with **@Generable guided generation** — constrained decoding straight into Swift
structs. That maps exactly onto `{weeks → days → segments}`: the model *cannot* emit
schema-invalid output, killing the malformed-JSON failure class. `@Guide` adds per-field
constraints. Free, offline, no API key.

Limits that shape the design:
- **Context: 4096 tokens on iOS 26** (26.4 adds `contextSize`/`tokenCount` APIs); **8192 on
  iOS 27 beta**. A 12-week plan (~5–10k tokens) does NOT fit — parse **one week per fresh
  session** (a week ≈ 400–900 tokens; fits comfortably). Apple's own guidance is to split.
- **Devices:** Apple Intelligence hardware only — iPhone 15 Pro and later. Runtime
  `SystemLanguageModel.default.availability` gates cleanly (three unavailable reasons).
- **Text-only on iOS 26.** PDFs → PDFKit text extraction; scanned PDFs → Vision's new
  `RecognizeDocumentsRequest` (on-device OCR **with table structure** — ideal for coach
  plans). iOS 27 adds image input + an OCR system tool to the model itself.
- **Quality:** entity extraction is its wheelhouse, but it's not Claude — expect misreads
  on messy coach prose. Our deterministic validators + escalation carry that (see below).
  WWDC26 shipped an **Evaluations framework** + `fm` CLI to measure on real plans first.
- **Speed:** ~30 tok/s on iPhone 15 Pro → a full 12-week plan could take 1.5–4 min locally
  vs ~30 s via Claude. Mitigate: per-week streaming UI, prewarmed sessions, cloud as the
  "fast" option. Single workouts are near-instant. **Benchmark before committing UX.**

## The kicker (WWDC26)

iOS 27 adds a **`LanguageModel` protocol** — and Anthropic ships an official
**`ClaudeForFoundationModels`** Swift package implementing it, including a
**`.proxied(headers:baseURL:)` mode built for exactly our Cloudflare worker** (key stays
server-side). Local model and Claude sit behind the SAME `LanguageModelSession` +
@Generable types: one code path, two engines. Apple also offers
`PrivateCloudComputeLanguageModel` (32k context, free tier <2M downloads) as a possible
middle tier that keeps the Apple-privacy story.

## Recommended architecture (matches our existing validator-escalation pattern)

1. Single workout description → on-device, @Generable → `WorkoutSegment`s.
2. Pasted plan → regex week-splitter → one local session per week → validators →
   **only failing weeks escalate to Claude** via the proxy.
3. PDF → PDFKit / Vision OCR → route as text; only hostile PDFs go to Claude vision.
4. Model unavailable (old device/OS, AI off, downloading) → current cloud path unchanged.

## Strategic wins

- The **5.1.2(i) AI-consent gate stops applying to the default path** — consent becomes an
  opt-in escalation ("parse this tricky week in the cloud?"), not a gate on the core flow.
- Zero marginal API cost for most parses; works offline; "your plan never leaves your
  phone" becomes literally true by default — a marketing line, not just compliance.
- Deployment target stays iOS 17: weak-link the framework, `#available(iOS 26)` +
  runtime availability check (two-axis fallback: old OS → cloud; new OS old device → cloud).

## Effort

Prototype 2–4 days (mirror schema as @Generable, `LocalPlanParser` behind the parser
protocol, week chunker, eval on 20–30 real plans). Production +1–2 weeks (gating UI,
streaming progress, OCR path, consent-as-escalation, success telemetry). iOS 27 follow-up
a few days (8k window, ClaudeForFoundationModels unification, PCC evaluation).

Key sources: developer.apple.com/documentation/foundationmodels · WWDC25 #301 · WWDC26
#241 & #339 · machinelearning.apple.com tech report 2025 ·
github.com/anthropics/ClaudeForFoundationModels · support.apple.com/121115 (device list)
