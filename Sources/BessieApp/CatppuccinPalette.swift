import Foundation

/// The four upstream Catppuccin flavors pinned from catppuccin/palette v1.8.0.
enum CatppuccinFlavor: String, CaseIterable, Sendable {
    case latte
    case frappe
    case macchiato
    case mocha
}

/// Stable upstream color keys in Catppuccin's canonical order.
enum CatppuccinColorName: String, CaseIterable, Sendable {
    case rosewater, flamingo, pink, mauve, red, maroon, peach, yellow
    case green, teal, sky, sapphire, blue, lavender, text
    case subtext1, subtext0, overlay2, overlay1, overlay0
    case surface2, surface1, surface0, base, mantle, crust
}

/// One opaque sRGB color from the pinned upstream palette.
struct CatppuccinColor: Equatable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    init(rgb: UInt32) {
        precondition(rgb <= 0xFF_FF_FF)
        red = UInt8((rgb >> 16) & 0xFF)
        green = UInt8((rgb >> 8) & 0xFF)
        blue = UInt8(rgb & 0xFF)
        alpha = 0xFF
    }

    var hex: String {
        String(format: "#%02x%02x%02x", red, green, blue)
    }
}

struct CatppuccinFlavorPalette: Sendable {
    let colors: [CatppuccinColorName: CatppuccinColor]

    subscript(name: CatppuccinColorName) -> CatppuccinColor? {
        colors[name]
    }
}

/// Canonical native palette source. Terminal themes remain independently pinned.
struct CatppuccinPalette: Sendable {
    private let flavors: [CatppuccinFlavor: CatppuccinFlavorPalette]

    subscript(flavor: CatppuccinFlavor) -> CatppuccinFlavorPalette {
        // This is total by construction and locked by the exact palette contract tests.
        flavors[flavor]!
    }

    static let v1_8_0 = CatppuccinPalette(flavors: [
        .latte: flavor("dc8a78 dd7878 ea76cb 8839ef d20f39 e64553 fe640b df8e1d 40a02b 179299 04a5e5 209fb5 1e66f5 7287fd 4c4f69 5c5f77 6c6f85 7c7f93 8c8fa1 9ca0b0 acb0be bcc0cc ccd0da eff1f5 e6e9ef dce0e8"),
        .frappe: flavor("f2d5cf eebebe f4b8e4 ca9ee6 e78284 ea999c ef9f76 e5c890 a6d189 81c8be 99d1db 85c1dc 8caaee babbf1 c6d0f5 b5bfe2 a5adce 949cbb 838ba7 737994 626880 51576d 414559 303446 292c3c 232634"),
        .macchiato: flavor("f4dbd6 f0c6c6 f5bde6 c6a0f6 ed8796 ee99a0 f5a97f eed49f a6da95 8bd5ca 91d7e3 7dc4e4 8aadf4 b7bdf8 cad3f5 b8c0e0 a5adcb 939ab7 8087a2 6e738d 5b6078 494d64 363a4f 24273a 1e2030 181926"),
        .mocha: flavor("f5e0dc f2cdcd f5c2e7 cba6f7 f38ba8 eba0ac fab387 f9e2af a6e3a1 94e2d5 89dceb 74c7ec 89b4fa b4befe cdd6f4 bac2de a6adc8 9399b2 7f849c 6c7086 585b70 45475a 313244 1e1e2e 181825 11111b"),
    ])

    private static func flavor(_ values: String) -> CatppuccinFlavorPalette {
        let rgbValues = values.split(separator: " ").map { UInt32($0, radix: 16)! }
        precondition(rgbValues.count == CatppuccinColorName.allCases.count)
        return CatppuccinFlavorPalette(colors: Dictionary(uniqueKeysWithValues:
            zip(CatppuccinColorName.allCases, rgbValues.map { CatppuccinColor(rgb: $0) })
        ))
    }
}
