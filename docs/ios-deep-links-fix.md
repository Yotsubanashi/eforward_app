# iOS Deep Links Fix — Password Reset Not Opening the App

**App:** E-Forward iOS (`com.ardentnetworks.eforward`, Team ID `K9973Z86YT`)
**Domain owner action required:** `eforward.ardentnetworks.com.ph` (Nuxt / openresty server)

---

## Problem

When a user taps the **password-reset link** in Outlook (e.g.
`https://eforward.ardentnetworks.com.ph/reset-password?token=…`), iOS opens the
web page in Safari **instead of the app's Reset Password screen**.

## Root cause

The reset link is an **iOS Universal Link**. For iOS to hand the link to the
app, the domain must serve an **Apple App Site Association (AASA)** file. Right
now that file is **not served correctly** — the Nuxt SPA catch-all returns the
website HTML for that path:

```
GET https://eforward.ardentnetworks.com.ph/.well-known/apple-app-site-association
→ 200 OK, Content-Type: text/html   ❌  (returns the Nuxt web page, not JSON)
```

Because iOS can't validate the file, it never routes the tap into the app.

> The app side is already correct and does **not** need changes. Once the server
> serves the file below, tapping the link will open the app's reset screen.

---

## What needs to be done (server side)

Serve this exact file at:

```
https://eforward.ardentnetworks.com.ph/.well-known/apple-app-site-association
```

**File contents (no `.json` extension on the filename):**

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "K9973Z86YT.com.ardentnetworks.eforward",
        "paths": [ "/reset-password", "/reset-password/*" ]
      }
    ]
  }
}
```

### Requirements (all must be true)

- [ ] Served over **HTTPS** with a valid certificate
- [ ] **`Content-Type: application/json`** (Apple rejects other content types)
- [ ] Returns **HTTP 200** with **no redirects** (no 301/302 to the SPA)
- [ ] The route is matched **before** the Nuxt/Vue SPA catch-all
- [ ] Filename has **no extension** (`apple-app-site-association`, not `.json`)
- [ ] No authentication / no cookies required to fetch it

---

## Example server config

### nginx / openresty

Place this **above** the SPA fallback `location /` block:

```nginx
location = /.well-known/apple-app-site-association {
    alias /var/www/eforward/apple-app-site-association;  # adjust path; no .json extension
    default_type application/json;
    add_header Cache-Control "public, max-age=3600";
}
```

### Nuxt 3 (alternative, if serving from the Nuxt app itself)

Put the file in the project's `public/` directory:

```
public/.well-known/apple-app-site-association
```

and add a route rule in `nuxt.config.ts` so it is returned as JSON and not
caught by the SPA fallback:

```ts
export default defineNuxtConfig({
  routeRules: {
    '/.well-known/apple-app-site-association': {
      headers: { 'content-type': 'application/json' },
    },
  },
})
```

---

## How to verify after deploying

```bash
curl -i https://eforward.ardentnetworks.com.ph/.well-known/apple-app-site-association
```

**Expected result:**

```
HTTP/1.1 200 OK
Content-Type: application/json
...

{"applinks":{"apps":[],"details":[{"appID":"K9973Z86YT.com.ardentnetworks.eforward","paths":["/reset-password","/reset-password/*"]}]}}
```

You can also validate with Apple's tool:
`https://app-site-association.cdn-apple.com/a/v1/eforward.ardentnetworks.com.ph`

---

## After it's live — important for testers

iOS downloads and caches the AASA file **when the app is installed or updated**,
not on every tap. So once the server change is live:

1. **Delete** the E-Forward app from the test device.
2. **Reinstall** from TestFlight (this triggers iOS to re-fetch the AASA file).
3. Request a password reset, open the email in Outlook, and tap the link.
4. The app should open directly on the **Reset Password** screen.

> The device also needs a working internet connection at install time so iOS can
> fetch the file from Apple's CDN.

---

## Reference — how it fits together

| Piece | Value / Location | Status |
|---|---|---|
| Associated domain (app entitlement) | `applinks:eforward.ardentnetworks.com.ph` | ✅ Already set in app |
| App ID | `K9973Z86YT.com.ardentnetworks.eforward` | ✅ |
| Reset link path | `/reset-password?token=…` | ✅ App handles it |
| AASA file on server | `/.well-known/apple-app-site-association` | ❌ **Needs this fix** |

The reference copy of the AASA file also lives in the app repo at
`md_file/well-known/apple-app-site-association`.
