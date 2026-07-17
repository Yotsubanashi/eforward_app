# Face ID / Biometric Login — Backend Guide

This document describes **everything the backend must provide** so the mobile
app's Face ID / Fingerprint / PIN login works smoothly.

> ## Status: already implemented in `e-forward-server`
>
> A scan of the `e-forward-server` repo confirmed all three endpoints already
> exist and return the correct token keys:
> `POST /auth/mobile-login` (returns `accessToken` + `refreshToken`),
> `POST /auth/refresh`, and `GET /auth/me`.
>
> The only gap was refresh-token **lifetime** (mobile got 7 days and each
> refresh downgraded it). That is fixed on the branch
> **`feature/faceid-refresh-token`** — mobile logins now get a 30-day refresh
> token whose lifetime is preserved on rotation. See
> `e-forward-server/docs/FACEID_MOBILE_AUTH.md`.
>
> The rest of this document is the generic contract / reference, kept for any
> other backend (e.g. a second brand's server) that needs the same support.

The mobile side is already fully implemented. Biometric login only works when
the backend hands the app a **refresh token** and can exchange it for a fresh
**access token**. That is the entire job described here.

---

## 1. Why a refresh token is needed

"Face ID unlock" means: the user taps Face ID and is signed straight into the
dashboard **without typing a password**. To do that, the app must be able to
re-establish a session on its own. It does this by storing a long-lived
**refresh token** in the phone's secure enclave (iOS Keychain / Android
Keystore) and exchanging it for a new access token whenever the user unlocks.

So the backend must:

1. Return a `refreshToken` (and `accessToken`) when the user logs in.
2. Accept that `refreshToken` later and return a fresh `accessToken`.
3. Validate the access token on protected routes (already the case).

If the login response has **no** `refreshToken`, the app cannot do passwordless
Face ID — it falls back to replaying the stored password, which is less smooth
and breaks if anything about the password flow changes.

---

## 2. The contract (exact JSON the app expects)

The app accepts these key names (any one of each group):

- Access token: `accessToken` **or** `access_token` **or** `token`
- Refresh token: `refreshToken` **or** `refresh_token`

The examples below use `accessToken` and `refreshToken`.

### 2.1 `POST /auth/mobile-login` — add tokens to the response

Keep your existing response and **add two fields**.

**Request (unchanged):**
```json
{ "email": "ramon.napa@ardentnetworks.com.ph", "password": "••••••••" }
```

**Response 200 — add `accessToken` + `refreshToken`:**
```jsonc
{
  "message": "Login successful",
  "user": {
    "employee_id": "A0000939",
    "email_add": "ramon.napa@ardentnetworks.com.ph",
    "role": "ADMIN",
    "status": "ACTIVE"
  },
  "permissions": { "modules": [ /* ... */ ] },

  "accessToken": "<short-lived JWT>",   // NEW — required
  "refreshToken": "<long-lived token>"  // NEW — required for Face ID
}
```

### 2.2 `POST /auth/refresh` — new endpoint (the core of Face ID)

**Request:**
```json
{ "refreshToken": "<the stored refresh token>" }
```

**Response 200:**
```json
{
  "accessToken": "<new JWT>",
  "refreshToken": "<new/rotated refresh token>"
}
```

**Response 401 or 403** when the refresh token is missing, expired, or revoked.
The app treats this as "token no longer valid" and cleanly falls back to the
stored password — it does not crash.

> Returning a **rotated** `refreshToken` (a new one each refresh) is
> recommended. The app stores whatever new refresh token you return.

### 2.3 `GET /auth/me` — already used, confirm only

**Request header:**
```
Authorization: Bearer <accessToken>
Accept: application/json
```

**Response 200:** the user profile in the same shape login returns. Must
include an id (`employee_id` / `id`) and, to block disabled accounts, a status
field (`status` / `account_status` / `accountStatus`).

Inactive status values the app rejects: `ITV, INACTIVE, INA, DISABLED,
DEACTIVATED, SUSPENDED, BLOCKED`.

---

## 3. Reference implementation (Node.js / Express + `jsonwebtoken`)

Adapt to your actual stack. **Keep the JSON keys identical.**

```js
// npm i jsonwebtoken
const jwt = require('jsonwebtoken');

const ACCESS_SECRET  = process.env.JWT_ACCESS_SECRET;   // set in env
const REFRESH_SECRET = process.env.JWT_REFRESH_SECRET;  // a DIFFERENT secret
const ACCESS_TTL  = '30m';   // short-lived access token
const REFRESH_TTL = '60d';   // long-lived → Face ID keeps working for weeks

function issueTokens(user) {
  const payload = { sub: user.employee_id, email: user.email_add, role: user.role };
  const accessToken  = jwt.sign(payload, ACCESS_SECRET,  { expiresIn: ACCESS_TTL });
  const refreshToken = jwt.sign({ sub: user.employee_id }, REFRESH_SECRET, { expiresIn: REFRESH_TTL });
  return { accessToken, refreshToken };
}

// 1) LOGIN — add tokens to your existing response
app.post('/api/auth/mobile-login', async (req, res) => {
  const { email, password } = req.body;
  const user = await authenticate(email, password);      // your existing logic
  if (!user) return res.status(401).json({ message: 'Invalid credentials' });

  const { accessToken, refreshToken } = issueTokens(user);
  await saveRefreshToken(user.employee_id, refreshToken); // optional: for revocation

  return res.json({
    message: 'Login successful',
    user,
    permissions: await getPermissions(user),
    accessToken,          // NEW
    refreshToken,         // NEW
  });
});

// 2) REFRESH — new endpoint
app.post('/api/auth/refresh', async (req, res) => {
  const { refreshToken } = req.body;
  if (!refreshToken) return res.status(401).json({ message: 'Missing refresh token' });

  try {
    const decoded = jwt.verify(refreshToken, REFRESH_SECRET);
    if (!(await isRefreshTokenValid(decoded.sub, refreshToken)))   // optional revocation check
      return res.status(403).json({ message: 'Refresh token revoked' });

    const user   = await getUserById(decoded.sub);
    const tokens = issueTokens(user);
    await rotateRefreshToken(decoded.sub, refreshToken, tokens.refreshToken);
    return res.json(tokens);                                       // { accessToken, refreshToken }
  } catch (e) {
    return res.status(401).json({ message: 'Invalid or expired refresh token' });
  }
});

// 3) ME — verify the access token (you likely already have this)
app.get('/api/auth/me', requireAuth, async (req, res) => {
  const user = await getUserById(req.user.sub);
  return res.json({ user });
});

// Middleware used by /auth/me and every protected route
function requireAuth(req, res, next) {
  const h = req.headers.authorization || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : null;
  if (!token) return res.status(401).json({ message: 'No token' });
  try {
    req.user = jwt.verify(token, ACCESS_SECRET);
    next();
  } catch {
    return res.status(401).json({ message: 'Invalid or expired token' });
  }
}
```

### Optional revocation table (recommended)

If you want to be able to revoke a device's biometric session (e.g. "log out
all devices"), store refresh tokens server-side:

```sql
CREATE TABLE refresh_tokens (
  id          BIGINT PRIMARY KEY AUTO_INCREMENT,
  employee_id VARCHAR(20)  NOT NULL,
  token_hash  VARCHAR(255) NOT NULL,   -- store a hash, never the raw token
  expires_at  DATETIME     NOT NULL,
  revoked     BOOLEAN      DEFAULT 0,
  created_at  DATETIME     DEFAULT CURRENT_TIMESTAMP
);
```

- `saveRefreshToken` inserts a row (hash the token first).
- `isRefreshTokenValid` checks the hash exists, is not revoked, not expired.
- `rotateRefreshToken` revokes the old row and inserts the new one.

Revocation is optional. Plain stateless JWT refresh tokens also work; you just
can't force-log-out a device before the token expires.

---

## 4. Token lifetime — this is what makes it "smooth"

| Token | Recommended TTL | Why |
|-------|-----------------|-----|
| Access token  | 15–30 minutes | Short; refreshed automatically. |
| Refresh token | **30–90 days** | Long; lets Face ID work for weeks without re-typing the password. |

If the refresh token expires quickly, Face ID will constantly fall back to the
password path — which is exactly the behavior we're trying to remove.

---

## 5. Do it on BOTH backends

The app selects the backend by the user's email domain:

- Ardent:    `https://eforward-api.ardentnetworks.com.ph/api`
- Versatech: `https://eforward-api.versatech.com.ph/api`

Both must:
- Return `refreshToken` on `/auth/mobile-login`.
- Implement `POST /auth/refresh` identically.

Otherwise Face ID works for one company's users but not the other's.

---

## 6. Test checklist

1. Deploy backend changes.
2. App: log in with password → confirm the login response now contains
   `refreshToken`.
3. App: Settings → enable Biometric (stores email + password + refresh token).
4. App: log out.
5. App: on the login screen tap Face ID → should go straight to the dashboard,
   **no password dialog**.
6. Wait past the access-token expiry (e.g. 31 min) → tap Face ID again → still
   works (refresh renews the access token).
7. Revoke the refresh token server-side (or change password) → tap Face ID →
   app shows an error and asks for a password login. ✔ expected.

---

## 7. Summary — what the backend team must ship

- [ ] `POST /auth/mobile-login` returns `accessToken` **and** `refreshToken`.
- [ ] `POST /auth/refresh` accepts `{ "refreshToken" }`, returns fresh
      `accessToken` (+ rotated `refreshToken`); `401/403` when invalid.
- [ ] `GET /auth/me` returns the profile for `Bearer <accessToken>` (likely
      already done).
- [ ] Refresh token TTL is long (30–90 days).
- [ ] Shipped to **both** Ardent and Versatech backends.
