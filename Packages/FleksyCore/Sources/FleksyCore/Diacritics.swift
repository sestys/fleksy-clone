import Foundation

/// Fast diacritic folding for the letters used in Czech and common Latin accents.
public enum Diacritics {
    static let foldTable: [UInt32: UInt32] = {
        let pairs: [(String, String)] = [
            ("áàâäãåāæ", "a"), ("čçćĉ", "c"), ("ďđ", "d"), ("éèêëěē", "e"), ("ģ", "g"),
            ("íìîïī", "i"), ("ĺľł", "l"), ("ňñń", "n"), ("óòôöõøōœ", "o"), ("ŕř", "r"),
            ("šßśŝ", "s"), ("ťţ", "t"), ("úùûüůū", "u"), ("ýÿ", "y"), ("žźż", "z"),
        ]
        var table: [UInt32: UInt32] = [:]
        for (accented, base) in pairs {
            let b = base.unicodeScalars.first!.value
            for s in accented.unicodeScalars { table[s.value] = b }
        }
        return table
    }()

    @inline(__always)
    public static func fold(_ scalar: UInt32) -> UInt32 {
        foldTable[scalar] ?? scalar
    }

    public static func fold(_ string: String) -> String {
        String(String.UnicodeScalarView(string.unicodeScalars.map { Unicode.Scalar(fold($0.value)) ?? $0 }))
    }

    public static func scalars(_ string: String) -> [UInt32] {
        string.unicodeScalars.map { $0.value }
    }
}
