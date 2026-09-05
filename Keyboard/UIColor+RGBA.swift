import UIKit
import FleksyCore

extension UIColor {
    convenience init(_ c: RGBA) {
        self.init(red: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
}
