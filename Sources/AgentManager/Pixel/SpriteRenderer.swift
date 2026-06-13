import CoreGraphics
import Foundation

/// 1ピクセルの RGB（0...1）。
struct PixelColor {
    let r: CGFloat, g: CGFloat, b: CGFloat
}

/// 猫1種ぶんの配色。SpriteData の文字（B/S/P/W/E/N/O）に対応する。
struct CatPalette {
    let body: PixelColor
    let shade: PixelColor
    let patch: PixelColor
    let white: PixelColor
    let eye: PixelColor
    let eyeNight: PixelColor   // 夜に光る目
    let nose: PixelColor
    let outline: PixelColor
}

enum SpriteRenderer {
    /// 1論理ピクセル → 4 デバイスピクセル（論理シーン2x描画 × Retina 2x）でベイクする。
    /// 32x32pt の描画レクトに 64x64px の画像が 1:1 で載るため、実行時の補間が発生しない。
    static let bakeScale = 4

    // MARK: - 毛色パレット（8種）

    private static let white = PixelColor(r: 0.97, g: 0.96, b: 0.93)
    private static let pink = PixelColor(r: 0.91, g: 0.56, b: 0.60)
    private static let outline = PixelColor(r: 0.13, g: 0.11, b: 0.13)
    private static let glow = PixelColor(r: 0.96, g: 0.94, b: 0.42)

    /// session_id ハッシュ % 8 で割当てる毛色。順序を変えると既存セッションの猫が化けるので不変に保つ。
    static let palettes: [CatPalette] = [
        // 0: キジトラ
        CatPalette(body: .init(r: 0.72, g: 0.55, b: 0.36), shade: .init(r: 0.50, g: 0.37, b: 0.22),
                   patch: .init(r: 0.72, g: 0.55, b: 0.36), white: white,
                   eye: .init(r: 0.35, g: 0.65, b: 0.35), eyeNight: glow, nose: pink, outline: outline),
        // 1: 黒
        CatPalette(body: .init(r: 0.24, g: 0.23, b: 0.27), shade: .init(r: 0.16, g: 0.15, b: 0.19),
                   patch: .init(r: 0.24, g: 0.23, b: 0.27), white: .init(r: 0.32, g: 0.31, b: 0.35),
                   eye: .init(r: 0.92, g: 0.78, b: 0.25), eyeNight: glow, nose: pink, outline: outline),
        // 2: 白
        CatPalette(body: .init(r: 0.95, g: 0.95, b: 0.93), shade: .init(r: 0.82, g: 0.82, b: 0.80),
                   patch: .init(r: 0.95, g: 0.95, b: 0.93), white: white,
                   eye: .init(r: 0.36, g: 0.58, b: 0.90), eyeNight: glow, nose: pink, outline: outline),
        // 3: 三毛（白地に黒S・茶P のぶち）
        CatPalette(body: .init(r: 0.95, g: 0.94, b: 0.90), shade: .init(r: 0.26, g: 0.24, b: 0.24),
                   patch: .init(r: 0.88, g: 0.56, b: 0.22), white: white,
                   eye: .init(r: 0.85, g: 0.65, b: 0.25), eyeNight: glow, nose: pink, outline: outline),
        // 4: タキシード
        CatPalette(body: .init(r: 0.20, g: 0.20, b: 0.25), shade: .init(r: 0.13, g: 0.13, b: 0.17),
                   patch: .init(r: 0.20, g: 0.20, b: 0.25), white: white,
                   eye: .init(r: 0.38, g: 0.72, b: 0.42), eyeNight: glow, nose: pink, outline: outline),
        // 5: シャム（クリーム地に焦げ茶ポイント）
        CatPalette(body: .init(r: 0.93, g: 0.87, b: 0.76), shade: .init(r: 0.78, g: 0.69, b: 0.56),
                   patch: .init(r: 0.42, g: 0.32, b: 0.26), white: white,
                   eye: .init(r: 0.40, g: 0.62, b: 0.94), eyeNight: glow, nose: .init(r: 0.45, g: 0.33, b: 0.30), outline: outline),
        // 6: 茶トラ
        CatPalette(body: .init(r: 0.90, g: 0.60, b: 0.27), shade: .init(r: 0.74, g: 0.45, b: 0.15),
                   patch: .init(r: 0.90, g: 0.60, b: 0.27), white: white,
                   eye: .init(r: 0.80, g: 0.60, b: 0.22), eyeNight: glow, nose: pink, outline: outline),
        // 7: グレー
        CatPalette(body: .init(r: 0.62, g: 0.64, b: 0.68), shade: .init(r: 0.48, g: 0.50, b: 0.54),
                   patch: .init(r: 0.62, g: 0.64, b: 0.68), white: white,
                   eye: .init(r: 0.90, g: 0.76, b: 0.30), eyeNight: glow, nose: pink, outline: outline),
    ]

    // MARK: - ハッシュ（毛色・個性の決定論的割当）

    /// FNV-1a 64bit。同じ session_id は常に同じ猫になる。
    static func fnv1a(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01b3
        }
        return h
    }

    static func paletteIndex(for sessionID: String) -> Int {
        Int(fnv1a(sessionID) % UInt64(palettes.count))
    }

    /// 歩速倍率 0.8...1.2（ハッシュの余りビットから決定論的に）。
    static func speedFactor(for sessionID: String) -> CGFloat {
        let bits = (fnv1a(sessionID) >> 8) % 100
        return 0.8 + CGFloat(bits) / 100.0 * 0.4
    }

    /// 行動タイマーのジッター用シード。
    static func rngSeed(for sessionID: String) -> UInt64 {
        fnv1a(sessionID) | 1   // LCG の種が 0 にならないように
    }

    // MARK: - ベイク

    private struct CacheKey: Hashable {
        let anim: CatAnim
        let frame: Int
        let palette: Int
        let mirrored: Bool
        let nightEyes: Bool
    }

    private static var catCache: [CacheKey: CGImage] = [:]
    private static var propCache: [String: CGImage] = [:]

    /// 猫フレームを取得（遅延ベイク+キャッシュ）。最悪 ~900 枚の極小画像で済む。
    static func catImage(anim: CatAnim, frame: Int, paletteIndex: Int,
                         mirrored: Bool, nightEyes: Bool) -> CGImage {
        let frames = SpriteData.catFrames[anim]!
        let idx = frame % frames.count
        let key = CacheKey(anim: anim, frame: idx, palette: paletteIndex,
                           mirrored: mirrored, nightEyes: nightEyes)
        if let img = catCache[key] { return img }
        let p = palettes[paletteIndex]
        let colors: [Character: PixelColor] = [
            "O": p.outline, "B": p.body, "S": p.shade, "P": p.patch,
            "W": p.white, "E": nightEyes ? p.eyeNight : p.eye, "N": p.nose,
        ]
        let img = bake(frame: frames[idx], colors: colors, mirrored: mirrored)
        catCache[key] = img
        return img
    }

    /// 毛糸玉。
    static func yarnImage(frame: Int) -> CGImage {
        propImage(name: "yarn\(frame % SpriteData.yarn.count)") {
            bake(frame: SpriteData.yarn[frame % SpriteData.yarn.count], colors: [
                "O": outline,
                "B": .init(r: 0.80, g: 0.32, b: 0.34),
                "S": .init(r: 0.60, g: 0.20, b: 0.23),
            ], mirrored: false)
        }
    }

    /// クッション。variant 0=青 / 1=赤（どの寝床か見分けやすいよう色違いにする）。
    static func cushionImage(variant: Int) -> CGImage {
        let palettes: [[Character: PixelColor]] = [
            [
                "O": .init(r: 0.20, g: 0.21, b: 0.30),
                "B": .init(r: 0.46, g: 0.50, b: 0.70),
                "S": .init(r: 0.36, g: 0.40, b: 0.58),
                "W": .init(r: 0.62, g: 0.66, b: 0.82),
            ],
            [
                "O": .init(r: 0.30, g: 0.17, b: 0.16),
                "B": .init(r: 0.76, g: 0.42, b: 0.36),
                "S": .init(r: 0.62, g: 0.32, b: 0.28),
                "W": .init(r: 0.88, g: 0.60, b: 0.52),
            ],
        ]
        let v = variant % palettes.count
        return propImage(name: "cushion\(v)") {
            bake(frame: SpriteData.cushion, colors: palettes[v], mirrored: false)
        }
    }

    /// キャットタワー。
    static func towerImage() -> CGImage {
        propImage(name: "tower") {
            bake(frame: SpriteData.catTower, colors: [
                "O": .init(r: 0.22, g: 0.17, b: 0.13),
                "B": .init(r: 0.82, g: 0.74, b: 0.60),
                "S": .init(r: 0.68, g: 0.60, b: 0.47),
                "P": .init(r: 0.62, g: 0.48, b: 0.32),
                "N": .init(r: 0.51, g: 0.38, b: 0.25),
            ], mirrored: false)
        }
    }

    /// 観葉植物。
    static func plantImage() -> CGImage {
        propImage(name: "plant") {
            bake(frame: SpriteData.plant, colors: [
                "O": .init(r: 0.10, g: 0.16, b: 0.11),
                "B": .init(r: 0.32, g: 0.60, b: 0.36),
                "S": .init(r: 0.21, g: 0.45, b: 0.27),
                "P": .init(r: 0.70, g: 0.45, b: 0.30),
                "N": .init(r: 0.55, g: 0.33, b: 0.22),
            ], mirrored: false)
        }
    }

    /// エモート。
    static func emoteImage(kind: EmoteKind, frame: Int) -> CGImage {
        let frames = SpriteData.emotes[kind]!
        let idx = frame % frames.count
        let accent: PixelColor
        switch kind {
        case .alert:   accent = .init(r: 0.90, g: 0.25, b: 0.22)
        case .sparkle: accent = .init(r: 0.98, g: 0.85, b: 0.30)
        case .zzz:     accent = .init(r: 0.72, g: 0.80, b: 0.96)
        }
        return propImage(name: "emote.\(kind.rawValue)\(idx)") {
            bake(frame: frames[idx], colors: [
                "O": .init(r: 0.18, g: 0.17, b: 0.20),
                "W": .init(r: 0.98, g: 0.97, b: 0.95),
                "N": accent,
            ], mirrored: false)
        }
    }

    private static func propImage(name: String, build: () -> CGImage) -> CGImage {
        if let img = propCache[name] { return img }
        let img = build()
        propCache[name] = img
        return img
    }

    /// 文字マップ → bakeScale 倍にプリスケールした CGImage。
    /// CGContext に 1論理px = bakeScale^2 の矩形を直接塗るので補間・AA は一切介在しない。
    private static func bake(frame: Frame, colors: [Character: PixelColor],
                             mirrored: Bool) -> CGImage {
        let rows = frame.count
        let cols = frame[0].count
        let s = bakeScale
        let ctx = CGContext(
            data: nil, width: cols * s, height: rows * s,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setShouldAntialias(false)
        for (r, row) in frame.enumerated() {
            for (c, ch) in row.enumerated() {
                guard let color = colors[ch] else { continue }   // '.' は透明のまま
                let x = mirrored ? (cols - 1 - c) : c
                ctx.setFillColor(red: color.r, green: color.g, blue: color.b, alpha: 1)
                // CGContext は左下原点なので行を反転して塗る。
                ctx.fill(CGRect(x: x * s, y: (rows - 1 - r) * s, width: s, height: s))
            }
        }
        return ctx.makeImage()!
    }
}
