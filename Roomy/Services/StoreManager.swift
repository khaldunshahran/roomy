import Foundation
import StoreKit

/// StoreKit 2 manager for the single non-consumable product "Roomy Forever"
/// (product id `roomy_forever_v1`). One product, one entitlement, no prices
/// hard-coded anywhere — the only price ever shown is `product.displayPrice`.
///
/// Entitlement is cached in UserDefaults ("roomy.unlocked") so restore works
/// offline once StoreKit has established it, and so a second device with the
/// same Apple ID picks the unlock up via `restore()` without needing the App
/// Store. No external payment links or web paywalls anywhere.
@MainActor
final class StoreManager: ObservableObject {

    static let productID = Config.storeProductID

    @Published private(set) var product: Product?
    @Published private(set) var isUnlocked: Bool = false
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseInProgress = false
    @Published private(set) var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        // Offline fast-path: trust the cached entitlement until StoreKit
        // proves otherwise.
        isUnlocked = UserDefaults.standard.bool(forKey: "roomy.unlocked")
        updatesTask = Task { await self.listenForTransactions() }
        Task { await self.load() }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Fetch the product from the App Store and verify any current entitlement.
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
            if product == nil {
                errorMessage = "Couldn't find the Roomy Forever product in the App Store. Try again in a moment."
            }
            await verifyEntitlements()
        } catch {
            errorMessage = "Couldn't reach the App Store. Check your connection and try again."
        }
    }

    /// Buy Roomy Forever. Never hard-codes a price — the only price ever
    /// displayed is `product.displayPrice` from StoreKit.
    func purchase() async {
        guard let product else {
            errorMessage = "Product isn't loaded yet."
            return
        }
        purchaseInProgress = true
        errorMessage = nil
        defer { purchaseInProgress = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    unlock()
                case .unverified:
                    errorMessage = "The purchase couldn't be verified. Contact support if you were charged."
                }
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Purchase is pending approval (e.g. Ask to Buy). It will unlock automatically once approved."
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Purchase failed. You were not charged. Please try again."
        }
    }

    /// Restore a prior Roomy Forever purchase: works after reinstall and on a
    /// second device signed in with the same Apple ID. `Transaction.updates`
    /// (via `listenForTransactions`) also re-verifies in the background; this
    /// is the explicit user-triggered path.
    func restore() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        var found = false
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.productID == Self.productID {
                    found = true
                    break
                }
            case .unverified:
                break
            }
            if found { break }
        }
        if found {
            unlock()
        } else {
            errorMessage = "No Roomy Forever purchase found for this Apple ID."
        }
    }

    /// Silent entitlement check used by `load()`: no error copy, just unlocks
    /// if the Apple ID owns the product.
    private func verifyEntitlements() async {
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.productID == Self.productID {
                    unlock()
                    return
                }
            case .unverified:
                break
            }
        }
    }

    /// Listens for transaction updates (purchases made elsewhere, pending
    /// approvals resolving, renewals, etc.). Runs for the lifetime of the app.
    private func listenForTransactions() async {
        for await update in Transaction.updates {
            if case .verified(let transaction) = update,
               transaction.productID == Self.productID {
                await transaction.finish()
                unlock()
            }
        }
    }

    /// Persist the entitlement locally so unlock survives offline launches and
    /// reinstalls (in combination with `restore()` against the Apple ID).
    private func unlock() {
        UserDefaults.standard.set(true, forKey: "roomy.unlocked")
        isUnlocked = true
    }
}
