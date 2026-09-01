//
//  AlertCategory.swift
//  Haptic Alert Watch
//
//  Grouping plus alert identity. Per SPEC §7.1 the identity is *assigned*,
//  never chosen: there is no haptic picker anywhere, and `soundID` is an
//  iPhone-only channel because the Watch substitutes its standard ping
//  for any custom sound (SPEC §3.1).
//

import Foundation
import SwiftData

@Model
final class AlertCategory {
    var id: UUID = UUID()
    var name: String = ""
    /// Auto-assigned from `AlertIdentity`, never user-chosen. Affects the
    /// iPhone alert sound only — the Watch ignores it.
    var soundID: String = AlertIdentity.fallback.soundID
    var symbolName: String = "bell.fill"
    var colorHex: String = "#007AFF"

    init(
        id: UUID = UUID(),
        name: String,
        soundID: String,
        symbolName: String,
        colorHex: String
    ) {
        self.id = id
        self.name = name
        self.soundID = soundID
        self.symbolName = symbolName
        self.colorHex = colorHex
    }

    /// Creates a category with its alert identity assigned automatically,
    /// rotating through the table so consecutive categories differ.
    convenience init(name: String, symbolName: String, colorHex: String, existingCount: Int) {
        self.init(
            id: UUID(),
            name: name,
            soundID: AlertIdentity.assign(forExistingCount: existingCount).soundID,
            symbolName: symbolName,
            colorHex: colorHex
        )
    }
}

/// The fixed internal table of alert identities.
///
/// Kept as a table rather than free-form user input so that if richer
/// differentiation ever becomes deliverable, categories pick it up with no
/// data migration and no user action (SPEC §7.1).
struct AlertIdentity: Sendable, Equatable {
    let soundID: String

    static let fallback = AlertIdentity(soundID: "default")

    /// Currently one entry, matching §7.1's "design for one reliably
    /// distinct alerting identity". The spike's generated test tones were
    /// deliberately not promoted into this table — they were diagnostic
    /// signals, not alert sounds. Adding real bundled sounds here later
    /// needs no migration and no user action; they are iPhone-only either
    /// way, since the Watch substitutes its standard ping (§3.1).
    static let all: [AlertIdentity] = [
        AlertIdentity(soundID: "default"),
    ]

    static func assign(forExistingCount count: Int) -> AlertIdentity {
        guard !all.isEmpty else { return fallback }
        return all[count % all.count]
    }
}
