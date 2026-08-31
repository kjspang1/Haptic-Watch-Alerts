//
//  QuizResults.swift
//  HapticLab Watch App
//
//  Persists a confusion matrix across sessions so the test can run over
//  several days of ordinary wear. Key question isn't overall accuracy —
//  it's *which* identities get mistaken for which, since that determines
//  how many alert categories are worth building (SPEC §7).
//

import Foundation
import Observation

@Observable
final class QuizResults {
    /// answers[playedID][guessedID] = count
    private(set) var answers: [String: [String: Int]] = [:]

    private let storeKey = "HapticLab.confusionMatrix"

    init() { load() }

    func record(played: HapticPattern, guessed: HapticPattern) {
        answers[played.id, default: [:]][guessed.id, default: 0] += 1
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

    func trials(for pattern: HapticPattern) -> Int {
        answers[pattern.id]?.values.reduce(0, +) ?? 0
    }

    func accuracy(for pattern: HapticPattern) -> Double? {
        let n = trials(for: pattern)
        guard n > 0 else { return nil }
        return Double(answers[pattern.id]?[pattern.id] ?? 0) / Double(n)
    }

    /// The identity most often mistaken for this one, and how many times.
    func topConfusion(for pattern: HapticPattern, in pool: [HapticPattern]) -> (HapticPattern, Int)? {
        guard let row = answers[pattern.id] else { return nil }
        let wrong = row.filter { $0.key != pattern.id && $0.value > 0 }
        guard let best = wrong.max(by: { $0.value < $1.value }),
              let confused = pool.first(where: { $0.id == best.key }) else { return nil }
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
