// AlgorithmVersion.swift
// Vehicle Damage Investigation Assistant
// Versioned identity of the scoring algorithms + the constants that drive them.
//
// NOTE(AI Developer), added 2026-09 for the "trust the number" work item.
//
// The problem this solves: every score this app has ever produced was
// stamped with nothing but a date. Two `MatchResult`s persisted a month
// apart can carry the same 78% and mean completely different things,
// because the thresholds, tolerances, and trial counts behind that
// number changed in between with no record of it. For an investigative
// document that may be re-read, re-exported, or challenged long after
// the fact, "which version of the algorithm produced this?" has to be
// answerable from the artifact itself, not from git archaeology on the
// app binary that happened to be installed that week.
//
// So: `AlgorithmVersion.current` is stamped into every `MatchResult` at
// analysis time, persisted with the case JSON, and rendered in both the
// results screen and the PDF. It carries two things:
//
//   1. `identifier` -- a human-quotable version string. Bump this
//      WHENEVER a change can move a score, including a threshold tweak.
//      A pure UI/copy change does not need a bump.
//   2. `constants` -- the actual numeric values in force at the moment
//      of analysis, captured from the live source of truth (the
//      matchers' own static properties) rather than re-typed here.
//      This is the part that makes an old report interpretable: even if
//      nobody wrote down what "v1.1.0" meant, the report still says
//      exactly what tolerance and trial count produced its numbers.
//
// Deliberately NOT a build number or a git SHA: those change on every
// commit including pure-UI ones, so they'd tell an investigator that
// the algorithm changed when it didn't. This is a semantic statement
// about the MATH, maintained by hand.

import Foundation

// MARK: - Algorithm Version

struct AlgorithmVersion: Codable, Equatable {

    /// One captured constant: what it is, its value, and what it does.
    /// The `explanation` exists so a report read years later is
    /// self-describing without the source code next to it.
    struct Constant: Codable, Equatable, Identifiable {
        var id: String { name }
        var name: String
        var value: String
        var explanation: String
    }

    /// Semantic version of the SCORING MATH. Bump on any change that
    /// can move a number; see this file's header.
    var identifier: String

    /// The numeric parameters in force when this result was produced.
    var constants: [Constant]

    // MARK: Current

    /// NOTE(AI Developer): bump `identifier` whenever any value read
    /// below changes, or whenever a scoring FORMULA changes even if no
    /// constant moved. History:
    ///   1.0.0 -- baseline at the time version stamping was introduced:
    ///            7 weighted factors, CIEDE2000 paint, tool-mark
    ///            null-model significance from commit 7391b73.
    ///   1.1.0 -- tool-mark significance switched from a normal-theory
    ///            z-score to a rank-based permutation p-value; scar
    ///            fingerprint matching gained a null model and p-value
    ///            of its own (it previously had none).
    ///   1.2.0 -- null-model trial counts raised 120 -> 1000 for both
    ///            matchers after a resolution audit (the p-value floor
    ///            of 1/121 sat only ~6 discrete steps below the 0.05
    ///            threshold, and trial count alone flipped 3-4% of
    ///            verdicts); p-value resolution added to the recorded
    ///            constants.
    ///
    ///            The 120 and 1/121 above are DELIBERATELY STALE: this
    ///            list records what each version changed, so rewriting
    ///            them to the current constant would destroy the very
    ///            history it exists to carry. PROCESS.md sec.2 says to
    ///            grep for the number when a constant moves; version
    ///            history is the one place the old number is the
    ///            correct content. Do not "fix" this. Scores from 1.1.0 and 1.2.0 are directly
    ///            comparable -- the estimator is unchanged, only its
    ///            precision -- but a 1.1.0 p-value is quantised roughly
    ///            8x more coarsely than its printed decimals suggest.
    static var current: AlgorithmVersion {
        AlgorithmVersion(
            identifier: "1.2.0",
            constants: [
                Constant(
                    name: "Tool-mark minimum overlap",
                    value: "\(ToolMarkMatcher.minimumOverlapLength) rhythm elements",
                    explanation: "Shortest overlapping run of striation spacings allowed to produce a score at all."
                ),
                Constant(
                    name: "Tool-mark null-model trials",
                    value: "\(ToolMarkMatcher.nullModelTrialCount) permutations",
                    explanation: "Shuffled-baseline trials used to judge whether a striation score exceeds chance."
                ),
                Constant(
                    name: "Significance level",
                    value: String(format: "p < %.2f", ForensicNullModel.significanceLevel),
                    explanation: "A correlation is only reported as meaningful when its permutation p-value is below this."
                ),
                // NOTE(AI Developer), added 2026-09-06. The stamp records
                // the trial counts above, but the trial count's real
                // consequence is not obvious from the number itself: a
                // permutation p-value is a discrete multiple of
                // 1/(1+trials), so that fraction is the smallest p-value
                // the test can express and therefore the resolution of
                // every p-value in the report. Recording it explicitly
                // means a reader can tell whether a quoted "p = 0.003"
                // was a real measurement or the floor of a coarse test,
                // without knowing this arithmetic. Two thresholds that
                // both round to the same printed decimals can rest on
                // very different amounts of evidence.
                Constant(
                    name: "P-value resolution",
                    value: String(format: "%.4f (smallest expressible p-value)",
                                  1.0 / Double(1 + ToolMarkMatcher.nullModelTrialCount)),
                    explanation: "Permutation p-values are multiples of this. A p-value at this value means \"no chance trial matched\", not zero probability. Each p-value counts one more trial than were actually run (p = (1 + matching trials) / (1 + trials)), so multiplying a p-value by the trial count overstates the matching count by about one -- the summary's \"N of M chance trials\" is the exact figure."
                ),
                Constant(
                    name: "Scar fingerprint position tolerance",
                    value: String(format: "%.0f%% of scar length", ScarFingerprintMatcher.positionToleranceNormalized * 100),
                    explanation: "How far apart two markings may sit along their own scars and still be called the same marking."
                ),
                Constant(
                    name: "Scar fingerprint null-model trials",
                    value: "\(ScarFingerprintMatcher.nullModelTrialCount) resamples",
                    explanation: "Random-marking trials used to judge whether a marking-match percentage exceeds chance."
                ),
                Constant(
                    name: "Factor weights",
                    value: ForensicFactor.allCases
                        .map { String(format: "%@ %.0f%%", $0.displayName, $0.weight * 100) }
                        .joined(separator: ", "),
                    explanation: "Relative contribution of each factor to the composite correlation score."
                )
            ]
        )
    }

    /// Single-line form for a report footer or a UI caption.
    var displayLine: String { "Analysis algorithm v\(identifier)" }
}

// MARK: - Shared Null-Model Utilities

/// NOTE(AI Developer), added 2026-09. Both the tool-mark matcher and the
/// scar-fingerprint matcher now judge their raw score against a
/// null model (what an UNRELATED pair of scars would score from the same
/// search). They previously had no shared machinery -- the tool-mark one
/// carried its own private PRNG and the fingerprint one had no null
/// model whatsoever -- so this exists to make both use the SAME
/// deterministic randomness and the SAME definition of a p-value. Two
/// significance verdicts in the same report must not be computed two
/// different ways.
enum ForensicNullModel {

    /// A permutation p-value below this is reported as "unlikely to be
    /// coincidence." 0.05 is the conventional screening threshold and is
    /// deliberately not pushed stricter: this is an investigative
    /// triage aid, not a courtroom statistical claim.
    static let significanceLevel: Double = 0.05

    /// Rank-based (permutation) p-value: the fraction of null trials
    /// that scored at least as high as the real score.
    ///
    /// NOTE(AI Developer): this deliberately REPLACES the previous
    /// normal-theory z-score approach as the significance test. A
    /// z-score assumes the null distribution is roughly normal, and
    /// these null distributions are neither -- they are scores bounded
    /// in [0, 100] produced by a keep-the-best-of-many-tries search,
    /// which pushes the distribution hard against its upper bound and
    /// leaves it strongly left-skewed. Under that skew a z of 2.0 does
    /// not correspond to the ~2.3% tail it would in a normal
    /// distribution, so the old threshold was quietly claiming a false-
    /// positive rate it could not deliver. A rank p-value makes no
    /// distributional assumption at all: it just counts how often chance
    /// alone did this well, which is exactly the question being asked.
    ///
    /// Uses the standard (1 + count) / (1 + trials) form so the result
    /// is never exactly 0 -- a finite number of trials cannot
    /// demonstrate an impossibility, and reporting "p = 0" from 120
    /// trials would overstate the evidence.
    static func permutationPValue(realScore: Double, nullScores: [Double]) -> Double? {
        guard !nullScores.isEmpty else { return nil }
        let atLeastAsExtreme = nullScores.filter { $0 >= realScore }.count
        return Double(1 + atLeastAsExtreme) / Double(1 + nullScores.count)
    }

    /// Plain-language rendering of a p-value, floored at the resolution
    /// the trial count can actually support.
    ///
    /// NOTE(AI Developer): returns a COMPLETE labelled string ("p =
    /// 0.003"), so it must never be interpolated into a sentence that
    /// supplies its own noun -- see `trialCountDisplay` below for the
    /// bug that caused.
    static func pValueDisplay(_ p: Double, trials: Int) -> String {
        let resolution = 1.0 / Double(1 + trials)
        if p <= resolution { return String(format: "p < %.3f", resolution) }
        return String(format: "p = %.3f", p)
    }

    /// How many null trials actually scored at least as high as the real
    /// score, recovered from the p-value.
    ///
    /// NOTE(AI Developer), added 2026-09-06 after Ledger caught a
    /// category error in the summary copy. Both matchers' summaries said
    /// "scored this well or better in only \(pValueDisplay(...)) of
    /// \(trials) chance trials", which renders as "in only p = 0.003 of
    /// 1000 chance trials" -- a sentence that promises a COUNT of trials
    /// and receives a PROBABILITY, inviting the reader to parse
    /// "p = 0.003" as a quantity out of 1000. The defect existed only at
    /// the join: the helper was correct, and the sentence was correct
    /// before the helper existed.
    ///
    /// `permutationPValue` is `(1 + atLeastAsExtreme) / (1 + trials)`,
    /// so this inverts it exactly rather than approximating. The
    /// rounding guards against float drift in that round trip.
    ///
    /// The floor case is the valuable one: at the smallest expressible
    /// p-value this returns **0**, so the sentence reads "0 of 1000
    /// chance trials" -- which is both literally correct and the
    /// clearest statement in the whole report of what a floor p-value
    /// means (no chance trial matched, NOT zero probability). The old
    /// wording hid the strongest true claim available behind a notation
    /// error.
    static func trialCountAtLeastAsExtreme(pValue: Double, trials: Int) -> Int {
        let count = pValue * Double(1 + trials) - 1
        return max(0, Int(count.rounded()))
    }

    /// A small deterministic PRNG (SplitMix64).
    ///
    /// NOTE(AI Developer): deliberately NOT
    /// `SystemRandomNumberGenerator` -- re-running analysis on unchanged
    /// data must report the same significance verdict every time, which
    /// a forensic tool has to guarantee. Previously lived privately
    /// inside `ToolMarkMatcher`; hoisted here unchanged so the
    /// fingerprint null model uses the identical generator rather than a
    /// second, independently-written one.
    struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
        mutating func next() -> UInt64 {
            state = state &+ 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    /// Deterministic FNV-1a seed over raw `Double` bit patterns.
    ///
    /// NOTE(AI Developer): deliberately NOT Swift's `Hasher`/`hashValue`
    /// -- those mix in a random per-process seed by design, so the same
    /// inputs would seed differently across app launches and silently
    /// break the reproducibility the seeded generator exists for.
    /// Stable across runs, launches, and devices for the same values.
    static func seed(from groups: [[Double]]) -> UInt64 {
        var h: UInt64 = 1469598103934665603 // FNV-1a 64-bit offset basis
        func mix(_ value: UInt64) {
            h ^= value
            h = h &* 1099511628211 // FNV-1a 64-bit prime
        }
        for (index, group) in groups.enumerated() {
            for v in group { mix(v.bitPattern) }
            if index < groups.count - 1 {
                mix(0x9E3779B97F4A7C15) // separator between groups
            }
        }
        return h
    }
}
