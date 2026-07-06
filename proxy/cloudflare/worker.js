// PaceSync → Anthropic API proxy (Cloudflare Worker).
//
// Same job as the Netlify version (proxy/netlify/functions/anthropic.mjs): holds the
// Anthropic key server-side and forwards /v1/messages, gated by a shared app token.
//
// Why Cloudflare instead of Netlify: a Worker awaiting a fetch() to Anthropic is I/O,
// not CPU time, so it can stay open for the full length of a long Claude call (PDF
// transcription runs ~27s/page). Netlify's synchronous functions cap at ~30s, which
// is too tight for native-PDF transcription.
//
// Secrets (set with `wrangler secret put <NAME>`, never committed):
//   ANTHROPIC_API_KEY  — the real Anthropic key
//   APP_SHARED_TOKEN   — the token the app sends in x-app-token

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";

const ALLOWED_MODELS = new Set([
  "claude-sonnet-4-6",
  "claude-opus-4-8",
  "claude-haiku-4-5-20251001",
]);

function json(status, obj) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json" },
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/v1/messages") {
      return json(404, { error: { type: "not_found", message: "Unknown path" } });
    }
    if (request.method !== "POST") {
      return json(405, { error: { type: "method_not_allowed", message: "Use POST" } });
    }

    // 1) Gate access with the shared app token.
    if (!env.APP_SHARED_TOKEN || request.headers.get("x-app-token") !== env.APP_SHARED_TOKEN) {
      return json(401, { error: { type: "unauthorized", message: "Invalid or missing app token" } });
    }

    // 1a) Body-size cap — the app token is client-embedded and therefore extractable, so the real
    //     defence against a drained bill is limiting abuse here, not token secrecy. Reject oversized
    //     bodies before spending any upstream tokens.
    const MAX_BODY_BYTES = 3_000_000; // ~3 MB (a big PDF's transcribed markdown is well under this)
    if (Number(request.headers.get("content-length") || 0) > MAX_BODY_BYTES) {
      return json(413, { error: { type: "too_large", message: "Request body too large" } });
    }

    // 1b) Daily request caps (per-IP + a global ceiling), so a leaked token can't run up the bill.
    //     Requires a KV namespace bound as RATE_KV (see cloudflare/README). No-ops if unbound.
    if (env.RATE_KV) {
      const day = new Date().toISOString().slice(0, 10);
      const ip = request.headers.get("cf-connecting-ip") || "unknown";
      const perIpCap = Number(env.DAILY_IP_CAP || 200);
      const globalCap = Number(env.DAILY_GLOBAL_CAP || 5000);
      const ipKey = `rl:ip:${ip}:${day}`;
      const allKey = `rl:all:${day}`;
      const [ipRaw, allRaw] = await Promise.all([env.RATE_KV.get(ipKey), env.RATE_KV.get(allKey)]);
      const ipCount = Number(ipRaw || 0);
      const allCount = Number(allRaw || 0);
      if (ipCount >= perIpCap || allCount >= globalCap) {
        return json(429, { error: { type: "rate_limited", message: "Daily request limit reached — try again tomorrow." } });
      }
      // Best-effort increment (2-day TTL so keys self-expire). Approximate under high concurrency,
      // which is fine for a billing guard.
      await Promise.all([
        env.RATE_KV.put(ipKey, String(ipCount + 1), { expirationTtl: 172_800 }),
        env.RATE_KV.put(allKey, String(allCount + 1), { expirationTtl: 172_800 }),
      ]);
    }

    // 2) Server-held Anthropic key.
    if (!env.ANTHROPIC_API_KEY) {
      return json(500, { error: { type: "config_error", message: "Server is missing ANTHROPIC_API_KEY" } });
    }

    // 3) Parse + lightly validate the body.
    let body;
    try {
      body = await request.json();
    } catch {
      return json(400, { error: { type: "bad_request", message: "Body must be valid JSON" } });
    }
    if (typeof body?.model === "string" && !ALLOWED_MODELS.has(body.model)) {
      return json(400, { error: { type: "model_not_allowed", message: `Model ${body.model} is not permitted` } });
    }

    // 4) Forward to Anthropic with the real key attached server-side.
    let upstream;
    try {
      upstream = await fetch(ANTHROPIC_URL, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-api-key": env.ANTHROPIC_API_KEY,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify(body),
      });
    } catch (e) {
      return json(502, { error: { type: "upstream_unreachable", message: String(e) } });
    }

    // 5) Pass the upstream response straight through (status preserved so the app's
    //    429/529 retry logic keeps working).
    const text = await upstream.text();
    return new Response(text, {
      status: upstream.status,
      headers: { "content-type": "application/json" },
    });
  },
};
