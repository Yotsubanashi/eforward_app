# How to Make the Reset-Password Link Open the App (Full Setup Guide)

**Goal:** When a user taps the password-reset link in Outlook / their email, the
**E-Forward app opens directly on the Reset Password screen** (instead of opening
the website in Safari).

**App:** E-Forward iOS — `com.ardentnetworks.eforward`, Team ID `K9973Z86YT`
**Domain:** `eforward.ardentnetworks.com.ph`
**Reset link format:** `https://eforward.ardentnetworks.com.ph/reset-password?token=…`

---

## How it works (the big picture)

There are two ways iOS can send a tapped link into the app. You only need **one**
of them working. This guide covers both — start with Option A.

| | Option A — Universal Link (recommended) | Option B — Custom scheme (fallback) |
|---|---|---|
| What the email link stays as | `https://…/reset-password?token=…` | same |
| Server change needed | ✅ Yes — serve the AASA file | ❌ No |
| Website change needed | ❌ No | ✅ Yes — add redirect script |
| Experience | Seamless — jumps straight into the app | Browser opens first, then bounces into app |

> ✅ **The app itself is already fully built for both options.** It registers the
> `eforward://` scheme and already routes `/reset-password?token=…` to the Reset
> Password screen. **No app code change and no new build is required** — only the
> server (Option A) or website (Option B) needs work.

---

## Option A — Universal Link (recommended)

For iOS to hand an `https://` link to the app, the domain must serve a small file
called the **AASA** (Apple App Site Association) at this exact URL:

```
https://eforward.ardentnetworks.com.ph/.well-known/apple-app-site-association
```

Right now that URL returns the website's HTML instead of the required JSON, so
iOS can't validate it and falls back to Safari. Fixing that is the whole job.

### The file contents (this IS the "file" — you create it, you don't download it)

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

### Setup with Nginx Proxy Manager (web UI) — no shell, no file upload

1. Log into **Nginx Proxy Manager**.
2. **Hosts → Proxy Hosts**, find `eforward.ardentnetworks.com.ph`, click **Edit**.
3. Open the **Advanced** tab → the **Custom Nginx Configuration** box.
4. Paste this and click **Save**:

```nginx
location = /.well-known/apple-app-site-association {
    default_type application/json;
    add_header Cache-Control "public, max-age=3600";
    return 200 '{"applinks":{"apps":[],"details":[{"appID":"K9973Z86YT.com.ardentnetworks.eforward","paths":["/reset-password","/reset-password/*"]}]}}';
}
```

Why this works:
- `return 200 '…'` **is** the file — nginx replies with this JSON directly, so
  there is no physical file to create or upload.
- `location =` is an **exact match**, so it beats the Nuxt/SPA catch-all
  (`location /`) — the request never reaches the website backend.
- `default_type application/json` sets the content type Apple requires.
- Saving in NPM auto-runs `nginx -t` and reloads; a bad config is rejected with
  an error and not applied.

### Setup with plain nginx / openresty (if NOT using NPM)

**1. Create the file** (no `.json` extension):

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

**2. Add this location block ABOVE the `location /` SPA fallback:**

```nginx
location = /.well-known/apple-app-site-association {
    alias /var/www/eforward/.well-known/apple-app-site-association;  # no .json extension
    default_type application/json;
    add_header Cache-Control "public, max-age=3600";
}
```

**3. Test and reload:**

```bash
sudo nginx -t
sudo systemctl reload nginx   # or: sudo systemctl reload openresty
```

### Requirements checklist (all must be true)

- [ ] Served over **HTTPS** with a valid certificate
- [ ] **`Content-Type: application/json`**
- [ ] Returns **HTTP 200** with **no redirects**
- [ ] Matched **before** the Nuxt/SPA catch-all
- [ ] Filename/path has **no `.json` extension**
- [ ] No authentication / no cookies required

### Verify it's live

Open the URL in a browser — you should see the raw JSON, not the website.

Or run:

```bash
curl -i https://eforward.ardentnetworks.com.ph/.well-known/apple-app-site-association
```

Expected:

```
HTTP/1.1 200 OK
Content-Type: application/json
...

{"applinks":{"apps":[],"details":[{"appID":"K9973Z86YT.com.ardentnetworks.eforward","paths":["/reset-password","/reset-password/*"]}]}}
```

You can also check Apple's cached copy:
`https://app-site-association.cdn-apple.com/a/v1/eforward.ardentnetworks.com.ph`

---

## Option B — Custom scheme fallback (no server change)

Use this only if you **cannot** change the server, or as a belt-and-suspenders
layer alongside Option A. This is a change to the **website's `/reset-password`
page**, not the app.

The idea: the web page opens as usual, detects the platform, and for mobile
redirects into the app using the custom scheme `eforward://reset-password?token=…`
(which the app already handles). Desktop users just see the normal web form.

```html
<script>
(function () {
  const params = new URLSearchParams(window.location.search);
  const token = params.get('token');
  if (!token) return; // no token -> stay on the web form

  const ua = navigator.userAgent || '';
  const isMobile = /iPhone|iPad|iPod|Android/i.test(ua);

  if (isMobile) {
    // Open the app via the custom scheme (no AASA needed)
    window.location.href = 'eforward://reset-password?token=' + encodeURIComponent(token);
    // If the app isn't installed, the browser stays here, so keep the
    // normal web reset form visible below as a fallback.
  }
  // Desktop: do nothing; show the website reset form.
})();
</script>
```

Trade-offs: the browser opens first then bounces into the app, iOS may show an
"Open in E-Forward?" prompt, and there is no app-install fallback (keep the web
form visible).

---

## Final testing on a device (required for Option A)

iOS downloads and caches the AASA file **only when the app is installed or
updated** — not on every tap. So after the server change is live:

1. **Delete** the E-Forward app from the test iPhone.
2. **Reinstall** from TestFlight (this triggers iOS to re-fetch the AASA file).
   The device needs internet at install time so iOS can fetch it from Apple's CDN.
3. Request a password reset, open the email in **Outlook**, and tap the link.
4. ✅ The app should open directly on the **Reset Password** screen with the token
   already applied.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| URL shows the website / HTML, not JSON | SPA catch-all is winning | Ensure the `location =` block is present and (plain nginx) placed **above** `location /` |
| `Content-Type` is `text/html` | Missing `default_type application/json` | Add it to the location block |
| Link still opens Safari after fix | iOS cached the old AASA | Delete + reinstall the app, ensure internet at install |
| Works on fresh install only | Expected iOS behavior | AASA is only fetched on install/update |
| `/.well-known/acme-challenge` conflict | Let's Encrypt block shadowing | Keep ACME scoped to `/.well-known/acme-challenge/` only |

---

## Reference — how the pieces fit

| Piece | Value / Location | Status |
|---|---|---|
| Associated domain (app entitlement) | `applinks:eforward.ardentnetworks.com.ph` | ✅ Already set in app |
| Custom URL scheme (app) | `eforward://` | ✅ Already registered |
| App deep-link handler | `lib/app.dart` → routes `/reset-password?token=…` | ✅ Already built |
| App ID | `K9973Z86YT.com.ardentnetworks.eforward` | ✅ |
| AASA file on server | `/.well-known/apple-app-site-association` | ❌ **Needs Option A** |

A reference copy of the AASA file also lives in the app repo at
`md_file/well-known/apple-app-site-association`.
