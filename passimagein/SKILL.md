---
name: "PassImageIn"
description: >
  Upload files from the gateway to s.passimage.in and return a public URL.
  Use this EVERY TIME you create, save, or capture a file the user should see —
  screenshots, images, exports, documents, PDFs, CSVs, JSON, ZIPs. Never reply
  with a local file path; always upload and share the URL.
version: "1.1.0"
user-invocable: true
metadata: {"openclaw": {"requires": {"env": ["PASSIMAGE_FILES_API_KEY"]}, "primaryEnv": "PASSIMAGE_FILES_API_KEY"}}
---

# PassImageIn

This skill is the canonical way to share any file with the user. Whenever another skill (browser-automation, crawlnode, or any future skill) produces a file, follow the rules here to upload it and share the public URL.

## Golden rule

> **Never reply with a local file path.** Local paths like `/tmp/foo.png` or `/home/autoscale/workspace/result.csv` mean nothing to the user — they can't open them. Always upload via PassImageIn and share the returned public URL.

## When to use

Use this skill whenever you produce or capture a file the user should see:

- Screenshots from the browser tool or the CrawlNode API
- Generated exports (CSV, JSON, XLSX, ZIP, PDF)
- Downloaded documents
- Logs or text files the user asked you to deliver

Do **not** use this skill for files that are purely internal scratch state.

## Where does the file path come from? (CRITICAL)

The path you upload **must** be the exact path returned by the tool that just created the file on **this turn**. Never search the disk for files.

| Source tool | Where the path lives in the tool result |
|---|---|
| `browser.screenshot` (built-in) | `details.path`, or `details.media.mediaUrl`, or `details.media.path` |
| CrawlNode `/api/screenshot` | The path you passed to `curl --output` in this same exec call |
| Any custom write you did | The path you just wrote to with `--output`, `>`, or similar |

> **Do NOT** run `ls -t *.png`, `find /tmp ...`, or any other "newest file" search. Old screenshots from earlier runs are sitting on disk. Picking by modification time or extension will silently upload the **wrong** file.
>
> **Do NOT** assume the file extension. Screenshots can be `.png` or `.jpg`. Documents can be `.pdf`, `.csv`, `.json`, etc. Read the actual path string the tool gave you.

## Upload command

Run this through the **exec** tool with `"host": "gateway"`:

```bash
PUBLIC_URL=$(curl -sS -X POST "https://s.passimage.in/upload" \
  -H "X-API-Key: $PASSIMAGE_FILES_API_KEY" \
  -H "Content-Type: <mime-type>" \
  -H "X-Filename: <filename>" \
  --data-binary "@<exact-path-from-tool-result>")
echo "$PUBLIC_URL"
```

Replace the three placeholders using the file path you obtained above:

1. `<mime-type>` — see the table below.
2. `<filename>` — the basename of the path (e.g. `screenshot-1730000000.png`).
3. `<exact-path-from-tool-result>` — the exact string the tool returned. Quote it.

The response body is the public URL as **plain text**, e.g. `https://s.passimage.in/f/8d5ee2e3d5c3.png`. Capture it in a shell variable so you can include it in your reply.

## Mime-type reference

| File extension | `Content-Type` to send |
|---|---|
| `.png` | `image/png` |
| `.jpg`, `.jpeg` | `image/jpeg` |
| `.gif` | `image/gif` |
| `.webp` | `image/webp` |
| `.pdf` | `application/pdf` |
| `.csv` | `text/csv` |
| `.json` | `application/json` |
| `.txt`, `.log`, `.md` | `text/plain` |
| `.html` | `text/html` |
| `.zip` | `application/zip` |
| `.xlsx` | `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` |
| `.xls` | `application/vnd.ms-excel` |
| anything else | `application/octet-stream` |

Match the extension at the **end of the actual path string** — not what you assume the file should be.

## Retry policy

1. If the upload command fails (non-200, empty body, network error), **retry once**.
2. If the second attempt also fails, tell the user "Upload failed for `<filename>`" in your reply and continue with the rest of the task.
3. **Never loop more than two attempts** for the same file. Move on.

## What to do with the public URL

- Include the URL in your **next** assistant message to the user, on the same line as the action that produced the file.
- Example format for screenshots: `- <action description> (<public URL>)`
- Example format for files: `Generated <filename>: <public URL>`

When the task ends, list every uploaded URL in your final summary message so the user has them all in one place.

## Examples

### Uploading a PNG screenshot

The screenshot tool returned `details.path = /tmp/browser-1730000000.png`.

```bash
PUBLIC_URL=$(curl -sS -X POST "https://s.passimage.in/upload" \
  -H "X-API-Key: $PASSIMAGE_FILES_API_KEY" \
  -H "Content-Type: image/png" \
  -H "X-Filename: browser-1730000000.png" \
  --data-binary "@/tmp/browser-1730000000.png")
echo "$PUBLIC_URL"
```

### Uploading a JPG screenshot

The screenshot tool returned `details.path = /tmp/browser-1730000001.jpg`.

```bash
PUBLIC_URL=$(curl -sS -X POST "https://s.passimage.in/upload" \
  -H "X-API-Key: $PASSIMAGE_FILES_API_KEY" \
  -H "Content-Type: image/jpeg" \
  -H "X-Filename: browser-1730000001.jpg" \
  --data-binary "@/tmp/browser-1730000001.jpg")
echo "$PUBLIC_URL"
```

### Uploading a CSV export

You just wrote `/tmp/results.csv`.

```bash
PUBLIC_URL=$(curl -sS -X POST "https://s.passimage.in/upload" \
  -H "X-API-Key: $PASSIMAGE_FILES_API_KEY" \
  -H "Content-Type: text/csv" \
  -H "X-Filename: results.csv" \
  --data-binary "@/tmp/results.csv")
echo "$PUBLIC_URL"
```

## Important rules (summary)

- **Never reply with a local file path.** Always upload and share the public URL.
- **Use the exact path from the tool that created the file.** Never `ls` or `find` to look for it.
- **Don't assume the extension.** Read the actual path string.
- **Pick the right `Content-Type`** from the table above.
- **Retry once on failure**, then move on. Never loop.
- **Every upload URL goes in your reply** to the user, and again in your final summary message.
