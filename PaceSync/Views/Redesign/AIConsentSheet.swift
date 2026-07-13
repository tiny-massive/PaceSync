// AIConsentSheet.swift
// One-time disclosure required by App Review Guideline 5.1.2(i): apps must clearly
// disclose and get explicit permission BEFORE sending user content to a third-party AI.
// Shown once, before the first parse (plan import, one-off workout, or re-import).

import SwiftUI

enum AIConsent {
    static let key = "aiParseConsentGiven"
    static var given: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    static let privacyPolicyURL = URL(string: "https://pacesync-proxy.pacesync.workers.dev/privacy")!
    static let supportURL = URL(string: "https://pacesync-proxy.pacesync.workers.dev/support")!
}

struct AIConsentSheet: View {
    /// Runs after the user grants consent (the action they originally tapped).
    var onContinue: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.s4) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Theme.accent)
                .padding(.top, Theme.s6)

            Text("PaceSync uses AI to read your plan")
                .font(.psTitle).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)

            Text("To turn your plan into workouts, the text you import (or your PDF) is sent to Anthropic's Claude for parsing. Nothing else ever leaves your phone — no health data, no calendar, no personal details.")
                .font(.psBody).foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.s5)

            Link("Privacy Policy", destination: AIConsent.privacyPolicyURL)
                .font(.psCallout).tint(Theme.accent)

            Spacer(minLength: Theme.s2)

            Button {
                AIConsent.given = true
                dismiss()
                onContinue()
            } label: {
                Text("Continue")
            }
            .buttonStyle(PSPrimaryButtonStyle())
            .padding(.horizontal, Theme.s5)

            Button("Not now") { dismiss() }
                .font(.psCallout).tint(Theme.ink2)
                .padding(.bottom, Theme.s5)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
