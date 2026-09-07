import Foundation

/// One reading of a tap: a key it might have been, and what it costs to assume so.
/// The key actually reported costs nothing.
public struct KeyProbability: Equatable, Sendable {
    public let character: String
    public let cost: Double
    public init(character: String, cost: Double) {
        self.character = character
        self.cost = cost
    }
}

/// The keys a single tap could plausibly have meant, cheapest first.
public struct TouchSample: Equatable, Sendable {
    public let alternatives: [KeyProbability]
    public init(alternatives: [KeyProbability]) { self.alternatives = alternatives }

    /// Cost of reading this tap as `character`, or nil if it is out of reach.
    public func cost(of character: String) -> Double? {
        alternatives.first { $0.character == character }?.cost
    }

    /// Keyed by folded scalar, for the corrector's inner loop.
    func costsByScalar() -> [UInt32: Double] {
        var map: [UInt32: Double] = [:]
        map.reserveCapacity(alternatives.count)
        for alternative in alternatives {
            guard let scalar = alternative.character.unicodeScalars.first else { continue }
            let folded = Diacritics.fold(scalar.value)
            if let existing = map[folded], existing <= alternative.cost { continue }
            map[folded] = alternative.cost
        }
        return map
    }
}

/// Where the keys physically are, so a tap can be read as the key it landed nearest
/// rather than only as the key it landed inside.
///
/// The corrector's fallback model knows only that two letters are "adjacent", at a flat
/// price. That throws away most of what a touch tells you: a tap two points from the
/// g/h border is nearly ambiguous, while one dead in the middle of g is not. Reading the
/// coordinates instead is what lets you type quickly without aiming, and it costs no
/// memory and no shipped data.
public struct SpatialModel: Equatable, Sendable {
    public struct KeyBox: Equatable, Sendable {
        public let character: String
        public let centerX: Double
        public let centerY: Double
        public let width: Double
        public let height: Double

        public init(character: String, centerX: Double, centerY: Double, width: Double, height: Double) {
            self.character = character
            self.centerX = centerX
            self.centerY = centerY
            self.width = width
            self.height = height
        }
    }

    public var keys: [KeyBox]
    /// Touch spread as a fraction of a key's size. Bigger means more willing to read a
    /// tap as a neighbour.
    public var spread = 0.55
    /// Alternatives dearer than this are dropped: past here the discrete fallback of a
    /// plain unrelated-letter substitution is just as good and much cheaper to carry.
    public var maxCost = 1.0
    public var maxAlternatives = 4

    public init(keys: [KeyBox] = []) { self.keys = keys }

    /// Reads a tap at (`x`, `y`) that was reported as `typed`.
    ///
    /// Costs are relative to the reported key, which is why a confident tap yields only
    /// itself: every other key is then far enough away to exceed `maxCost`.
    public func sample(x: Double, y: Double, typed: String) -> TouchSample? {
        guard !keys.isEmpty else { return nil }
        let lowered = typed.lowercased()
        // Squared Mahalanobis-style distance under an axis-aligned Gaussian over key centres.
        func distance(_ key: KeyBox) -> Double {
            let sx = max(spread * key.width, 0.0001)
            let sy = max(spread * key.height, 0.0001)
            let dx = (x - key.centerX) / sx
            let dy = (y - key.centerY) / sy
            return dx * dx + dy * dy
        }
        guard let anchor = keys.first(where: { $0.character == lowered }) else { return nil }
        let base = distance(anchor)
        var others: [KeyProbability] = []
        for key in keys where key.character != lowered {
            // -log of the likelihood ratio against the key we were told was hit. A tap
            // on the border between two keys costs nothing to read either way, which is
            // the whole point; costs are floored at zero because a substitution cheaper
            // than an exact match would invert the edit distance.
            let cost = max(0, 0.5 * (distance(key) - base))
            guard cost <= maxCost else { continue }
            others.append(KeyProbability(character: key.character, cost: cost))
        }
        others.sort { $0.cost == $1.cost ? $0.character < $1.character : $0.cost < $1.cost }
        // The reported key always leads, even where a neighbour ties with it.
        let alternatives = [KeyProbability(character: lowered, cost: 0)]
            + others.prefix(max(0, maxAlternatives - 1))
        return TouchSample(alternatives: alternatives)
    }
}
