# PaceSync API Proxy

A tiny Netlify Function that holds the Anthropic API key **server-side** and forwards
PaceSync's parse requests to `https://api.anthropic.com/v1/messages`. This is what lets us
remove the embedded key from the app binary (the #1 security issue).

Access is gated by a shared **app token** so only the PaceSync app can use it.

## Deploy (one-time)

> **Never paste the Anthropic key into the terminal or share it in chat.** Set it in the
> Netlify UI so it stays out of shell history and out of this repo.

1. **Create a NEW Anthropic key** at <https://console.anthropic.com/settings/keys>
   (this replaces the compromised one that shipped in the app — see step 6 to revoke the old one).
2. In Netlify: **Add new site → Import / deploy** this `proxy/` folder (or run `netlify init` from
   inside `proxy/` if you use the CLI).
3. In **Site settings → Environment variables**, add two variables:
   - `ANTHROPIC_API_KEY` = your new `sk-ant-...` key
   - `APP_SHARED_TOKEN`  = a long random string you generate (e.g. `openssl rand -hex 24`).
     This is the token the app sends to prove it's allowed to use the proxy.
4. Deploy. Your endpoint will be `https://<your-site>.netlify.app/v1/messages`.
5. **Give me the site URL and the `APP_SHARED_TOKEN`** (the token is fine to share — it only
   permits using *your* rate-limited proxy and is rotatable; the Anthropic key is NOT) and I'll
   flip the app over to the proxy and delete `Secrets.swift`.
6. Once the app is on the proxy and verified, **revoke the old key** in the Anthropic console.

## Test it

```sh
curl -sS https://<your-site>.netlify.app/v1/messages \
  -H "content-type: application/json" \
  -H "x-app-token: <APP_SHARED_TOKEN>" \
  -d '{"model":"claude-sonnet-4-6","max_tokens":64,"messages":[{"role":"user","content":"say hi"}]}'
```

A 401 means the token is wrong; a normal Anthropic JSON response means it works.

## What changes in the app (I'll do this once the proxy is live)

In `ClaudeParserService.callClaude(...)`:
- Point `apiURL` at `https://<your-site>.netlify.app/v1/messages`.
- Send `x-app-token: <APP_SHARED_TOKEN>` instead of `x-api-key`.
- Drop the `x-api-key` / `anthropic-version` headers (the proxy adds them) and delete `Secrets.swift`.

The shared app token embedded in the app is acceptable for TestFlight (low blast radius, rotatable).
A per-user auth model (e.g. Sign in with Apple → short-lived tokens) can replace it before a wide
public launch.

## Alternative host

This function is plain `fetch` and ports to a Cloudflare Worker almost verbatim if you'd rather
use Cloudflare — say the word and I'll add a `worker.js` variant.
