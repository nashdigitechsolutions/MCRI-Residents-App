# Release checklist - MCRI Residents

## 1. One-time setup

- [x] **Upload key** (created 2026-11-22). `C:keysmcri-upload.jks`, alias `upload`.
  The password is in `C:keysmcri-upload-credentials.txt` and `android/key.properties` (git-ignored, never commit).
  **Back up both `C:keys` files** (password manager + offline copy). Lose them and you can't update the app.
  Certificate SHA-256: `D2:D6:A6:AA:60:8C:EF:EF:A9:50:33:E8:C9:5B:31:C2:20:E0:AE:D3:55:82:C8:A9:53:6A:AA:D5:D0:6E:B2:65`
  SHA-1: `23:44:47:52:09:76:70:3B:D0:DA:67:66:49:8A:58:AF:57:36:33:59` (some stores ask for these).
- [ ] **App ID** is `online.mcriresidents.app`. Once the app is published on Play, this ID can never change.
  Phones that have a debug build under the old `com.example…` ID will install this as a separate app. Uninstall the old one.

## 2. Backend first

- [ ] Run the SQL in `db/migrations/` (API repo) against the production database.
- [ ] Optional speed-up: Hyperdrive.
  1. Run `npx wrangler hyperdrive create mcri-db --connection-string="<DATABASE_URL>"`.
  2. Uncomment the `[[hyperdrive]]` block in `wrangler.toml` and paste in the printed id.
- [ ] Deploy the API with `npx wrangler deploy`.
- [ ] Smoke test:
  - log in
  - send a chat message
  - mark an equipment request bought
  - request a password reset and check the branded email in Gmail

## 3. Website

- [ ] Merge the website branch into `main`. Cloudflare Pages deploys it automatically.

## 4. App build

- [ ] Bump `version:` in `pubspec.yaml`. The number after `+` must go up for every Play upload.
- [ ] Run `flutter analyze` and `flutter test`. Both must be clean.
- [ ] Run `flutter build appbundle --release`. The output is `build/app/outputs/bundle/release/app-release.aab`.
- [ ] Optional: build a sideload APK with `flutter build apk --release --split-per-abi`.
- [ ] Install it on a real phone and check:
  - [ ] first-run tour, then sign in
  - [ ] push notifications arrive and open the right screen
  - [ ] dark mode
  - [ ] biometric unlock
  - [ ] puzzle on forgot password, on sign-up, and after 3 wrong passwords
  - [ ] admin dashboard charts and the table toggle

## 5. Play Console

- [ ] App icon (512×512), feature graphic (1024×500), at least 2 phone screenshots.
- [ ] Privacy policy URL. The app stores email, profile and chat data.
- [ ] Data safety form: email, name, messages and device push ID are collected. All of it is encrypted in transit.
- [ ] Content rating questionnaire. Choose "communication": the app has user chat.
- [ ] Start with an internal testing track, then roll out to production.

## 6. Website APK download (mcriresidents.online/download)

The APK is served from the R2 bucket `mcri-app-downloads` through the API (`/api/app/android`).
After building a new version, run these from the API folder:
```
npx wrangler r2 object put mcri-app-downloads/android/mcri-residents.apk --remote --file <path>app-release.apk --content-type application/vnd.android.package-archive
npx wrangler r2 object put mcri-app-downloads/android/latest.json --remote --file latest.json --content-type application/json
```
`latest.json` looks like `{"version":"1.1.0","build":2,"sha256":"<sha256 of the apk>"}`.
Use the universal `app-release.apk` (works on every phone).

## 7. Free Android stores

Upload the same signed build everywhere: universal `app-release.apk`, or `app-release.aab` where a store accepts bundles.
When a listing goes live, paste its link into `ANDROID_STORES` in the website's `src/pages/Download.tsx`. The row then stops saying "Coming soon".

| Store | Phones | Portal | Upload |
|---|---|---|---|
| Palm Store (do first) | Tecno, Infinix, itel | Dlightek / Transsion developer portal | APK |
| Samsung Galaxy Store | Samsung | Galaxy Store Seller Portal | APK |
| Xiaomi GetApps | Xiaomi, Redmi, POCO | Xiaomi Mi Developer Console | APK |
| Huawei AppGallery | Huawei, Honor | AppGallery Connect | APK or AAB |
| Uptodown / APKPure | any Android | their developer upload pages | APK |

Every store asks for: app name, short and full description, 512×512 icon, at least 2 phone screenshots, a category (Lifestyle or Communication),
a **privacy policy URL**, a support email, and a content rating ("communication" or "social": the app has user chat).

**Phones without Google services (Huawei).** Sign-in works because Google sign-in runs in the browser.
Push notifications use OneSignal over Firebase, so they won't arrive on Huawei phones without Google services.
Chat, the badge and the in-app banners still work while the app is open. For Huawei push, add OneSignal's Huawei (HMS) setup later.

**Every account needs approval.** The app is public, so new sign-ups wait in Admin > New accounts until an admin approves them.
This is on top of email verification.
