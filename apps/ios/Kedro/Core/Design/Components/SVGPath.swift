import SwiftUI

/// Parses SVG path data (`d` attributes) into a SwiftUI `Path`. Supports M L H V C S Q T A Z in
/// absolute and relative forms, implicit repeats, and compact number syntax ("1-2.5.5").
/// Used for the curated avatar art, which is authored on a 48 × 48 grid like the mockups.
nonisolated enum SVGPath {
    static func path(_ data: String) -> Path {
        var parser = Parser(data)
        return parser.parse()
    }

    /// SVG path data for a circle.
    static func circle(_ cx: Double, _ cy: Double, _ r: Double) -> String {
        ellipse(cx, cy, r, r)
    }

    /// SVG path data for an ellipse.
    static func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> String {
        "M\(cx - rx) \(cy)A\(rx) \(ry) 0 1 0 \(cx + rx) \(cy)A\(rx) \(ry) 0 1 0 \(cx - rx) \(cy)Z"
    }

    /// SVG path data for a rounded rectangle.
    static func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double, radius r: Double = 0) -> String {
        guard r > 0 else { return "M\(x) \(y)h\(width)v\(height)h\(-width)Z" }
        return "M\(x + r) \(y)H\(x + width - r)A\(r) \(r) 0 0 1 \(x + width) \(y + r)V\(y + height - r)"
            + "A\(r) \(r) 0 0 1 \(x + width - r) \(y + height)H\(x + r)A\(r) \(r) 0 0 1 \(x) \(y + height - r)"
            + "V\(y + r)A\(r) \(r) 0 0 1 \(x + r) \(y)Z"
    }

    private struct Parser {
        private let scalars: [Character]
        private var index = 0
        private var path = Path()
        private var current = CGPoint.zero
        private var subpathStart = CGPoint.zero
        private var lastCubicControl: CGPoint?
        private var lastQuadControl: CGPoint?

        init(_ data: String) {
            scalars = Array(data)
        }

        mutating func parse() -> Path {
            var command: Character?
            while true {
                skipSeparators()
                guard index < scalars.count else { break }
                let character = scalars[index]
                if character.isLetter {
                    command = character
                    index += 1
                } else if command == nil {
                    break // malformed: numbers before any command
                }
                guard let active = command else { break }
                let before = index
                apply(active)
                // After M/m, implicit repeats are L/l.
                if active == "M" { command = "L" }
                if active == "m" { command = "l" }
                if active == "Z" || active == "z" { command = nil }
                if index == before, !(active == "Z" || active == "z") { break } // no progress: stop
            }
            return path
        }

        private mutating func apply(_ command: Character) {
            let relative = command.isLowercase
            let origin = relative ? current : .zero
            switch command.uppercased() {
            case "M":
                guard let point = point(relativeTo: origin) else { return }
                path.move(to: point)
                current = point
                subpathStart = point
                clearControls()
            case "L":
                guard let point = point(relativeTo: origin) else { return }
                path.addLine(to: point)
                current = point
                clearControls()
            case "H":
                guard let x = number() else { return }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                clearControls()
            case "V":
                guard let y = number() else { return }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                clearControls()
            case "C":
                guard let c1 = point(relativeTo: origin), let c2 = point(relativeTo: origin), let end = point(relativeTo: origin) else { return }
                path.addCurve(to: end, control1: c1, control2: c2)
                lastCubicControl = c2
                lastQuadControl = nil
                current = end
            case "S":
                guard let c2 = point(relativeTo: origin), let end = point(relativeTo: origin) else { return }
                let c1 = reflected(lastCubicControl)
                path.addCurve(to: end, control1: c1, control2: c2)
                lastCubicControl = c2
                lastQuadControl = nil
                current = end
            case "Q":
                guard let control = point(relativeTo: origin), let end = point(relativeTo: origin) else { return }
                path.addQuadCurve(to: end, control: control)
                lastQuadControl = control
                lastCubicControl = nil
                current = end
            case "T":
                guard let end = point(relativeTo: origin) else { return }
                let control = reflected(lastQuadControl)
                path.addQuadCurve(to: end, control: control)
                lastQuadControl = control
                lastCubicControl = nil
                current = end
            case "A":
                guard let rx = number(), let ry = number(), let rotation = number(),
                      let largeArc = flag(), let sweep = flag(), let end = point(relativeTo: origin)
                else { return }
                addArc(to: end, rx: rx, ry: ry, rotationDegrees: rotation, largeArc: largeArc, sweep: sweep)
                current = end
                clearControls()
            case "Z":
                path.closeSubpath()
                current = subpathStart
                clearControls()
            default:
                index = scalars.count // unsupported command: stop
            }
        }

        private mutating func clearControls() {
            lastCubicControl = nil
            lastQuadControl = nil
        }

        private func reflected(_ control: CGPoint?) -> CGPoint {
            guard let control else { return current }
            return CGPoint(x: 2 * current.x - control.x, y: 2 * current.y - control.y)
        }

        /// SVG endpoint arc → cubic Béziers (SVG 1.1 implementation notes F.6.5).
        private mutating func addArc(to end: CGPoint, rx rxIn: Double, ry ryIn: Double, rotationDegrees: Double, largeArc: Bool, sweep: Bool) {
            let start = current
            var rx = abs(rxIn), ry = abs(ryIn)
            guard rx > 0, ry > 0, start != end else {
                path.addLine(to: end)
                return
            }
            let phi = rotationDegrees * .pi / 180
            let cosPhi = cos(phi), sinPhi = sin(phi)
            let dx = (start.x - end.x) / 2, dy = (start.y - end.y) / 2
            let x1p = cosPhi * dx + sinPhi * dy
            let y1p = -sinPhi * dx + cosPhi * dy
            let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
            if lambda > 1 {
                rx *= lambda.squareRoot()
                ry *= lambda.squareRoot()
            }
            let numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
            let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
            var coefficient = denominator == 0 ? 0 : (max(0, numerator) / denominator).squareRoot()
            if largeArc == sweep { coefficient = -coefficient }
            let cxp = coefficient * rx * y1p / ry
            let cyp = -coefficient * ry * x1p / rx
            let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
            let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

            func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
                atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            }
            let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
            var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
            if !sweep && delta > 0 { delta -= 2 * .pi }
            if sweep && delta < 0 { delta += 2 * .pi }

            let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
            let step = delta / Double(segments)
            let k = 4.0 / 3.0 * tan(step / 4)
            func point(_ theta: Double) -> CGPoint {
                let x = rx * cos(theta), y = ry * sin(theta)
                return CGPoint(x: cx + cosPhi * x - sinPhi * y, y: cy + sinPhi * x + cosPhi * y)
            }
            func derivative(_ theta: Double) -> CGPoint {
                let x = -rx * sin(theta), y = ry * cos(theta)
                return CGPoint(x: cosPhi * x - sinPhi * y, y: sinPhi * x + cosPhi * y)
            }
            var theta = theta1
            for _ in 0..<segments {
                let next = theta + step
                let p0 = point(theta), p1 = point(next)
                let d0 = derivative(theta), d1 = derivative(next)
                path.addCurve(
                    to: p1,
                    control1: CGPoint(x: p0.x + k * d0.x, y: p0.y + k * d0.y),
                    control2: CGPoint(x: p1.x - k * d1.x, y: p1.y - k * d1.y)
                )
                theta = next
            }
        }

        // MARK: Tokens

        private mutating func skipSeparators() {
            while index < scalars.count, scalars[index] == " " || scalars[index] == "," || scalars[index].isNewline || scalars[index] == "\t" {
                index += 1
            }
        }

        private mutating func point(relativeTo origin: CGPoint) -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return CGPoint(x: origin.x + x, y: origin.y + y)
        }

        private mutating func flag() -> Bool? {
            skipSeparators()
            guard index < scalars.count, scalars[index] == "0" || scalars[index] == "1" else { return nil }
            defer { index += 1 }
            return scalars[index] == "1"
        }

        private mutating func number() -> Double? {
            skipSeparators()
            guard index < scalars.count else { return nil }
            let start = index
            if scalars[index] == "-" || scalars[index] == "+" { index += 1 }
            var sawDot = false, sawDigit = false
            while index < scalars.count {
                let character = scalars[index]
                if character.isNumber {
                    sawDigit = true
                } else if character == ".", !sawDot {
                    sawDot = true
                } else if character == "e" || character == "E", sawDigit {
                    index += 1
                    if index < scalars.count, scalars[index] == "-" || scalars[index] == "+" { index += 1 }
                    continue
                } else {
                    break
                }
                index += 1
            }
            guard sawDigit, let value = Double(String(scalars[start..<index])) else {
                index = start
                return nil
            }
            return value
        }
    }
}
