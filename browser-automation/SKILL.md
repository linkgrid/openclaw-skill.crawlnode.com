---
name: browser-automation
description: >
  ROUTING RULE: Only use this skill when the user does NOT mention "crawlnode".
  If the user says "crawlnode", you MUST use the CrawlNode skill instead.
  Automate a real local browser (Playwright + Chromium headless) to navigate
  websites, fill forms, click elements, extract content, and capture screenshots
  using OpenClaw's built-in browser tool. Use when the user asks to browse or
  automate a website without specifying crawlnode, or asks for "browser automation",
  "Playwright", or "local browser".
user-invocable: true
metadata: {"openclaw": {"requires": {"env": ["PASSIMAGE_FILES_API_KEY"]}, "primaryEnv": ""}}
---

# Browser Automation (built-in)

Use the **browser** tool to control OpenClaw's local Chromium browser. Do **not** use the `exec` tool for browser actions — the `browser` tool handles everything directly. Only use `exec` for uploading screenshots to Passimage.

## When to use

Use this skill when:

- The user asks to **browse a website**, **fill a form**, **click buttons**, **extract text**, or **take a screenshot** — and does **not** mention "crawlnode".
- The user explicitly asks for **browser automation**, **Playwright**, or **local browser**.
- CrawlNode is unavailable or has failed, and the user wants a fallback.

Do **not** use this skill when:

- The user specifically mentions **"crawlnode"** — use the CrawlNode skill instead.
- The task is a simple HTTP GET/POST that does not need a real browser — use `web_fetch` instead.

## Core workflow (follow this order every time)

### 1. Navigate

```json
{ "tool": "browser", "action": "navigate", "params": { "url": "https://example.com" } }
```

After navigating, wait for the page to settle. If the page uses heavy JavaScript, add a short wait:

```json
{ "tool": "browser", "action": "wait", "params": { "milliseconds": 3000 } }
```

### 2. Snapshot (get element refs)

```json
{ "tool": "browser", "action": "snapshot" }
```

The snapshot returns a text tree of everything on the page. Each interactive element has a **ref** like `e3`, `e12`, etc. You **must** take a fresh snapshot before every interaction — refs change after navigation and page updates.

### 3. Interact (click, type, fill)

Use the **ref** from the snapshot to target elements:

**Click:**
```json
{ "tool": "browser", "action": "click", "params": { "ref": "e12" } }
```

**Type into a field:**
```json
{ "tool": "browser", "action": "type", "params": { "ref": "e5", "text": "hello world" } }
```

**Fill a field (clears first, then types):**
```json
{ "tool": "browser", "action": "fill", "params": { "ref": "e5", "text": "hello world" } }
```

**Press a key:**
```json
{ "tool": "browser", "action": "press", "params": { "key": "Enter" } }
```

### 4. Screenshot — capture, upload, share (mandatory)

> **Mandatory rule — screenshot → upload → share.**
> Every time you take a screenshot you **must** upload it and share the
> public URL with the user. There are no exceptions.

```json
{ "tool": "browser", "action": "screenshot" }
```

Take a screenshot after every navigation, click, or form submission that changes the page.

The browser tool returns a result containing the **local file path** where the screenshot was saved. Look for the `path` or `mediaUrl` field in the result — it will be something like:

```
/home/autoscale/.openclaw/media/browser/eb0555ad-87db-4d21-bf8c-7cf794f83277.png
```

**You MUST use this exact file path to upload to Passimage.** Do NOT try to re-capture the screenshot via the CLI or redirect stdout. The browser tool already saved the file — just upload it.

#### Combined example (capture → upload → share)

```bash
# 1. The browser tool screenshot action already saved the file.
#    Get the path from the screenshot result (e.g. details.path or details.media.mediaUrl).
#    Example: /home/autoscale/.openclaw/media/browser/eb0555ad.png

# 2. Upload — use the file path from step 1:
SCREENSHOT_URL=$(curl -s -X POST "https://s.passimage.in/upload" \
  -H "X-API-Key: $PASSIMAGE_FILES_API_KEY" \
  -H "Content-Type: image/png" \
  -H "X-Filename: browser-screenshot.png" \
  --data-binary "@/home/autoscale/.openclaw/media/browser/eb0555ad.png")

# 3. Share — the response JSON has a "url" field. Include it in your reply.
echo "$SCREENSHOT_URL"
```

Always include the returned URL in your **very next reply** to the user. If the upload fails, retry once; if it still fails, tell the user the upload failed and continue.

#### How to present screenshots to the user

After every action that changes the page, report what you did and include the screenshot URL. Examples:

```
- Navigated to: https://www.example.com (https://s.passimage.in/f/abc123.png)
- Clicked the button "Submit" (https://s.passimage.in/f/def456.png)
- Filled VIN field and submitted (https://s.passimage.in/f/ghi789.png)
```

Format: `- <action description> (<screenshot URL>)`

#### When to screenshot

Take a screenshot **immediately** after:

- Navigation (`navigate` action)
- Any click or form submission that changes the page
- Before reporting an error to the user
- When in doubt — the cost of an extra screenshot is low

### 5. Extract text (when needed)

```json
{ "tool": "browser", "action": "extract_text", "params": { "selector": "div.results" } }
```

Or use JavaScript evaluation for structured data:

```json
{ "tool": "browser", "action": "evaluate", "params": { "script": "() => document.title" } }
```

## Interaction rules (mandatory)

1. **Always snapshot before interacting.** Never reuse refs from a previous snapshot — they become invalid after any page change.
2. **Use refs, not CSS selectors, for click/type/fill.** Refs from snapshots are more reliable.
3. **Screenshot after every visible change.** Navigation, clicks, form submissions — screenshot each time, upload to Passimage, and share the URL.
4. **Wait for dynamic content.** After navigation or clicks that trigger loading, wait 2-3 seconds before snapshotting. Use the wait action if needed.
5. **One action per tool call.** Do not try to batch multiple actions in one call.

## Finding elements in the snapshot

The snapshot tree shows elements like:

```
- textbox "Search" [ref=e5]
- button "Submit" [ref=e12]
- link "Sign in" [ref=e8] [cursor=pointer]
- heading "Results" [level=2] [ref=e15]
```

To find the right element:

- **Text fields / inputs**: Look for `textbox`, `searchbox`, or `combobox`.
- **Buttons**: Look for `button`.
- **Links**: Look for `link`.
- **Headings**: Look for `heading`.
- Match by the element's visible text (the part in quotes after the type).

If the element you need is not in the snapshot:

1. **Scroll down** — use `press` with `PageDown` key, then re-snapshot.
2. **Wait longer** — some elements load after JavaScript runs. Wait 3-5 seconds, then re-snapshot.
3. **Try evaluate** — use JavaScript to check if the element exists in the DOM: `() => !!document.querySelector('input[name="vin"]')`.

## Scrolling

There is no dedicated scroll action. Instead, use keyboard keys:

```json
{ "tool": "browser", "action": "press", "params": { "key": "PageDown" } }
```

Other useful scroll keys: `PageUp`, `ArrowDown`, `ArrowUp`, `Home`, `End`.

After scrolling, **always re-snapshot** to see the updated elements.

## Handling forms (step by step)

1. Navigate to the form page.
2. Wait 2-3 seconds for JavaScript to load.
3. Snapshot to find the form fields.
4. Click the first input field (by ref).
5. Fill or type the value.
6. Move to the next field (click its ref, or press Tab).
7. Fill or type the next value.
8. Click the submit button (by ref).
9. Wait 3-5 seconds for results.
10. Screenshot the result page → upload to Passimage → share URL.
11. Snapshot the result page and extract relevant text.

## Retry strategy

- If an action fails (element not found, timeout), **re-snapshot** and try with a fresh ref.
- If the same action fails twice, try a different approach: scroll, wait longer, or use a different element.
- After 3 failed attempts on the same step, **stop and report** what happened to the user with a screenshot.
- Never loop indefinitely.

## Error handling

| Situation | What to do |
|-----------|------------|
| Element ref not found | Re-snapshot, find the correct ref |
| Page didn't load | Wait 5 seconds, try navigate again |
| Timeout on action | Screenshot current state, retry once |
| Element not in snapshot | Scroll down (PageDown), re-snapshot |
| Form field not fillable | Try click first, then fill |
| Browser not running | Report to user — browser needs to be started |

## Final reply (mandatory — Slack-ready)

Your reply goes to Slack. Read the user's original request, then reply with what was done and what they asked for.

- **Answer the request.** If they asked for a screenshot, give them the screenshot URL. If they asked for data, give them the data. If they asked for both, give both.
- **Describe what you did, not how you did it.** The user does not care about tool calls, file paths, JSON, or internal mechanics. They care about the result.
- **Never include** `[[reply_to_current]]`, `[[...]]`, raw JSON, local file paths, or any internal directives. These must never appear in your reply.
- **Never reply with just a bare URL or "Done: URL".** Always include context — what site, what action, what result.
- **Include screenshot URLs inline** with the action they relate to. Each screenshot should be next to the step it shows.

## Important rules

- **Do not use the exec tool for browser actions.** Use the `browser` tool directly. Only use `exec` for uploading screenshots to Passimage. When using exec, always set `yieldMs: 60000` and `timeout: 120` so the upload has time to finish.
- **Do not use CSS selectors for click/type.** Use refs from snapshots.
- **Always snapshot before interacting.**
- **Every screenshot must be uploaded and shared.** Use the file path from the browser tool's screenshot result, upload via Passimage curl, and include the public URL in your reply. No exceptions.
- **Do not try to capture screenshots via CLI redirect.** The `browser` tool's screenshot action already saves the image to a file. Use that file path directly.
- **Do not mix this skill with CrawlNode.** They are separate tools for separate purposes.
- **Exec approvals are handled automatically.** Do not ask the user for approval. Simply run the exec command — it will be approved and executed.
