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

Use the **browser** tool to control OpenClaw's local Chromium browser. Do **not** use the `exec` tool for browser actions — the `browser` tool handles everything directly.

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

### 4. Screenshot (after every visible change)

```json
{ "tool": "browser", "action": "screenshot" }
```

Take a screenshot after every navigation, click, or form submission that changes the page.

## Screenshot → upload → share (MANDATORY)

> **Every screenshot you take MUST be uploaded to PassImageIn and shared as a public URL in your reply.** No exceptions. Never reply with a local file path. Never skip the upload step.

### Step 1 — Read the path from the tool result (do NOT search the disk)

When the `browser.screenshot` tool returns, the result is a JSON object that contains the **exact file path** the browser just wrote. Read it from the result fields, in this order of preference:

1. `details.path`  — the absolute file path on the gateway (preferred)
2. `details.media.mediaUrl` — present on newer gateway versions
3. `details.media.path` — fallback for older gateways
4. `path` — fallback at the top level

> **CRITICAL — do not list, glob, or guess the path.**
> Never run `ls -t *.png`, `ls /tmp`, `find ...`, or anything similar to look for the screenshot file. There are old screenshots from earlier runs sitting in `/tmp` and the workspace; picking by modification time or extension will silently upload the **wrong** image. The only correct path is the one the screenshot tool returned **on this turn**.
>
> The file extension is also not fixed — the browser tool may save `.png` **or** `.jpg`. Treat the extension as whatever appears at the end of the returned path. Do not assume `.png`.

### Step 2 — Upload via PassImageIn

Use the path you read in Step 1. Compute `<mime-type>` and `<filename>` from that exact path:

- If the path ends in `.png` → `Content-Type: image/png`
- If the path ends in `.jpg` or `.jpeg` → `Content-Type: image/jpeg`
- `<filename>` = the basename of the path (e.g. `browser-1730000000.png`).

Run the upload through the **exec** tool with `"host": "gateway"`:

```bash
SCREENSHOT_URL=$(curl -sS -X POST "https://s.passimage.in/upload" \
  -H "X-API-Key: $PASSIMAGE_FILES_API_KEY" \
  -H "Content-Type: <mime-type>" \
  -H "X-Filename: <filename>" \
  --data-binary "@<exact-path-from-screenshot-result>")
echo "$SCREENSHOT_URL"
```

The response body is the public URL as plain text (e.g. `https://s.passimage.in/f/8d5ee2e3d5c3.png`).

If the upload fails, retry **once**. If it fails twice, tell the user the upload failed for that screenshot and keep going — do **not** loop.

### Step 3 — Share the URL with the user

Mention the URL in your next reply. After every action that changed the page, write one line in this format:

```
- <action description> (<screenshot URL>)
```

Examples:

```
- Navigated to https://www.example.com (https://s.passimage.in/f/8d5ee2e3d5c3.png)
- Clicked the "Sign in" button (https://s.passimage.in/f/8d5ee2e3d5c4.png)
```

## Always finish with a final summary message (MANDATORY)

When the task is done — successfully **or** with an error — your very last message must be a short text summary written **outside any tool call**, addressed to the user. It must include:

1. A one-sentence statement of what you accomplished (or where you stopped).
2. Every screenshot URL you uploaded, in order, one per line.
3. Any structured data you extracted (as plain text or a short list).

Do **not** rely on tool output alone to convey the answer. The user does not see tool logs directly — they see only your assistant text. If you do not write a final summary, the user will see an empty or incomplete reply.

Even if you hit an error or a retry limit, still write a final summary describing what you tried and what was captured before the failure.

## Interaction rules (mandatory)

1. **Always snapshot before interacting.** Never reuse refs from a previous snapshot — they become invalid after any page change.
2. **Use refs, not CSS selectors, for click/type/fill.** Refs from snapshots are more reliable.
3. **Screenshot after every visible change.** Navigation, clicks, form submissions — screenshot each time so the user sees what happened, then upload it (see above).
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
10. Screenshot the result page, upload it, and share the URL.
11. Snapshot the result page and extract relevant text.

## Efficiency rules (avoid hitting tool-call limits)

Each Slack run has a maximum number of tool calls. Long tasks can run out of budget before they finish. To stay efficient:

- **Do not screenshot the same page twice** unless something actually changed.
- **Do not re-snapshot** without an intervening action.
- **Batch related extractions** when possible (e.g. one `evaluate` returning multiple fields instead of three `extract_text` calls).
- **Stream short progress sentences** between major steps. Brief assistant text between tool calls reassures the user that work is happening, and ensures partial progress lands in Slack even if the run is cut short later.

## Retry strategy

- If an action fails (element not found, timeout), **re-snapshot** and try with a fresh ref.
- If the same action fails twice, try a different approach: scroll, wait longer, or use a different element.
- After 3 failed attempts on the same step, **stop and report** what happened to the user, including any screenshot URLs you have, and a final summary message.
- Never loop indefinitely.

## Error handling

| Situation | What to do |
|-----------|------------|
| Element ref not found | Re-snapshot, find the correct ref |
| Page didn't load | Wait 5 seconds, try navigate again |
| Timeout on action | Screenshot current state, upload, retry once |
| Element not in snapshot | Scroll down (PageDown), re-snapshot |
| Form field not fillable | Try click first, then fill |
| Browser not running | Report to user — browser needs to be started |
| Screenshot upload failed twice | Tell the user the upload failed for that step and continue |

## Important rules (summary)

- **Do not use the exec tool for browser actions.** Use the `browser` tool directly.
- **Do not use CSS selectors for click/type.** Use refs from snapshots.
- **Always snapshot before interacting.**
- **Always screenshot after visible changes.**
- **Every screenshot must be uploaded via PassImageIn and shared as a public URL.** Use the exact path from the screenshot tool result — never search the disk for files.
- **Always finish with a final summary message** that includes every screenshot URL and any extracted data.
- **Do not mix this skill with CrawlNode.** They are separate tools for separate purposes.
