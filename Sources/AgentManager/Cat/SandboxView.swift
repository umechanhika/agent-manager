import SwiftUI

/// 箱庭ビュー本体。論理シーン 160x110 を 2x（320x220pt）で描画する。
/// Canvas はヒットテスト無効にし、猫位置の透明ヒットレクトを上に重ねる
/// （空き領域はパネル背景へ抜けるので isMovableByWindowBackground の窓ドラッグが生きる。
///   ScrollView を挟まないので ClickThroughHostingView の first-click も効く）。
struct SandboxView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var simulation: CatSimulation

    /// ホバー中の猫（ネームプレートのフル表示用。移動停止は simulation 側）。
    @State private var hoveredID: String?

    private static let scale: CGFloat = 2
    private static let panelSize = CGSize(width: 320, height: 220)

    var body: some View {
        ZStack(alignment: .top) {
            canvas
                .allowsHitTesting(false)
            hitRects
            header
                .allowsHitTesting(false)
            if store.sessions.isEmpty {
                Text("セッションなし")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
    }

    // MARK: - Canvas（空 → 星 → 床 → 小物 → 猫(y順) → ネームプレート → エモート）

    private var canvas: some View {
        Canvas { context, _ in
            let snap = simulation.snapshot
            let theme = SkyTheme.current()
            let s = Self.scale

            drawSky(context, theme: theme, tick: snap.twinkle)
            drawFloor(context, theme: theme)

            // 小物（猫より奥）。
            draw(context, image: SpriteRenderer.plantImage(),
                 topLeft: CGPoint(x: 4, y: 48), w: 12, h: 16)
            for cushion in CatSimulation.Scene.cushions {
                draw(context, image: SpriteRenderer.cushionImage(),
                     topLeft: CGPoint(x: cushion.x - 8, y: cushion.y - 3), w: 16, h: 8)
            }
            draw(context, image: SpriteRenderer.yarnImage(frame: snap.yarnFrame),
                 topLeft: CGPoint(x: snap.yarnPos.x - 4, y: snap.yarnPos.y - 4), w: 8, h: 8)

            // 猫（snapshot は y 昇順 = 奥→手前）。
            for cat in snap.cats {
                let cx = cat.pos.x.rounded()
                let cy = cat.pos.y.rounded()
                let awake = cat.anim != .sleep
                let image = SpriteRenderer.catImage(
                    anim: cat.anim, frame: cat.frame, paletteIndex: cat.paletteIndex,
                    mirrored: cat.facingLeft, nightEyes: theme.isNight && awake)
                draw(context, image: image, topLeft: CGPoint(x: cx - 8, y: cy - 8), w: 16, h: 16)
                drawNameplate(context, cat: cat, cx: cx * s, topY: (cy + 8) * s + 1, theme: theme)
                if let emote = cat.emote, cat.emoteVisible {
                    let img = SpriteRenderer.emoteImage(kind: emote, frame: cat.emoteFrame)
                    draw(context, image: img, topLeft: CGPoint(x: cx - 2, y: cy - 19), w: 10, h: 10)
                }
            }
        }
    }

    /// CGImage を論理座標（左上原点・論理px）で描く。ベイクは 4x プリスケール済みなので
    /// 2x 描画レクトとデバイスピクセルが 1:1 に揃い、補間でにじまない。
    private func draw(_ context: GraphicsContext, image: CGImage,
                      topLeft: CGPoint, w: CGFloat, h: CGFloat) {
        let s = Self.scale
        let rect = CGRect(x: topLeft.x.rounded() * s, y: topLeft.y.rounded() * s,
                          width: w * s, height: h * s)
        var img = Image(decorative: image, scale: CGFloat(SpriteRenderer.bakeScale) / s)
        img = img.interpolation(.none).antialiased(false)
        context.draw(img, in: rect)
    }

    private func drawSky(_ context: GraphicsContext, theme: SkyTheme, tick: Int) {
        let s = Self.scale
        // フラット3横帯（グラデ禁止：ピクセル風）。
        let bands: [(CGFloat, CGFloat)] = [(0, 24), (24, 42), (42, 55)]
        for (i, band) in bands.enumerated() {
            context.fill(
                Path(CGRect(x: 0, y: band.0 * s, width: 160 * s, height: (band.1 - band.0) * s)),
                with: .color(theme.sky[i]))
        }
        if theme.isNight {
            for (i, star) in Self.stars.enumerated() where (tick + i * 7) % 24 < 16 {
                let bright = (tick + i * 5) % 24 < 8
                context.fill(
                    Path(CGRect(x: star.x * s, y: star.y * s, width: s, height: s)),
                    with: .color(.white.opacity(bright ? 0.95 : 0.55)))
            }
        }
    }

    private func drawFloor(_ context: GraphicsContext, theme: SkyTheme) {
        let s = Self.scale
        context.fill(Path(CGRect(x: 0, y: 55 * s, width: 160 * s, height: 55 * s)),
                     with: .color(theme.floor))
        // 床の最奥に陰の帯を1本（疑似奥行き）。
        context.fill(Path(CGRect(x: 0, y: 55 * s, width: 160 * s, height: 2 * s)),
                     with: .color(theme.floorShade))
    }

    private func drawNameplate(_ context: GraphicsContext, cat: CatSimulation.CatSnapshot,
                               cx: CGFloat, topY: CGFloat, theme: SkyTheme) {
        let full = cat.label
        let name = (hoveredID == cat.id || full.count <= 10) ? full : String(full.prefix(9)) + "…"
        let resolved = context.resolve(
            Text(name)
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.white.opacity(theme.isNight ? 0.7 : 0.92)))
        let size = resolved.measure(in: CGSize(width: 300, height: 20))
        let bg = CGRect(x: (cx - size.width / 2 - 2).rounded(), y: topY,
                        width: size.width + 4, height: size.height + 1)
        context.fill(Path(roundedRect: bg, cornerRadius: 2),
                     with: .color(.black.opacity(theme.isNight ? 0.30 : 0.42)))
        context.draw(resolved, at: CGPoint(x: cx, y: bg.midY), anchor: .center)
    }

    /// 夜空の星（論理座標・固定シード）。
    private static let stars: [CGPoint] = [
        CGPoint(x: 12, y: 8), CGPoint(x: 30, y: 18), CGPoint(x: 44, y: 6),
        CGPoint(x: 58, y: 26), CGPoint(x: 70, y: 12), CGPoint(x: 84, y: 32),
        CGPoint(x: 95, y: 7), CGPoint(x: 108, y: 20), CGPoint(x: 121, y: 10),
        CGPoint(x: 133, y: 28), CGPoint(x: 146, y: 15), CGPoint(x: 152, y: 38),
        CGPoint(x: 22, y: 38), CGPoint(x: 66, y: 44),
    ]

    // MARK: - ヒットレクト（猫クリック→ターミナル前面化）

    private var hitRects: some View {
        // snapshot は y 昇順なので ZStack で後置＝手前の猫が hit-test に勝つ。
        ForEach(simulation.snapshot.cats) { cat in
            Color.clear
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let session = store.sessions.first(where: { $0.id == cat.id }) {
                        ITermFocus.focus(session: session)
                    }
                }
                .onHover { hovering in
                    hoveredID = hovering ? cat.id : nil
                    simulation.setHovered(hovering ? cat.id : nil)
                }
                .help(tooltip(for: cat))
                .position(x: cat.pos.x.rounded() * Self.scale,
                          y: cat.pos.y.rounded() * Self.scale)
        }
    }

    private func tooltip(for cat: CatSimulation.CatSnapshot) -> String {
        guard let session = store.sessions.first(where: { $0.id == cat.id }) else { return cat.label }
        var status = session.stateLabel
        if let since = session.stateSinceDate {
            status += " · " + Self.shortElapsed(from: since, to: Date())
        }
        return "\(session.label) — \(status)\n\(session.cwd)"
    }

    /// 経過秒を 30s / 4m / 2h / 1d のように短く整形（旧 ContentView から移植）。
    private static func shortElapsed(from date: Date, to now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60
        if h < 24 { return "\(h)h" }
        return "\(h / 24)d"
    }

    // MARK: - ヘッダー細帯（件数 + ドラッグつまみ）

    private var header: some View {
        let waiting = store.sessions.filter { $0.needsAttention }.count
        return ZStack {
            Capsule()
                .fill(.white.opacity(0.30))
                .frame(width: 26, height: 3)
            HStack(spacing: 4) {
                Text("\(store.sessions.count) 匹")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                if waiting > 0 {
                    Text("· \(waiting) 待ち")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Session.amber)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 14)
        .background(.black.opacity(0.25))
    }
}

/// 時刻バケットで変わる昼夜テーマ。空はフラット横帯3色。
struct SkyTheme {
    let sky: [Color]        // 上→下の3帯
    let floor: Color
    let floorShade: Color
    let isNight: Bool

    static func current(now: Date = Date()) -> SkyTheme {
        let hour: Int
        if let s = ProcessInfo.processInfo.environment["AGENT_MANAGER_HOUR"], let h = Int(s) {
            hour = h   // 検証用の時刻注入
        } else {
            hour = Calendar.current.component(.hour, from: now)
        }
        switch hour {
        case 5..<8:   return dawn
        case 8..<17:  return day
        case 17..<20: return dusk
        default:      return night
        }
    }

    private static let dawn = SkyTheme(
        sky: [Color(red: 0.45, green: 0.38, blue: 0.56),
              Color(red: 0.78, green: 0.55, blue: 0.50),
              Color(red: 0.93, green: 0.72, blue: 0.53)],
        floor: Color(red: 0.56, green: 0.43, blue: 0.32),
        floorShade: Color(red: 0.47, green: 0.35, blue: 0.26),
        isNight: false)

    private static let day = SkyTheme(
        sky: [Color(red: 0.45, green: 0.71, blue: 0.91),
              Color(red: 0.56, green: 0.78, blue: 0.94),
              Color(red: 0.68, green: 0.85, blue: 0.97)],
        floor: Color(red: 0.62, green: 0.47, blue: 0.34),
        floorShade: Color(red: 0.52, green: 0.38, blue: 0.27),
        isNight: false)

    private static let dusk = SkyTheme(
        sky: [Color(red: 0.33, green: 0.27, blue: 0.47),
              Color(red: 0.70, green: 0.38, blue: 0.40),
              Color(red: 0.91, green: 0.59, blue: 0.37)],
        floor: Color(red: 0.49, green: 0.37, blue: 0.30),
        floorShade: Color(red: 0.40, green: 0.29, blue: 0.24),
        isNight: false)

    private static let night = SkyTheme(
        sky: [Color(red: 0.08, green: 0.11, blue: 0.20),
              Color(red: 0.11, green: 0.15, blue: 0.27),
              Color(red: 0.15, green: 0.20, blue: 0.34)],
        floor: Color(red: 0.27, green: 0.22, blue: 0.20),
        floorShade: Color(red: 0.21, green: 0.17, blue: 0.16),
        isNight: true)
}
