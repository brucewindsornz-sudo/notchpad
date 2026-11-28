import SwiftUI

struct FlightAnimationSettingsSection: View {
    static var previewOnPad: (() -> Void)?

    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var themes = ThemeStore.shared
    @State private var hovered: String?
    @State private var clicked: String?
    @State private var clickCount = 0
    @State private var surprise: FlightEffect = .gate

    init() {}

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Boomerang animation").font(.headline)
                Text("Choose how a floating pad flies back to the notch. Point at a tile to watch it, or click to choose it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id("flightAnimation")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 12, alignment: .top)], spacing: 10) {
                let matched = FlightEffect.resolve(setting: "theme", theme: themes.current) ?? .boomerang
                tile("theme", title: "Match theme", detail: "Now: \(matched.label).",
                     symbol: "paintpalette", effect: matched)
                tile("classic", title: "Classic", detail: "The pad glides back into the notch.",
                     symbol: "arrow.up.to.line", effect: .boomerang)
                tile("random", title: "Surprise me", detail: "NotchPad picks an animation each time.",
                     symbol: "shuffle", effect: surprise)
                ForEach(FlightEffect.allCases) { effect in
                    tile(effect.id, title: effect.label, detail: effect.detail, symbol: effect.symbol, effect: effect)
                }
            }
            .padding(.vertical, 4)
            Picker("Speed", selection: $settings.closeSpeed) {
                ForEach(CloseSpeed.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("This also changes the speed of closing animations.")
            HStack(spacing: 8) {
                Button("Try it on the pad") { Self.previewOnPad?() }
                Text("Floats the pad, then sends it back with your choice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(reduceMotionOn
                 ? "Reduce motion is on, so the pad uses the classic glide."
                 : "When Reduce motion is on, the pad uses the classic glide.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tile(_ key: String, title: String, detail: String, symbol: String, effect: FlightEffect) -> some View {
        let selected = settings.flightEffect == key
        let playing = (hovered ?? clicked) == key && !reduceMotionOn && !testNoEffects
        return Button {
            choose(key)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                FlightTilePreview(effect: effect, theme: themes.current, playing: playing, classic: key == "classic")
                    .id(clicked == key ? "\(key)-\(clickCount)" : key)
                    .frame(maxWidth: .infinity)
                    .frame(height: 67)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 2.5 : 1))
                HStack(spacing: 4) {
                    Image(systemName: symbol).font(.caption2).foregroundStyle(.secondary)
                    Text(title).font(.caption).lineLimit(1)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark").font(.caption2).foregroundStyle(Color.accentColor)
                    }
                }
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title + ": " + detail)
        .accessibilityLabel(Text(title + " boomerang animation"))
        .accessibilityHint(Text(detail))
        .accessibilityValue(Text(selected ? "Selected" : ""))
        .onHover { inside in
            if inside {
                if key == "random" { pickSurprise() }
                hovered = key
            } else if hovered == key {
                hovered = nil
            }
        }
    }

    private func pickSurprise() {
        if let next = FlightEffect.allCases.filter({ $0 != surprise }).randomElement() { surprise = next }
    }

    private func choose(_ key: String) {
        settings.flightEffect = key
        if key == "random" { pickSurprise() }
        clicked = key
        clickCount += 1
        let token = clickCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if clickCount == token { clicked = nil }
        }
    }
}

private struct FlightTilePreview: View {
    let effect: FlightEffect
    let theme: PadThemeSpec
    let playing: Bool
    let classic: Bool

    @State private var scene: FlightScene?
    @State private var started = Date()

    private var key: String { "\(effect.id)|\(theme.id)|\(theme.name)" }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(.sRGB, red: 0.11, green: 0.13, blue: 0.2),
                                    Color(.sRGB, red: 0.23, green: 0.17, blue: 0.25)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let scene = scene {
                if playing {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                        frame(scene, t: loop(at: timeline.date, duration: scene.duration))
                    }
                } else {
                    frame(scene, t: classic ? 0.35 : 0.48)
                }
            }
        }
        .onAppear { rebuild() }
        .onChange(of: key) { _ in rebuild() }
        .onChange(of: playing) { on in if on { started = Date() } }
    }

    private func frame(_ scene: FlightScene, t: Double) -> some View {
        FlightEffectCanvas(scene: scene, t: t, fit: true, classicPreview: classic,
                           visible: CGRect(x: 240, y: 0, width: 940, height: 650))
    }

    private func rebuild() {
        scene = FlightScene.mock(effect: effect, theme: theme, layout: .right)
        started = Date()
    }

    private func loop(at date: Date, duration: Double) -> Double {
        let head = 0.3, tail = 0.45
        let elapsed = max(0, date.timeIntervalSince(started))
        let cycle = elapsed.truncatingRemainder(dividingBy: head + duration + tail)
        return clamp01((cycle - head) / duration)
    }
}
