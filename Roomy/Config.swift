import Foundation

/// Central configuration constants for Roomy.
/// Values marked CONFIG must be reviewed before the first TestFlight/App Store submission.
enum Config {
    static let appName = "Roomy"
    static let bundleID = "com.roomyapp.ios" // CONFIG: placeholder. WARNING: bundle ID cannot be changed after first App Store submission.
    static let storeProductID = "roomy_forever_v1"
    static let supportEmail = "support@roomyapp.example" // CONFIG: replace with real support email
    static let privacyPolicyURLString = "https://example.com/roomy/privacy" // CONFIG: replace with hosted policy URL
    static let appleStandardEULAURLString = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"

    enum FirstWin {
        static let maxItems = 10
    }

    enum Estimate {
        static let smartRatio = 0.70
        static let smallerRatio = 0.82
        static let bestRatio = 0.45
    }

    enum Reminders {
        static let backgroundTaskID = "com.roomyapp.ios.refresh"
    }
}
