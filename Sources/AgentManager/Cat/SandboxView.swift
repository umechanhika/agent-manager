import AppKit
import SwiftUI

/// 箱庭ビュー本体。論理シーンを 2x で描画する（倍率固定でピクセルパーフェクト維持）。
/// ウィンドウのリサイズに追従して論理シーン自体が広がる（部屋が広くなる）。
/// Canvas はヒットテスト無効にし、猫位置の透明ヒットレクト・左壁の掲示板を上に重ねる
/// （空き領域はパネル背景へ抜けるので isMovableByWindowBackground の窓ドラッグが生きる。
///   ScrollView を挟まないので ClickThroughHostingView の first-click も効く）。
struct SandboxView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var simulation: CatSimulation

    /// ホバー中の猫（ネームプレートのフル表示用。移動停止は simulation 側）。
    @State private var hoveredID: String?

    private static let scale: CGFloat = 2

    var body: some View {
        // 掲示板は store だけに依存させ、8Hz の snapshot 更新では再描画させない
        // （子ビューに分離。layout は Equatable 値で渡すので変化時のみ再評価される）。
        let layout = simulation.snapshot.layout
        return ZStack(alignment: .topLeading) {
            canvas
                .allowsHitTesting(false)
            BoardView(store: store, layout: layout, scale: Self.scale)
            hitRects
            if store.sessions.isEmpty {
                Text("セッションなし")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Canvas（壁 → 窓 → 床 → 小物 → 猫(y順) → ネームプレート → エモート）

    private var canvas: some View {
        Canvas { context, _ in
            let snap = simulation.snapshot
            let layout = snap.layout
            let theme = SkyTheme.current()

            drawRoom(context, layout: layout, theme: theme, twinkle: snap.twinkle)

            // 小物（猫より奥）。
            draw(context, image: SpriteRenderer.plantImage(),
                 topLeft: layout.plantTopLeft, w: 16, h: 16)
            draw(context, image: SpriteRenderer.towerImage(),
                 topLeft: layout.towerTopLeft, w: 24, h: 38)
            for (i, spot) in layout.sleepSpots.prefix(2).enumerated() {
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
                drawNameplate(context, cat: cat, cx: cx * Self.scale,
                              topY: (cy + 8) * Self.scale + 1, theme: theme)
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
    /// 配置は layout から導出され、リサイズで床・窓ガラスが伸びる。
    private func drawRoom(_ context: GraphicsContext, layout: CatSimulation.RoomLayout,
                          theme: SkyTheme, twinkle: Int) {
        let s = Self.scale
        func fillRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
            context.fill(Path(CGRect(x: x * s, y: y * s, width: w * s, height: h * s)),
                         with: .color(color))
        }
        func fill(_ r: CGRect, _ color: Color) {
            context.fill(Path(CGRect(x: r.minX * s, y: r.minY * s,
                                     width: r.width * s, height: r.height * s)),
                         with: .color(color))
        }

        let W = layout.width, wb = layout.wallBottom

        // 壁と巾木。
        fillRect(0, 0, W, wb, theme.wall)
        fillRect(0, wb - 3, W, 3, theme.wallShade)

        // 窓（枠2px・十字の桟）。空のフラット3横帯は窓ガラスの中にだけ見える。
        let frameColor = Color(red: 0.43, green: 0.32, blue: 0.23)
        let win = layout.windowRect
        fill(win, frameColor)
        let glass = win.insetBy(dx: 2, dy: 2)
        for i in 0..<3 {
            let bandH = glass.height / 3
            fill(CGRect(x: glass.minX, y: glass.minY + bandH * CGFloat(i),
                        width: glass.width, height: bandH), theme.sky[i])
        }
        if theme.isNight {
            for (i, star) in Self.starRatios.enumerated() where (twinkle + i * 7) % 24 < 16 {
                let bright = (twinkle + i * 5) % 24 < 8
                let x = (glass.minX + star.x * glass.width).rounded()
                let y = (glass.minY + star.y * glass.height).rounded()
                fillRect(x, y, 1, 1, .white.opacity(bright ? 0.95 : 0.55))
            }
        }
        fillRect(glass.midX - 1, win.minY, 2, win.height, frameColor)        // 縦桟
        fillRect(win.minX, glass.midY - 1, win.width, 2, frameColor)         // 横桟
        fillRect(win.minX - 2, win.maxY, win.width + 4, 2, frameColor)       // 窓台

        // 木の床: 板の継ぎ目（横）と互い違いの短い縦継ぎ目。
        fillRect(0, wb, W, layout.height - wb, theme.floor)
        fillRect(0, wb, W, 2, theme.floorShade)
        var plank = 0
        for y in stride(from: wb + 8 as CGFloat, to: layout.height, by: 8) {
            fillRect(0, y, W, 1, theme.floorSeam)
            let x1 = CGFloat((plank * 53 + 20) % Int(W))
            let x2 = CGFloat((plank * 53 + 100) % Int(W))
            fillRect(x1, y - 8 + 1, 1, 7, theme.floorSeam)
            fillRect(x2, y - 8 + 1, 1, 7, theme.floorSeam)
            plank += 1
        }

        // ラグ（前列中央帯と毛糸玉の下）。
        let r = layout.rugRect
        let rug = CGRect(x: r.minX * s, y: r.minY * s, width: r.width * s, height: r.height * s)
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

    /// 夜空の星（窓ガラス内の比率座標 0–1・固定シード）。窓が広がっても比率で追従する。
    private static let starRatios: [CGPoint] = [
        CGPoint(x: 0.08, y: 0.10), CGPoint(x: 0.20, y: 0.32), CGPoint(x: 0.34, y: 0.06),
        CGPoint(x: 0.45, y: 0.58), CGPoint(x: 0.60, y: 0.18), CGPoint(x: 0.74, y: 0.66),
        CGPoint(x: 0.84, y: 0.10), CGPoint(x: 0.93, y: 0.40), CGPoint(x: 0.14, y: 0.74),
        CGPoint(x: 0.97, y: 0.84), CGPoint(x: 0.28, y: 0.52), CGPoint(x: 0.66, y: 0.86),
        CGPoint(x: 0.40, y: 0.26), CGPoint(x: 0.88, y: 0.62),
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
                .help(tooltipForCat(cat))
                .position(x: cat.pos.x.rounded() * Self.scale,
                          y: cat.pos.y.rounded() * Self.scale)
        }
    }

    private func tooltipForCat(_ cat: CatSimulation.CatSnapshot) -> String {
        guard let session = store.sessions.first(where: { $0.id == cat.id }) else { return cat.label }
        return SessionTooltip.text(for: session)
    }
}

/// セッションのツールチップ文（猫のヒットレクトと掲示板の行で共有）。
enum SessionTooltip {
    static func text(for session: Session) -> String {
        var status = session.stateLabel
        if let since = session.stateSinceDate {
            status += " · " + shortElapsed(from: since, to: Date())
        }
        return "\(session.label) — \(status)\n\(session.cwd)"
    }

    /// 経過秒を 30s / 4m / 2h / 1d のように短く整形（旧 ContentView から移植）。
    static func shortElapsed(from date: Date, to now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60
        if h < 24 { return "\(h)h" }
        return "\(h / 24)d"
    }
}

/// 左壁の掲示板（セッション一覧）。各行は「その子の色の猫アイコン ＋ 名前 ＋ ›」の
/// ネームプレートで、クリックで対応するターミナルへ飛べる（ホバーで行が光り、カーソルが
/// ポインタに変わるので "タップで遷移できる" と一目で分かる）。
/// store と layout だけに依存させ、8Hz の snapshot 更新では再評価されない。
struct BoardView: View {
    @ObservedObject var store: SessionStore
    let layout: CatSimulation.RoomLayout
    let scale: CGFloat

    /// ホバー中の行（ハイライト用）。
    @State private var hoveredID: String?

    /// 1行の高さと猫アイコンの表示サイズ（pt）。読みやすさ優先で前版(7pt)から拡大。
    private static let rowH: CGFloat = 14
    private static let iconPt: CGFloat = 14

    var body: some View {
        let theme = SkyTheme.current()
        let rect = layout.boardRect
        let s = scale
        // 表示順（done→processing→waiting→idle）→ ラベル順で並べる。
        let order = Session.StatusCategory.displayOrder
        let sessions = store.sessions.sorted { a, b in
            let ia = order.firstIndex(of: a.category) ?? order.count
            let ib = order.firstIndex(of: b.category) ?? order.count
            return ia != ib ? ia < ib : a.label < b.label
        }
        let pad: CGFloat = 3
        let avail = rect.height * s - pad * 2
        let capacity = max(0, Int(avail / Self.rowH))
        // あふれる場合は最終行を「ほか +N」に使うので 1 行ぶん空ける。
        let needsOverflow = sessions.count > capacity
        let rowCap = needsOverflow ? max(0, capacity - 1) : capacity
        let shown = Array(sessions.prefix(rowCap))
        let overflow = sessions.count - shown.count

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(shown) { session in
                row(session, theme: theme)
            }
            if overflow > 0 {
                Text("ほか +\(overflow)")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(theme.isNight ? 0.5 : 0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Self.rowH - 3)
                    .padding(.leading, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, pad)
        .frame(width: rect.width * s, height: rect.height * s, alignment: .topLeading)
        .background(boardBackground(theme))
        .position(x: rect.midX * s, y: rect.midY * s)
    }

    /// 木目調の掲示板の背景（夜は減光）。
    private func boardBackground(_ theme: SkyTheme) -> some View {
        let wood = Color(red: 0.36, green: 0.27, blue: 0.20)
        return RoundedRectangle(cornerRadius: 4)
            .fill(wood.opacity(theme.isNight ? 0.55 : 0.85))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color(red: 0.22, green: 0.16, blue: 0.11).opacity(0.8), lineWidth: 1)
            )
    }

    private func row(_ session: Session, theme: SkyTheme) -> some View {
        let hovered = hoveredID == session.id
        // session.id だけで決まる決定論マッピングなので、simulation に触れずに
        // その子と同じ見た目の猫を描ける（＝8Hz 非依存を維持できる）。
        let iconPx = CGFloat(SpriteRenderer.bakeScale * 16)
        let cat = SpriteRenderer.catImage(
            anim: .sit, frame: 0,
            paletteIndex: SpriteRenderer.paletteIndex(for: session.id),
            mirrored: false, nightEyes: false)
        return HStack(spacing: 3) {
            Image(decorative: cat, scale: iconPx / Self.iconPt)
                .interpolation(.none)
                .antialiased(false)
            Text(session.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(theme.isNight ? 0.78 : 0.96))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 1)
            // › でタップ＝遷移を示唆。ホバー時は明るくする。
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(hovered ? 0.92 : (theme.isNight ? 0.40 : 0.55)))
        }
        .padding(.horizontal, 2)
        .frame(height: Self.rowH)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(.white.opacity(hovered ? 0.14 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture { ITermFocus.focus(session: session) }
        .onHover { inside in
            if inside {
                hoveredID = session.id
                NSCursor.pointingHand.push()
            } else {
                if hoveredID == session.id { hoveredID = nil }
                NSCursor.pop()
            }
        }
        .help(SessionTooltip.text(for: session))
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
