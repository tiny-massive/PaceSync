# PaceSync proxy — Cloudflare Worker

Same proxy as the Netlify version, but on Cloudflare Workers, which can stay open for the
full length of a long Claude call. We need this because **native-PDF transcription runs
~27s per page** and Netlify's synchronous functions cap at ~30s (empirically verified:
1 page = 27s on Netlify with no margin; 2 pages time out).

## Deploy (one-time)

> Never paste the Anthropic key into chat. `wrangler secret put` prompts for the value
> interactively, so it stays out of shell history.

1. Install + log in:
   ```sh
   npm install -g wrangler
   wrangler login
   ```
2. From this folder, set the two secrets (paste the value when prompted):
   ```sh
   cd proxy/cloudflare
   wrangler secret put ANTHROPIC_API_KEY     # paste your Anthropic key
   wrangler secret put APP_SHARED_TOKEN       # paste: ROTATED-OLD-APP-TOKEN
   ```
3. Deploy:
   ```sh
   wrangler deploy
   ```
   It prints a URL like `https://pacesync-proxy.<your-subdomain>.workers.dev`.
4. **Send me that URL** and I'll point the app at `https://…workers.dev/v1/messages`
   (a one-line change to `Secrets.proxyURL`).

## Test it

```sh
curl -sS https://pacesync-proxy.<your-subdomain>.workers.dev/v1/messages \
  -H "content-type: application/json" \
  -H "x-app-token: ROTATED-OLD-APP-TOKEN" \
  -d '{"model":"claude-sonnet-4-6","max_tokens":64,"messages":[{"role":"user","content":"say hi"}]}'
```

Once it's live we can also retire the Netlify site (or keep it as a backup — the app only
points at one URL at a time).
