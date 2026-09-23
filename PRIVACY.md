# Vaulty Privacy Policy

_Last updated: 23 September 2026_

Vaulty is a private notebook for facts and dates: sizes, codes, renewals, birthdays. It keeps everything on your phone. There are no accounts or servers, and we never see your vault.

> **Before publishing:** replace `privacy@YOUR-DOMAIN` and `[Developer name]` below. Host this page at a public URL; both stores ask for one.

## The short version

- Your vault is stored only on your device, and it is encrypted.
- Vaulty has no account, no sign-up, no ads and no analytics.
- We (the developer) collect nothing, and there is no Vaulty server to send anything to.
- On iOS, Google's text-recognition library sends anonymous diagnostics to Google. See [Text recognition (ML Kit)](#text-recognition-ml-kit).

## What Vaulty stores, and where

| What | Where it lives | Protection |
|---|---|---|
| Memories: titles, notes, details, dates, people and tags | An SQLCipher database in the app's private storage | AES-256. The key is generated on the device and held in the Android Keystore or iOS Keychain. |
| Photos you attach or scan | Files in the app's private storage | AES-256-GCM, with a key held in the Keystore or Keychain |
| Preferences: your first name (optional), onboarding goals, reminder time, theme, app-lock setting | Android Keystore-backed storage or the iOS Keychain | Encrypted by the operating system |
| Scheduled reminders | Your phone's notification scheduler | Local only |

None of this is uploaded, synced or shared by Vaulty. On Android, the vault is excluded from Google cloud backup and from device-to-device transfer. To move phones, use **You → Backup → Create backup**. That file is encrypted with a password you choose (AES-256-GCM, with the key derived through PBKDF2-SHA256 over 600,000 iterations). You decide where the file goes, and without the password it cannot be read, including by us.

## Permissions

| Permission | Why | When |
|---|---|---|
| Camera | To scan a document, card or label | Only when you tap **Scan a document** |
| Photos | To read text from a picture you pick | Only when you pick one |
| Face ID, fingerprint or device PIN | To lock the app | Only if you turn on app lock. Vaulty gets a yes or no from the system and never sees your biometrics. |
| Notifications | Reminders before something is due | You can turn them off in the app or in system settings |
| Run at startup (Android) | To restore scheduled reminders after a reboot | Automatic |

Scanning and text recognition happen on your device. Images are never uploaded.

Notifications show an item's title and when it is due, for example "Car insurance expires in 7 days". They never show the details stored inside it. You can hide notification content on your lock screen in your phone's settings.

## Text recognition (ML Kit)

Vaulty reads text from photos with Google ML Kit's on-device text recognition. Your images and the text found in them stay on your phone. ML Kit itself is built to send Google a small amount of diagnostic data, which Google [describes](https://developers.google.com/ml-kit/android-data-disclosure) as follows:

- device information: manufacturer, model, OS version
- app information: package name, app version
- a per-installation identifier. It is not your advertising ID and is not linked to you.
- performance metrics, API configuration, event types and error codes

Google says this data is used "for diagnostics and usage analytics", is encrypted in transit, and is not shared with third parties.

- **Android:** the release app has no internet permission at all, so this data cannot leave your phone.
- **iOS:** apps cannot be blocked from the network in the same way, so ML Kit may send this diagnostic data to Google when you use scanning. It contains nothing from your vault.

## What we don't do

- We do not collect, sell, rent or share personal data.
- We do not use advertising, tracking, analytics or crash-reporting services of our own.
- We do not combine data with other apps or websites.

## Children

Vaulty is not directed at children under 13 and collects no personal data from anyone.

## Deleting your data

- Delete an item: open it, then choose **More → Delete**. After an 8-second undo window it is permanently removed, along with its photos.
- Delete everything: go to **You → Erase everything**.
- Uninstalling the app deletes the vault. On iOS the system can keep the orphaned key in the Keychain; Vaulty wipes it the next time it is installed, and without the deleted database it unlocks nothing.

Because nothing is stored with us, there is nothing for us to delete or export on request.

## Changes

If this policy changes, we'll update the date above and describe the change in the release notes. Vaulty will never start collecting vault contents.

## Contact

[Developer name]: privacy@YOUR-DOMAIN
