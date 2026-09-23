# Store privacy answers

The answers to give in App Store Connect ("App Privacy") and Play Console ("Data safety"), with the reasoning behind each. The public policy is in [PRIVACY.md](PRIVACY.md). Host it at a URL and paste that URL into both consoles.

**The one thing to account for:** Vaulty's own code sends nothing anywhere. The only thing that can is Google ML Kit text recognition, which is built to send anonymous diagnostics to Google. Google lists what it sends here:

- [Android data disclosure](https://developers.google.com/ml-kit/android-data-disclosure)
- [iOS data disclosure](https://developers.google.com/ml-kit/ios-data-disclosure)

| | Android | iOS |
|---|---|---|
| Can ML Kit's telemetry reach the network? | **No.** Release builds remove `android.permission.INTERNET` (see `android/app/src/release/AndroidManifest.xml`). | **Yes.** iOS has no per-app network permission. |
| What the label says | No data collected | Diagnostics and a device ID, not linked to the user, not used for tracking |

Re-check both after any dependency change. `flutter build apk --release`, then check `build/app/intermediates/merged_manifest/release/**/AndroidManifest.xml` (or run `aapt dump permissions` on the APK). It must still show no `INTERNET` permission. Checked on 23 Sep 2026, the merged release manifest requests:

- `USE_BIOMETRIC`
- `USE_FINGERPRINT`
- `RECEIVE_BOOT_COMPLETED`
- `POST_NOTIFICATIONS`
- `VIBRATE`
- `ACCESS_NETWORK_STATE`

`ACCESS_NETWORK_STATE` comes from ML Kit's transport library. It only lets code ask whether a network exists. It cannot send anything, and it is left in so that library doesn't throw.

---

## Apple App Store: App Privacy

**Do you or your third-party partners collect data from this app?** Yes. "Third-party partners" includes SDKs, and ML Kit is one.

Choose these data types and answer the same way for each:

| Data type (Apple's category) | ML Kit field it covers | Linked to the user? | Used for tracking? | Purpose |
|---|---|---|---|---|
| Identifiers → **Device ID** | Per-installation identifier. Google says it is not linked to the user; declared to be safe. | No | No | Analytics |
| Diagnostics → **Performance Data** | Latency and other performance metrics | No | No | Analytics |
| Diagnostics → **Other Diagnostic Data** | Device model and OS, app version, API configuration, event types, error codes | No | No | Analytics |

Everything else: **not collected**. That covers contact info, user content, photos, location, financial, health, browsing, search history, purchases, and usage data.

The resulting label reads **"Data Not Linked to You: Identifiers, Diagnostics"**, with no tracking section.

These match `ios/Runner/PrivacyInfo.xcprivacy`, which Xcode merges with ML Kit's own manifest when it generates the app's privacy report. ML Kit has shipped privacy manifests since its February 2024 release ([release notes](https://developers.google.com/ml-kit/release-notes)). Before submitting, open **Product → Archive → Generate Privacy Report** and confirm the report and the label agree.

Also in App Store Connect:

- **Privacy Policy URL:** the hosted PRIVACY.md.
- **App Tracking Transparency:** not needed. Nothing tracks, and there is no IDFA.
- **Encryption / export compliance:** Vaulty uses standard AES-256 through SQLCipher and the `cryptography` package, only to protect the user's own data. Answer the export-compliance questions to match. Once confirmed, you can add `ITSAppUsesNonExemptEncryption` to Info.plist so the question stops appearing on each upload.

## Google Play: Data safety

Play counts data as **collected** only when it is transmitted off the device. The Android release has no internet access, so neither Vaulty nor ML Kit can transmit anything. Data handled only on the device (the vault, OCR images and results, preferences) is not "collected" under Play's definition.

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **No** |
| (Shown after "No") | The listing reads "No data collected" and "No data shared with third parties" |

Put this in the **App content → Data safety** notes, or have it ready for a policy reviewer who asks about the ML Kit SDK:

> Vaulty is fully offline. The release build does not request android.permission.INTERNET (it is removed with tools:node="remove"), so no data can leave the device. Google ML Kit text recognition runs on-device; its diagnostic logging cannot transmit without network access. All user data is stored locally, encrypted (SQLCipher AES-256, key in Android Keystore), and is excluded from cloud backup and device transfer.

**If Play pushes back**, for example because its SDK Index flags ML Kit as a data collector, switch to the conservative answer. It matches Google's ML Kit disclosure:

| Data type | Collected | Shared | Ephemeral | Required | Purpose |
|---|---|---|---|---|---|
| Device or other IDs | Yes | No | No | Required | Analytics |
| App info and performance → Diagnostics | Yes | No | No | Required | Analytics |
| App info and performance → Other app performance data | Yes | No | No | Required | Analytics |

With that answer: encrypted in transit is Yes, and the deletion-request question is answered "no data is linked to a user". Don't pick this by default. It tells users the app sends data, which the Android build cannot do.

Other Play Console items:

- **Privacy policy URL:** the hosted PRIVACY.md. Required, even with "No data collected".
- **Permissions declarations:**
  - `USE_BIOMETRIC`: app lock.
  - `POST_NOTIFICATIONS`: reminders.
  - `RECEIVE_BOOT_COMPLETED`: re-arms reminders after a reboot.
  - None of these are restricted permissions.
- **Target audience:** 13+ (see "Children" in the policy).

## Data flow

| Data | Leaves the device? |
|---|---|
| Vault database | Never. The only way out is a user-initiated `.vault` export, protected by a password. |
| Photos and OCR text | Never |
| Preferences (name, goals, reminder defaults) | Never. Stored in the Keychain or Keystore. |
| Notifications | Local scheduler only. They show titles, never field values. |
| ML Kit diagnostics | Android: never, because there is no network. iOS: sent to Google, anonymous. |
