//
//  HapticLabView.swift
//  HapticLab Watch App
//

import SwiftUI

struct HapticLabView: View {
    @State private var results = QuizResults()
    @State private var quizSet: QuizSet = .bursts

    var body: some View {
        TabView {
            LearnView()
                .tabItem { Text("Learn") }
            QuizView(results: results, quizSet: $quizSet)
                .tabItem { Text("Quiz") }
            ScoreView(results: results, quizSet: quizSet)
                .tabItem { Text("Score") }
        }
        .tabViewStyle(.verticalPage)
    }
}

/// Tap each identity by name to build a mental model before testing blind.
struct LearnView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Bursts") {
                    ForEach(HapticPattern.bursts) { p in
                        Button(p.label) { p.play() }
                    }
                }
                Section("Singles (baseline)") {
                    ForEach(HapticPattern.singles) { p in
                        Button(p.label) { p.play() }
                    }
                }
            }
            .navigationTitle("Learn")
        }
    }
}

/// The actual measurement: play one at random, guess blind, record the result.
struct QuizView: View {
    let results: QuizResults
    @Binding var quizSet: QuizSet

    @State private var current: HapticPattern?
    @State private var lastOutcome: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Set", selection: $quizSet) {
                        ForEach(QuizSet.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .onChange(of: quizSet) { current = nil; lastOutcome = nil }
                }

                Section {
                    if current == nil {
                        Button("Play a random haptic") { next() }
                    } else {
                        Button("Replay") { current?.play() }
                    }
                    if let lastOutcome {
                        Text(lastOutcome).font(.footnote)
                    }
                }

                if current != nil {
                    Section("Which was it?") {
                        ForEach(quizSet.patterns) { p in
                            Button(p.label) { answer(p) }
                        }
                    }
                }
            }
            .navigationTitle("Quiz")
        }
    }

    private func next() {
        guard let pick = quizSet.patterns.randomElement() else { return }
        current = pick
        // Brief delay so the tap you just made isn't confused with the haptic.
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            pick.play()
        }
    }

    private func answer(_ guess: HapticPattern) {
        guard let played = current else { return }
        results.record(played: played, guessed: guess)
        lastOutcome = guess.id == played.id
            ? "Correct — \(played.label)"
            : "Wrong — that was \(played.label)"
        current = nil
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            next()
        }
    }
}

/// Per-identity accuracy plus the most common confusion — the number that
/// actually answers "how many alert identities can we ship?"
struct ScoreView: View {
    let results: QuizResults
    let quizSet: QuizSet
    @State private var confirmingReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let pct = Int(results.overallAccuracy * 100)
                    Text("\(results.totalCorrect)/\(results.totalTrials) correct (\(pct)%)")
                        .font(.headline)
                    Text("Chance = \(Int(100.0 / Double(max(quizSet.patterns.count, 1))))% for \(quizSet.patterns.count) options")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Section(quizSet.label) {
                    ForEach(quizSet.patterns) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(p.label).font(.caption)
                                Spacer()
                                if let acc = results.accuracy(for: p) {
                                    Text("\(Int(acc * 100))%")
                                        .font(.caption)
                                        .foregroundStyle(acc >= 0.8 ? .green : acc >= 0.5 ? .yellow : .red)
                                } else {
                                    Text("—").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if let (confused, n) = results.topConfusion(for: p, in: quizSet.patterns) {
                                Text("often felt as \(confused.label) (\(n)x)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button("Reset data", role: .destructive) { confirmingReset = true }
                }
            }
            .navigationTitle("Score")
            .confirmationDialog("Erase all quiz results?", isPresented: $confirmingReset) {
                Button("Erase", role: .destructive) { results.reset() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

#Preview {
    HapticLabView()
}
