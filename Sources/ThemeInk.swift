import AppKit

/// "Ink": the colours a theme gives to the parts of a note (title, list markers, numbers, links ...).
/// Ink is drawn as colour-only decoration on top of the text and is never stored in the note.
struct ThemeInk: Equatable {
    enum Kind: String, CaseIterable {
        case title, heading, marker, checkbox, done, number, link, tag, mention, quote, code, body
    }

    var title: NSColor        // the first line of the note
    var heading: NSColor      // "# Heading", "Heading:" and LINES IN CAPITALS
    var marker: NSColor       // "-", "*", "•", "1.", the "#" of a heading, the ">" of a quote
    var checkbox: NSColor     // "[ ]" and "[x]"
    var done: NSColor         // the words of a ticked item (also struck through)
    var number: NSColor       // numbers, times, dates, days, money
    var link: NSColor         // web addresses and email addresses
    var tag: NSColor          // #tags
    var mention: NSColor      // @names
    var quote: NSColor        // "> quoted lines" and "text in quotes"
    var code: NSColor         // `backticks`
    /// Colours the ordinary words drift through, line by line, down the note. Empty: plain theme text.
    var body: [NSColor] = []

    func color(for kind: Kind) -> NSColor? {
        switch kind {
        case .title: return title
        case .heading: return heading
        case .marker: return marker
        case .checkbox: return checkbox
        case .done: return done
        case .number: return number
        case .link: return link
        case .tag: return tag
        case .mention: return mention
        case .quote: return quote
        case .code: return code
        case .body: return body.first
        }
    }

    /// Six colours that show the theme's character at a glance (for gallery dots).
    var swatches: [NSColor] { [title, heading, number, link, tag, mention] }

    /// Body colour for a line `phase` of the way along the gradient (0...1, wraps back and forth).
    func bodyColor(phase: Double) -> NSColor? {
        guard let first = body.first else { return nil }
        guard body.count > 1 else { return first }
        var t: Double = phase.truncatingRemainder(dividingBy: 2)
        if t < 0 { t += 2 }
        if t > 1 { t = 2 - t }
        let scaled: Double = t * Double(body.count - 1)
        let i: Int = min(Int(scaled), body.count - 2)
        let f: CGFloat = CGFloat(scaled - Double(i))
        return body[i].blended(withFraction: f, of: body[i + 1]) ?? body[i]
    }

    static func palette(title: String, heading: String, marker: String, checkbox: String, done: String,
                        number: String, link: String, tag: String, mention: String, quote: String, code: String,
                        body: [String] = []) -> ThemeInk {
        func c(_ hex: String) -> NSColor { NSColor(hex: hex) ?? .textColor }
        return ThemeInk(title: c(title), heading: c(heading), marker: c(marker), checkbox: c(checkbox), done: c(done),
                        number: c(number), link: c(link), tag: c(tag), mention: c(mention), quote: c(quote),
                        code: c(code), body: body.map(c))
    }

    // MARK: Palettes

    /// Built-in themes. Standard themes use their official palettes; where an official colour is too faint on its
    /// own background (WCAG 4.5:1 for words, 3:1 for markers and ticked items) it has been nudged lighter or darker
    /// along the same hue. tests/ink-contrast.py checks every entry.
    static let builtIn: [String: ThemeInk] = [
        "notch": ThemeInk.palette(title: "#0a84ff", heading: "#bf5af2", marker: "#ff9f0a", checkbox: "#30d158", done: "#8e8e93", number: "#ffd60a", link: "#64d2ff", tag: "#ff375f", mention: "#ff9f0a", quote: "#c7c7cc", code: "#66d4cf"),
        "graphite": ThemeInk.palette(title: "#9fcbff", heading: "#c6b3ff", marker: "#98989d", checkbox: "#98989d", done: "#7c7c80", number: "#ffb340", link: "#70d7ff", tag: "#ff8a80", mention: "#a7e3a0", quote: "#b8b8bd", code: "#ffd479"),
        "midnight": ThemeInk.palette(title: "#9cc4ff", heading: "#6ea8ff", marker: "#6ea8ff", checkbox: "#7ee0c3", done: "#6c7a9c", number: "#ffcf7a", link: "#7fdcff", tag: "#ff8fb8", mention: "#b9a2ff", quote: "#a9b8d9", code: "#9de4ff"),
        "paper": ThemeInk.palette(title: "#b8471a", heading: "#3d5a80", marker: "#e06a18", checkbox: "#4f7a3a", done: "#968d78", number: "#2f6f5e", link: "#1f5fa8", tag: "#a8325e", mention: "#6a4fa0", quote: "#6e6656", code: "#7a4a1a"),
        "catppuccin-mocha": ThemeInk.palette(title: "#cba6f7", heading: "#89b4fa", marker: "#94e2d5", checkbox: "#a6e3a1", done: "#7f849c", number: "#fab387", link: "#74c7ec", tag: "#f5c2e7", mention: "#f9e2af", quote: "#a6adc8", code: "#a6e3a1"),
        "catppuccin-latte": ThemeInk.palette(title: "#8839ef", heading: "#145ff5", marker: "#179299", checkbox: "#3e9c2a", done: "#868a9c", number: "#bc4501", link: "#187585", tag: "#c71f9a", mention: "#976014", quote: "#6a6d82", code: "#327c21"),
        "dracula": ThemeInk.palette(title: "#ff79c6", heading: "#bd93f9", marker: "#ffb86c", checkbox: "#50fa7b", done: "#6272a4", number: "#bd93f9", link: "#8be9fd", tag: "#50fa7b", mention: "#ffb86c", quote: "#f1fa8c", code: "#f1fa8c"),
        "nord": ThemeInk.palette(title: "#88c0d0", heading: "#81a1c1", marker: "#5e81ac", checkbox: "#a3be8c", done: "#6f7d98", number: "#b691af", link: "#8fbcbb", tag: "#ebcb8b", mention: "#d18a74", quote: "#9aa5b8", code: "#a3be8c"),
        "tokyo-night": ThemeInk.palette(title: "#7aa2f7", heading: "#bb9af7", marker: "#ff9e64", checkbox: "#9ece6a", done: "#5c6692", number: "#ff9e64", link: "#7dcfff", tag: "#73daca", mention: "#e0af68", quote: "#9aa5ce", code: "#9ece6a"),
        "gruvbox-dark": ThemeInk.palette(title: "#fabd2f", heading: "#8ec07c", marker: "#fe8019", checkbox: "#b8bb26", done: "#928374", number: "#d3869b", link: "#83a598", tag: "#fb5643", mention: "#fe8019", quote: "#a89984", code: "#b8bb26"),
        "gruvbox-light": ThemeInk.palette(title: "#956110", heading: "#407856", marker: "#af3a03", checkbox: "#79740e", done: "#928374", number: "#8f3f71", link: "#076678", tag: "#9d0006", mention: "#af3a03", quote: "#766a5f", code: "#74700d"),
        "solarized-dark": ThemeInk.palette(title: "#b58900", heading: "#e96630", marker: "#268bd2", checkbox: "#859900", done: "#5f767e", number: "#2aa198", link: "#3295da", tag: "#dd649f", mention: "#858ace", quote: "#839496", code: "#859900"),
        "solarized-light": ThemeInk.palette(title: "#8c6a00", heading: "#c24815", marker: "#268bd2", checkbox: "#819400", done: "#809090", number: "#217d76", link: "#2074af", tag: "#cd2d7a", mention: "#6166c0", quote: "#5e737a", code: "#667500"),
        "rose-pine": ThemeInk.palette(title: "#c4a7e7", heading: "#9ccfd8", marker: "#ebbcba", checkbox: "#31748f", done: "#6e6a86", number: "#f6c177", link: "#9ccfd8", tag: "#eb6f92", mention: "#ebbcba", quote: "#908caa", code: "#ebbcba"),
        "rose-pine-dawn": ThemeInk.palette(title: "#7e649b", heading: "#467881", marker: "#d16f6b", checkbox: "#286983", done: "#908b9e", number: "#9e6210", link: "#467881", tag: "#ab526c", mention: "#286983", quote: "#716d8c", code: "#c2423c"),
        "one-dark": ThemeInk.palette(title: "#e5c07b", heading: "#61afef", marker: "#c678dd", checkbox: "#98c379", done: "#6e7786", number: "#d19a66", link: "#56b6c2", tag: "#e17079", mention: "#c678dd", quote: "#98c379", code: "#98c379"),
        "monokai": ThemeInk.palette(title: "#a6e22e", heading: "#66d9ef", marker: "#f92672", checkbox: "#a6e22e", done: "#75715e", number: "#ae81ff", link: "#66d9ef", tag: "#fa4989", mention: "#fd971f", quote: "#e6db74", code: "#e6db74"),
        "kanagawa": ThemeInk.palette(title: "#7e9cd8", heading: "#957fb8", marker: "#ffa066", checkbox: "#98bb6c", done: "#727169", number: "#d27e99", link: "#7fb4ca", tag: "#e46876", mention: "#e6c384", quote: "#98bb6c", code: "#7aa89f"),
        "everforest-dark": ThemeInk.palette(title: "#a7c080", heading: "#83c092", marker: "#e69875", checkbox: "#a7c080", done: "#859289", number: "#d699b6", link: "#7fbbb3", tag: "#e67e80", mention: "#dbbc7f", quote: "#9da9a0", code: "#dbbc7f"),
        "github-dark": ThemeInk.palette(title: "#d2a8ff", heading: "#79c0ff", marker: "#ff7b72", checkbox: "#3fb950", done: "#6e7681", number: "#ffa657", link: "#58a6ff", tag: "#56d4dd", mention: "#e3b341", quote: "#a5d6ff", code: "#7ee787"),
        "github-light": ThemeInk.palette(title: "#8250df", heading: "#0550ae", marker: "#cf222e", checkbox: "#1a7f37", done: "#6e7781", number: "#953800", link: "#0969da", tag: "#1b7c83", mention: "#9a6700", quote: "#0a3069", code: "#116329"),
        "matrix": ThemeInk.palette(title: "#eaffec", heading: "#39ff6a", marker: "#3bfa73", checkbox: "#3bfa73", done: "#3c8a50", number: "#d8ff4a", link: "#7dffd2", tag: "#4cff9a", mention: "#a6ffcc", quote: "#5fd47a", code: "#d0ff8a", body: ["#c8ffd0", "#7ee89a", "#45d46c"]),
        "stargate": ThemeInk.palette(title: "#ffb875", heading: "#ffd29a", marker: "#69d4ff", checkbox: "#69d4ff", done: "#5f7f8f", number: "#7fe3ff", link: "#9fd8ff", tag: "#ffd27a", mention: "#9cf0e0", quote: "#9fbccb", code: "#ffe0b0"),
        "storm": ThemeInk.palette(title: "#fff27a", heading: "#b2b9ff", marker: "#7fd4ff", checkbox: "#7fd4ff", done: "#6b7594", number: "#7fe9ff", link: "#8fb8ff", tag: "#d49bff", mention: "#ffd07a", quote: "#9fa9c8", code: "#c3f0ff"),
        "transporter": ThemeInk.palette(title: "#ffe08a", heading: "#f7aafd", marker: "#c99bff", checkbox: "#9df5ff", done: "#7a6890", number: "#9df5ff", link: "#9fcbff", tag: "#ff9ad5", mention: "#ffd28a", quote: "#c4b0d8", code: "#e7c9ff", body: ["#f4deff", "#d9c4ff", "#ffd1ec"]),
        "singularity": ThemeInk.palette(title: "#ffd08a", heading: "#ff946e", marker: "#ff6b6b", checkbox: "#ffb27a", done: "#7d6470", number: "#ffc06b", link: "#c9a7ff", tag: "#ff7fa8", mention: "#ffb27a", quote: "#c9b0b8", code: "#ffd9c2", body: ["#fde8ee", "#ffd4c2", "#e8c8ff"]),
        "phosphor": ThemeInk.palette(title: "#fff3d6", heading: "#ffbf5e", marker: "#ff9d2e", checkbox: "#ff9d2e", done: "#8a6634", number: "#ff9d2e", link: "#ffe6b8", tag: "#ffb454", mention: "#ffcc80", quote: "#d9a865", code: "#ffe9c4"),
        "chalkboard": ThemeInk.palette(title: "#fff38a", heading: "#9fd6ff", marker: "#ff9fc6", checkbox: "#fff38a", done: "#7f9488", number: "#ffb38a", link: "#9fd6ff", tag: "#ff9fc6", mention: "#b9f0a8", quote: "#c9cfb8", code: "#fff6c2"),
        "ember-typewriter": ThemeInk.palette(title: "#a8321a", heading: "#963b1e", marker: "#c2461f", checkbox: "#7a5a2a", done: "#9c8466", number: "#8a4b12", link: "#2f5d8a", tag: "#8a2f4a", mention: "#5a6b2a", quote: "#6e5844", code: "#6b3a1a"),
        "field-notes": ThemeInk.palette(title: "#5b6b1e", heading: "#725024", marker: "#a06a1a", checkbox: "#5b6b1e", done: "#968b6e", number: "#b03a2e", link: "#2c5d7c", tag: "#7a4f1e", mention: "#4f6a2a", quote: "#6b6450", code: "#5a4a2a"),
        "blueprint": ThemeInk.palette(title: "#ffffff", heading: "#79d8ff", marker: "#79d8ff", checkbox: "#79d8ff", done: "#6a8aa8", number: "#ffe066", link: "#a8e6ff", tag: "#8cf5e0", mention: "#c9d9ff", quote: "#9fbfd9", code: "#ffe9a0"),
        "neon-district": ThemeInk.palette(title: "#ff73b8", heading: "#70e8e1", marker: "#ffe66b", checkbox: "#70e8e1", done: "#8a6a85", number: "#ffe66b", link: "#70e8e1", tag: "#ff73b8", mention: "#b48cff", quote: "#d6a8d0", code: "#9ffff0", body: ["#ffd9ec", "#d9e6ff", "#c8fff6"]),
        "morning-edition": ThemeInk.palette(title: "#b3261e", heading: "#111111", marker: "#b3261e", checkbox: "#3a3a35", done: "#8f8d82", number: "#1f4e79", link: "#1f4e79", tag: "#6a3a1a", mention: "#3d5a40", quote: "#5a5a52", code: "#3a3a35"),
        "synthwave": ThemeInk.palette(title: "#ffb35c", heading: "#ff5e9c", marker: "#3ff0ff", checkbox: "#3ff0ff", done: "#7a5f8f", number: "#ffd36b", link: "#3ff0ff", tag: "#ff5e9c", mention: "#c98cff", quote: "#d9b8e0", code: "#8cf7ff", body: ["#ffe8f5", "#ffd0e6", "#ffc9a8"]),
        "aurora": ThemeInk.palette(title: "#4ef2b8", heading: "#6fe3ff", marker: "#c49bff", checkbox: "#4ef2b8", done: "#5f8a84", number: "#ffe39a", link: "#6fe3ff", tag: "#c49bff", mention: "#9fffd9", quote: "#a8cfc6", code: "#d4f8ff", body: ["#e4fff6", "#c8fff0", "#d9e2ff"]),
        "deep-sea": ThemeInk.palette(title: "#38e2ff", heading: "#7fffd4", marker: "#ffb07a", checkbox: "#7fffd4", done: "#4f7a8f", number: "#ffb07a", link: "#9ee9ff", tag: "#ff8fa8", mention: "#b8f2e6", quote: "#9ec4d6", code: "#c0fff0"),
        "liquid-glass": ThemeInk.palette(title: "#006be0", heading: "#3b3fbf", marker: "#0a8f8a", checkbox: "#007aff", done: "#818d9e", number: "#cd3428", link: "#0060df", tag: "#097c78", mention: "#5856d6", quote: "#4a5668", code: "#9a3fbf"),
    ]

    // MARK: Custom themes

    /// Ink for a theme file. `notchpad-ink-<kind> = #hex` keys win; then the file's 16-colour palette
    /// (`palette = 1=#…` … `palette = 15=#…`); then colours derived from the accent and text colours.
    /// Derived colours are made legible against the background; colours the file sets itself are used as written.
    ///
    /// Keys: notchpad-ink-title, -heading, -marker, -checkbox, -done, -number, -link, -tag, -mention, -quote,
    /// -code, and notchpad-ink-gradient = #hex, #hex, … (body text colours down the note; "none" for plain).
    static func derived(for theme: PadThemeSpec) -> ThemeInk {
        let bg = theme.background, fg = theme.text
        func pal(_ n: Int) -> NSColor? { theme.extras["palette.\(n)"].flatMap(NSColor.init(hex:)) }
        // Prefer the bright version of a colour on dark backgrounds, the normal one on light backgrounds.
        func ansi(_ n: Int) -> NSColor? { theme.isDark ? (pal(n + 8) ?? pal(n)) : (pal(n) ?? pal(n + 8)) }
        func hue(_ shift: CGFloat) -> NSColor { theme.accent.rotatingHue(by: shift) }
        let accent = theme.accent
        var ink = ThemeInk(
            title: ansi(5) ?? accent,
            heading: ansi(4) ?? (accent.blended(withFraction: 0.35, of: fg) ?? accent),
            marker: ansi(1) ?? hue(0.5),
            checkbox: ansi(2) ?? accent,
            done: pal(8) ?? (fg.blended(withFraction: 0.5, of: bg) ?? fg),
            number: ansi(3) ?? hue(0.12),
            link: ansi(6) ?? hue(-0.12),
            tag: ansi(2) ?? hue(0.33),
            mention: pal(theme.isDark ? 3 : 11) ?? hue(-0.33),
            quote: fg.blended(withFraction: 0.3, of: ansi(6) ?? bg) ?? fg,
            code: ansi(2).flatMap { $0.blended(withFraction: 0.35, of: fg) } ?? hue(0.2))
        let kinds: [(WritableKeyPath<ThemeInk, NSColor>, String, Double)] = [
            (\.title, "title", 4.5), (\.heading, "heading", 4.5), (\.marker, "marker", 3), (\.checkbox, "checkbox", 3),
            (\.done, "done", 3), (\.number, "number", 4.5), (\.link, "link", 4.5), (\.tag, "tag", 4.5),
            (\.mention, "mention", 4.5), (\.quote, "quote", 4.5), (\.code, "code", 4.5),
        ]
        for (path, key, minimum) in kinds {
            if let own = theme.extras["notchpad-ink-" + key].flatMap(NSColor.init(hex:)) {
                ink[keyPath: path] = own
            } else {
                ink[keyPath: path] = ink[keyPath: path].legible(on: bg, minimum: minimum)
            }
        }
        if let raw = theme.extras["notchpad-ink-gradient"] {
            ink.body = raw.split(separator: ",").compactMap { NSColor(hex: String($0)) }
        }
        return ink
    }
}

extension PadThemeSpec {
    var ink: ThemeInk {
        if !isCustom, let ink = ThemeInk.builtIn[id] { return ink }
        return ThemeInk.derived(for: self)
    }
}

extension NSColor {
    /// WCAG relative luminance.
    var inkLuminance: Double {
        let c = usingColorSpace(.sRGB) ?? self
        func lin(_ v: CGFloat) -> Double {
            let x = Double(v)
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        let r: Double = 0.2126 * lin(c.redComponent)
        let g: Double = 0.7152 * lin(c.greenComponent)
        let b: Double = 0.0722 * lin(c.blueComponent)
        return r + g + b
    }

    func inkContrast(with other: NSColor) -> Double {
        let a: Double = inkLuminance, b: Double = other.inkLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// The same colour moved towards white (dark backgrounds) or black (light ones) until it reads clearly.
    func legible(on background: NSColor, minimum: Double) -> NSColor {
        let target: NSColor = background.inkLuminance < 0.18 ? .white : .black
        var colour: NSColor = usingColorSpace(.sRGB) ?? self
        var step = 0
        while colour.inkContrast(with: background) < minimum && step < 20 {
            step += 1
            colour = (usingColorSpace(.sRGB) ?? self).blended(withFraction: CGFloat(step) * 0.05, of: target) ?? colour
        }
        return colour
    }

    func rotatingHue(by shift: CGFloat) -> NSColor {
        let c = usingColorSpace(.sRGB) ?? self
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var nh: CGFloat = h + shift
        nh -= floor(nh)
        return NSColor(hue: nh, saturation: max(s, 0.45), brightness: max(b, 0.55), alpha: 1)
    }
}

// MARK: Finding the parts of a note

/// One stretch of the note to colour. Spans are applied in order, so later ones win.
struct InkSpan {
    var range: NSRange
    var kind: ThemeInk.Kind
}

/// Reads plain text and says which parts are titles, list markers, numbers, links and so on.
/// Works on whole lines only, so callers can colour just the lines on screen.
enum InkScanner {
    private static func re(_ pattern: String) -> NSRegularExpression {
        // The patterns are fixed, so a failure here is a programming mistake caught by the first build check.
        try! NSRegularExpression(pattern: pattern, options: [])
    }

    private static let list = re(#"[ \t]*([-*•+–◦▪]|\d{1,3}[.)])[ \t]+"#)
    private static let checkbox = re(#"[ \t]*(\[[ xX✓✔]\]|[☐☑☒✅])(?=[ \t]|$)"#)
    private static let hashHeading = re(#"[ \t]*(#{1,6})[ \t]+\S"#)
    private static let quoteLine = re(#"[ \t]*(>+)"#)
    private static let inline = re(
        #"(\b(?:https?://|www\.)[^\s<>"]*[^\s<>".,;:!?)\]'’”])"#                       // 1 link
        + #"|([\w.+-]+@[\w-]+(?:\.[\w-]+)*\.[A-Za-z]{2,})"#                             // 2 email
        + #"|(`[^`\n]+`)"#                                                              // 3 code
        + #"|("[^"\n]{1,120}"|“[^”\n]{1,120}”)"#                                        // 4 quoted
        + #"|((?<![\w#&])#[\p{L}_][\p{L}\p{N}_/-]*)"#                                   // 5 tag
        + #"|((?<![\w@])@[\p{L}\p{N}_](?:[\p{L}\p{N}_.-]*[\p{L}\p{N}_])?)"#             // 6 name
        + #"|((?:\b[A-Z]{1,3})?[$€£¥₹]\s?\d[\d,]*(?:\.\d+)?(?:\s?(?:[kKmM]|bn)\b)?"#   // 7 money
        + #"|\b\d{1,2}:\d{2}(?::\d{2})?(?:\s?[aApP]\.?[mM]\b\.?)?"#                     //   times
        + #"|\b\d{1,2}\s?[aApP][mM]\b"#
        + #"|\b\d{1,4}[/.-]\d{1,2}[/.-]\d{1,4}\b"#                                      //   dates
        + #"|\b\d+(?:st|nd|rd|th)\b"#
        + #"|\b(?:Mon|Tue|Tues|Wed|Thu|Thur|Thurs|Fri)\b|\b(?:Mon|Tues|Wednes|Thurs|Fri|Satur|Sun)day\b"#
        + #"|\b(?:Jan|Feb|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec|January|February|March|April|June|July|August|September|October|November|December)\b"#
        + #"|\b(?i:today|tonight|tomorrow|yesterday|noon|midnight)\b"#
        + #"|\b\d[\d,]*(?:\.\d+)?(?:%|\s?(?:kg|km|cm|mm|ml|hrs?|mins?|[gmlhL])\b|\b))"#   //   plain numbers
    )
    private static let inlineKinds: [ThemeInk.Kind] = [.link, .link, .code, .quote, .tag, .mention, .number]

    /// The first line with something on it: the note's title. Nil when the note is blank.
    static func titleLine(in text: NSString) -> NSRange? {
        let length = text.length
        var i = 0
        while i < length {
            let c = text.character(at: i)
            if c != 32 && c != 9 && c != 10 && c != 13 && c != 0x2028 && c != 0x2029 { break }
            i += 1
        }
        guard i < length else { return nil }
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: i, length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }

    /// Spans for every line touching `range` (pass whole lines). `title` is the result of `titleLine(in:)`.
    /// Works on a copy of just those lines, so a long note costs no more than the part being coloured.
    static func scan(_ text: NSString, in range: NSRange, title: NSRange?) -> [InkSpan] {
        let part = Part(text.substring(with: range) as NSString)
        let titleStart: Int = title.map { $0.location - range.location } ?? -1
        var spans: [InkSpan] = []
        part.ns.enumerateSubstrings(in: NSRange(location: 0, length: part.ns.length),
                                    options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            scanLine(part, line, isTitle: line.location == titleStart, into: &spans)
        }
        for i in spans.indices { spans[i].range.location += range.location }
        return spans
    }

    /// The text being scanned, kept both ways so regular expressions do not copy it again.
    private struct Part {
        let ns: NSString
        let string: String
        init(_ ns: NSString) { self.ns = ns; self.string = ns as String }
    }

    private static func firstMatch(_ re: NSRegularExpression, _ part: Part, from: Int, to end: Int) -> NSTextCheckingResult? {
        guard from <= end else { return nil }
        return re.firstMatch(in: part.string, options: [.anchored], range: NSRange(location: from, length: end - from))
    }

    private static func scanLine(_ part: Part, _ line: NSRange, isTitle: Bool, into spans: inout [InkSpan]) {
        guard line.length > 0 else { return }
        let end = NSMaxRange(line)
        if let m = firstMatch(hashHeading, part, from: line.location, to: end) {
            let hashes = m.range(at: 1)
            spans.append(InkSpan(range: hashes, kind: .marker))
            let rest = NSRange(location: NSMaxRange(hashes), length: end - NSMaxRange(hashes))
            spans.append(InkSpan(range: rest, kind: isTitle ? .title : .heading))
            return
        }
        if isTitle {
            spans.append(InkSpan(range: line, kind: .title))
            return
        }
        if let m = firstMatch(quoteLine, part, from: line.location, to: end) {
            let marks = m.range(at: 1)
            spans.append(InkSpan(range: marks, kind: .marker))
            let rest = NSRange(location: NSMaxRange(marks), length: end - NSMaxRange(marks))
            spans.append(InkSpan(range: rest, kind: .quote))
            scanInline(part, rest, into: &spans)
            return
        }
        var bodyStart = line.location
        var isList = false
        if let m = firstMatch(list, part, from: line.location, to: end) {
            spans.append(InkSpan(range: m.range(at: 1), kind: .marker))
            bodyStart = NSMaxRange(m.range)
            isList = true
        }
        if let m = firstMatch(checkbox, part, from: bodyStart, to: end) {
            let box = m.range(at: 1)
            let mark = part.ns.substring(with: box)
            let ticked = !(mark == "[ ]" || mark == "☐")
            spans.append(InkSpan(range: box, kind: .checkbox))
            bodyStart = NSMaxRange(m.range)
            if ticked {
                // Strike through the words, not the space after the box.
                while bodyStart < end, part.ns.character(at: bodyStart) == 32 || part.ns.character(at: bodyStart) == 9 { bodyStart += 1 }
                if bodyStart < end { spans.append(InkSpan(range: NSRange(location: bodyStart, length: end - bodyStart), kind: .done)) }
                return
            }
            isList = true
        }
        if !isList, isHeadingLike(part.ns.substring(with: line)) {
            spans.append(InkSpan(range: line, kind: .heading))
            return
        }
        let rest = NSRange(location: bodyStart, length: end - bodyStart)
        guard rest.length > 0 else { return }
        spans.append(InkSpan(range: rest, kind: .body))
        scanInline(part, rest, into: &spans)
    }

    /// "Shopping:" or "TO DO" on a short line of its own.
    private static func isHeadingLike(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard s.count >= 2, s.count <= 48, !s.contains("://") else { return false }
        if s.hasSuffix(":"), !s.dropLast().contains(":"), s.contains(where: { $0.isLetter }) { return true }
        var capitals = 0
        for ch in s {
            if ch.isLowercase { return false }
            if ch.isUppercase { capitals += 1 }
        }
        return capitals >= 3
    }

    private static func scanInline(_ part: Part, _ range: NSRange, into spans: inout [InkSpan]) {
        guard range.length > 0 else { return }
        inline.enumerateMatches(in: part.string, options: [], range: range) { match, _, _ in
            guard let match else { return }
            for (i, kind) in inlineKinds.enumerated() where match.range(at: i + 1).location != NSNotFound {
                spans.append(InkSpan(range: match.range(at: i + 1), kind: kind))
                break
            }
        }
    }
}
