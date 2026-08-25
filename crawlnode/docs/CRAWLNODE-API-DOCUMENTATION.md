# CrawlNode API Usage Documentation

## Table of Contents

1. [Introduction](#1-introduction)
2. [Architecture Overview](#2-architecture-overview)
3. [Authentication](#3-authentication)
4. [Base URL and Endpoints](#4-base-url-and-endpoints)
5. [API Reference](#5-api-reference)
6. [Error Handling](#6-error-handling)
7. [Usage Examples](#7-usage-examples)
8. [Best Practices](#8-best-practices)
9. [SDK and Libraries](#9-sdk-and-libraries)

## 1. Introduction

CrawlNode is a distributed browser automation system that provides a unified HTTP API for managing browser sessions across multiple nodes. The API allows users to create browser sessions, navigate pages, interact with elements, capture network traffic, take screenshots, and perform various automation tasks.

### Key Features

- **Distributed architecture**: Sessions are load-balanced across multiple nodes
- **Session management**: Create, manage, and destroy browser sessions
- **Browser automation**: Navigate, click, input, drag, and other UI interactions
- **Network capture**: Monitor and download HTTP requests/responses via MITM proxy
- **Proxy support**: Use custom proxies or auto-assign from managed proxy pool
- **Screenshot capture**: Take full window screenshots
- **Captcha solving**: Built-in slider captcha recognition and automation

### Supported Browsers

- Google Chrome (versions 125, 145 tested and supported)
- Windows platform with UI Automation

## 2. Architecture Overview

```
┌─────────────────┐      proxy       ┌─────────────────┐
│    Chrome       │ ───────────────► │     agent       │
│                 │ ◄─────────────── │ (FastAPI/MITM)  │
└───┬────────┬────┘   UIAutomation   └─────────────────┘
    │        │                                ▲
    │        ▼                                │ HTTP API(8020)
    │     ┌───────┐                ┌──────────┴──────────┐
    │     │ proxy │                │   DispatcherClient  │
    │     │       │                │  (Asyncio Client)   │
    │     └──┬────┘                └──────────┬──────────┘
    │        │                                │ TCP Socket(8010)
    ▼        ▼                                ▼
┌─────────────────┐                ┌─────────────────────┐                  ┌─────────────┐
│    website      │                │  DispatcherServer   │ ◄────────────────│    User     │
│                 │                │  (Asyncio Server)   │  HTTP API(8000)  │             │
└─────────────────┘                └──────────┬──────────┘                  └─────────────┘
                                              │ MySQL(3306)
                                              ▼
                                       ┌─────────────┐                      ┌─────────────┐
                                       │    MySQL    │                      │  Manager    │
                                       │  Database   │                      │             │
                                       └─────────────┘                      └─────┬───────┘
                                              ▲                                   │ Web(80)
                                              │ MySQL(3306)                       ▼
                                     ┌────────┴────────┐                  ┌─────────────────┐
                                     │    dashboard    │ ◄─────────────── │   dashboard-ui  │
                                     │    (FastAPI)    │   HTTP API(80)   │    (Vue.js)     │
                                     └─────────────────┘                  └─────────────────┘
```

### Request Flow

1. **Client Request**: User sends HTTP request to DispatcherServer (`api1.crawlnode.com:8001`)
2. **Authentication**: DispatcherServer validates the `Token` header
3. **Session Routing**: For existing sessions, routes to the appropriate node via `X-Session-Id`
4. **Node Selection**: For new sessions (`/api/start`), selects best available node based on load
5. **Request Forwarding**: DispatcherServer forwards request to DispatcherClient on selected node
6. **Agent Processing**: DispatcherClient forwards to local Agent (FastAPI service on port 8020)
7. **Browser Interaction**: Agent performs the requested operation on Chrome browser
8. **Response Path**: Response travels back through the same path to the client

## 3. Authentication

All API requests require authentication via a `Token` header.

### Token Header

```http
Token: your-api-token-here
```

### Token Management

- Tokens are managed through the dashboard UI or directly in the database
- Each token has:
  - `token`: Unique identifier string
  - `name`: Human-readable description
  - `valid_from`, `valid_until`: Optional validity period
  - `status`: 10 (enabled) or 20 (disabled)
  - `nodes`: Optional regex pattern to restrict token to specific nodes

### Token Validation

- Only tokens with `status = 10` are accepted
- Token must be within validity period if specified
- If `nodes` regex is specified, only matching nodes can be used

## 4. Base URL and Endpoints

### Base URL

```
http://api1.crawlnode.com:8001
```

**Note**: The port is mandatory and is **8001** (TCP 8011) for the current fleet. Port 80 and the legacy 8000/8010 dispatcher are a separate instance with no nodes attached — they answer with `503 No client available`. Verified Aug 24 2026: `:8001` reaches auth, bare domain and `:8000` do not.

### Session Management

Sessions represent individual browser instances. Each session:
- Has a unique `session_id` (UUID format)
- Maps to a specific node and Chrome process
- Maintains its own user data directory, cookies, and network capture

### Required Headers

| Header | Required For | Description |
|--------|--------------|-------------|
| `Token` | All requests | Authentication token |
| `X-Session-Id` | All except `/api/start` | Session identifier |
| `Content-Type` | POST requests | Should be `application/json` |

## 5. API Reference

### 5.1 Session Management

#### POST /api/start

Create a new browser session or reuse an existing one.

**Headers:**
- `Token`: Required
- `X-Session-Id`: Optional (for session reuse)

**Request Body:**
```json
{
  "session_id": "optional-session-id",
  "proxy": "auto|user:pass@host:port|none",
  "extension": true|false
}
```

**Parameters:**
- `session_id` (string, optional): Reuse existing session
- `proxy` (string, optional): 
  - `"auto"`: Auto-assign from managed proxy pool
  - `"user:pass@host:port"`: Use specific proxy
  - Empty/omitted: No proxy
- `extension` (boolean, optional): Enable network capture extension (default: false)

**Response:**
```json
{
  "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

**Response Headers:**
- `X-Session-Id`: The session ID to use in subsequent requests

---

#### POST /api/destroy

Terminate the browser process and free resources.

**Headers:**
- `Token`: Required
- `X-Session-Id`: Required

**Request Body:**
```json
{}
```

**Response:**
```json
{
  "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

---

#### POST /api/clear

Clear the session's user data directory (cookies, cache, etc.).

**Headers:**
- `Token`: Required
- `X-Session-Id`: Required

**Request Body:**
```json
{}
```

**Response:**
```json
{
  "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

### 5.2 Browser Navigation

#### POST /api/go

Navigate to a URL.

**Headers:**
- `Token`: Required
- `X-Session-Id`: Required

**Request Body:**
```json
{
  "url": "https://www.example.com"
}
```

**Response:**
```json
{
  "url": "https://www.example.com",
  "title": "Example Domain"
}
```

---

#### POST /api/refresh

Refresh the current page.

**Headers:**
- `Token`: Required
- `X-Session-Id`: Required

**Request Body:**
```json
{}
```

**Response:**
```json
{
  "title": "Example Domain"
}
```

### 5.3 Window Management

#### POST /api/maximize

Maximize the browser window.

**Headers:**
- `Token`: Required
- `X-Session-Id`: Required

**Request Body:**
```json
{}
```

**Response:**
```json
{
  "title": "Example Domain"
}
```

---

#### POST /api/minimize

Minimize the browser window.

**Headers:**
- `Token`: Required
- `X-Session-Id`: Required

**Request Body:**
```json
{}
```

**Response:**
```json
{
  "title": "Example Domain"
}
```

---

#### POST /api/resize

Resize and position the browser window.

**Headers:**
- `Token`: Required
- `X-Session-Id`: Required

**Request Body:**
```json
{
  "width": 1280,
  "height": 720,
  "x": 100,
  "y": 100
}
```

**Parameters:**
- `width` (number, required): Window width in pixels
- `height` (number, required): Window height in pixels
- `x` (number, optional): Window x position
- `y` (number, optional): Window y position

**Response:**
```json
{
  "x": 100,
  "y": 100,
  "width": 1280,
  "height": 720
}
```

### 5.4 Page Interaction

#### POST /api/view

Get the UI automation tree for element identification.

**Headers:**
- `Token`: Required
- `X-Session-Id`: Required

**Request Body:**
```json
{}
```

**Response:**
```json
{
  "elements": {
    "element_id": "0_0_1920_1080",
    "name": "Document",
    "control_type": "DocumentControl",
    "automation_id": "",
    "rectangle": {
      "left": 0,
      "top": 0,
      "right": 1920,
      "bottom": 1080
    },
    "isEnabled": true,
    "path": "0",
    "children": [
      {
        "element_id": "100_50_200_80",
        "name": "Submit",
        "control_type": "ButtonControl",
        "automation_id": "submitBtn",
        "rectangle": {
          "left": 100,
          "top": 50,
          "right": 200,
          "bottom": 80
        },
        "isEnabled": true,
        "path": "0/1",
        "children": []
      }
    ]
  }
}
```

**Element Properties:**
- `element_id`: Coordinate-based identifier (`left_top_right_bottom`)
- `automation_id`: HTML/application-defined identifier
- `name`: Element name or text content
- `control_type`: Element type (ButtonControl, EditControl, etc.)
- `rectangle`: Element position and size
- `isEnabled`: Whether element is interactive
- `path`: Tree path for navigation
- `children`: Nested child elements

---

#### POST /api/click

Click on a page element.

**Headers:**
- `Token`: Required
- `X-Session-Id`: Required

**Request Body (Option 1 - by element_id):**
```json
{
  "element_id": "100_50_200_80"
}
```

**Request Body (Option 2 - by automation_id):**
```json
{
  "automation_id": "submitBtn"
}
```

**Response:**
```json
{
  "text": "Button text or name"
}
```

**Note:** Either `element_id` or `automation_id` must be provided. Use `/api/view` to get these identifiers.

---

#### POST /api/input

Type text or send keys to an element.

**Headers:**
- `Token`: Required
- `X-Session-Id`: Required

**Request Body:**
```json
{
  "element_id": "200_100_400_130",
  "keys": "hello{tab}world{enter}"
}
```

**Parameters:**
- `element_id` OR `automation_id`: Element identifier
- `keys` (string, required): Text to type. Supports special keys:
  - `{tab}`: Tab key
  - `{enter}`: Enter key
  - `{ctrl}`, `{alt}`, `{shift}`: Modifier keys
  - `{backspace}`, `{delete}`: Deletion keys

**Response:**
```json
{
  "keys": "hello{tab}world{enter}"
}
```

---

#### POST /api/drag

Perform drag operation (useful for sliders, captchas).

**Headers:**
- `Token`: Required
- `X-Session-Id`: Required

**Request Body:**
```json
{
  "path": [[100, 200], [150, 200], [200, 200]],
  "interval": 50
}
```

**Parameters:**
- `path` (array, required): Array of [x, y] coordinates (minimum 2 points)
- `interval` (number, required): Delay between points in milliseconds

**Response:**
```json
{
  "x": 200,
  "y": 200
}
```

**Note:** Coordinates are relative to the window. The drag automatically performs smooth interpolation between points.

### 5.5 Screen Capture

#### POST /api/screenshot

Capture a screenshot of the browser window.

**Headers:**
- `Token`: Required
- `X-Session-Id`: Required

**Request Body:**
```json
{}
```

**Response:**
- **Content-Type**: `image/png`
- **Body**: PNG binary data

**Example usage with curl:**
```bash
curl -X POST "http://api1.crawlnode.com:8001/api/screenshot" \
  -H "Token: your-token-here" \
  -H "X-Session-Id: your-session-id" \
  -H "Content-Type: application/json" \
  -d '{}' \
  --output screenshot.png
```

### 5.6 Network Traffic

#### POST /api/network

Get list of captured network requests.

**Headers:**
- `Token`: Required
- `X-Session-Id`: Required

**Request Body:**
```json
{}
```

**Response:**
```json
[
  {
    "request_id": 1,
    "url": "https://www.example.com/",
    "status_code": 200,
    "content_type": "text/html",
    "content_length": "1234"
  },
  {
    "request_id": 2,
    "url": "https://www.example.com/api/data",
    "status_code": 200,
    "content_type": "application/json",
    "content_length": "256"
  }
]
```

**Note:** Network capture requires starting the session with `"extension": true`.

---

#### POST /api/download

Download raw HTTP request/response data.

**Headers:**
- `Token`: Required
- `X-Session-Id`: Required

**Request Body:**
```json
{
  "request_id": 2
}
```

**Response:**
```json
{
  "id": "2",
  "request": "R0VUIC8gSFRUUC8xLjEK...",
  "response": "SFRUUC8xLjEgMjAwIE9LCk..."
}
```

**Response Fields:**
- `id`: Request ID
- `request`: Base64-encoded raw HTTP request
- `response`: Base64-encoded raw HTTP response

### 5.7 Advanced Features

#### POST /api/solve_captcha

Automatically solve slider-type captchas.

**Headers:**
- `Token`: Required
- `X-Session-Id`: Required

**Request Body:**
```json
{}
```

**Response:**
```json
{
  "success": true,
  "distance": 120,
  "slide_from": {"x": 10, "y": 100},
  "slide_to": {"x": 130, "y": 100}
}
```

**Note:** This feature uses computer vision to detect and solve slider captchas automatically. Success depends on captcha type and page structure.

## 6. Error Handling

### HTTP Status Codes

| Code | Source | Description |
|------|--------|-------------|
| **200** | Success | Request completed successfully |
| **500** | Agent | Business logic error (Chrome/UI automation) |
| **510** | DispatcherClient | Proxy/forwarding layer error |
| **520** | DispatcherServer | Dispatcher server error |

### Error Response Format

Errors return JSON with detail field:

```json
{
  "detail": "Error description"
}
```

### Common Error Categories

#### Authentication Errors (520)
- **Invalid token**: Token not found or disabled
- **Token expired**: Token outside validity period
- **Node restriction**: Token restricted to different nodes

```bash
# Example
HTTP/1.1 520 
Content-Type: text/plain

Dispatcher Server: Invalid token
```

#### Session Errors (520)
- **X-Session-Id not provided**: Missing session header (except for `/api/start`)
- **No available node**: All nodes offline or at capacity
- **Node not found**: Session's node no longer available

#### Agent Errors (500)
- **Chrome window not found**: Browser closed or crashed
- **UI operation busy**: Another operation in progress (10s timeout)
- **Chrome load url failed/timeout**: Network or navigation issues
- **Missing parameter**: Required fields not provided

```json
{
  "detail": "Chrome load url: https://example.com timeout"
}
```

#### Client Errors (510)
- **Failed to connect to Agent HTTP**: Agent service not running
- **Invalid response content length**: Communication error

### Error Recovery Strategies

1. **Authentication Errors**: Verify token and validity period
2. **Session Errors**: Create new session with `/api/start`
3. **Network Errors**: Implement retry with exponential backoff
4. **Chrome Errors**: Destroy and recreate session
5. **Node Unavailability**: Let dispatcher auto-select different node

## 7. Usage Examples

### 7.1 Basic Session Workflow

```bash
# 1. Create session
curl -X POST "http://api1.crawlnode.com:8001/api/start" \
  -H "Token: your-token-here" \
  -H "Content-Type: application/json" \
  -d '{"extension": true}'

# Response: {"session_id": "abc123"}

# 2. Navigate to page
curl -X POST "http://api1.crawlnode.com:8001/api/go" \
  -H "Token: your-token-here" \
  -H "X-Session-Id: abc123" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://www.example.com"}'

# 3. Take screenshot
curl -X POST "http://api1.crawlnode.com:8001/api/screenshot" \
  -H "Token: your-token-here" \
  -H "X-Session-Id: abc123" \
  -H "Content-Type: application/json" \
  -d '{}' \
  --output screenshot.png

# 4. Clean up
curl -X POST "http://api1.crawlnode.com:8001/api/destroy" \
  -H "Token: your-token-here" \
  -H "X-Session-Id: abc123" \
  -H "Content-Type: application/json" \
  -d '{}'
```

### 7.2 Form Interaction Example

```bash
# Get page elements
curl -X POST "http://api1.crawlnode.com:8001/api/view" \
  -H "Token: your-token-here" \
  -H "X-Session-Id: abc123" \
  -H "Content-Type: application/json" \
  -d '{}'

# Click on username field (using element_id from view response)
curl -X POST "http://api1.crawlnode.com:8001/api/click" \
  -H "Token: your-token-here" \
  -H "X-Session-Id: abc123" \
  -H "Content-Type: application/json" \
  -d '{"element_id": "100_50_300_80"}'

# Type username
curl -X POST "http://api1.crawlnode.com:8001/api/input" \
  -H "Token: your-token-here" \
  -H "X-Session-Id: abc123" \
  -H "Content-Type: application/json" \
  -d '{"element_id": "100_50_300_80", "keys": "myusername"}'

# Tab to password field and type password
curl -X POST "http://api1.crawlnode.com:8001/api/input" \
  -H "Token: your-token-here" \
  -H "X-Session-Id: abc123" \
  -H "Content-Type: application/json" \
  -d '{"keys": "{tab}mypassword"}'

# Submit form
curl -X POST "http://api1.crawlnode.com:8001/api/click" \
  -H "Token: your-token-here" \
  -H "X-Session-Id: abc123" \
  -H "Content-Type: application/json" \
  -d '{"automation_id": "submitBtn"}'
```

### 7.3 Network Monitoring Example

```bash
# Start session with network capture
curl -X POST "http://api1.crawlnode.com:8001/api/start" \
  -H "Token: your-token-here" \
  -H "Content-Type: application/json" \
  -d '{"extension": true}'

# Navigate and perform actions...

# Get network requests
curl -X POST "http://api1.crawlnode.com:8001/api/network" \
  -H "Token: your-token-here" \
  -H "X-Session-Id: abc123" \
  -H "Content-Type: application/json" \
  -d '{}'

# Download specific request/response
curl -X POST "http://api1.crawlnode.com:8001/api/download" \
  -H "Token: your-token-here" \
  -H "X-Session-Id: abc123" \
  -H "Content-Type: application/json" \
  -d '{"request_id": 5}'
```

### 7.4 Python Example

```python
import requests
import json
import base64

class CrawlNodeClient:
    def __init__(self, base_url, token):
        self.base_url = base_url.rstrip('/')
        self.token = token
        self.session_id = None
    
    def _headers(self):
        headers = {
            'Token': self.token,
            'Content-Type': 'application/json'
        }
        if self.session_id:
            headers['X-Session-Id'] = self.session_id
        return headers
    
    def start_session(self, proxy=None, extension=False):
        data = {'extension': extension}
        if proxy:
            data['proxy'] = proxy
            
        response = requests.post(
            f"{self.base_url}/api/start",
            headers=self._headers(),
            json=data
        )
        response.raise_for_status()
        
        result = response.json()
        self.session_id = result['session_id']
        return result
    
    def navigate(self, url):
        response = requests.post(
            f"{self.base_url}/api/go",
            headers=self._headers(),
            json={'url': url}
        )
        response.raise_for_status()
        return response.json()
    
    def take_screenshot(self):
        response = requests.post(
            f"{self.base_url}/api/screenshot",
            headers=self._headers(),
            json={}
        )
        response.raise_for_status()
        return response.content  # PNG binary data
    
    def get_elements(self):
        response = requests.post(
            f"{self.base_url}/api/view",
            headers=self._headers(),
            json={}
        )
        response.raise_for_status()
        return response.json()
    
    def click_element(self, element_id=None, automation_id=None):
        data = {}
        if element_id:
            data['element_id'] = element_id
        elif automation_id:
            data['automation_id'] = automation_id
        else:
            raise ValueError("Must provide element_id or automation_id")
            
        response = requests.post(
            f"{self.base_url}/api/click",
            headers=self._headers(),
            json=data
        )
        response.raise_for_status()
        return response.json()
    
    def type_text(self, text, element_id=None, automation_id=None):
        data = {'keys': text}
        if element_id:
            data['element_id'] = element_id
        elif automation_id:
            data['automation_id'] = automation_id
            
        response = requests.post(
            f"{self.base_url}/api/input",
            headers=self._headers(),
            json=data
        )
        response.raise_for_status()
        return response.json()
    
    def get_network_requests(self):
        response = requests.post(
            f"{self.base_url}/api/network",
            headers=self._headers(),
            json={}
        )
        response.raise_for_status()
        return response.json()
    
    def download_request(self, request_id):
        response = requests.post(
            f"{self.base_url}/api/download",
            headers=self._headers(),
            json={'request_id': request_id}
        )
        response.raise_for_status()
        data = response.json()
        
        # Decode base64 request/response
        return {
            'id': data['id'],
            'request': base64.b64decode(data['request']),
            'response': base64.b64decode(data['response'])
        }
    
    def destroy_session(self):
        if not self.session_id:
            return
            
        response = requests.post(
            f"{self.base_url}/api/destroy",
            headers=self._headers(),
            json={}
        )
        response.raise_for_status()
        result = response.json()
        self.session_id = None
        return result

# Usage example
if __name__ == "__main__":
    client = CrawlNodeClient("http://api1.crawlnode.com:8001", "your-token-here")
    
    try:
        # Start session with network capture
        print("Starting session...")
        client.start_session(extension=True)
        
        # Navigate to page
        print("Navigating to page...")
        client.navigate("https://www.example.com")
        
        # Take screenshot
        print("Taking screenshot...")
        screenshot = client.take_screenshot()
        with open("screenshot.png", "wb") as f:
            f.write(screenshot)
        
        # Get page elements
        print("Getting page elements...")
        elements = client.get_elements()
        print(f"Found {len(elements['elements'].get('children', []))} elements")
        
        # Get network requests
        print("Getting network requests...")
        requests_data = client.get_network_requests()
        print(f"Captured {len(requests_data)} network requests")
        
    finally:
        # Always clean up
        print("Destroying session...")
        client.destroy_session()
```

## 8. Best Practices

### 8.1 Session Management

1. **Always clean up sessions**: Call `/api/destroy` when done to free resources
2. **Handle session failures**: If a session becomes unresponsive, create a new one
3. **Monitor session lifecycle**: Sessions may be terminated by nodes going offline
4. **Use session reuse carefully**: Only reuse sessions for related tasks

### 8.2 Error Handling

1. **Implement retry logic**: Network errors and node unavailability are common
2. **Use exponential backoff**: Prevent overwhelming the system during outages
3. **Handle different error types**: 520/510/500 errors require different responses
4. **Log errors with context**: Include session_id, operation, and timing information

### 8.3 Performance Optimization

1. **Minimize screenshots**: Only take screenshots when necessary (they're large)
2. **Batch operations**: Combine multiple UI actions when possible
3. **Use appropriate timeouts**: Chrome operations can be slow on complex pages
4. **Enable network capture selectively**: Only when you need to monitor traffic

### 8.4 Element Interaction

1. **Always call /api/view first**: Get current element tree before interaction
2. **Prefer automation_id over element_id**: automation_id is more stable than coordinates
3. **Handle dynamic content**: Element positions may change as page loads
4. **Wait between operations**: Allow time for page updates and animations

### 8.5 Proxy Usage

1. **Test proxy availability**: Ensure proxies work before using them
2. **Monitor proxy health**: Proxies may become unavailable or blocked
3. **Use proxy pools**: Distribute load across multiple proxies
4. **Handle proxy authentication**: Use proper username:password format

### 8.6 Security Considerations

1. **Keep tokens secure**: Never expose tokens in client-side code
2. **Use HTTPS when possible**: Protect token transmission
3. **Implement token rotation**: Regularly update API tokens
4. **Monitor token usage**: Track and audit API access
5. **Restrict token scope**: Use node restrictions when appropriate

## 9. SDK and Libraries

### 9.1 Official Support

Currently, CrawlNode provides:
- **REST API**: Standard HTTP/JSON interface
- **OpenAPI specification**: Auto-generated from FastAPI endpoints
- **Dashboard UI**: Web interface for testing and management

### 9.2 Community Libraries

The following languages/frameworks have community-supported libraries:

- **Python**: `requests` library works well (see example above)
- **JavaScript/Node.js**: `axios` or `fetch` API
- **Java**: `OkHttp` or `Apache HttpClient`
- **C#**: `HttpClient`
- **Go**: `net/http` package
- **PHP**: `cURL` or `Guzzle`

### 9.3 Sample Integrations

#### Selenium Migration

If migrating from Selenium WebDriver, the key mappings are:

| Selenium | CrawlNode |
|----------|-----------|
| `driver = webdriver.Chrome()` | `POST /api/start` |
| `driver.get(url)` | `POST /api/go` |
| `driver.find_element().click()` | `POST /api/view` + `POST /api/click` |
| `driver.find_element().send_keys()` | `POST /api/input` |
| `driver.get_screenshot_as_png()` | `POST /api/screenshot` |
| `driver.quit()` | `POST /api/destroy` |

#### Testing Framework Integration

CrawlNode can be integrated with popular testing frameworks:

- **pytest**: Use fixtures for session management
- **unittest**: Override setUp/tearDown methods
- **Jest**: Use beforeEach/afterEach hooks
- **TestNG**: Use @BeforeMethod/@AfterMethod annotations

---

## Conclusion

This documentation provides comprehensive coverage of the CrawlNode API. For additional support:

1. **Dashboard UI**: Use the built-in API test page for interactive exploration
2. **Error Guide**: Refer to the separate error handling guide for troubleshooting
3. **Community**: Check the project repository for updates and community contributions

The API is designed to be compatible with existing browser automation workflows while providing the benefits of distributed architecture and managed infrastructure.