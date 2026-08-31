//
//  QuizResults.swift
//  HapticLab Watch App
//
//  Persists a confusion matrix across sessions so the test can run over
//  several days of ordinary wear. Key question isn't overall accuracy —
//  it's *which* haptics get mistaken for which, since that determines how
//  many alert categories are worth building (SPEC §7).
//

import Foundation
import Observation

@Observable
final class QuizResults {
    /// answers[played][guessed] = count
    private(set) var answers: [String: [String: Int]] = [:]

    private let storeKey = "HapticLab.confusionMatrix"

    init() { load() }

    func record(played: Haptic, guessed: Haptic) {
        answers[played.rawValue, default: [:]][guessed.rawValue, default: 0] += 1
        save()
    }

    func reset() {
        answers = [:]
        save()
    }

    var totalTrials: Int {
        answers.values.reduce(0) { $0 + $1.values.reduce(0, +) }
    }

    var totalCorrect: Int {
        answers.reduce(0) { sum, entry in sum + (entry.value[entry.key] ?? 0) }
    }

    var overallAccuracy: Double {
        totalTrials == 0 ? 0 : Double(totalCorrect) / Double(totalTrials)
    }

    func trials(for haptic: Haptic) -> Int {
        answers[haptic.rawValue]?.values.reduce(0, +) ?? 0
    }

    func accuracy(for haptic: Haptic) -> Double? {
        let n = trials(for: haptic)
        guard n > 0 else { return nil }
        let correct = answers[haptic.rawValue]?[haptic.rawValue] ?? 0
        return Double(correct) / Double(n)
    }

    /// The haptic most often mistaken for this one, and how many times.
    func topConfusion(for haptic: Haptic) -> (Haptic, Int)? {
        guard let row = answers[haptic.rawValue] else { return nil }
        let wrong = row.filter { $0.key != haptic.rawValue && $0.value > 0 }
        guard let best = wrong.max(by: { $0.value < $1.value }),
              let confused = Haptic(rawValue: best.key) else { return nil }
        return (confused, best.value)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(answers) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data)
        else { return }
        answers = decoded
    }
}
