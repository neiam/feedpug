# FeedPug Android client

A minimal Kotlin / Jetpack Compose reader for FeedPug. It authenticates with a
per-user **API token** using the same device-pairing flow as `../dms`:

1. In the FeedPug web app, open the account menu → **Devices**, generate a token.
2. The page shows a QR encoding `feedpug://pair?base=<server>&token=<token>`.
3. The app **scans the QR** (or you open the URI / paste the fields), verifies it
   by calling `GET /api/profile`, and stores `(baseUrl, token)` in
   `EncryptedSharedPreferences`.
4. Every request then sends `Authorization: Bearer <token>`.

## Features (MVP)

- **Pair** screen: QR scan (ZXing) + manual URL/token entry + verify.
- **Timeline**: aggregated newsfeed, **full-text search** over entry bodies, your
  **saved views** as filter chips (tap to apply, "All" to clear), unread-only
  toggle, "load more" keyset pagination, mark-all-read, unpair. **Swipe a row
  left** to mark that entry unread.
- **Detail**: full entry rendered in a (JavaScript-disabled) WebView, marks the
  entry read on open, toggle reactions from your palette, open original in browser.
- **Theming**: FeedPug's **Blueprint** default plus the shared neiam OKLCh
  palettes (Her, After Dark, Forest, Sky, Clays, Stones, Dark, Light) and the
  **B612** typeface — the same set as the web frontend. Pick a theme from the
  palette menu in the timeline top bar; the choice persists in its own encrypted
  prefs file.

## Build

Requires Android Studio (Koala+) or a local Android SDK with JDK 17–21. Point at
your SDK via `local.properties` (`sdk.dir=/path/to/Android/Sdk`) or `ANDROID_HOME`.

```sh
cd android
./gradlew :app:assembleDebug      # builds app/build/outputs/apk/debug/app-debug.apk
./gradlew installDebug            # install on a connected device/emulator
```

Builds clean against AGP 8.5.2 / Gradle 8.9 (the wrapper is committed). Verified
to produce a debug APK with SDK platform 34 + build-tools 34/35/36.

## Connecting to a dev server

- The manifest sets `usesCleartextTraffic="true"` so you can point at a plain
  `http://` LAN address during development.
- On the **Android emulator**, the host machine is reachable at `http://10.0.2.2:4000`.
  Generate the web token while serving on that host, or just edit the Server URL
  field on the Pair screen after scanning.
- For real devices, use your machine's LAN IP (e.g. `http://192.168.1.50:4000`)
  or set `FEEDPUG_PUBLIC_URL` on the server so the QR encodes a reachable origin.

## Layout

```
app/src/main/java/org/neiam/feedpug/app/
  MainActivity.kt            # nav host + feedpug://pair deep-link handling
  data/PairUri.kt            # parse feedpug://pair?base=&token=
  data/TokenStore.kt         # EncryptedSharedPreferences credential store
  data/ThemeStore.kt         # persisted theme preference
  data/Models.kt             # kotlinx.serialization API models
  data/FeedPugClient.kt      # Retrofit API + Bearer interceptor
  ui/PairScreen.kt           # QR scan + manual pairing
  ui/TimelineScreen.kt       # newsfeed list + theme menu
  ui/DetailScreen.kt         # entry reader + reactions
  ui/theme/AppTheme.kt       # neiam OKLCh palettes (ALL_THEMES)
  ui/theme/Typography.kt     # B612 typography
  ui/theme/Theme.kt          # FeedPugTheme wrapper (palette + type)
res/font/                    # b612_regular.ttf, b612_bold.ttf
```
