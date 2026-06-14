import SwiftUI

/// アプリのトップビュー。「窓のある一室」を1つの世界として描き、その中にセッション一覧を取り込む。
/// 上＝壁（窓帯＋壁に掛けた木プレートの一覧）、下＝床（猫がアンビエントに過ごす固定ストリップ）。
/// 全要素が `SkyTheme`（昼夜パレット）を共有し、別レイヤー感を無くして地続きの部屋に見せる。
///
/// 8Hz で動くのは CatFloorView の Canvas だけ。一覧(SessionPlatesView)は store のみ・窓帯は
/// SkyTheme のみに依存させ 8Hz の再描画に巻き込まない。RootView は plain `let` 保持で自身を
/// 再評価させない（＝CPU を抑える要）。
struct RootView: View {
    let store: SessionStore
    let simulation: CatSimulation

    var body: some View {
        VStack(spacing: 0) {
            WallView(store: store)              // 窓帯＋木プレート一覧（高さは件数で伸縮）
            CatFloorView(simulation: simulation) // 床＋猫（固定高）
        }
        .frame(width: 240)
    }
}

/// ガラスのチューニング定数（磨りガラスの不透明度。視認性 vs 透け感の調整点）。
enum GlassStyle {
    static let opacity: Double = 0.20
}

/// 壁一面が窓（外の景色）。その前にガラス製の一覧パネルが浮く。
/// `.background` で塗るので高さは中身（プレート）に追従し、無限に広がらない。
struct WallView: View {
    let store: SessionStore

    var body: some View {
        SessionPlatesView(store: store)
            .background(WindowWallBackground())   // 壁一面の窓（外の景色）
    }
}

/// 一覧の背景＝壁一面の窓（外の景色）。枠なしの全面ガラスで、空〜地平線の丘をピクセルアートで描く。
/// 行の高さに合わせたフラットなバンドで構成し、各セッション行が均一色の帯に乗る（＝境界が自然な区切りに）。
/// 太陽/月・雲・星は文字の無い右側へ寄せて可読性を確保。一覧の高さに追従し、SkyTheme のみ依存＝静的（8Hz 非依存）。
struct WindowWallBackground: View {
    /// 一覧の行ジオメトリ（SessionPlatesView と一致させて背景バンドを行に合わせる）。
    static let rowH: CGFloat = 30
    static let topPad: CGFloat = 6
    static let botPad: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            drawBackground(context, size: size, theme: SkyTheme.current())
        }
    }

    /// 行の高さに合わせたフラットなバンドで背景を構成し、境界が「区切り」に見えるようにする。
    /// 各セッション行が均一色の帯に乗るので可読性が上がる。太陽/月・雲・丘は文字の無い右側／境界へ寄せる。
    private func drawBackground(_ context: GraphicsContext, size: CGSize, theme: SkyTheme) {
        let W = size.width, H = size.height
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: Color) {
            context.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(c))
        }
        func disc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ c: Color) {
            let ri = Int(r.rounded()); guard ri > 0 else { return }
            for dy in -ri...ri {
                let hw = (Double(ri * ri - dy * dy)).squareRoot().rounded()
                rect(cx - CGFloat(hw), cy + CGFloat(dy), CGFloat(hw) * 2 + 1, 1, c)
            }
        }
        func cloud(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat) {
            let c = Color.white.opacity(0.9)
            rect(cx - w / 2, cy, w, 3, c); rect(cx - w * 0.30, cy - 2, w * 0.55, 3, c); rect(cx - w * 0.08, cy - 3.5, w * 0.30, 3, c)
        }

        let rowH = Self.rowH, topPad = Self.topPad, botPad = Self.botPad
        let usable = H - topPad - botPad
        let n = max(1, Int((usable / rowH).rounded()))
        func bandTop(_ i: Int) -> CGFloat { i == 0 ? 0 : topPad + CGFloat(i) * rowH }
        func bandBot(_ i: Int) -> CGFloat { i == n - 1 ? H : topPad + CGFloat(i + 1) * rowH }

        // 空グラデの端点（昼/夜）。下（地平線）ほど淡い。各行はこのグラデを1点サンプルしたフラット色。
        let top = theme.isNight ? (0.09, 0.12, 0.22) : (0.42, 0.68, 0.90)
        let bot = theme.isNight ? (0.16, 0.22, 0.34) : (0.74, 0.86, 0.96)
        let skyTop = Color(red: top.0, green: top.1, blue: top.2)
        let hillRows = n >= 3 ? 1 : 0          // 3件以上なら最下行を丘（緑の均一帯）に
        let skyRows = n - hillRows
        let hill = theme.isNight ? Color(red: 0.17, green: 0.23, blue: 0.21) : Color(red: 0.50, green: 0.66, blue: 0.40)

        for i in 0..<n {
            let y0 = bandTop(i), y1 = bandBot(i)
            let color: Color
            if i >= skyRows {
                color = hill
            } else {
                let t = skyRows <= 1 ? 0 : CGFloat(i) / CGFloat(skyRows - 1)
                color = Color(red: top.0 + (bot.0 - top.0) * t,
                              green: top.1 + (bot.1 - top.1) * t,
                              blue: top.2 + (bot.2 - top.2) * t)
            }
            rect(0, y0, W, y1 - y0 + 0.5, color)
        }
        // 行境界のかすかな仕切り線（背景が区切りに見えるよう締める）。
        if n > 1 {
            for i in 1..<n {
                rect(0, topPad + CGFloat(i) * rowH - 0.5, W, 1, .black.opacity(theme.isNight ? 0.10 : 0.06))
            }
        }
        // 空/丘の境界に小さな稜線（右寄り・左の文字に被らない）。
        if hillRows > 0 {
            let by = topPad + CGFloat(skyRows) * rowH
            let crest = theme.isNight ? Color(red: 0.20, green: 0.27, blue: 0.24) : Color(red: 0.54, green: 0.70, blue: 0.42)
            func crestBump(_ cx: CGFloat, _ w: CGFloat, _ h: CGFloat) {
                let rows: [CGFloat] = [1.0, 0.6, 0.3]; let rh = h / CGFloat(rows.count)
                for (k, fr) in rows.enumerated() { rect(cx - w * fr / 2, by - rh * CGFloat(k + 1), w * fr, rh + 0.6, crest) }
            }
            crestBump(W * 0.55, W * 0.5, 8); crestBump(W * 0.82, W * 0.4, 6)
        }
        // 星（夜・右寄りのみ。左の文字を避ける）。
        if theme.isNight {
            for st in Self.stars where st.x > 0.5 {
                rect((st.x * W).rounded(), (topPad + st.y * usable * 0.5).rounded(), 1, 1, .white.opacity(st.z > 0.5 ? 0.9 : 0.55))
            }
        }
        // 太陽/月＋雲は右上（文字は左寄せなので重ならない）。
        let cx = W - 34, cy = max(18, topPad + rowH * 0.5)
        if theme.isNight {
            disc(cx, cy, 11, Color(red: 0.94, green: 0.94, blue: 0.87))
            disc(cx + 7, cy - 3, 10, skyTop)                 // 三日月に欠けさせる
        } else {
            disc(cx, cy, 12, Color(red: 1.0, green: 0.90, blue: 0.50))
            if n >= 2 { cloud(W * 0.70, topPad + rowH * 1.5, W * 0.20) }
        }
    }

    private static let stars: [(x: CGFloat, y: CGFloat, z: CGFloat)] = [
        (0.06, 0.06, 0.9), (0.16, 0.16, 0.4), (0.27, 0.04, 0.8), (0.37, 0.20, 0.5),
        (0.46, 0.10, 0.9), (0.57, 0.18, 0.4), (0.66, 0.06, 0.7), (0.76, 0.22, 0.9),
        (0.84, 0.12, 0.5), (0.92, 0.05, 0.8), (0.12, 0.30, 0.6), (0.50, 0.30, 0.5),
        (0.70, 0.34, 0.7), (0.30, 0.40, 0.4), (0.88, 0.40, 0.8), (0.20, 0.52, 0.6),
        (0.60, 0.54, 0.5), (0.40, 0.62, 0.7),
    ]
}

/// 付随表示の「床と猫」。横長の固定ストリップで、セッションの賑わいをアンビエントに映す。
/// 猫はセッション数ぶん増減するが名札なし・クリック遷移なし（遷移は一覧のプレートから）。
/// 各猫の気分はそのセッションの状態＋経過時間で決まり、働くセッションが多いほど床が賑わう。
struct CatFloorView: View {
    @ObservedObject var simulation: CatSimulation

    private static let scale: CGFloat = 2
    private static let stripWidth: CGFloat = 240
    private static let stripHeight: CGFloat = 88   // 論理 44 × 2x

    var body: some View {
        Canvas { context, _ in
            let snap = simulation.snapshot
            let layout = snap.layout
            let theme = SkyTheme.current()

            drawFloor(context, layout: layout, theme: theme)

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

            // 猫（snapshot は y 昇順 = 奥→手前）。名札は付けない（匿名のアンビエント表示）。
            for cat in snap.cats {
                let cx = cat.pos.x.rounded()
                let cy = cat.pos.y.rounded()
                let awake = cat.anim != .sleep
                let image = SpriteRenderer.catImage(
                    anim: cat.anim, frame: cat.frame, paletteIndex: cat.paletteIndex,
                    mirrored: cat.facingLeft, nightEyes: theme.isNight && awake)
                draw(context, image: image, topLeft: CGPoint(x: cx - 8, y: cy - 8), w: 16, h: 16)
                if let emote = cat.emote, cat.emoteVisible {
                    let img = SpriteRenderer.emoteImage(kind: emote, frame: cat.emoteFrame)
                    draw(context, image: img, topLeft: CGPoint(x: cx - 2, y: cy - 19), w: 10, h: 10)
                }
            }
        }
        .frame(width: Self.stripWidth, height: Self.stripHeight)
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

    /// 床（全面）＋上端の巾木シェード＋板の継ぎ目＋ラグ。窓・壁は WallView 側にあるのでここでは描かない。
    private func drawFloor(_ context: GraphicsContext, layout: CatSimulation.RoomLayout, theme: SkyTheme) {
        let s = Self.scale
        func fillRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
            context.fill(Path(CGRect(x: x * s, y: y * s, width: w * s, height: h * s)), with: .color(color))
        }
        let W = layout.width, H = layout.height

        // 木の床（全面）。上端に巾木＝壁との境を示す濃いシェードを2段。
        fillRect(0, 0, W, H, theme.floor)
        fillRect(0, 0, W, 2, theme.wallShade)
        fillRect(0, 2, W, 2, theme.floorShade)
        var plank = 0
        for y in stride(from: 8 as CGFloat, to: H, by: 8) {
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
}

/// セッションのツールチップ文（一覧と共有しうる短文整形ユーティリティ）。
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

/// 時刻バケットで変わる昼夜テーマ。窓の空（外の景色）・壁・床の色を一括で時刻連動させ、
/// 全要素を地続きの一室として調和させる単一ソース。
struct SkyTheme {
    let sky: [Color]        // 窓の中・上→下の3帯
    let wall: Color
    let wallShade: Color    // 巾木
    let floor: Color
    let floorShade: Color
    let floorSeam: Color     // 床板の継ぎ目
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
