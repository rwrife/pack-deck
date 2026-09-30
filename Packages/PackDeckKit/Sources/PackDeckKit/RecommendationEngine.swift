import Foundation

/// Deterministic recommendation engine for trip packing quantities.
///
/// Rules are explicit and local-only:
/// - Known duration + no laundry: scale by full trip days.
/// - Known duration + laundry available: cap by one laundry cycle.
/// - Known duration + laundry unknown: conservative cap by one cycle and
///   downgrade confidence.
/// - Missing/invalid duration: keep base quantity and downgrade confidence.
public struct RecommendationEngine: Sendable {
    public let laundryCycleDays: Int

    public init(laundryCycleDays: Int = 7) {
        self.laundryCycleDays = max(1, laundryCycleDays)
    }

    public func recommend(for items: [KitItem], on trip: Trip) -> [Recommendation] {
        items.map { recommend(for: $0, on: trip) }
    }

    public func recommend(for item: KitItem, on trip: Trip) -> Recommendation {
        let normalizedBase = max(item.baseQuantity, 1)
        let baseWasInvalid = item.baseQuantity < 1

        guard let duration = trip.durationNights else {
            return Recommendation(
                id: item.id,
                quantity: normalizedBase,
                reason: .unknownDurationBaseQuantity,
                confidence: lowConfidence(reason: .unknownDurationBaseQuantity, force: baseWasInvalid)
            )
        }

        guard duration >= 1 else {
            return Recommendation(
                id: item.id,
                quantity: normalizedBase,
                reason: .invalidDurationBaseQuantity,
                confidence: lowConfidence(reason: .invalidDurationBaseQuantity, force: baseWasInvalid)
            )
        }

        // duration == Int.max must not trap the +1; a saturated day count
        // is a derived artifact and is surfaced as low confidence below.
        let daysSum = duration.addingReportingOverflow(1)
        let tripDays = daysSum.overflow ? Int.max : daysSum.partialValue

        switch trip.laundryAccess {
        case .unavailable:
            return scaledRecommendation(
                for: item,
                base: normalizedBase,
                days: tripDays,
                reason: .fullTripWithoutLaundry,
                baseWasInvalid: baseWasInvalid,
                daysSaturated: daysSum.overflow
            )

        case .available:
            if tripDays > laundryCycleDays {
                return scaledRecommendation(
                    for: item,
                    base: normalizedBase,
                    days: laundryCycleDays,
                    reason: .laundryCycleCap,
                    baseWasInvalid: baseWasInvalid
                )
            }

            return scaledRecommendation(
                for: item,
                base: normalizedBase,
                days: tripDays,
                reason: .tripDurationScaled,
                baseWasInvalid: baseWasInvalid
            )

        case .unknown:
            let conservativeDays = min(tripDays, laundryCycleDays)
            return scaledRecommendation(
                for: item,
                base: normalizedBase,
                days: conservativeDays,
                reason: .unknownLaundryConservative,
                baseWasInvalid: baseWasInvalid,
                forceLowConfidence: true
            )
        }
    }

    /// Multiplies base by days without trapping; a saturating overflow is
    /// reported explicitly via `quantityOverflowSaturated` and always
    /// downgrades confidence — a saturated number is never presented as a
    /// confident recommendation.
    private func scaledRecommendation(
        for item: KitItem,
        base: Int,
        days: Int,
        reason: RecommendationReason,
        baseWasInvalid: Bool,
        forceLowConfidence: Bool = false,
        daysSaturated: Bool = false
    ) -> Recommendation {
        let product = base.multipliedReportingOverflow(by: max(days, 1))
        let overflowed = product.overflow || daysSaturated

        var lowReasons: [String] = []
        if overflowed {
            lowReasons.append(RecommendationReason.quantityOverflowSaturated.rawValue)
        }
        if baseWasInvalid {
            lowReasons.append(RecommendationReason.invalidBaseQuantityNormalized.rawValue)
        }
        if forceLowConfidence, lowReasons.isEmpty {
            lowReasons.append(RecommendationReason.unknownLaundryConservative.rawValue)
        }

        guard !lowReasons.isEmpty else {
            return Recommendation(
                id: item.id,
                quantity: product.partialValue,
                reason: reason,
                confidence: .confident
            )
        }

        return Recommendation(
            id: item.id,
            quantity: overflowed ? Int.max : product.partialValue,
            reason: reason,
            confidence: .lowConfidence(reason: lowReasons.joined(separator: "; "))
        )
    }

    private func lowConfidence(reason: RecommendationReason, force: Bool) -> Confidence {
        if force {
            return .lowConfidence(reason: RecommendationReason.invalidBaseQuantityNormalized.rawValue)
        }

        return .lowConfidence(reason: reason.rawValue)
    }
}
