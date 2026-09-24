# Roomy — App Store Submission Checklist

Only the manual steps the founder must do themselves. Technical build/test steps are in `README.md`.

## A. Apple Developer

- [ ] Enroll in the **Apple Developer Program** ($99/year) under your legal identity (individual or organization). You cannot submit without this.
- [ ] Note your **Team ID** (App Store Connect → your name → Team ID). You'll need it for `ExportOptions.plist` (see section D).

## B. App Store Connect

- [ ] Create the app record in App Store Connect (bundle ID `com.roomyapp.ios` — remember, this can never change after submission).
- [ ] Create a **non-consumable** in-app purchase with product ID `roomy_forever_v1` (€9.99 tier, "Lifetime" / "Forever unlock").
- [ ] Set the **privacy policy URL** to your hosted `PrivacyPolicy/index.html` URL.
- [ ] Set the privacy **nutrition label to "Data Not Collected"** — **only if the pre-submission network audit proves it** (see go/no-go gates below). If the audit finds any third-party data flow, do not claim this.
- [ ] Complete the age-rating questionnaire; target **4+**.

## C. GitHub secrets

Add these under *repo → Settings → Secrets and variables → Actions* so `ios-testflight.yml` can sign and upload:

| Secret | One-line how-to |
|---|---|
| `APPSTORE_ISSUER_ID` | App Store Connect → Users and Access → Integrations → App Store Connect API → copy the Issuer ID. |
| `APPSTORE_API_KEY_ID` | Same page → create a new API key with "Developer" role → copy the Key ID. |
| `APPSTORE_API_PRIVATE_KEY` | Download the `.p8` file when creating that key (only chance) → paste its entire contents. |
| `IOS_DIST_P12_BASE64` | Export your "Apple Distribution" certificate from Keychain Access as `.p12` → `base64` the file, paste the string. |
| `IOS_DIST_P12_PASSWORD` | The password you set when exporting that `.p12`. |
| `IOS_PROVISION_PROFILE_BASE64` | Download the App Store distribution provisioning profile from the Developer portal → `base64` the `.mobileprovision` file, paste the string. |

## D. Replace CONFIG placeholders

- [ ] `Config.swift` → `privacyPolicyURLString`: replace with the real public URL of your hosted `PrivacyPolicy/index.html`.
- [ ] `Config.swift` → `supportEmail`: replace the placeholder with your real support address (and update the same address in the hosted policy page — it's a template placeholder there too).
- [ ] `Roomy/ExportOptions.plist` → `YOUR_TEAM_ID`: replace with the Team ID from section A.

## E. TestFlight testing

- [ ] Install the build via **TestFlight** (internal or external tester).
- [ ] Run the **21-row device checklist** on a real iPhone:
  1. [ ] Live Photos keep their motion after compression
  2. [ ] HDR photo keeps its look (or the app warns HDR may change)
  3. [ ] Slow-motion video keeps audio in sync
  4. [ ] Portrait-mode photos compress correctly
  5. [ ] Edited assets (cropped/filtered) compress as displayed
  6. [ ] Long 4K video compression completes
  7. [ ] Low storage: graceful handling, no half-written files
  8. [ ] Incoming phone call mid-compression: work survives or restarts cleanly
  9. [ ] Airplane mode: everything works offline
  10. [ ] iCloud-only originals download before compressing
  11. [ ] Limited photo-library access: app works with the chosen set
  12. [ ] Denied photo access: app explains and doesn't crash
  13. [ ] Access revoked later in Settings: app handles it gracefully
  14. [ ] Cancelling a job keeps prior completed work intact
  15. [ ] Kill the app mid-job → relaunch: no lost originals, no duplicates
  16. [ ] Metadata (date, location) preserved in compressed copies
  17. [ ] Corrupt/unreadable file: reported to the user, not silently skipped
  18. [ ] A compression that would produce a *larger* file is discarded
  19. [ ] Purchase restores after delete + reinstall
  20. [ ] Purchase restores on a second device with the same Apple ID
  21. [ ] Notification permission denied: reminders off, nothing breaks
- [ ] Fix and re-test anything that fails before submitting.

## F. Screenshots

- [ ] Prepare screenshots in **6.7"** and **6.5"** display sizes.
- [ ] Order them in marketing order: (1) core promise (free up space), (2) compress flow, (3) before/after sizes, (4) verify-then-save safety, (5) one-time €9.99 purchase.

## G. Review notes draft

Paste this (adapted) into App Store Connect's review notes:

> Roomy is a one-time, non-consumable purchase (roomy_forever_v1). "Restore Purchases" is on the Settings screen; it queries StoreKit directly — no accounts.
>
> Compression flow is verify-then-save: every compressed file is verified before the original is touched.
>
> Deletion goes to the iOS Recently Deleted album (recoverable in the Photos app for 30 days) — the app never hard-deletes photos.
>
> The app supports limited photo-library access and fully degrades when access is denied.
>
> Test account: none needed — no login. To test the purchase, use a sandbox Apple ID.

## H. Go/no-go gates (all must pass before submitting)

- [ ] **Zero data-loss paths**: every manual compression path is verify-then-save; deletion only ever goes to Recently Deleted.
- [ ] **Network audit clean**: instrument the release build and confirm traffic goes only to Apple endpoints (App Store/StoreKit, iCloud if user-enabled). Nothing else.
- [ ] **Purchase restores**: on reinstall *and* on a second device, "Restore Purchases" works.
- [ ] **Label / policy / binary agree**: the privacy nutrition label, the hosted privacy policy, and what the binary actually does all say the same thing.

Then: submit for review.

---

> ⚖️ **Legal disclaimer:** the privacy policy and any terms in this repo are templates. They must be reviewed by a qualified lawyer before launch. This checklist is not legal advice.
