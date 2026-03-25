# crawlnode-skill

An [OpenClaw](https://openclaw.org) Skill that enables OpenClaw to operate a remote browser through the [CrawlNode](https://crawlnode.com) API.

## Overview

crawlnode-skill gives OpenClaw full browser automation capabilities by interfacing with CrawlNode's distributed browser infrastructure. When a user request requires browsing the web, filling out forms, extracting page content, or any other browser-based interaction, this skill handles the entire lifecycle of a remote browser session.

## How It Works

To fulfill a user request that requires a browser, crawlnode-skill follows this workflow:

1. **Create a session** -- Starts a new remote browser instance via `/api/start`
2. **Navigate** -- Directs the browser to the appropriate pages via `/api/go`
3. **Interact** -- Performs the necessary actions on the page:
   - Inspect the page element tree (`/api/view`)
   - Click elements (`/api/click`)
   - Type into fields (`/api/input`)
   - Download network responses (`/api/download`)
   - Drag elements such as sliders (`/api/drag`)
4. **Extract content** -- Retrieves page text and data via `/api/download`
5. **Capture screenshots** -- Takes a screenshot after each action via `/api/screenshot` to verify results and provide visual feedback
6. **Destroy the session** -- Tears down the remote browser via `/api/destroy` to free resources

## Configuration

### Environment Variable

| Variable | Required | Description |
|----------|----------|-------------|
| `CRAWLNODE_TOKEN` | Yes | API token for authenticating with the CrawlNode API |

The skill reads `CRAWLNODE_TOKEN` from the environment and passes it as the `Token` header on every request to the CrawlNode API.

### API Endpoint

All requests are sent to:

```
http://api1.crawlnode.com
```

## API Capabilities

| Endpoint | Purpose |
|----------|---------|
| `POST /api/start` | Create a new browser session |
| `POST /api/destroy` | Destroy a session and free resources |
| `POST /api/go` | Navigate to a URL |
| `POST /api/view` | Get the page's UI element tree |
| `POST /api/click` | Click an element by ID |
| `POST /api/input` | Type text or send keystrokes |
| `POST /api/drag` | Drag between coordinates (sliders, captchas) |
| `POST /api/screenshot` | Capture a PNG screenshot |
| `POST /api/network` | List captured network requests |
| `POST /api/download` | Download raw HTTP request/response data |
| `POST /api/solve_captcha` | Auto-solve slider captchas |
| `POST /api/refresh` | Refresh the current page |
| `POST /api/maximize` | Maximize the browser window |
| `POST /api/resize` | Resize and reposition the window |
| `POST /api/clear` | Clear cookies and cache |

For full request/response schemas and usage examples, see the [CrawlNode API Documentation](docs/CRAWLNODE-API-DOCUMENTATION.md).

## Session Lifecycle

```
  CRAWLNODE_TOKEN
        │
        ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  /api/start  │────►│   /api/go    │────►│  /api/view   │
│  Create      │     │  Navigate    │     │  Inspect     │
└──────────────┘     └──────────────┘     └──────┬───────┘
                                                 │
                              ┌───────────────────┤
                              ▼                   ▼
                     ┌──────────────┐     ┌──────────────┐
                     │ /api/click   │     │ /api/input   │
                     │ /api/drag    │     │ /api/download│
                     └──────┬───────┘     └──────┬───────┘
                            │                    │
                            └────────┬───────────┘
                                     ▼
                            ┌──────────────────┐
                            │ /api/screenshot  │  (after each action)
                            └────────┬─────────┘
                                     │
                                     ▼
                            ┌──────────────────┐
                            │  /api/destroy    │
                            │  Clean up        │
                            └──────────────────┘
```

## Installation

1. Define the `CRAWLNODE_TOKEN` environment variable in your OpenClaw instance
2. Clone the repo:
   ```bash
   git clone https://github.com/linkgrid/openclaw-skill.crawlnode.com.git
   ```

## Deployment

This skill is deployed as a GitHub repo at:

https://github.com/linkgrid/openclaw-skill.crawlnode.com.git

Deploying to production is simply pushing to GitHub:

```bash
git push origin main
```

## Documentation

- [CrawlNode API Documentation](docs/CRAWLNODE-API-DOCUMENTATION.md) -- Complete API reference with request/response schemas, error handling, and code examples
