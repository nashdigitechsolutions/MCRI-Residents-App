# Release checklist — MCRI Residents

## 1. One-time setup

- [ ] **Upload key.** Create it once and back it up somewhere safe. If you lose it, you can't publish updates.
  ```
  keytool -genkey -v -keystore C:\keys\mcri-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
  ```
  Then create `android/key.properties`. Git ignores this file; never commit it.
  ```
  storePassword=…
  keyPassword=…
  keyAlias=upload
  storeFile=C:/keys/mcri-upload.jks
  ```
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
