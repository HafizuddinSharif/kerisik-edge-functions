# URL resolve and sanitize — portable logic

Extracted from `supabase/functions/api/import-recipe/index.ts` so you can reuse it in another project (Node, Deno, or browser).

---

## 1. `resolveToFinalUrl(url: string): Promise<string>`

**Purpose:** Follow HTTP redirects and return the final URL (after all 3xx redirects).

**Logic:**
- `fetch(url, { redirect: "follow" })` — the runtime follows redirects automatically.
- Return `response.url` — the final URL after redirects.

**Use case:** Short links (e.g. `youtu.be/...`, bit.ly) or platform URLs that redirect to a canonical location.

### Code (runtime-agnostic)

```typescript
async function resolveToFinalUrl(url: string): Promise<string> {
  const res = await fetch(url, { redirect: "follow" });
  return res.url;
}
```

**Notes:**
- In **Node 18+** use global `fetch`.
- In **Deno** and **browser** `fetch` is built-in.
- On network/HTTP errors, `fetch` throws; handle in the caller (retries, validation, etc.).

---

## 2. `sanitizeUrl(url: string): Promise<string>`

**Purpose:** Normalise and minimise a URL by:
- Resolving to a canonical form per platform (TikTok, Instagram, YouTube).
- Stripping query parameters when a canonical form is used.

**Logic (high level):**
1. **TikTok**  
   - If URL has `@username` and `/video/<id>`, keep `https://www.tiktok.com/@<username>/video/<id>` (no query).  
   - Else try to get canonical URL from the page `<link rel="canonical">` (requires `getCanonicalFromHtml`).  
   - Else if only `/video/<id>` is present, strip query params and return that URL.
2. **Instagram**  
   - If path is `/reel/<shortcode>`, normalise to `https://www.instagram.com/p/<shortcode>/` (reels and posts use the same `p/` form for the shortcode).
3. **YouTube**  
   - `youtube.com/watch?v=<id>` → `https://www.youtube.com/watch?v=<id>` (only `v` kept).  
   - `youtu.be/<id>` → `https://www.youtube.com/watch?v=<id>`.
4. **Anything else**  
   - Parse as `URL`, set `url.search = ""`, return `url.toString()`.

So “sanitize” = platform-specific canonical form + remove query string when we have a canonical form; otherwise just remove query string.

### Code (depends on `getCanonicalFromHtml` for TikTok fallback)

```typescript
async function sanitizeUrl(url: string): Promise<string> {
  let minimalUrl: string | null = null;

  // TikTok → prefer https://www.tiktok.com/@<username>/video/<video_id>
  if (url.includes("tiktok.com")) {
    const withUser = url.match(/\/@([^/]+)\/video\/(\d+)/);
    if (withUser) {
      minimalUrl = `https://www.tiktok.com/@${withUser[1]}/video/${withUser[2]}`;
    } else {
      const canonical = await getCanonicalFromHtml(url, "tiktok");
      if (canonical) {
        minimalUrl = canonical;
      } else {
        const idOnly = url.match(/\/video\/(\d+)/);
        if (idOnly) {
          const u = new URL(url);
          u.search = "";
          minimalUrl = u.toString();
        }
      }
    }
  } else if (url.includes("instagram.com")) {
    // Instagram reel → canonical /p/<shortcode>/
    const match = url.match(/\/reel\/([A-Za-z0-9_-]+)/);
    if (match) {
      minimalUrl = `https://www.instagram.com/p/${match[1]}/`;
    }
  } else if (url.includes("youtube.com")) {
    const match = url.match(/\/watch\?v=([A-Za-z0-9_-]+)/);
    if (match) {
      minimalUrl = `https://www.youtube.com/watch?v=${match[1]}`;
    }
  } else if (url.includes("youtu.be")) {
    const match = url.match(/youtu\.be\/([A-Za-z0-9_-]+)/);
    if (match) {
      minimalUrl = `https://www.youtube.com/watch?v=${match[1]}`;
    }
  }

  if (!minimalUrl) {
    const urlObj = new URL(url);
    urlObj.search = "";
    minimalUrl = urlObj.toString();
  }

  return minimalUrl;
}
```

---

## 3. `getCanonicalFromHtml(pageUrl: string, platform: "tiktok"): Promise<string | null>`

**Purpose:** For TikTok URLs that don’t already have `@username`, fetch the HTML and read `<link rel="canonical" href="...">` to get the canonical TikTok URL (with username).

**Logic:**
- GET `pageUrl` with a browser-like `User-Agent` and `Accept` header.
- For `platform === "tiktok"`, match:
  - `rel="canonical"` or `rel='canonical'`
  - `href` starting with `https://www.tiktok.com/@.../video/\d+`
- Parse that href as `URL`, clear `search`, return `url.toString()`.
- On any error (network, parse), return `null` so the caller can fallback (e.g. ID-only URL or original URL without query).

### Code

```typescript
async function getCanonicalFromHtml(
  pageUrl: string,
  platform: "tiktok"
): Promise<string | null> {
  try {
    const resp = await fetch(pageUrl, {
      redirect: "follow",
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
        Accept:
          "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      },
    });
    const html = await resp.text();

    if (platform === "tiktok") {
      const m = html.match(
        /<link[^>]+rel=["']canonical["'][^>]+href=["'](https?:\/\/www\.tiktok\.com\/@[^"']+?\/video\/\d+)["']/i
      );
      if (m) {
        const u = new URL(m[1]);
        u.search = "";
        return u.toString();
      }
    }
  } catch {
    // Caller falls back to ID-only or query-stripped URL
  }
  return null;
}
```

---

## 4. Usage in another project

Typical flow (same as in import-recipe):

```typescript
const rawUrl = "https://youtu.be/dQw4w9WgXcQ";
const resolved = await resolveToFinalUrl(rawUrl);   // e.g. https://www.youtube.com/watch?v=dQw4w9WgXcQ
const sanitized = await sanitizeUrl(resolved);       // same, or canonical form for TikTok/Instagram
// use sanitized for storage, dedup, or downstream API
```

**Dependencies:**
- Global `fetch` (Node 18+, Deno, browser).
- `URL` (built-in).

**Optional:** Add timeouts, retries, or validation (e.g. allowlist of hostnames) around `fetch` in your project.

---

## 5. Summary

| Function                 | Input              | Output        | Side effect      |
|--------------------------|--------------------|---------------|------------------|
| `resolveToFinalUrl`      | Any URL string     | Final URL     | 1 GET (redirects) |
| `getCanonicalFromHtml`   | Page URL, platform | Canonical URL or null | 1 GET (HTML) |
| `sanitizeUrl`            | Resolved URL       | Normalised URL | 0–1 GET (only for TikTok without @username) |

Chaining: **resolve → sanitize** gives a stable, minimal URL for comparison or storage across TikTok, Instagram, YouTube, and other domains (others get query params stripped only).
