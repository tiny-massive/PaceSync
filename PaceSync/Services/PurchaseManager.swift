// PurchaseManager.swift
// One-time "Full Version" unlock (StoreKit 2) + the free-tier allowance it gates.
// Model: free download → 1 free plan import + a few one-off workouts → $12.99 unlock.
// The StoreKit entitlement is the ONLY source of truth for the unlock; the free-tier
// counters live in UserDefaults with an iCloud KV mirror (reads take the max of both,
// so a reinstall doesn't reset the allowance).

import Combine
import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {

    static let shared = PurchaseManager()
    static let productID = "studio.schoolwork.pacesync.fullversion"

    // Free-tier allowances (counted only on SUCCESSFUL saves — a failed parse
    // never burns the allowance; see recordPlanImport/recordOneOff call sites).
    static let freePlanImports = 1
    static let freeOneOffs = 3

    @Published private(set) var isUnlocked = false
    @Published private(set) var product: Product?
    @Published private(set) var purchaseInFlight = false

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task { await listenForTransactions() }
        Task {
            await refreshEntitlement()
            await loadProduct()
        }
    }

    // MARK: - Entitlement

    func refreshEntitlement() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result,
               t.productID == Self.productID, t.revocationDate == nil {
                unlocked = true
            }
        }
        isUnlocked = unlocked
    }

    /// Keeps the unlock live across devices/refunds while the app runs.
    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard case .verified(let t) = result else { continue }
            if t.productID == Self.productID {
                isUnlocked = t.revocationDate == nil
            }
            await t.finish()
        }
    }

    func loadProduct() async {
        if product == nil {
            product = try? await Product.products(for: [Self.productID]).first
        }
    }

    // MARK: - Purchase / restore

    enum PurchaseOutcome: Equatable {
        case success, cancelled, pending
        case failed(String)
    }

    func purchase() async -> PurchaseOutcome {
        await loadProduct()
        guard let product else {
            return .failed("The App Store product couldn't be loaded. Check your connection and try again.")
        }
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed("The purchase couldn't be verified.")
                }
                await transaction.finish()
                isUnlocked = true
                return .success
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed("Unknown purchase result.")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Re-syncs with the App Store (prompts for sign-in if needed) and re-reads entitlements.
    func restore() async -> Bool {
        try? await AppStore.sync()
        await refreshEntitlement()
        return isUnlocked
    }

    // MARK: - Free tier

    private static let plansKey = "racebound.free.planImports"
    private static let oneOffsKey = "racebound.free.oneOffs"

    private func used(_ key: String) -> Int {
        max(UserDefaults.standard.integer(forKey: key),
            Int(NSUbiquitousKeyValueStore.default.longLong(forKey: key)))
    }

    private func bump(_ key: String) {
        let v = used(key) + 1
        UserDefaults.standard.set(v, forKey: key)
        NSUbiquitousKeyValueStore.default.set(Int64(v), forKey: key)
    }

    var canImportPlan: Bool { isUnlocked || used(Self.plansKey) < Self.freePlanImports }
    var canCreateOneOff: Bool { isUnlocked || used(Self.oneOffsKey) < Self.freeOneOffs }
    var freeOneOffsLeft: Int { max(0, Self.freeOneOffs - used(Self.oneOffsKey)) }

    /// Call ONLY after the plan is durably saved.
    func recordPlanImport() { if !isUnlocked { bump(Self.plansKey) } }
    /// Call ONLY after the one-off workout is saved.
    func recordOneOff() { if !isUnlocked { bump(Self.oneOffsKey) } }

    #if DEBUG
    /// Test seam — clears the free-tier counters in both stores.
    func _resetFreeTierForTesting() {
        UserDefaults.standard.removeObject(forKey: Self.plansKey)
        UserDefaults.standard.removeObject(forKey: Self.oneOffsKey)
        NSUbiquitousKeyValueStore.default.removeObject(forKey: Self.plansKey)
        NSUbiquitousKeyValueStore.default.removeObject(forKey: Self.oneOffsKey)
    }
    #endif
}
