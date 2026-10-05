// PurchaseManagerTests.swift
// Free-tier allowance logic. (The StoreKit purchase flow itself is Apple's code,
// exercised manually via the Racebound.storekit config in the shared scheme.)

import XCTest
@testable import PaceSync

@MainActor
final class PurchaseManagerTests: XCTestCase {

    override func setUp() async throws {
        PurchaseManager.shared._resetFreeTierForTesting()
    }

    override func tearDown() async throws {
        PurchaseManager.shared._resetFreeTierForTesting()
    }

    func testFreshInstallHasFreeAllowance() {
        let pm = PurchaseManager.shared
        XCTAssertTrue(pm.canImportPlan, "A fresh install gets one free plan import")
        XCTAssertTrue(pm.canCreateOneOff, "A fresh install gets free one-off workouts")
        XCTAssertEqual(pm.freeOneOffsLeft, PurchaseManager.freeOneOffs)
    }

    func testPlanImportAllowanceIsConsumedOnlyWhenRecorded() {
        let pm = PurchaseManager.shared
        // Checking the gate repeatedly must NOT consume the allowance.
        _ = pm.canImportPlan
        _ = pm.canImportPlan
        XCTAssertTrue(pm.canImportPlan)

        pm.recordPlanImport()   // the successful-save hook
        if pm.isUnlocked {
            XCTAssertTrue(pm.canImportPlan, "Unlocked users are never gated")
        } else {
            XCTAssertFalse(pm.canImportPlan, "Free allowance is one plan import")
        }
    }

    func testOneOffAllowanceCountsDown() {
        let pm = PurchaseManager.shared
        guard !pm.isUnlocked else { return }   // entitlement present in this environment
        for i in 0..<PurchaseManager.freeOneOffs {
            XCTAssertTrue(pm.canCreateOneOff, "One-off \(i + 1) should be allowed")
            pm.recordOneOff()
        }
        XCTAssertFalse(pm.canCreateOneOff, "Allowance exhausted after \(PurchaseManager.freeOneOffs)")
        XCTAssertEqual(pm.freeOneOffsLeft, 0)
    }

    func testCountersSurviveViaMaxOfBothStores() {
        let pm = PurchaseManager.shared
        guard !pm.isUnlocked else { return }
        pm.recordPlanImport()
        // Simulate a reinstall wiping UserDefaults but not the iCloud KV mirror.
        UserDefaults.standard.removeObject(forKey: "racebound.free.planImports")
        XCTAssertFalse(pm.canImportPlan,
                       "The iCloud mirror must keep the allowance consumed after reinstall")
    }
}
