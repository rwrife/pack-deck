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

        let tripDays = duration + 1

        switch trip.laundryAccess {
        case .unavailable:
            return Recommendation(
                id: item.id,
                quantity: normalizedBase * tripDays,
                reason: .fullTripWithoutLaundry,
                confidence: baseWasInvalid
                    ? .lowConfidence(reason: RecommendationReason.invalidBaseQuantityNormalized.rawValue)
                    : .confident
            )

        case .available:
            if tripDays > laundryCycleDays {
                return Recommendation(
                    id: item.id,
                    quantity: normalizedBase * laundryCycleDays,
                    reason: .laundryCycleCap,
                    confidence: baseWasInvalid
                        ? .lowConfidence(reason: RecommendationReason.invalidBaseQuantityNormalized.rawValue)
                        : .confident
                )
            }

            return Recommendation(
                id: item.id,
                quantity: normalizedBase * tripDays,
                reason: .tripDurationScaled,
                confidence: baseWasInvalid
                    ? .lowConfidence(reason: RecommendationReason.invalidBaseQuantityNormalized.rawValue)
                    : .confident
            )

        case .unknown:
            let conservativeDays = min(tripDays, laundryCycleDays)
            return Recommendation(
                id: item.id,
                quantity: normalizedBase * conservativeDays,
                reason: .unknownLaundryConservative,
                confidence: .lowConfidence(
                    reason: baseWasInvalid
                        ? RecommendationReason.invalidBaseQuantityNormalized.rawValue
                        : RecommendationReason.unknownLaundryConservative.rawValue
                )
            )
        }
    }

    private func lowConfidence(reason: RecommendationReason, force: Bool) -> Confidence {
        if force {
            return .lowConfidence(reason: RecommendationReason.invalidBaseQuantityNormalized.rawValue)
        }

        return .lowConfidence(reason: reason.rawValue)
    }
}
