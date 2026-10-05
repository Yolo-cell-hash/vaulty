# Vaulty

Your 100% offline external brain & expiry engine. Built with Flutter for iOS and Android.

Vaulty stores the little facts you keep forgetting (shoe sizes, paint colors, Wi‑Fi codes) and the
things that expire (passports, insurance, subscriptions). It warns you before they lapse, and nothing ever
leaves the phone.

## Features

- **Smart capture**: type naturally (`Car insurance expires Nov 12, Policy #9812`) and the on-device
  parser pulls out the title, category, expiry date and details. You can also snap a document and ML Kit
  OCR reads it on-device.
- **Expiry Radar**: a bento grid and a full list sorted by urgency, with countdowns.
- **Memory Bank**: micro-cards for static facts, with values in monospace.
- **Ask your vault**: natural-language search backed by SQLite FTS5.
- **Local reminders**: scheduled with the OS only. The defaults are set during onboarding (time of day
  and how much warning) and can be changed under You → Reminders. Each item can pick its own days and
  time, or switch reminders off. Repeating dates default to 30/7/1 days before yearly dates and 3/1 before
  monthly ones. Tapping a reminder opens its item, whether or not the app was already running.
- **Repeating dates**: birthdays and anniversaries repeat yearly, and subscriptions can repeat monthly or
  yearly. They count down to the next occurrence and never show as "expired". With a birth year, the app
  shows "turns 28". A subscription with a date and no stated cadence is assumed to repeat monthly.
- **"Renewed it"**: when a passport or policy is renewed, tap *Renewed it* on the item (or swipe it right on
  the Radar) and pick +1 month to +10 years or an exact date. The countdown and reminders reset.
- **Undo delete**: deleting shows an Undo toast for 8 seconds. The row is soft-deleted first, and anything
  still pending when the app is killed is purged, photos included, on the next launch.
- **Personalised start**: onboarding goals order the capture templates and the "Try saying" examples.
- **People & tags**: "Mom's shoe size" links to Mom automatically, and `#car` becomes a tag. Each person
  and tag has its own page, and you can rename, merge or remove them.
- **Zero-trust storage**: SQLCipher AES-256 database, AES-GCM encrypted photos, and keys in iOS Keychain /
  Android Keystore. The app locks with Face ID / fingerprint / device PIN, and sensitive items stay blurred
  until you verify.
- **Encrypted `.vault` backups**: export everything, photos included, to Files / iCloud Drive / Google Drive,
  sealed with a passphrase. Restoring merges into the vault, and the most recently edited copy wins.
- A privacy cover hides the vault in the app switcher, and the app auto-locks after 20 seconds in the
  background.

## Project layout

```
lib/
  data/          SQLCipher database, schema, FTS5 index, repository
  models/        Memory, categories, urgency helpers
  services/      parser, OCR, notifications, auth, secure keys, encrypted attachments, settings
  state/         Riverpod providers
  screens/       onboarding, home, radar, search, me, capture, editor, detail, lock
  widgets/       mascot (drawn in code), cards, shared UI kit, iOS/Android system pieces (adaptive,
                 flow_sheet, nav_bar, swipe_actions)
  theme/         design tokens: paper/ink palette, type scale, spacing (see DESIGN.md)
  widgets/glyphs.dart   Vaulty Glyphs, the app's own icon set
assets/fonts/    Instrument Serif + Instrument Sans + DM Mono (bundled, OFL; no runtime downloads)
```

## Design

The UI follows the "Editorial Vault" system in [DESIGN.md](DESIGN.md): serif display type, paper and ink,
one violet brand colour, a lime accent, custom glyph icons, and no emoji, gradients or drop shadows.

The brand looks the same on both platforms, but system pieces take each platform's own form: on iOS that means
alerts, action sheets, pull-down menus, date wheels, stacked sheets for capture and editing, swipe actions, top
toasts and iOS haptics. [DESIGN.md](DESIGN.md#ios-and-android) has the full list.

## Running

```bash
flutter pub get
flutter run
```

- **Android**: minSdk 24. Release builds declare no `INTERNET` permission. R8 keep rules are in
  `android/app/proguard-rules.pro`.
- **iOS**: iPhone only, portrait. iPads run it in iPhone compatibility mode (see [DESIGN.md](DESIGN.md)).
  Deployment target 15.5 (required by ML Kit). Build on macOS with Xcode. On a Mac, run
  `cd ios && pod install` the first time.
- Both need Flutter 3.44 or newer (Dart 3.12), as set in `pubspec.yaml`.

## App icon

"Peekaboo" Vo. The sources in `assets/icon/` are rendered from the mascot painter:

- iOS: a full-bleed master, plus iOS 18 dark (`icon_ios_dark.png`, Vo on transparency over the system's dark
  backdrop) and tinted (`icon_ios_tinted.png`, a grayscale silhouette) variants. Both are the Android
  foreground and monochrome layers scaled 1.5x about the centre, which is the master's composition.
- Android: an adaptive foreground on the full 108dp canvas, plus a monochrome layer for themed icons.
- Notifications: `ic_stat_vaulty`, a white silhouette.

Regenerate the platform sizes with:

```bash
dart run flutter_launcher_icons
```

## Splash screen

A native splash (Vo on paper, or obsidian in dark mode) covers Android 12+'s SplashScreen API, older
Android and the iOS launch storyboard. It hands off to `SplashIntro` (`lib/widgets/splash_intro.dart`), which
starts from the identical frame and plays a roughly 1.5 s intro: Vo winks, the wordmark rises and the lime
dot pops. Tapping skips it, and it's skipped entirely when the system's reduce-motion setting is on. The lock
screen's biometric prompt waits until the intro ends.

- Native assets come from `assets/splash/splash_vo.png`, a 288 dp canvas at 4x with Vo at 176 dp, which fits
  Android 12's 192 dp icon circle.
- Regenerate them with `dart run flutter_native_splash:create`.
- If you change Vo's size, keep `SplashIntro.mascotSize` in sync so the handoff stays seamless.

## Tests

```bash
flutter test
```

`test/smart_parser_test.dart` covers the natural-language and OCR parsing rules.
`test/backup_test.dart` covers the `.vault` format: round-trip, wrong passphrase and tamper detection.
`test/recurrence_test.dart` covers repeating dates: leap days, short months and parser cadence detection.
`test/reminders_test.dart` covers reminder planning: defaults, per-item overrides, "don't remind me" and the
iOS 64-pending cap.
`test/database_test.dart` runs the schema migrations on desktop SQLite (`sqflite_common_ffi`): a v1
database upgrades without data loss, migrations are safe to re-run, and soft delete/undo/purge behave.
`test/adaptive_test.dart` checks that each platform gets its own dialogs, pickers, toasts, menus and sheets, that
a flow sheet closes whole and holds unsaved changes, and that swipe actions fire.

## Database upgrades

`VaultDatabase.schemaVersion` is the source of truth. Every schema change gets a new `_migrateToVN` step in
`onUpgrade`, which runs each step in order from the installed version. Rules:

- Only add things (columns with defaults, tables, indexes). Never drop or rename in place.
- Use `_addColumn`, which checks `PRAGMA table_info` first, so a half-finished upgrade can be re-run.
- Add a case to `test/database_test.dart` that builds the previous version and upgrades it.

| Version | Change |
|---|---|
| 1 | Memories, metadata, attachments, reminders, FTS5 index |
| 2 | Tags and people |
| 3 | Recurrence |
| 4 | Per-item reminders (`reminder_offsets`, `reminder_minutes`, `remind`) and soft delete (`deleted_at`) |

## Privacy and accessibility

- [PRIVACY.md](PRIVACY.md) is the public privacy policy. [STORE_PRIVACY.md](STORE_PRIVACY.md) has the App Store
  privacy label and Play Data safety answers, including how the ML Kit telemetry is handled on each platform.
- `ios/Runner/PrivacyInfo.xcprivacy` is the app's privacy manifest.
- On Android the vault is excluded from cloud backup and device transfer
  (`res/xml/data_extraction_rules.xml`).
- Every memory card reads as one sentence to TalkBack and VoiceOver (title, category, when it's due, the
  headline value unless hidden, and people). Tabs, chips and options announce their selected state, and
  switch rows read as one control.
- Text scales with the system setting up to 2x. Dense pieces (the nav capsule, tabs, date blocks,
  countdown badges) clamp lower. Text colours meet WCAG AA (4.5:1) in both themes.

## `.vault` backup format

```
"VLTY" | version (1B) | PBKDF2 iterations (u32 BE) | salt (16B) | nonce (12B) | ciphertext | GCM tag (16B)
```

- Key: PBKDF2-HMAC-SHA256 over the passphrase, 600k iterations, with a random salt per file.
- Payload: gzip(JSON) encrypted with AES-256-GCM. The header is authenticated as associated data, so a
  changed iteration count or salt is detected.
- Photos are decrypted into memory, embedded, and re-encrypted with the device key on restore. Plaintext
  never touches disk. Very large photo libraries are held in memory while exporting.

## Notes and limitations

- OCR uses Google ML Kit's bundled on-device model on both platforms. It is not Apple Vision.
- Voice capture relies on the keyboard's dictation mic. No speech SDK is bundled, because some of them
  use the network.
