import Foundation

extension NightSummary {
    /// The stages that own a labelled row in the timeline chart, in row order.
    static let percentageStages: [SleepStage] = [.awake, .rem, .core, .deep]

    /// Each labelled stage's whole-number share of the night.
    ///
    /// The denominator is the sum of `percentageStages` only. `asleepUnspecified` and
    /// `inBed` are excluded because neither owns a row that could carry a label, and
    /// including them would leave the visible column summing to less than 100 with no
    /// indication of where the remainder went.
    ///
    /// Values are distributed by the largest-remainder method so they sum to exactly 100.
    /// Rounding each value independently would land the column on 99 or 101 for many
    /// nights. Ties are broken by `SleepStage.rowIndex`, making the result deterministic.
    ///
    /// The arithmetic is done on whole seconds as integers rather than on percentages as
    /// `Double`s. In floating point a true 27.5% evaluates to 27.500000000000004, which
    /// makes an exact tie between remainders unrepresentable and lets rounding noise decide
    /// which stage receives a leftover point. Integer division and modulo make both the
    /// remainder comparison and the tie-break exact.
    ///
    /// Returns an empty dictionary when no labelled stage has any duration, which is the
    /// case for a night recorded entirely as unspecified sleep. Callers show no
    /// percentages at all rather than four rows reading `0%`.
    public var stagePercentages: [SleepStage: Int] {
        let seconds = Self.percentageStages.map { stage in
            max(0, Int((stageDurations[stage] ?? 0).rounded()))
        }
        let total = seconds.reduce(0, +)
        guard total > 0 else { return [:] }

        let scaled = seconds.map { $0 * 100 }
        var whole = scaled.map { $0 / total }
        let remainders = scaled.map { $0 % total }

        let leftover = 100 - whole.reduce(0, +)
        if leftover > 0 {
            let byDescendingRemainder = remainders.indices.sorted { lhs, rhs in
                if remainders[lhs] == remainders[rhs] {
                    return Self.percentageStages[lhs].rowIndex
                        < Self.percentageStages[rhs].rowIndex
                }
                return remainders[lhs] > remainders[rhs]
            }
            for index in byDescendingRemainder.prefix(leftover) {
                whole[index] += 1
            }
        }

        return Dictionary(uniqueKeysWithValues: zip(Self.percentageStages, whole))
    }
}
