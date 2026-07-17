# Face ID / Biometric Login — Frontend Guide

This documents how biometric login works **in the Flutter app** — the flow, the
files involved, and the exact code paths. The app side is fully implemented; it
only needs the backend to return a refresh token (see
`BIOMETRIC_BACKEND_GUIDE.md`).

---

## 1. The idea

There are two independent security features, both in **Settings → Security
Settings**:

1. **Biometric / Fingerprint / PIN unlock** — an alternate *way to log in*. A
   Face ID button on the login screen that signs the user in with no typing.
2. **Two-factor authentication** — after email+password, require a device
   biometric/PIN check before entering. (Not the subject of this doc.)

This doc is about #1.

"Face ID unlock" must sign the user in **without a password prompt**. To do that
the app needs something it can replay on its own. It stores, in the phone's
secure enclave, up to three things captured from a real login:

- the **email**,
- the **password**,
- the **refresh token** (preferred).

On a Face ID tap it prefers the refresh token (no password sent at all) and
falls back to the stored email+password only if the token is missing/expired.

---

## 2. Where things are stored

| Data | Storage | Survives logout? | Survives uninstall? |
|------|---------|------------------|---------------------|
| email / password / refresh token (for biometric) | Secure enclave (iOS Keychain / Android Keystore) via `flutter_secure_storage` | ✅ yes | iOS: yes / Android: no |
| access_token / refresh_token (current session) | `SharedPreferences` | ❌ cleared on logout | no |
| biometric toggle on/off | `SharedPreferences` | ✅ yes | no |

Secure-enclave storage is what lets the user log out and still come back with
Face ID.

### Files

| File | Responsibility |
|------|----------------|
| `lib/services/biometric_credential_store.dart` | Read/write email, password, refresh token in the secure enclave. |
| `lib/services/secure_unlock_service.dart` | The device biometric prompt (`local_auth`), the toggle flags, and resolving Face ID vs Fingerprint vs PIN. |
| `lib/screens/settings/security_screen.dart` | The Settings toggle. Arms (captures + stores) the credential when turned on. |
| `lib/screens/auth/login_screen.dart` | The Face ID button and the login flow it drives. |
| `lib/app.dart` | On startup, mirrors the live session's refresh token into the secure enclave when biometric is on. |

---

## 3. Flow — enabling biometric login (Settings)

`security_screen.dart` → `_onToggleBiometric(true)`:

1. Check the device actually supports biometric/PIN. If not, show an error and
   stop.
2. **Always** capture a fresh credential (`_armCredentialWithPassword`):
   - Read the signed-in user's email from the session.
   - Ask the user to confirm their password **once** (a dialog).
   - Verify it by calling `POST /auth/mobile-login`.
   - On success, store **email + password + refresh token** in the secure
     enclave.
   - On cancel or wrong password → leave the toggle **OFF** (never enable
     without a stored credential).
3. Only after a credential is stored, set the toggle ON.

This guarantees: **if the toggle is on, a valid credential is always stored.**
That is why the login screen never needs a setup dialog.

```
Settings toggle ON
     │
     ├─ device supports biometrics?  ── no ─▶ error, stop
     │            │ yes
     ├─ confirm password once (dialog)
     ├─ verify via /auth/mobile-login  ── fail ─▶ error, toggle stays OFF
     │            │ ok
     ├─ store email + password + refreshToken  (secure enclave)
     └─ toggle = ON
```

---

## 4. Flow — logging in with Face ID (Login screen)

`login_screen.dart` → `_handleBiometricLogin`:

1. **Device biometric prompt** (`SecureUnlockService.authenticate`,
   `biometricOnly: true` for Face ID/Fingerprint).
   - Fail / cancel → error *"Authentication failed. Please try again."* and
     stop. **No fallback.**
2. Face ID passed → **preferred path** `_tryBiometricRefreshLogin`:
   - Read the stored **refresh token**. If none → skip to step 3.
   - Select the correct backend from the stored email.
   - `POST /auth/refresh` with the token → get a new access token.
   - `GET /auth/me` with the new access token → load the profile.
   - Save new tokens, go to the dashboard. **No password sent, no dialog.**
3. If the refresh path didn't succeed → **fallback** stored email+password:
   - Read stored `{email, password}`.
   - `POST /auth/mobile-login` silently (no dialog).
   - On success → dashboard. On failure (e.g. password changed) → clear the
     stored credential, hide the button, ask for a password login.
4. If **nothing** is stored (shouldn't happen when the toggle is on) → show an
   error telling the user to log in with a password once. **No password
   dialog** is shown.

```
Tap Face ID
     │
     ├─ device biometric prompt ── fail/cancel ─▶ error, STOP
     │            │ success
     ├─ refresh token stored? ── yes ─▶ /auth/refresh ─▶ /auth/me ─▶ Dashboard ✅ (no password)
     │            │ no / refresh failed
     ├─ email+password stored? ── yes ─▶ /auth/mobile-login (silent) ─▶ Dashboard ✅
     │            │ no
     └─ error: "log in with your email and password once"  (no dialog)
```

Key point: there is **no password-confirmation dialog** on the login screen
anymore. Either Face ID logs you in, or you get an error. (The old
`_setupBiometricThenLogin` / `_promptForPassword` methods were removed.)

---

## 5. Flow — capturing the refresh token on a normal login

Every successful password login also arms biometric for next time:

- `login_screen.dart` → `_enterWithSession` stores the session, and if a
  `refreshToken` is present in the response, saves **email + password + refresh
  token** to the secure enclave.
- `app.dart` → `_captureRefreshTokenForBiometric` also mirrors the current
  session's refresh token into the secure enclave on startup when the toggle is
  on (covers app-update / already-signed-in cases).

So after the backend starts returning `refreshToken`, a user who simply logs in
once is fully armed for passwordless Face ID.

---

## 6. How the label / icon is chosen

`secure_unlock_service.dart` → `resolveMethod()` inspects the device's enrolled
biometrics:

- iPhone with Face ID → **Face ID** (icon + label).
- Touch ID / Android fingerprint → **Fingerprint**.
- Generic strong/weak (newer Android) → Fingerprint on Android, Face on iOS.
- Only a device passcode → **PIN** (and `biometricOnly` is relaxed so the OS
  passcode sheet is allowed).

---

## 7. What the app needs from the backend

Nothing on the app needs to change. It only needs the backend to:

1. Return `refreshToken` (and `accessToken`) on `POST /auth/mobile-login`.
2. Implement `POST /auth/refresh` → `{ accessToken, refreshToken }`.
3. Keep `GET /auth/me` returning the profile for `Bearer <accessToken>`.

See `BIOMETRIC_BACKEND_GUIDE.md` for the exact contract and reference code.

---

## 8. Diagnostic (temporary)

`login_screen.dart` has a temporary `🔑` debug block after a successful login
that prints the login response's top-level keys and the token fields. Use it to
confirm whether the backend already returns `accessToken` / `refreshToken`, then
remove it. Look for lines starting with `🔑` in the `flutter run` console.

---

## 9. Test checklist (app side)

1. Log in with password → console shows `🔑 refreshToken=<value>` (needs the
   backend change first).
2. Settings → enable Biometric → confirm password once.
3. Log out.
4. Login screen → tap Face ID → straight to dashboard, **no password dialog**.
5. Wait past access-token expiry → tap Face ID → still works.
6. Change the password on another device → tap Face ID → app clears the stored
   credential and asks for a password login.
