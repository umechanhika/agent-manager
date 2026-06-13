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

            drawRoom(context, theme: theme, twinkle: snap.twinkle)

            // 小物（猫より奥）。
            draw(context, image: SpriteRenderer.plantImage(),
                 topLeft: CatSimulation.Scene.plantTopLeft, w: 16, h: 16)
            draw(context, image: SpriteRenderer.towerImage(),
                 topLeft: CatSimulation.Scene.towerTopLeft, w: 24, h: 38)
            for (i, spot) in CatSimulation.Scene.sleepSpots.prefix(2).enumerated() {
                draw(context, image: SpriteRenderer.cushionImage(variant: i),
                     topLeft: CGPoint(x: spot.walkTo.x - 8, y: spot.walkTo.y - 3), w: 16, h: 8)
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

    /// 部屋の内装: 壁 → 大きな窓（空と星は窓の中）→ 巾木 → 木の床 → ラグ。
    private func drawRoom(_ context: GraphicsContext, theme: SkyTheme, twinkle: Int) {
        let s = Self.scale
        func fillRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
            context.fill(Path(CGRect(x: x * s, y: y * s, width: w * s, height: h * s)),
                         with: .color(color))
        }

        // 壁と巾木。
        fillRect(0, 0, 160, 55, theme.wall)
        fillRect(0, 52, 160, 3, theme.wallShade)

        // 窓（枠2px・十字の桟）。空のフラット3横帯は窓ガラスの中にだけ見える。
        let frameColor = Color(red: 0.43, green: 0.32, blue: 0.23)
        fillRect(46, 4, 76, 42, frameColor)
        let bands: [(CGFloat, CGFloat)] = [(6, 19), (19, 32), (32, 44)]
        for (i, band) in bands.enumerated() {
            fillRect(48, band.0, 72, band.1 - band.0, theme.sky[i])
        }
        if theme.isNight {
            for (i, star) in Self.stars.enumerated() where (twinkle + i * 7) % 24 < 16 {
                let bright = (twinkle + i * 5) % 24 < 8
                fillRect(star.x, star.y, 1, 1, .white.opacity(bright ? 0.95 : 0.55))
            }
        }
        fillRect(82, 6, 2, 38, frameColor)    // 縦桟
        fillRect(48, 23, 72, 2, frameColor)   // 横桟
        fillRect(44, 46, 80, 2, frameColor)   // 窓台（下枠を少し張り出す）

        // 木の床: 板の継ぎ目（横）と互い違いの短い縦継ぎ目。
        fillRect(0, 55, 160, 55, theme.floor)
        fillRect(0, 55, 160, 2, theme.floorShade)
        var plank = 0
        for y in stride(from: 63 as CGFloat, to: 110, by: 8) {
            fillRect(0, y, 160, 1, theme.floorSeam)
            let x1 = CGFloat((plank * 53 + 20) % 160)
            let x2 = CGFloat((plank * 53 + 100) % 160)
            fillRect(x1, y - 8 + 1, 1, 7, theme.floorSeam)
            fillRect(x2, y - 8 + 1, 1, 7, theme.floorSeam)
            plank += 1
        }

        // ラグ（前列中央帯と毛糸玉の下）。
        let rug = CGRect(x: 50 * s, y: 72 * s, width: 60 * s, height: 26 * s)
        context.fill(Path(roundedRect: rug, cornerRadius: 4 * s),
                     with: .color(Color(red: 0.45, green: 0.34, blue: 0.35)))
        context.fill(Path(roundedRect: rug.insetBy(dx: s, dy: s), cornerRadius: 3 * s),
                     with: .color(Color(red: 0.56, green: 0.43, blue: 0.44)))
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
        // 左端に状態ドット（メニューバーと同じ配色）。エモートが消えた後も状態が一目で分かる。
        let dot: CGFloat = 5
        let bg = CGRect(x: (cx - (size.width + dot + 2) / 2 - 2).rounded(), y: topY,
                        width: size.width + dot + 2 + 4, height: size.height + 1)
        context.fill(Path(roundedRect: bg, cornerRadius: 2),
                     with: .color(.black.opacity(theme.isNight ? 0.30 : 0.42)))
        context.fill(
            Path(ellipseIn: CGRect(x: bg.minX + 2, y: (bg.midY - dot / 2).rounded(),
                                   width: dot, height: dot)),
            with: .color(Session.color(for: cat.category)))
        context.draw(resolved,
                     at: CGPoint(x: bg.minX + 2 + dot + 2 + size.width / 2, y: bg.midY),
                     anchor: .center)
    }

    /// 夜空の星（論理座標・固定シード）。窓ガラスの内側（x48–120, y6–44）に収める。
    private static let stars: [CGPoint] = [
        CGPoint(x: 52, y: 9), CGPoint(x: 60, y: 16), CGPoint(x: 69, y: 8),
        CGPoint(x: 76, y: 27), CGPoint(x: 88, y: 12), CGPoint(x: 97, y: 30),
        CGPoint(x: 104, y: 9), CGPoint(x: 111, y: 20), CGPoint(x: 56, y: 34),
        CGPoint(x: 116, y: 38), CGPoint(x: 64, y: 28), CGPoint(x: 92, y: 39),
        CGPoint(x: 71, y: 18), CGPoint(x: 108, y: 33),
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

/// 時刻バケットで変わる昼夜テーマ。空（窓の中）はフラット横帯3色、壁と床も連動して明るさが変わる。
struct SkyTheme {
    let sky: [Color]        // 窓の中・上→下の3帯
    let wall: Color
    let wallShade: Color    // 巾木
    let floor: Color
    let floorShade: Color
    let floorSeam: Color    // 床板の継ぎ目
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
        wall: Color(red: 0.84, green: 0.75, blue: 0.70),
        wallShade: Color(red: 0.72, green: 0.62, blue: 0.57),
        floor: Color(red: 0.66, green: 0.50, blue: 0.35),
        floorShade: Color(red: 0.55, green: 0.41, blue: 0.28),
        floorSeam: Color(red: 0.57, green: 0.42, blue: 0.29),
        isNight: false)

    private static let day = SkyTheme(
        sky: [Color(red: 0.45, green: 0.71, blue: 0.91),
              Color(red: 0.56, green: 0.78, blue: 0.94),
              Color(red: 0.68, green: 0.85, blue: 0.97)],
        wall: Color(red: 0.90, green: 0.85, blue: 0.76),
        wallShade: Color(red: 0.79, green: 0.73, blue: 0.63),
        floor: Color(red: 0.70, green: 0.53, blue: 0.36),
        floorShade: Color(red: 0.58, green: 0.43, blue: 0.28),
        floorSeam: Color(red: 0.60, green: 0.44, blue: 0.29),
        isNight: false)

    private static let dusk = SkyTheme(
        sky: [Color(red: 0.33, green: 0.27, blue: 0.47),
              Color(red: 0.70, green: 0.38, blue: 0.40),
              Color(red: 0.91, green: 0.59, blue: 0.37)],
        wall: Color(red: 0.72, green: 0.61, blue: 0.58),
        wallShade: Color(red: 0.61, green: 0.50, blue: 0.47),
        floor: Color(red: 0.58, green: 0.44, blue: 0.31),
        floorShade: Color(red: 0.47, green: 0.35, blue: 0.25),
        floorSeam: Color(red: 0.49, green: 0.36, blue: 0.25),
        isNight: false)

    private static let night = SkyTheme(
        sky: [Color(red: 0.08, green: 0.11, blue: 0.20),
              Color(red: 0.11, green: 0.15, blue: 0.27),
              Color(red: 0.15, green: 0.20, blue: 0.34)],
        wall: Color(red: 0.24, green: 0.23, blue: 0.30),
        wallShade: Color(red: 0.18, green: 0.17, blue: 0.23),
        floor: Color(red: 0.30, green: 0.24, blue: 0.21),
        floorShade: Color(red: 0.23, green: 0.18, blue: 0.16),
        floorSeam: Color(red: 0.24, green: 0.18, blue: 0.16),
        isNight: true)
}
