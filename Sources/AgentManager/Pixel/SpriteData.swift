import Foundation
import CoreGraphics

/// ドット絵を文字列で表す。1文字=1ピクセル、1要素=1行。
/// 文字→役割:
///   `.` 透明  `O` 輪郭  `B` 体色  `S` 縞/陰  `P` 第2毛色(三毛のぶち/シャムのポイント)
///   `W` 白(腹/口元/靴下)  `E` 目  `N` 鼻・耳内・ピンク
/// 小物は B/S を主色/陰、P/N を副色に流用する（プロップごとに色マップを別定義）。
typealias Frame = [String]

/// 猫のアニメーション種別。フレーム数は `SpriteData.catFrames` の配列長が正。
enum CatAnim: String, Hashable, CaseIterable {
    case sit, meow, walk, groom, sleep, playYarn
}

/// エモート吹き出しの種別。
enum EmoteKind: String, Hashable, CaseIterable {
    case alert, sparkle, zzz
}

enum SpriteData {
    static let catSize = 16   // 猫フレームは 16x16 固定

    // MARK: - 猫

    /// 正面寄りの座りポーズ。フレーム2はしっぽの位置だけ変える。
    private static let sit: [Frame] = [
        [
            "................",
            "..OO.....OO.....",
            ".ONBO...OBNO....",
            ".OBBBOOOBPBO....",
            ".OBBBBBBPPBO....",
            ".OBEBBBBBEBO....",
            ".OBBBBNBBBBO....",
            "..OBWWWWWBO.....",
            "..OBSBSBSBO.....",
            ".OPPBBBBBBBO....",
            ".OPSBBBBBBSO....",
            ".OSBBBBBBBSO.OO.",
            ".OBBBBBBBBBOOBO.",
            ".OBBBBBBBBBOBO..",
            "..OWWOOOWWOO....",
            "................",
        ],
        [
            "................",
            "..OO.....OO.....",
            ".ONBO...OBNO....",
            ".OBBBOOOBPBO....",
            ".OBBBBBBPPBO....",
            ".OBEBBBBBEBO....",
            ".OBBBBNBBBBO....",
            "..OBWWWWWBO.....",
            "..OBSBSBSBO.....",
            ".OPPBBBBBBBO....",
            ".OPSBBBBBBSO....",
            ".OSBBBBBBBSO....",
            ".OBBBBBBBBBO.OO.",
            ".OBBBBBBBBBOOBO.",
            "..OWWOOOWWOO....",
            "................",
        ],
    ]

    /// 鳴く。座りポーズで口を小→大に開く。
    private static let meow: [Frame] = [
        [
            "................",
            "..OO.....OO.....",
            ".ONBO...OBNO....",
            ".OBBBOOOBPBO....",
            ".OBBBBBBPPBO....",
            ".OBEBBBBBEBO....",
            ".OBBBBNBBBBO....",
            "..OBWWNWWBO.....",
            "..OBSBSBSBO.....",
            ".OPPBBBBBBBO....",
            ".OPSBBBBBBSO....",
            ".OSBBBBBBBSO.OO.",
            ".OBBBBBBBBBOOBO.",
            ".OBBBBBBBBBOBO..",
            "..OWWOOOWWOO....",
            "................",
        ],
        [
            "................",
            "..OO.....OO.....",
            ".ONBO...OBNO....",
            ".OBBBOOOBPBO....",
            ".OBBBBBBPPBO....",
            ".OBEBBBBBEBO....",
            ".OBBBBNBBBBO....",
            "..OBWNNNWBO.....",
            "..OBSBSBSBO.....",
            ".OPPBBBBBBBO....",
            ".OPSBBBBBBSO....",
            ".OSBBBBBBBSO.OO.",
            ".OBBBBBBBBBOOBO.",
            ".OBBBBBBBBBOBO..",
            "..OWWOOOWWOO....",
            "................",
        ],
    ]

    /// 横向き歩行（右向きで描く。左向きはベイク時にミラー）。
    /// 0=ストライドA / 1=足が揃う / 2=ストライドB / 3=足が揃う。しっぽは前半やや高い。
    private static let walk: [Frame] = [
        [
            "................",
            "..........O..O..",
            ".........OBOOBO.",
            ".........OPBBBO.",
            ".........OBBEBO.",
            "..OO.....OBBBNO.",
            ".OBO..OOOOBBWWO.",
            ".OBOOBBBBBBBBO..",
            "..OBBPBBBBBBBO..",
            "...OBSBBBBSBBO..",
            "....OBBBBBBBBO..",
            "....OBO...OBO...",
            "...OBO.....OBO..",
            "...OO.......OO..",
            "................",
            "................",
        ],
        [
            "................",
            "..........O..O..",
            ".........OBOOBO.",
            ".........OPBBBO.",
            ".........OBBEBO.",
            "..OO.....OBBBNO.",
            ".OBO..OOOOBBWWO.",
            ".OBOOBBBBBBBBO..",
            "..OBBPBBBBBBBO..",
            "...OBSBBBBSBBO..",
            "....OBBBBBBBBO..",
            ".....OBO..OBO...",
            ".....OBO..OBO...",
            ".....OO...OO....",
            "................",
            "................",
        ],
        [
            "................",
            "..........O..O..",
            ".........OBOOBO.",
            ".........OPBBBO.",
            ".........OBBEBO.",
            ".OO......OBBBNO.",
            ".OBO..OOOOBBWWO.",
            ".OBOOBBBBBBBBO..",
            "..OBBPBBBBBBBO..",
            "...OBSBBBBSBBO..",
            "....OBBBBBBBBO..",
            "....OBO...OBO...",
            ".....OBO.OBO....",
            "......OO.OO.....",
            "................",
            "................",
        ],
        [
            "................",
            "..........O..O..",
            ".........OBOOBO.",
            ".........OPBBBO.",
            ".........OBBEBO.",
            ".OO......OBBBNO.",
            ".OBO..OOOOBBWWO.",
            ".OBOOBBBBBBBBO..",
            "..OBBPBBBBBBBO..",
            "...OBSBBBBSBBO..",
            "....OBBBBBBBBO..",
            ".....OBO..OBO...",
            ".....OBO..OBO...",
            ".....OO...OO....",
            "................",
            "................",
        ],
    ]

    /// 毛づくろい。目を閉じて前足を上げ、舌を出し入れする。
    private static let groom: [Frame] = [
        [
            "................",
            "..OO.....OO.....",
            ".ONBO...OBNO....",
            ".OBBBOOOBPBO....",
            ".OBBBBBBPPBO....",
            ".OBSBBBBBSBO....",
            ".OBBBBNBBBBO....",
            "..OBWWNWWBO.....",
            "..OBBWWBBBO.....",
            ".OPPBBBBBBBO....",
            ".OPSBBBBBBSO....",
            ".OSBBBBBBBSO.OO.",
            ".OBBBBBBBBBOOBO.",
            ".OBBBBBBBBBOBO..",
            "..OWWOOOWWOO....",
            "................",
        ],
        [
            "................",
            "..OO.....OO.....",
            ".ONBO...OBNO....",
            ".OBBBOOOBPBO....",
            ".OBBBBBBPPBO....",
            ".OBSBBBBBSBO....",
            ".OBBBBNBBBBO....",
            "..OBWWWWWBO.....",
            "..OBBWWBBBO.....",
            ".OPPBBBBBBBO....",
            ".OPSBBBBBBSO....",
            ".OSBBBBBBBSO.OO.",
            ".OBBBBBBBBBOOBO.",
            ".OBBBBBBBBBOBO..",
            "..OWWOOOWWOO....",
            "................",
        ],
    ]

    /// 丸まって寝る。フレーム2は胸が1px膨らむ（呼吸）。頭は右側、目は閉じ線(S)。
    private static let sleep: [Frame] = [
        [
            "................",
            "................",
            "................",
            "................",
            "......OOOO..OO..",
            "....OOBBBBOOBNO.",
            "...OBBBBBBBBSBO.",
            "..OPPSBBBBSBBBO.",
            "..OBBBBBBBBBBO..",
            ".OBBBBBBBBBBBBO.",
            ".OBSBBBBBBBSBBO.",
            ".OBBBBBBBBBBBO..",
            "..OBBWWBBBBBO...",
            "...OOOOOOOOO....",
            "................",
            "................",
        ],
        [
            "................",
            "................",
            "................",
            "......OOOO..OO..",
            "....OOBBBBOOBNO.",
            "...OBBBBBBBBSBO.",
            "..OPPSBBBBSBBBO.",
            "..OBBBBBBBBBBBO.",
            "..OBBBBBBBBBBO..",
            ".OBBBBBBBBBBBBO.",
            ".OBSBBBBBBBSBBO.",
            ".OBBBBBBBBBBBO..",
            "..OBBWWBBBBBO...",
            "...OOOOOOOOO....",
            "................",
            "................",
        ],
    ]

    /// 毛糸玉にじゃれる。低い姿勢で前足を上げ下げする（右向き）。
    private static let playYarn: [Frame] = [
        [
            "................",
            "................",
            "................",
            "................",
            "..........O..O..",
            ".........OBOOBO.",
            ".........OPBBBO.",
            ".........OBBEBO.",
            "..OO.....OBBBNO.",
            ".OBOOOOOOOBBWWO.",
            "..OBBPBBBBBBBO..",
            "..OBSBBBBSBBBO..",
            "..OBO...OBO..OWO",
            "..OO.....OO.....",
            "................",
            "................",
        ],
        [
            "................",
            "................",
            "................",
            "................",
            "..........O..O..",
            ".........OBOOBO.",
            ".........OPBBBO.",
            ".........OBBEBO.",
            "..OO.....OBBBNO.",
            ".OBOOOOOOOBBWWO.",
            "..OBBPBBBBBBBO..",
            "..OBSBBBBSBBBO..",
            "..OBO...OBO.....",
            "..OO.....OO.OWO.",
            "................",
            "................",
        ],
    ]

    /// 猫の全アニメーション。描画側はここを唯一の正とする。
    static let catFrames: [CatAnim: [Frame]] = [
        .sit: sit, .meow: meow, .walk: walk,
        .groom: groom, .sleep: sleep, .playYarn: playYarn,
    ]

    // MARK: - 小物

    /// 毛糸玉 8x8 ×2（転がりで糸筋が回る）。B=玉 S=糸筋。
    static let yarn: [Frame] = [
        [
            "..OOOO..",
            ".OBSBBO.",
            "OBBBSBBO",
            "OSBBBSBO",
            "OBSSBBBO",
            "OBBBSBBO",
            ".OBBSBO.",
            "..OOOO..",
        ],
        [
            "..OOOO..",
            ".OBBSBO.",
            "OBSBBBSO",
            "OBBSBBBO",
            "OSBBSBBO",
            "OBBBBSBO",
            ".OSBBBO.",
            "..OOOO..",
        ],
    ]
    static let yarnSize = (w: 8, h: 8)

    /// クッション 16x8。B=布 S=陰/中央ボタン W=ステッチ光。色違いはパレット側で出す。
    static let cushion: Frame = [
        "...OOOOOOOOOO...",
        ".OOBBBBBBBBBBOO.",
        "OBBWBBBBBBBBWBBO",
        "OBBBBBBSSBBBBBBO",
        "OBBBBBBSSBBBBBBO",
        "OBBWBBBBBBBBWBBO",
        ".OOSSSSSSSSSSOO.",
        "...OOOOOOOOOO...",
    ]
    static let cushionSize = (w: 16, h: 8)

    /// 観葉植物 16x16。丸い茂みの鉢植え（葉の間の輪郭線で葉群テクスチャを出す）。
    /// B=葉 S=濃い葉 P=鉢 N=鉢の陰。
    static let plant: Frame = [
        "....OOOOOO......",
        "..OOBBBBBBOO....",
        ".OBBSBBBBSBBO...",
        "OBBBBBOBBBBSBO..",
        "OBSBBOBBOBBBBO..",
        "OBBBBBOBBOBSBO..",
        ".OBSBBBBOBBBO...",
        "..OBBOBBBBBO....",
        "...OOBBBBOO.....",
        "....OOOOOOO.....",
        "....OPPPPPO.....",
        ".....OPNPO......",
        ".....OPPPO......",
        ".....OPNPO......",
        "......OOO.......",
        "................",
    ]
    static let plantSize = (w: 16, h: 16)

    /// キャットタワー 24x38。天板（猫の寝床スポット）＋中段＋サイザル柱＋台座。
    /// B=カーペット S=陰 P=柱 N=サイザル縞。
    static let catTower: Frame = [
        "..OOOOOOOOOOOOOOOOOO....",
        ".OBBBBBBBBBBBBBBBBBBO...",
        ".OSBBBBBBBBBBBBBBBBSO...",
        "..OOOOOOOOOOOOOOOOOO....",
        "..........OPPO..........",
        "..........OPPO..........",
        "..........ONNO..........",
        "..........OPPO..........",
        "..........OPPO..........",
        "..........ONNO..........",
        "..........OPPO..........",
        "..........OPPO..........",
        "..........ONNO..........",
        "..........OPPO..........",
        "....OOOOOOOOOOOOOOOO....",
        "...OBBBBBBBBBBBBBBBBO...",
        "...OSBBBBBBBBBBBBBBSO...",
        "....OOOOOOOOOOOOOOOO....",
        "..........OPPO..........",
        "..........OPPO..........",
        "..........ONNO..........",
        "..........OPPO..........",
        "..........OPPO..........",
        "..........ONNO..........",
        "..........OPPO..........",
        "..........OPPO..........",
        "..........ONNO..........",
        "..........OPPO..........",
        "..........OPPO..........",
        "..........ONNO..........",
        "..........OPPO..........",
        "..........OPPO..........",
        "..........ONNO..........",
        "..........OPPO..........",
        ".OOOOOOOOOOOOOOOOOOOOOO.",
        "OBBBBBBBBBBBBBBBBBBBBBBO",
        "OSBBBBBBBBBBBBBBBBBBBBSO",
        ".OOOOOOOOOOOOOOOOOOOOOO.",
    ]
    static let catTowerSize = (w: 24, h: 38)

    // MARK: - エモート（10x10 固定色: O=縁 W=吹き出し地 N=アクセント）

    private static let alert: [Frame] = [
        [
            "...OOOO...",
            "..OWWWWO..",
            ".OWWNNWWO.",
            ".OWWNNWWO.",
            ".OWWNNWWO.",
            ".OWWWWWWO.",
            ".OWWNNWWO.",
            "..OWWWWO..",
            "...OOOO...",
            "....O.....",
        ],
    ]

    private static let sparkle: [Frame] = [
        [
            "..........",
            "....N.....",
            "....N.....",
            "..NNNNN...",
            "....N.....",
            "....N.....",
            ".......N..",
            "......NNN.",
            ".......N..",
            "..........",
        ],
        [
            "..........",
            ".N........",
            "NNN.......",
            ".N...N....",
            "....NNN...",
            ".....N....",
            "..........",
            "........N.",
            ".......NNN",
            "........N.",
        ],
    ]

    private static let zzz: [Frame] = [
        [
            "..........",
            "..NNN.....",
            "....N.....",
            "...N......",
            "..NNN.....",
            "......NN..",
            ".......N..",
            "......NN..",
            "..........",
            "..........",
        ],
        [
            "..........",
            "..........",
            "...NNN....",
            ".....N....",
            "....N.....",
            "...NNN....",
            ".......NN.",
            "........N.",
            ".......NN.",
            "..........",
        ],
    ]

    static let emotes: [EmoteKind: [Frame]] = [
        .alert: alert, .sparkle: sparkle, .zzz: zzz,
    ]
    static let emoteSize = 10

    // MARK: - 検証

    /// 全フレームの寸法を検証する（文字アートのタイポが最有力バグなので debug 起動時に必ず呼ぶ）。
    static func validateAll() {
        #if DEBUG
        for (anim, frames) in catFrames {
            for (i, f) in frames.enumerated() {
                assertFrame(f, w: catSize, h: catSize, name: "cat.\(anim.rawValue)[\(i)]")
            }
        }
        for (i, f) in yarn.enumerated() { assertFrame(f, w: yarnSize.w, h: yarnSize.h, name: "yarn[\(i)]") }
        assertFrame(cushion, w: cushionSize.w, h: cushionSize.h, name: "cushion")
        assertFrame(plant, w: plantSize.w, h: plantSize.h, name: "plant")
        assertFrame(catTower, w: catTowerSize.w, h: catTowerSize.h, name: "catTower")
        for (kind, frames) in emotes {
            for (i, f) in frames.enumerated() {
                assertFrame(f, w: emoteSize, h: emoteSize, name: "emote.\(kind.rawValue)[\(i)]")
            }
        }
        #endif
    }

    private static func assertFrame(_ frame: Frame, w: Int, h: Int, name: String) {
        assert(frame.count == h, "\(name): 行数 \(frame.count) != \(h)")
        for (r, row) in frame.enumerated() {
            assert(row.count == w, "\(name) 行\(r): 幅 \(row.count) != \(w): \"\(row)\"")
        }
    }
}
