// PaceSync → Anthropic API proxy (Netlify Function).
//
// Why this exists: the Anthropic API key must NOT ship inside the iOS app binary
// (it is trivially extractable). This function holds the key server-side as an
// environment variable and forwards the app's parse requests to Anthropic.
//
// Access is gated by a shared app token so random callers can't burn your quota.
// (A per-user auth model can replace the shared token later — see README.)
//
// Endpoint (after deploy): https://<your-site>.netlify.app/v1/messages

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";

// Only allow the models the app actually uses — defense against someone using
// the proxy to call expensive models on your account.
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

export default async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: { type: "method_not_allowed", message: "Use POST" } });
  }

  // 1) Gate access with the shared app token.
  const expected = process.env.APP_SHARED_TOKEN;
  const provided = req.headers.get("x-app-token");
  if (!expected || provided !== expected) {
    return json(401, { error: { type: "unauthorized", message: "Invalid or missing app token" } });
  }

  // 2) Server-held Anthropic key.
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    return json(500, { error: { type: "config_error", message: "Server is missing ANTHROPIC_API_KEY" } });
  }

  // 3) Parse + lightly validate the body.
  let body;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: { type: "bad_request", message: "Body must be valid JSON" } });
  }
  if (typeof body?.model === "string" && !ALLOWED_MODELS.has(body.model)) {
    return json(400, { error: { type: "model_not_allowed", message: `Model ${body.model} is not permitted by this proxy` } });
  }

  // 4) Forward to Anthropic with the real key attached server-side.
  let upstream;
  try {
    upstream = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify(body),
    });
  } catch (e) {
    return json(502, { error: { type: "upstream_unreachable", message: String(e) } });
  }

  // 5) Pass the upstream response straight through (status + body preserved so
  //    the app's existing 429/529 retry logic keeps working).
  const text = await upstream.text();
  return new Response(text, {
    status: upstream.status,
    headers: { "content-type": "application/json" },
  });
};

// Route this function at /v1/messages so the app's base URL is just the site root.
export const config = { path: "/v1/messages" };
