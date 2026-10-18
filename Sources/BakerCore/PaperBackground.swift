import Foundation

/// Estimates only smooth paper/slide illumination; incompatible foreground colours never enter local refinement.
struct PaperBackground {
    typealias Colour = SIMD3<Double>
    private struct Sample { let x: Int; let y: Int; let colour: Colour }
    let adaptive: Bool
    private let width: Int, height: Int
    private let coefficients: [Colour]
    private let columns: [Int], rows: [Int]
    private let corrections: [Colour]
    private static let spacing = 32

    init(pixels: [UInt8], width: Int, height: Int) throws {
        self.width = width; self.height = height
        func sample(_ x: Int, _ y: Int) -> Sample? {
            let i = (y * width + x) * 4
            guard pixels[i + 3] >= 250 else { return nil }
            let a = Double(pixels[i + 3])
            return Sample(x: x, y: y, colour: Colour(Double(pixels[i]) / a, Double(pixels[i + 1]) / a, Double(pixels[i + 2]) / a))
        }
        var border: [Sample] = []
        let step = max(1, (width + height) / 512)
        for x in stride(from: 0, to: width, by: step) {
            if let value = sample(x, 0) { border.append(value) }
            if let value = sample(x, height - 1) { border.append(value) }
        }
        for y in stride(from: 0, to: height, by: step) {
            if let value = sample(0, y) { border.append(value) }
            if let value = sample(width - 1, y) { border.append(value) }
        }
        guard !border.isEmpty else { throw Self.unsuitable() }
        let median = Colour(Self.median(border.map { $0.colour.x }), Self.median(border.map { $0.colour.y }), Self.median(border.map { $0.colour.z }))
        if border.filter({ Self.distance($0.colour, median) <= 3 / 255.0 }).count * 10 >= border.count * 9 {
            adaptive = false; coefficients = [median]; columns = []; rows = []; corrections = []; return
        }
        guard width > 1, height > 1 else { throw Self.unsuitable() }
        // The low-order border fit anchors the estimate outside text, axes and filled figures.
        for inset in [4, 8] where width > inset * 2 && height > inset * 2 {
            for x in stride(from: inset, to: width - inset, by: max(4, step)) {
                if let value = sample(x, inset) { border.append(value) }
                if let value = sample(x, height - 1 - inset) { border.append(value) }
            }
            for y in stride(from: inset, to: height - inset, by: max(4, step)) {
                if let value = sample(inset, y) { border.append(value) }
                if let value = sample(width - 1 - inset, y) { border.append(value) }
            }
        }
        let basis = border.map { Self.basis(Self.coordinate($0.x, width), Self.coordinate($0.y, height)) }
        let values = border.map(\.colour)
        let fitted = try Self.fit(basis, values: values, iterations: 6, noise: 3 / 255)
        let inliers = zip(basis, values).filter { Self.distance(Self.evaluate(fitted, $0.0), $0.1) <= 12 / 255.0 }.count
        guard inliers * 10 >= border.count * 7 else { throw Self.unsuitable() }
        coefficients = fitted; adaptive = true
        columns = Self.nodes(width); rows = Self.nodes(height)
        var grid: [Colour] = []; grid.reserveCapacity(columns.count * rows.count)
        for cy in rows {
            try Task.checkCancellation()
            for cx in columns {
                var localBasis: [[Double]] = [], residuals: [Colour] = []
                for py in stride(from: max(0, cy - 40), through: min(height - 1, cy + 40), by: 5) {
                    for px in stride(from: max(0, cx - 40), through: min(width - 1, cx + 40), by: 5) {
                        guard let point = sample(px, py) else { continue }
                        let expected = Self.evaluate(fitted, Self.basis(Self.coordinate(px, width), Self.coordinate(py, height)))
                        guard Self.distance(expected, point.colour) < 24 / 255.0 else { continue }
                        localBasis.append([1, Double(px - cx) / 40, Double(py - cy) / 40])
                        residuals.append(point.colour - expected)
                    }
                }
                if localBasis.count >= 12 {
                    let adjustment = try Self.fit(localBasis, values: residuals, iterations: 4, noise: 2 / 255)
                    grid.append(adjustment[0])
                } else { grid.append(.zero) }
            }
        }
        corrections = grid
    }
    func colour(x: Int, y: Int) -> Colour {
        guard adaptive else { return coefficients[0] }
        let u = Self.coordinate(x, width), v = Self.coordinate(y, height)
        let row0 = coefficients[0] + coefficients[2] * v + coefficients[5] * (v*v) + coefficients[9] * (v*v*v)
        let row1 = coefficients[1] + coefficients[4] * v + coefficients[8] * (v*v)
        let row2 = coefficients[3] + coefficients[7] * v
        let base = Self.clamp(((coefficients[6] * u + row2) * u + row1) * u + row0)
        let ix = min(x / Self.spacing, columns.count - 2), iy = min(y / Self.spacing, rows.count - 2)
        let tx = Double(x - columns[ix]) / Double(columns[ix + 1] - columns[ix])
        let ty = Double(y - rows[iy]) / Double(rows[iy + 1] - rows[iy])
        let a = corrections[iy * columns.count + ix], b = corrections[iy * columns.count + ix + 1]
        let c = corrections[(iy + 1) * columns.count + ix], d = corrections[(iy + 1) * columns.count + ix + 1]
        return Self.clamp(base + (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty)
    }
    private static func nodes(_ size: Int) -> [Int] {
        var result = Array(stride(from: 0, to: size, by: spacing))
        if result.last != size - 1 { result.append(size - 1) }
        return result
    }
    private static func coordinate(_ value: Int, _ size: Int) -> Double { size > 1 ? Double(value) * 2 / Double(size - 1) - 1 : 0 }
    private static func basis(_ x: Double, _ y: Double) -> [Double] { [1, x, y, x*x, x*y, y*y, x*x*x, x*x*y, x*y*y, y*y*y] }
    private static func evaluate(_ coefficients: [Colour], _ basis: [Double]) -> Colour {
        var value = Colour.zero
        for i in coefficients.indices { value += coefficients[i] * basis[i] }
        return value
    }
    private static func distance(_ a: Colour, _ b: Colour) -> Double { max(abs(a.x - b.x), abs(a.y - b.y), abs(a.z - b.z)) }
    private static func clamp(_ colour: Colour) -> Colour { Colour(min(1, max(0, colour.x)), min(1, max(0, colour.y)), min(1, max(0, colour.z))) }
    private static func median(_ values: [Double]) -> Double { let values = values.sorted(); return values[values.count / 2] }
    private static func unsuitable() -> BakerError {
        BakerError(message: "Paper & Slides needs a plain or smoothly shaded background. Try a tighter crop; use Photo Cutout for a photographed subject.", code: .invalidInput)
    }
    /// Shared tiny weighted least-squares fit for illumination and local residual planes.
    private static func fit(_ basis: [[Double]], values: [Colour], iterations: Int, noise: Double) throws -> [Colour] {
        let n = basis[0].count
        var weights = [Double](repeating: 1, count: basis.count), result = [Colour](repeating: .zero, count: n)
        for _ in 0..<iterations {
            try Task.checkCancellation()
            var matrix = [Double](repeating: 0, count: n * n), rhs = [Colour](repeating: .zero, count: n)
            for k in basis.indices {
                let row = basis[k], weight = weights[k]
                for i in 0..<n {
                    rhs[i] += values[k] * (row[i] * weight)
                    for j in 0..<n { matrix[i*n+j] += row[i] * row[j] * weight }
                }
            }
            for i in 0..<n { matrix[i*n+i] += 0.000001 }
            for i in 0..<n {
                var pivot = i
                for j in i..<n where abs(matrix[j*n+i]) > abs(matrix[pivot*n+i]) { pivot = j }
                guard abs(matrix[pivot*n+i]) > 1e-12 else { throw unsuitable() }
                if pivot != i { for j in 0..<n { matrix.swapAt(i*n+j, pivot*n+j) }; rhs.swapAt(i, pivot) }
                let divisor = matrix[i*n+i]
                for j in i..<n { matrix[i*n+j] /= divisor }; rhs[i] /= divisor
                for k in 0..<n where k != i {
                    let factor = matrix[k*n+i]
                    for j in i..<n { matrix[k*n+j] -= factor * matrix[i*n+j] }; rhs[k] -= rhs[i] * factor
                }
            }
            result = rhs
            for k in basis.indices { weights[k] = min(1, noise / max(distance(evaluate(result, basis[k]), values[k]), 1e-9)) }
        }
        return result
    }
}
