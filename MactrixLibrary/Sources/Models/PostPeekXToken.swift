import Foundation

/// The `token` query value of X's syndication endpoint for one post ID
/// (MATRIX-201).
///
/// X's own embed code derives it from the ID, and post-peek
/// (https://github.com/tsvb/post-peek, MIT) does the same:
/// `((Number(id) / 1e15) * Math.PI).toString(36)` with every run of `0` and
/// the `.` removed. The value depends on how JavaScript writes a fraction in
/// base 36, so `radixString` ports that algorithm (V8's
/// `DoubleToRadixCString`, which JavaScriptCore shares) digit for digit.
public enum PostPeekXToken {
    /// The token of `id`, or nil for an ID that is not a number.
    public static func token(for id: String) -> String? {
        guard let value = Double(id), value.isFinite else { return nil }
        return radixString(value / 1e15 * Double.pi, radix: 36).filter { $0 != "0" && $0 != "." }
    }

    private static let digits = Array("0123456789abcdefghijklmnopqrstuvwxyz")

    /// `value.toString(radix)` as JavaScript writes it, for a finite value
    /// and a radix from 2 to 36.
    static func radixString(_ value: Double, radix: Int) -> String {
        precondition(value.isFinite && (2 ... 36).contains(radix))
        let base = Double(radix)
        let negative = value < 0
        let magnitude = abs(value)

        var integer = magnitude.rounded(.down)
        var fraction = magnitude - integer
        // Fraction digits only up to the precision of the value: half the
        // distance to the next double.
        var delta = max(Double.leastNonzeroMagnitude, 0.5 * (magnitude.nextUp - magnitude))
        var fractionDigits: [Int] = []
        if fraction >= delta {
            repeat {
                fraction *= base
                delta *= base
                let digit = Int(fraction)
                fractionDigits.append(digit)
                fraction -= Double(digit)
                // Round half to even.
                if fraction > 0.5 || (fraction == 0.5 && digit & 1 == 1), fraction + delta > 1 {
                    // Carry into the digits already written.
                    while true {
                        guard let last = fractionDigits.popLast() else {
                            integer += 1
                            break
                        }
                        if last + 1 < radix {
                            fractionDigits.append(last + 1)
                            break
                        }
                    }
                    break
                }
            } while fraction >= delta
        }

        // Integer digits. The digits below the precision of the value are 0.
        var integerDigits: [Int] = []
        while (integer / base).exponent > 52 {
            integer /= base
            integerDigits.append(0)
        }
        repeat {
            let remainder = integer.truncatingRemainder(dividingBy: base)
            integerDigits.append(Int(remainder))
            integer = (integer - remainder) / base
        } while integer > 0

        var result = negative ? "-" : ""
        result += String(integerDigits.reversed().map { digits[$0] })
        if !fractionDigits.isEmpty {
            result += "." + String(fractionDigits.map { digits[$0] })
        }
        return result
    }
}
