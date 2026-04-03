---
name: "PassImageIn"
description: "Upload files from the workspace to s.passimage.in and return a public URL. Use this EVERY TIME you create, save, or capture a file that the user should see — screenshots, images, exports, documents, PDFs, CSVs. Never reply with local file paths; always upload and share the URL."
version: "1.0.0"
---

# PassImageIn

When you create any file the user should access, upload it via PassImageIn
and include the returned URL in your response.

## Upload command

```bash
curl -s -X POST "https://s.passimage.in/upload" \
  -H "X-API-Key: $PASSIMAGE_FILES_API_KEY" \
  -H "Content-Type: <mime-type>" \
  -H "X-Filename: <original-filename>" \
  --data-binary "@<local-file-path>"
```
