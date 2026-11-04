import Foundation

/// A terminal's colors: background, text, cursor, and the 16 ANSI colors. A project picks one so
/// its terminals look unlike other projects' (backlog doc UI, Terminal themes).
public struct TerminalTheme: Sendable, Equatable, Identifiable {
    /// An sRGB color.
    public struct RGB: Sendable, Hashable {
        public let red: UInt8
        public let green: UInt8
        public let blue: UInt8

        public init(_ hex: UInt32) {
            red = UInt8((hex >> 16) & 0xFF)
            green = UInt8((hex >> 8) & 0xFF)
            blue = UInt8(hex & 0xFF)
        }
    }

    public let id: String
    public let name: String
    public let background: RGB
    public let foreground: RGB
    public let cursor: RGB
    /// Black, red, green, yellow, blue, magenta, cyan, white, then their bright forms.
    public let ansi: [RGB]

    init(id: String, name: String, background: UInt32, foreground: UInt32, cursor: UInt32? = nil, ansi: [UInt32]) {
        self.id = id
        self.name = name
        self.background = RGB(background)
        self.foreground = RGB(foreground)
        self.cursor = RGB(cursor ?? foreground)
        self.ansi = ansi.map(RGB.init)
    }

    /// The theme with this id; nil (the terminal's own colors) for none or an unknown one.
    public static func named(_ id: String?) -> TerminalTheme? {
        id.flatMap { id in all.first { $0.id == id } }
    }

    /// The themes on offer, dark ones first; each background is plainly unlike the others'.
    public static let all: [TerminalTheme] = [
        TerminalTheme(id: "solarized-dark", name: "Solarized Dark", background: 0x002B36, foreground: 0x839496, cursor: 0x93A1A1,
                      ansi: [0x073642, 0xDC322F, 0x859900, 0xB58900, 0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5,
                             0x586E75, 0xCB4B16, 0x586E75, 0x657B83, 0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3]),
        TerminalTheme(id: "dracula", name: "Dracula", background: 0x282A36, foreground: 0xF8F8F2,
                      ansi: [0x21222C, 0xFF5555, 0x50FA7B, 0xF1FA8C, 0xBD93F9, 0xFF79C6, 0x8BE9FD, 0xF8F8F2,
                             0x6272A4, 0xFF6E6E, 0x69FF94, 0xFFFFA5, 0xD6ACFF, 0xFF92DF, 0xA4FFFF, 0xFFFFFF]),
        TerminalTheme(id: "nord", name: "Nord", background: 0x2E3440, foreground: 0xD8DEE9,
                      ansi: [0x3B4252, 0xBF616A, 0xA3BE8C, 0xEBCB8B, 0x81A1C1, 0xB48EAD, 0x88C0D0, 0xE5E9F0,
                             0x4C566A, 0xBF616A, 0xA3BE8C, 0xEBCB8B, 0x81A1C1, 0xB48EAD, 0x8FBCBB, 0xECEFF4]),
        TerminalTheme(id: "gruvbox-dark", name: "Gruvbox Dark", background: 0x282828, foreground: 0xEBDBB2,
                      ansi: [0x282828, 0xCC241D, 0x98971A, 0xD79921, 0x458588, 0xB16286, 0x689D6A, 0xA89984,
                             0x928374, 0xFB4934, 0xB8BB26, 0xFABD2F, 0x83A598, 0xD3869B, 0x8EC07C, 0xEBDBB2]),
        TerminalTheme(id: "one-dark", name: "One Dark", background: 0x282C34, foreground: 0xABB2BF,
                      ansi: [0x282C34, 0xE06C75, 0x98C379, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xABB2BF,
                             0x5C6370, 0xE06C75, 0x98C379, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xFFFFFF]),
        TerminalTheme(id: "tokyo-night", name: "Tokyo Night", background: 0x1A1B26, foreground: 0xC0CAF5,
                      ansi: [0x15161E, 0xF7768E, 0x9ECE6A, 0xE0AF68, 0x7AA2F7, 0xBB9AF7, 0x7DCFFF, 0xA9B1D6,
                             0x414868, 0xF7768E, 0x9ECE6A, 0xE0AF68, 0x7AA2F7, 0xBB9AF7, 0x7DCFFF, 0xC0CAF5]),
        TerminalTheme(id: "monokai", name: "Monokai", background: 0x272822, foreground: 0xF8F8F2,
                      ansi: [0x272822, 0xF92672, 0xA6E22E, 0xF4BF75, 0x66D9EF, 0xAE81FF, 0xA1EFE4, 0xF8F8F2,
                             0x75715E, 0xF92672, 0xA6E22E, 0xF4BF75, 0x66D9EF, 0xAE81FF, 0xA1EFE4, 0xF9F8F5]),
        TerminalTheme(id: "solarized-light", name: "Solarized Light", background: 0xFDF6E3, foreground: 0x657B83, cursor: 0x586E75,
                      ansi: [0x073642, 0xDC322F, 0x859900, 0xB58900, 0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5,
                             0x002B36, 0xCB4B16, 0x586E75, 0x657B83, 0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3]),
        TerminalTheme(id: "github-light", name: "GitHub Light", background: 0xFFFFFF, foreground: 0x24292F,
                      ansi: [0x24292F, 0xCF222E, 0x116329, 0x4D2D00, 0x0969DA, 0x8250DF, 0x1B7C83, 0x6E7781,
                             0x57606A, 0xA40E26, 0x1A7F37, 0x633C01, 0x218BFF, 0xA475F9, 0x3192AA, 0x8C959F]),
    ]
}
