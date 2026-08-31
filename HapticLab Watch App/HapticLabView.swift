//
//  HapticLabView.swift
//  HapticLab Watch App
//

import SwiftUI

struct HapticLabView: View {
    @State private var results = QuizResults()

    var body: some View {
        TabView {
            LearnView()
                .tabItem { Text("Learn") }
            QuizView(results: results)
                .tabItem { Text("Quiz") }
            ScoreView(results: results)
                .tabItem { Text("Score") }
        }
        .tabViewStyle(.verticalPage)
    }
}

/// Tap each haptic by name to build a mental model before testing blind.
struct LearnView: View {
    var body: some View {
        NavigationStack {
            List(Haptic.allCases) { haptic in
                Button(haptic.label) { haptic.play() }
            }
            .navigationTitle("Learn")
        }
    }
}

/// The actual measurement: play one at random, guess blind, record the result.
struct QuizView: View {
    let results: QuizResults

    @State private var current: Haptic?
    @State private var lastOutcome: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if current == nil {
                        Button("Play a random haptic") { next() }
                    } else {
                        Button("Replay") { current?.play() }
                        if let lastOutcome {
                            Text(lastOutcome).font(.footnote)
                        }
                    }
                }

                if current != nil {
                    Section("Which was it?") {
                        ForEach(Haptic.allCases) { haptic in
                            Button(haptic.label) { answer(haptic) }
                        }
                    }
                }
            }
            .navigationTitle("Quiz")
        }
    }

    private func next() {
        let pick = Haptic.allCases.randomElement()!
        current = pick
        // Brief delay so the tap you just made isn't confused with the haptic.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { pick.play() }
    }

    private func answer(_ guess: Haptic) {
        guard let played = current else { return }
        results.record(played: played, guessed: guess)
        lastOutcome = guess == played
            ? "Correct — \(played.label)"
            : "Wrong — that was \(played.label)"
        current = nil
        // Immediately queue the next trial to keep sessions quick.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { next() }
    }
}

/// Per-haptic accuracy plus the most common confusion — the number that
/// actually answers "how many alert identities can we ship?"
struct ScoreView: View {
    let results: QuizResults
    @State private var confirmingReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let pct = Int(results.overallAccuracy * 100)
                    Text("\(results.totalCorrect)/\(results.totalTrials) correct (\(pct)%)")
                        .font(.headline)
                }

                Section("Per haptic") {
                    ForEach(Haptic.allCases) { haptic in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(haptic.label).font(.caption)
                                Spacer()
                                if let acc = results.accuracy(for: haptic) {
                                    Text("\(Int(acc * 100))%")
                                        .font(.caption)
                                        .foregroundStyle(acc >= 0.8 ? .green : acc >= 0.5 ? .yellow : .red)
                                } else {
                                    Text("—").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if let (confused, n) = results.topConfusion(for: haptic) {
                                Text("often heard as \(confused.label) (\(n)x)")
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
