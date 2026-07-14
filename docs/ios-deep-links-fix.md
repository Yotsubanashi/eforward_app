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

### nginx / openresty — step by step

**Step 1 — Create the AASA file on the server** (no `.json` extension):

```bash
sudo mkdir -p /var/www/eforward/.well-known
sudo tee /var/www/eforward/.well-known/apple-app-site-association > /dev/null <<'EOF'
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
EOF
sudo chmod 644 /var/www/eforward/.well-known/apple-app-site-association
```

**Step 2 — Add the location block to the server config** for
`eforward.ardentnetworks.com.ph`.

> ⚠️ The block **must come before** the SPA fallback `location /` block,
> otherwise the Nuxt catch-all swallows the request and returns HTML. Use
> `location =` (exact match) so it always wins.

```nginx
server {
    listen 443 ssl;
    server_name eforward.ardentnetworks.com.ph;

    # ... existing ssl_certificate / ssl_certificate_key lines stay as they are ...

    # --- AASA file for iOS Universal Links (must be ABOVE "location /") ---
    location = /.well-known/apple-app-site-association {
        alias /var/www/eforward/.well-known/apple-app-site-association;  # no .json extension
        default_type application/json;
        add_header Cache-Control "public, max-age=3600";
    }

    # --- existing Nuxt / SPA fallback (leave as-is, keep it LAST) ---
    location / {
        try_files $uri $uri/ /index.html;
        # ... or existing proxy_pass to the Nuxt server ...
    }
}
```

**Step 3 — Test the config and reload nginx** (reload does not drop connections):

```bash
sudo nginx -t          # must print "syntax is ok" / "test is successful"
sudo systemctl reload nginx
# openresty: sudo systemctl reload openresty
```

**Common gotcha:** if there is a separate `location ^~ /.well-known/ { ... }`
block (e.g. for Let's Encrypt / certbot), an ACME block using `^~` can shadow
this exact-match one. Keep the ACME challenge scoped to
`/.well-known/acme-challenge/` only, so it does not capture the AASA path.

### Nginx Proxy Manager (jc21 web UI) — recommended for this setup

NPM proxies to a backend, so there is no easy file path to `alias`. Instead,
**return the JSON inline** — no file to upload, no volume to mount.

1. Open **Nginx Proxy Manager** → **Hosts** → **Proxy Hosts**.
2. Click the **⋮ / Edit** on the host for `eforward.ardentnetworks.com.ph`.
3. Go to the **Advanced** tab → **Custom Nginx Configuration** box.
4. Paste this block and **Save**:

```nginx
location = /.well-known/apple-app-site-association {
    default_type application/json;
    add_header Cache-Control "public, max-age=3600";
    return 200 '{"applinks":{"apps":[],"details":[{"appID":"K9973Z86YT.com.ardentnetworks.eforward","paths":["/reset-password","/reset-password/*"]}]}}';
}
```

Why this works:
- `location =` is an **exact match**, so it wins over NPM's default `location /`
  proxy block — the request never reaches the Nuxt backend.
- `return 200 '…'` serves the body directly with **HTTP 200, no redirect**.
- `default_type application/json` sets the content type Apple requires.

Saving in NPM automatically runs `nginx -t` and reloads; if the config is bad,
NPM shows an error and does **not** apply it. No shell access needed.

> If the SSL certificate is terminated by NPM (it usually is), the HTTPS + valid
> cert requirement is already satisfied — nothing else to do.

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
