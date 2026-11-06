/// Maps band levels to evenly spaced column heights across a wide surface:
/// lows at the centre, highs toward both edges, softened so bands blend.
public enum Silhouette {
    public static func heights(levels: [Float], columns: Int) -> [Float] {
        guard !levels.isEmpty, columns > 0 else { return [] }
        let soft = levels.indices.map { i -> Float in
            let before = levels[max(i - 1, 0)], after = levels[min(i + 1, levels.count - 1)]
            return (before + 2 * levels[i] + after) / 4
        }
        let centre = Float(columns - 1) / 2
        return (0..<columns).map { x in
            let distance = abs(Float(x) - centre) / max(centre, 1)
            let position = distance * Float(soft.count - 1)
            let index = min(Int(position), max(soft.count - 2, 0))
            guard soft.count > 1 else { return soft[0] }
            let fraction = position - Float(index)
            return soft[index] * (1 - fraction) + soft[index + 1] * fraction
        }
    }
}
