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

function page(title, bodyHtml) {
  return new Response(
    `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>
body{font:16px/1.6 -apple-system,system-ui,sans-serif;max-width:640px;margin:0 auto;padding:32px 20px;color:#1b1d1f;background:#f5f6f7}
h1{font-size:24px}h2{font-size:17px;margin-top:28px}a{color:#0f8a4c}
@media(prefers-color-scheme:dark){body{color:#f2f2f7;background:#1c1c1e}a{color:#35d07f}}
</style></head><body>${bodyHtml}</body></html>`,
    { headers: { "content-type": "text/html; charset=utf-8" } });
}

const PRIVACY_HTML = `
<h1>PaceSync Privacy Policy</h1>
<p><em>Effective 13 July 2026 · Schoolwork Studio (Pty) Ltd</em></p>
<p>PaceSync turns a running training plan into scheduled workouts on your Apple Watch
and calendar. It is built to keep your data on your phone.</p>
<h2>What leaves your device</h2>
<p>One thing only: the <strong>training-plan text you choose to import</strong> (pasted text,
an uploaded PDF, or a workout description you type). With your explicit permission — asked
once, before the first import — it is sent over an encrypted connection to our server and
forwarded to <strong>Anthropic's Claude API</strong>, which converts it into structured workouts.
Anthropic retains API inputs and outputs for up to about 30 days for abuse monitoring, then
deletes them (see Anthropic's privacy documentation). We attach no name, email, account, or
device identifier — PaceSync has no accounts.</p>
<h2>What never leaves your device</h2>
<ul>
<li><strong>Health data.</strong> PaceSync reads completed workouts from HealthKit only to tick
off matching runs in your plan, entirely on your phone. Health data is never sent to us, to
Anthropic, or to anyone else, and is never used for advertising.</li>
<li><strong>Calendar.</strong> Events are created in a dedicated “PaceSync” calendar directly
on your phone via Apple's EventKit.</li>
<li><strong>Your plans and settings.</strong> Stored on-device, with an optional backup in
your personal iCloud (Apple's key-value storage) that only you can access.</li>
</ul>
<h2>What we don't do</h2>
<p>No analytics, no tracking, no ads, no accounts, no sale or sharing of data. Our server
keeps short-lived request counters (by IP address, deleted within 48 hours) purely to
prevent abuse.</p>
<h2>Your choices</h2>
<p>You can decline AI parsing (the app just won't be able to convert plans), delete any plan
in the app (which also removes its calendar events), and revoke Health or Calendar access in
iOS Settings at any time.</p>
<h2>Contact</h2>
<p><a href="mailto:bernhardt@schoolwork.studio">bernhardt@schoolwork.studio</a></p>`;

const SUPPORT_HTML = `
<h1>PaceSync Support</h1>
<p>PaceSync gets complex running workouts onto your Apple Watch without building them by
hand — describe a workout or upload a plan, and it syncs to the native Workout app.</p>
<h2>Common questions</h2>
<p><strong>My workout isn't on my Watch.</strong> Open the workout in PaceSync and tap
“Sync to Watch”, then check the Workout app on the Watch for that day. Scheduling requires
watchOS 11 or later and Health access.</p>
<p><strong>My plan didn't parse correctly.</strong> Plans with a clear week-by-week layout
parse best. Try “Re-import” from the plan's menu, or paste the plan as text.</p>
<p><strong>Restore my plans.</strong> Settings → Backup → Restore from file, or reinstall —
plans back up automatically to your iCloud.</p>
<h2>Get in touch</h2>
<p>Email <a href="mailto:bernhardt@schoolwork.studio">bernhardt@schoolwork.studio</a> —
include your iOS version and a screenshot if something looks wrong.</p>
<p><a href="/privacy">Privacy Policy</a></p>`;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    // Public pages (required App Store listing URLs) — no token needed.
    if (request.method === "GET" && url.pathname === "/privacy") {
      return page("PaceSync Privacy Policy", PRIVACY_HTML);
    }
    if (request.method === "GET" && url.pathname === "/support") {
      return page("PaceSync Support", SUPPORT_HTML);
    }
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
