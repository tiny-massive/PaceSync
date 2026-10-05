// PaywallSheet.swift
// The one-time-unlock paywall. Shown when the free allowance is used up.
// "Pay once. No subscription." is the product's positioning — the sheet says so.

import SwiftUI
import StoreKit

struct PaywallSheet: View {
    enum Context { case planImport, oneOff }
    var context: Context = .planImport
    /// Runs after a successful purchase/restore so the caller can resume the action.
    var onUnlocked: () -> Void = {}

    @ObservedObject private var purchases = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var errorText: String?
    @State private var restoring = false

    private var contextLine: String {
        switch context {
        case .planImport: return "You've used your free plan import."
        case .oneOff:     return "You've used your free custom workouts."
        }
    }

    var body: some View {
        VStack(spacing: Theme.s4) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.accent)
                .padding(.top, Theme.s6)

            Text("Unlock Racebound")
                .font(.psLargeTitle).foregroundStyle(Theme.ink)

            Text(contextLine)
                .font(.psCallout).foregroundStyle(Theme.ink2)

            VStack(alignment: .leading, spacing: Theme.s3) {
                bullet("Unlimited plan imports — PDF, text, or pasted")
                bullet("Unlimited one-off workouts")
                bullet("Every future update included")
            }
            .padding(.vertical, Theme.s2)

            Spacer(minLength: Theme.s2)

            if let errorText {
                Text(errorText)
                    .font(.psCaption).foregroundStyle(Theme.error)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.s5)
            }

            Button {
                Task { await buy() }
            } label: {
                HStack(spacing: 8) {
                    if purchases.purchaseInFlight {
                        ProgressView().controlSize(.small).tint(Theme.onAccent)
                    }
                    Text(purchases.product.map { "Unlock for \($0.displayPrice)" } ?? "Unlock")
                }
            }
            .buttonStyle(PSPrimaryButtonStyle())
            .disabled(purchases.purchaseInFlight)
            .padding(.horizontal, Theme.s5)

            Text("Pay once. Yours forever. No subscription.")
                .font(.psCaption).foregroundStyle(Theme.ink3)

            Button {
                Task { await restore() }
            } label: {
                if restoring {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Restore Purchase")
                }
            }
            .font(.psCallout).tint(Theme.ink2)
            .padding(.bottom, Theme.s5)
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .task { await purchases.loadProduct() }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15)).foregroundStyle(Theme.accent)
            Text(text).font(.psBody).foregroundStyle(Theme.ink)
        }
    }

    private func buy() async {
        errorText = nil
        switch await purchases.purchase() {
        case .success:
            dismiss()
            onUnlocked()
        case .cancelled:
            break
        case .pending:
            errorText = "Purchase pending approval — it unlocks automatically once approved."
        case .failed(let message):
            errorText = message
        }
    }

    private func restore() async {
        errorText = nil
        restoring = true
        let unlocked = await purchases.restore()
        restoring = false
        if unlocked {
            dismiss()
            onUnlocked()
        } else {
            errorText = "No previous purchase found for this Apple Account."
        }
    }
}
