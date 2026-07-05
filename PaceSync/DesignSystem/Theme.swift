// Theme.swift
// PaceSync design system — the single source of truth for colour, type, spacing and
// radii. Ported from the Figma "PaceSync — Design System" board. Every colour is
// light/dark adaptive, so views never hardcode a hex again.

import SwiftUI
import UIKit

// MARK: - Hex helpers

private extension UIColor {
    convenience init(_ hex: UInt, _ alpha: CGFloat = 1) {
        self.init(red:   CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8)  & 0xFF) / 255,
                  blue:  CGFloat( hex        & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// A colour that resolves differently in light vs dark mode.
private func dyn(_ light: UInt, _ dark: UInt) -> Color {
    Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
}
private func dyn(light: (UInt, CGFloat), dark: (UInt, CGFloat)) -> Color {
    Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark.0, dark.1) : UIColor(light.0, light.1) })
}

// MARK: - Theme

enum Theme {

    // Surfaces
    static let canvas        = dyn(0xF5F6F7, 0x1C1C1E)
    static let surface       = dyn(0xFFFFFF, 0x2C2C2E)
    static let surfaceRaised = dyn(0xFBFCFC, 0x363638)
    static let hairline      = dyn(light: (0x14181C, 0.09), dark: (0xFFFFFF, 0.11))

    // Ink (text)
    static let ink   = dyn(0x1B1D1F, 0xF2F2F7)   // primary
    static let ink2  = dyn(0x5C6470, 0x98989D)   // secondary
    static let ink3  = dyn(0x8B929D, 0x7C7C82)   // tertiary / captions

    // Accent — the ONE green. Primary action, progress ring, today marker only.
    static let accent     = dyn(0x0F8A4C, 0x35D07F)
    static let accentSoft = dyn(0xE4F3EC, 0x11362B)
    static let onAccent   = Color.white

    // Semantic — state only, never as accent
    static let warning = dyn(0xC6820A, 0xE9A83A)
    static let error   = dyn(0xDB3B41, 0xFF6B6B)

    // Chip / control fills
    static let chipFill = dyn(0xF1F2F3, 0x3A3A3C)
    static let control  = dyn(0xEBECEE, 0x3A3A3C)

    // Radii — two values only
    static let rCard:    CGFloat = 16
    static let rRow:     CGFloat = 12
    static let rControl: CGFloat = 12
    static let rChip:    CGFloat = 8

    // Spacing scale
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24

    // MARK: Workout categories — one dot vocabulary across rows, calendar & detail
    enum Category {
        case easy, long, tempo, intervals, hills, strength, rest

        var color: Color {
            switch self {
            case .easy:      return dyn(0x3178C6, 0x6FB3F2)   // blue
            case .long:      return dyn(0x0E7490, 0x22D3EE)   // cyan — clearly apart from easy-blue
            case .tempo:     return dyn(0xC2610E, 0xF0A03A)   // orange
            case .intervals: return dyn(0xB32B5E, 0xF26FA0)   // crimson
            case .hills:     return dyn(0x92610F, 0xD9A05B)   // brown — its own type, not intervals
            case .strength:  return dyn(0x7C3AED, 0xA78BFA)   // purple
            case .rest:      return dyn(0xB4BAC4, 0x6B7078)   // neutral grey
            }
        }
    }
}

// MARK: - Typography
// System font (San Francisco) is the native, correct choice on iOS — Inter was the
// Figma stand-in. Numbers use monospaced (tabular) digits so columns line up.

extension Font {
    static let psLargeTitle = Font.system(size: 22, weight: .semibold)
    static let psTitle      = Font.system(size: 17, weight: .semibold)
    static let psHeadline   = Font.system(size: 15, weight: .semibold)
    static let psBody       = Font.system(size: 15, weight: .regular)
    static let psCallout    = Font.system(size: 13, weight: .regular)
    static let psCaption    = Font.system(size: 12, weight: .regular)
    static let psLabel      = Font.system(size: 10.5, weight: .semibold)
}

extension View {
    /// Tabular numerals for any view showing numbers (dates, distances, counts).
    func psTabular() -> some View { self.monospacedDigit() }
}

// MARK: - Category derivation

extension WorkoutDay {
    /// Best-guess display category for the dot vocabulary, derived from the parsed
    /// segments and title. Heuristic — refined once we see real plans running.
    var displayCategory: Theme.Category {
        if isRestDay { return .rest }
        let types = Set(segments.map { $0.type })
        let t = title.lowercased()

        // Hard-effort types win over easy; warm-up/cool-down never dominate.
        if types.contains(.interval) || t.contains("interval") || t.contains("rep")
            || t.contains("speed") || t.contains("track")     { return .intervals }
        if types.contains(.hills) || t.contains("hill")       { return .hills }
        if types.contains(.tempo) || t.contains("tempo") || t.contains("threshold") { return .tempo }
        if t.contains("strength") || t.contains("gym")
            || t.contains("cross") || t.contains("weight")    { return .strength }
        if t.contains("long")                                 { return .long }

        let miles = segments.compactMap { $0.distanceMiles }.reduce(0, +)
        if miles >= 10                                        { return .long }
        if types.contains(.easy) || miles > 0                 { return .easy }
        return .easy
    }
}
