# Roomy

**Roomy** is an iPhone photo/video compressor. The one-line promise:

> **Free up iPhone storage by compressing photos and videos — safely, entirely on-device.**

## Key rules

- **On-device only.** All compression happens locally using Apple frameworks (Swift/SwiftUI). No servers, no accounts, no ads, no analytics, no tracking.
- **Verify-then-save.** Every compressed file is verified before it replaces anything — a failed verification keeps the original.
- **Recently Deleted only.** Originals are never hard-deleted by the app; with your confirmation they move to the iOS *Recently Deleted* album, where they stay recoverable.
- **One purchase.** A single €9.99 one-time, non-consumable StoreKit in-app purchase — no subscriptions.

## Repo layout

```
roomy/
├── README.md
├── SUBMISSION_CHECKLIST.md
├── PrivacyPolicy/
│   └── index.html            # Static privacy policy page (host this as the policy URL)
├── Roomy/
│   ├── Roomy.xcodeproj/      # Xcode project
│   ├── Roomy/                # App source (Swift/SwiftUI)
│   │   ├── Config.swift      # CONFIG values (see below)
│   │   ├── Resources/
│   │   │   └── AppIcon-src/
│   │   │       ├── icon-1024.png   # 1024×1024 icon master
│   │   │       └── ICON_NOTE.md    # How to generate the full iconset
│   │   └── Assets.xcassets/
│   │       └── AppIcon.appiconset/ # Generated icons + Contents.json
│   ├── Roomy.storekit        # Local StoreKit config for testing the purchase
│   └── ExportOptions.plist   # App Store export options (needs YOUR_TEAM_ID)
└── .github/
    └── workflows/
        ├── ios-compile-check.yml  # Free simulator build on every push
        └── ios-testflight.yml     # TestFlight upload (needs GitHub secrets)
```

## How to push

In **Windows PowerShell** (commands assume you are inside the repo folder):

```powershell
cd C:\path\to\roomy
git init
git add .
git commit -m "Initial Roomy commit"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/roomy.git
git push -u origin main
```

> Replace `YOUR_USERNAME` with your GitHub username.

## How CI builds

- **`ios-compile-check.yml`** — runs on every push. Builds the app for the iOS Simulator on GitHub's free runners. **No Apple account, no certificates, no secrets needed.**
- **`ios-testflight.yml`** — uploads a signed build to TestFlight. Runs manually (`workflow_dispatch`). **Requires the GitHub secrets** listed in `SUBMISSION_CHECKLIST.md` (signing certificate `.p12`, provisioning profile, App Store Connect API key).

## CONFIG values you must set

In `Roomy/Roomy/Config.swift`:

| Value | What to put |
|---|---|
| `privacyPolicyURLString` | The public URL where you host `PrivacyPolicy/index.html` |
| `supportEmail` | Your real support email address |

In `Roomy/ExportOptions.plist`:

| Value | What to put |
|---|---|
| `YOUR_TEAM_ID` | Your Apple Developer Team ID (find it in App Store Connect under your name) |

> ⚠️ **Bundle ID warning:** the bundle ID is `com.roomyapp.ios`. **It cannot be changed after the first App Store submission** — choose carefully before submitting.

## Testing the purchase locally

1. In Xcode, open the **Roomy** scheme's settings (Product → Scheme → Edit Scheme).
2. Under **Run → Options → StoreKit Configuration**, select `Roomy.storekit`.
3. Run the app — purchases now use Apple's local sandbox instead of the App Store.

## Icon

The 1024×1024 master is at `Roomy/Resources/AppIcon-src/icon-1024.png`. The full iOS iconset is generated from it — sizes and `Contents.json` details are described in [`ICON_NOTE.md`](Roomy/Resources/AppIcon-src/ICON_NOTE.md).
