---
name: crawlnode
description: >
  Operate a remote browser to navigate websites, interact with page elements,
  fill forms, extract content, and capture screenshots using the CrawlNode
  distributed browser API. Use when the user needs browser automation,
  web scraping, or any task requiring a real browser.
user-invocable: true
metadata: {"openclaw": {"requires": {"env": ["CRAWLNODE_TOKEN"]}, "primaryEnv": "CRAWLNODE_TOKEN"}}
---

# CrawlNode remote browser

Use the **exec** tool to run `curl` against the CrawlNode HTTP API. Never log or echo the value of `CRAWLNODE_TOKEN`. Use `$CRAWLNODE_TOKEN` in shell only (the environment is injected per OpenClaw agent run when configured).

## When to use

Use this skill when the user needs:

- A real browser (JavaScript, cookies, UI automation)
- Navigation, clicking, typing, drag (sliders/captchas)
- Screenshots for verification or reporting
- Captured network traffic (when `extension: true` was used at session start)

Do **not** use this skill for simple static HTTP GET/POST where no browser is required—use a direct HTTP client instead.

## Environment

| Item | Value |
|------|--------|
| Base URL | `http://api1.crawlnode.com` (if requests fail, try `:8000` per CrawlNode docs) |
| Auth | Header `Token: <value from env CRAWLNODE_TOKEN>` on every request |
| Session | After `/api/start`, send header `X-Session-Id: <session_id>` on all other endpoints |
| JSON POSTs | `Content-Type: application/json` |

Store `session_id` from the JSON body (and/or `X-Session-Id` response header) and reuse it for the whole workflow.

## Session lifecycle (mandatory)

1. **Start**: `POST /api/start` → obtain `session_id`.
2. **Work**: All other calls include `Token` + `X-Session-Id` + JSON body as documented below.
3. **Destroy**: Always call `POST /api/destroy` when finished, including after errors. Remote browsers consume node resources until destroyed.
4. **Recovery**: If the session errors repeatedly (Chrome closed, timeouts), call `/api/destroy` if possible, then `/api/start` again.

Treat cleanup like a `finally` block: if something fails mid-task, still attempt `/api/destroy` with the last known `session_id`.

## API reference (curl via exec)

Replace `SESSION_ID` with the active session. Use environment expansion for the token, e.g. `-H "Token: $CRAWLNODE_TOKEN"` in bash.

### Session management

**POST /api/start** — create or reuse session.

```bash
curl -sS -X POST "http://api1.crawlnode.com/api/start" \
  -H "Token: $CRAWLNODE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"proxy":"auto","extension":false}'
```

Body fields (all optional unless noted):

- `session_id` — reuse existing session
- `proxy` — omit or empty for none; `"auto"` for pool; or `user:pass@host:port`
- `extension` — `true` only when you need `/api/network` and `/api/download` capture

**POST /api/destroy** — end session (requires `X-Session-Id`).

```bash
curl -sS -X POST "http://api1.crawlnode.com/api/destroy" \
  -H "Token: $CRAWLNODE_TOKEN" \
  -H "X-Session-Id: SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{}'
```

**POST /api/clear** — clear cookies/cache for the session.

```bash
curl -sS -X POST "http://api1.crawlnode.com/api/clear" \
  -H "Token: $CRAWLNODE_TOKEN" \
  -H "X-Session-Id: SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{}'
```

### Navigation

**POST /api/go**

```bash
curl -sS -X POST "http://api1.crawlnode.com/api/go" \
  -H "Token: $CRAWLNODE_TOKEN" \
  -H "X-Session-Id: SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{"url":"https://www.example.com"}'
```

**POST /api/refresh** — body `{}`.

### Window management

**POST /api/maximize** — body `{}`.

**POST /api/minimize** — body `{}`.

**POST /api/resize**

```bash
curl -sS -X POST "http://api1.crawlnode.com/api/resize" \
  -H "Token: $CRAWLNODE_TOKEN" \
  -H "X-Session-Id: SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{"width":1280,"height":720,"x":100,"y":100}'
```

### Page interaction

**POST /api/view** — returns UI tree with `elements` (root node with `children`). Each node may include:

- `element_id` — e.g. `100_50_200_80` (coordinate-based)
- `automation_id` — preferred when stable
- `name`, `control_type`, `rectangle`, `isEnabled`, `path`, `children`

**POST /api/click** — one of `element_id` or `automation_id`:

```bash
curl -sS -X POST "http://api1.crawlnode.com/api/click" \
  -H "Token: $CRAWLNODE_TOKEN" \
  -H "X-Session-Id: SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{"automation_id":"submitBtn"}'
```

**POST /api/input** — `keys` required; target via `element_id` or `automation_id`:

```bash
curl -sS -X POST "http://api1.crawlnode.com/api/input" \
  -H "Token: $CRAWLNODE_TOKEN" \
  -H "X-Session-Id: SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{"element_id":"200_100_400_130","keys":"hello{tab}world{enter}"}'
```

Special key tokens in `keys` include `{tab}`, `{enter}`, `{ctrl}`, `{alt}`, `{shift}`, `{backspace}`, `{delete}`.

**POST /api/drag** — path of `[x,y]` points and `interval` ms between points:

```bash
curl -sS -X POST "http://api1.crawlnode.com/api/drag" \
  -H "Token: $CRAWLNODE_TOKEN" \
  -H "X-Session-Id: SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{"path":[[100,200],[200,200]],"interval":50}'
```

### Screen capture

**POST /api/screenshot** — response body is **PNG binary** (`image/png`). Save to a file; do not paste raw bytes into chat.

```bash
curl -sS -X POST "http://api1.crawlnode.com/api/screenshot" \
  -H "Token: $CRAWLNODE_TOKEN" \
  -H "X-Session-Id: SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{}' \
  --output /tmp/crawlnode-screenshot.png
```

Take screenshots after important actions when the user needs verification; avoid excessive screenshots (large payloads).

### Network traffic

Requires starting the session with `"extension": true`.

**POST /api/network** — list captured requests (JSON array with `request_id`, `url`, `status_code`, etc.).

**POST /api/download** — raw HTTP bodies as base64:

```bash
curl -sS -X POST "http://api1.crawlnode.com/api/download" \
  -H "Token: $CRAWLNODE_TOKEN" \
  -H "X-Session-Id: SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{"request_id":2}'
```

Decode `request` and `response` fields from base64 when you need plain text (e.g. with a small script or `base64 -d`), without logging secrets.

### Advanced

**POST /api/solve_captcha** — body `{}`; may return `success`, `distance`, `slide_from`, `slide_to`. Use when a slider captcha blocks progress; combine with `/api/drag` as needed.

## Interaction workflow

For each page state:

1. **POST /api/view** to refresh the element tree.
2. Choose **`automation_id` over `element_id`** when both exist and the automation id is stable.
3. **POST /api/click** or **POST /api/input** (or **POST /api/drag**) as required.
4. **POST /api/screenshot** to a temp file to verify layout or report back.
5. Allow a short pause between steps when the page is loading or animating.

After **POST /api/go**, wait for navigation to settle before **/api/view** if the page is slow or dynamic.

## Network traffic extraction

1. Start session with `"extension": true` **only** if network capture is required.
2. After navigation and actions, **POST /api/network** to list `request_id` values.
3. **POST /api/download** per `request_id` to inspect raw request/response (base64).

## Error handling

| HTTP | Layer | What to do |
|------|--------|------------|
| 200 | — | Success |
| 500 | Agent | Chrome/UI automation error—screenshot if possible, then destroy session and consider new session |
| 510 | DispatcherClient | Proxy/forwarding—retry with exponential backoff (e.g. 2s, 4s), limited attempts |
| 520 | DispatcherServer | Auth, missing `X-Session-Id`, routing—verify token and headers; create a new session if session is invalid |

JSON errors often look like: `{"detail":"..."}`. Plain-text errors are possible (e.g. invalid token).

Before reporting a failure to the user, capture **POST /api/screenshot** to a file when the session may still be alive, so the user can see what the remote browser showed.

## Important rules

- Always call **/api/view** before relying on element identifiers; the tree changes after navigation and DOM updates.
- Prefer **automation_id** over **element_id** when practical.
- Always **/api/destroy** when done.
- Enable **extension: true** only when network capture is needed.
- Save screenshots with **curl `--output`** (or equivalent); never inline binary PNG in messages.
- Do not embed user-controlled strings directly into shell commands without proper quoting/escaping—prefer writing JSON bodies via a here-doc or a safely quoted file to avoid injection.
- For full schemas and examples, see `docs/CRAWLNODE-API-DOCUMENTATION.md` in this repository.
