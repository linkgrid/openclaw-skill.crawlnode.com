---
name: crawlnode
description: >
  Operate a remote browser to navigate websites, interact with page elements,
  fill forms, extract content, and capture screenshots using the CrawlNode
  distributed browser API. Use this skill whenever the user mentions
  "crawlnode" or asks to use a live browser to interact with a website
  (e.g. browse, click, fill forms, scrape dynamic content, take screenshots,
  automate a web workflow). Also use for any task requiring a real browser
  with JavaScript, cookies, or UI automation.
user-invocable: true
metadata: {"openclaw": {"requires": {"env": ["CRAWLNODE_TOKEN", "PASSIMAGE_FILES_API_KEY"]}, "primaryEnv": "CRAWLNODE_TOKEN"}}
---

# CrawlNode remote browser

Use the **exec** tool to run `curl` against the CrawlNode HTTP API. Never log or echo the values of `CRAWLNODE_TOKEN` or `PASSIMAGE_FILES_API_KEY`. Use `$CRAWLNODE_TOKEN` and `$PASSIMAGE_FILES_API_KEY` in shell only (the environment is injected per OpenClaw agent run when configured).

## When to use

**Always** use this skill when:

- The user mentions **"crawlnode"** (any casing) in their request
- The user asks to **use a live browser** to visit, interact with, or automate a website
- The task requires a **real browser** (JavaScript execution, cookies, UI automation)
- The user needs navigation, clicking, typing, drag (sliders/captchas)
- The user needs screenshots of a live web page for verification or reporting
- The user needs captured network traffic from a browser session

Do **not** use this skill for simple static HTTP GET/POST where no browser is required—use a direct HTTP client instead.

## Environment

| Item | Value |
|------|--------|
| Base URL | `http://api1.crawlnode.com` (if requests fail, try `:8000` per CrawlNode docs) |
| Auth | Header `Token: <value from env CRAWLNODE_TOKEN>` on every request |
| Session | After `/api/start`, send header `X-Session-Id: <session_id>` on all other endpoints |
| JSON POSTs | `Content-Type: application/json` |
| Screenshot uploads | `https://s.passimage.in` (base URL for uploads, no trailing slash) and `PASSIMAGE_FILES_API_KEY` (sent as `X-API-Key`) |

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

> **Mandatory rule — screenshot → upload → share.**
> Every time you take a screenshot you **must** upload it and share the
> public URL with the user. There are no exceptions. See the combined
> example below.

#### When to screenshot

Take a screenshot **immediately** after any of these events once the page has settled:

- **POST /api/go** (navigation)
- **POST /api/refresh**
- **POST /api/click** or **POST /api/input** that triggers a visible page change (new content, modal, navigation)
- **POST /api/solve_captcha** or **POST /api/drag** that alters the view
- Session start (first page load)
- Before reporting an error to the user (if the session is still alive)

When in doubt, screenshot. The cost of an extra screenshot is low; the cost of the user not seeing the current page is high.

#### Combined example (capture → upload → share)

```bash
# 1. Capture
curl -sS -X POST "http://api1.crawlnode.com/api/screenshot" \
  -H "Token: $CRAWLNODE_TOKEN" \
  -H "X-Session-Id: SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{}' \
  --output /tmp/crawlnode-screenshot.png

# 2. Upload — response is the public URL as plain text, e.g.:
#    https://s.passimage.in/f/8d5ee2e3d5c3.png
SCREENSHOT_URL=$(curl -s -X POST "https://s.passimage.in/upload" \
  -H "X-API-Key: $PASSIMAGE_FILES_API_KEY" \
  -H "Content-Type: image/png" \
  -H "X-Filename: crawlnode-screenshot.png" \
  --data-binary "@/tmp/crawlnode-screenshot.png")

# 3. Share — include $SCREENSHOT_URL in your reply (see format below)
echo "$SCREENSHOT_URL"
```

Always include the returned URL in your **very next reply** to the user. If the upload fails, retry once; if it still fails, tell the user the upload failed and continue.

#### How to present screenshots to the user

After every action, report what you did and append the screenshot URL in parentheses on the same line. Examples:

```
- Navigated to: https://www.vinaudit.com (https://s.passimage.in/f/8d5ee2e3d5c3.png)
- Clicked the button "[VIN SEARCH]" (https://s.passimage.in/f/8d5ee2e3d5c4.png)
```

Format: `- <action description> (<screenshot URL>)`

Each action that changes the page gets its own line with its own screenshot. This gives the user a visual step-by-step log of everything that happened.

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

Repeat for each page state:

1. **Screenshot → upload → share** the current page (see **Screen capture**). This is the first thing you do after any navigation or visible page change so the user always has an up-to-date view.
2. **POST /api/view** to refresh the element tree.
3. Choose **`automation_id` over `element_id`** when both exist and the automation id is stable.
4. **POST /api/click**, **POST /api/input**, or **POST /api/drag** as required.
5. If the action caused a visible change, go back to step 1.
6. Allow a short pause between steps when the page is loading or animating.

After **POST /api/go**, wait for navigation to settle, then start at step 1 (screenshot → upload → share) before doing anything else.

## Execution strategy

These rules help you complete tasks efficiently and avoid common failure modes.

### Navigation

- If the user provides a URL, navigate directly to it with `/api/go`. Do not detour through a search engine first.
- If the task requires finding something and no URL is given, use a search engine through CrawlNode. After the results page loads, inspect the `/api/view` tree for result links. If clicking a result element fails, extract the destination URL from the element's `name` or `path` and navigate to it directly with `/api/go`.
- After every `/api/go`, take a screenshot and verify the page loaded as expected. If you see a 404 page, an error, a redirect to an unexpected page, or a blank screen, try the site's root URL (e.g. `https://example.com/`) before attempting any interaction.

### Element identification

- Always call `/api/view` before interacting with a page. Never reuse element identifiers from a previous page state.
- Search the view tree systematically: look for `control_type` values like `EditControl` (text fields), `ButtonControl` (buttons), and `HyperlinkControl` (links). Match by `name`, `automation_id`, or position.
- When `automation_id` and `element_id` are both available, prefer `automation_id` — it is more stable across page reloads.
- If the view tree does not clearly expose the target element, try these fallbacks in order: (a) look for coordinate-based `element_id` values near the expected screen region, (b) use `/api/network` to discover form endpoints and submit data directly, (c) resize the window with `/api/resize` and re-fetch `/api/view` — some elements only appear at certain viewport sizes.

### Session validation

- After `/api/start`, immediately verify the response contains a non-empty `session_id`. If the field is missing or empty, retry the call once. If it still fails, report the raw API response to the user and stop.
- If any API call returns a 500 or 520 error mid-workflow, take a screenshot (if the session is still alive), destroy the session, start a fresh one, and retry the failed step once before reporting failure.

### Script structure

- Keep each `exec` call focused on a single logical step: start a session, navigate to a page, interact with an element, or take a screenshot. Avoid writing a single monolithic script that does everything — if one step fails in a large script, the error is harder to diagnose and recover from.
- Use a cleanup trap (`trap cleanup EXIT`) in every script that creates a session, so `/api/destroy` is always called even if the script fails partway through.
- Store intermediate results (view trees, screenshots) in a temporary directory and clean up after.

### Retries and failure limits

- Do not retry the same failing approach more than twice. If an action fails twice with the same method, switch to a different strategy (e.g. different element identifier, different navigation path, or different viewport size).
- After three different strategies have failed for the same step, stop. Report what you attempted, include screenshots of each failed state, and let the user decide how to proceed.
- Never loop indefinitely. If you are unsure whether an action succeeded, take a screenshot and verify visually before continuing.

### Efficiency

- Resize the browser window to a standard desktop size (e.g. `1440×1200`) early in the session with `/api/resize`. This ensures consistent element layout and avoids mobile or responsive views that may hide elements.
- Allow 3–5 seconds after `/api/go` or any action that triggers page navigation before taking a screenshot or calling `/api/view`. Pages with JavaScript may need time to render.
- When the task involves multiple pages, complete all actions on one page before navigating to the next. Do not jump back and forth between pages unnecessarily.

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

Before reporting a failure to the user, run the full **screenshot → upload → share** sequence (see **Screen capture**) when the session may still be alive, so the user can see what the remote browser showed.

## Important rules

- Always call **/api/view** before relying on element identifiers; the tree changes after navigation and DOM updates.
- Prefer **automation_id** over **element_id** when practical.
- Always **/api/destroy** when done.
- Enable **extension: true** only when network capture is needed.
- **Every screenshot must be uploaded and shared.** Save with `--output`, upload via Passimage, and include the public URL in your reply. No exceptions — never take a screenshot without uploading and sharing it.
- Do not embed user-controlled strings directly into shell commands without proper quoting/escaping—prefer writing JSON bodies via a here-doc or a safely quoted file to avoid injection.
- For full schemas and examples, see `docs/CRAWLNODE-API-DOCUMENTATION.md` in this repository.
