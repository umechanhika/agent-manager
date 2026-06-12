import Combine
import CoreGraphics
import Foundation

/// 箱庭シミュレーション。セッション状態を購読して猫の行動を 8Hz で進め、
/// 描画用スナップショットを publish する。レンダリングは SandboxView(Canvas) が担当。
final class CatSimulation: ObservableObject {

    // MARK: - シーン定数（論理ピクセル 160x110。描画は 2x）

    enum Scene {
        static let width: CGFloat = 160
        static let height: CGFloat = 110
        static let skyBottom: CGFloat = 55      // 空バンド y0–55 / 床バンド y55–110
        static let minX: CGFloat = 10, maxX: CGFloat = 150
        static let minY: CGFloat = 58, maxY: CGFloat = 94   // 猫の可動域
        /// クッション2つの中心（猫が寝に行く位置）。
        static let cushions: [CGPoint] = [CGPoint(x: 22, y: 86), CGPoint(x: 132, y: 86)]
        static let yarnHome = CGPoint(x: 80, y: 80)
        /// waiting の猫が集まる前列中央帯。
        static let frontY: CGFloat = 88
        static let frontCenterX: CGFloat = 80
    }

    // MARK: - スナップショット（描画用・イミュータブル）

    struct CatSnapshot: Identifiable, Equatable {
        let id: String          // session_id
        let pos: CGPoint        // 論理px（float のまま。丸めは描画側）
        let facingLeft: Bool
        let anim: CatAnim
        let frame: Int
        let paletteIndex: Int
        let label: String
        let category: Session.StatusCategory
        let emote: EmoteKind?
        let emoteVisible: Bool
        let emoteFrame: Int
    }

    struct Snapshot: Equatable {
        var cats: [CatSnapshot] = []     // y 昇順（奥→手前の描画順）
        var yarnPos: CGPoint = Scene.yarnHome
        var yarnFrame: Int = 0
        /// 星のまたたき用。8Hz だと毎 tick snapshot が変わって再描画され続けるので
        /// 1/4 に量子化する（静止シーンでは publish 自体をスキップして CPU を抑える）。
        var twinkle: Int = 0
    }

    @Published private(set) var snapshot = Snapshot()

    /// waiting への遷移エッジで呼ばれる（main.swift で MeowPlayer に配線する）。
    var onWaitingEdge: (() -> Void)?

    // MARK: - 内部モデル

    private enum ArrivalGoal {
        case rest    // 着いたら座る（その後 decideNext）
        case meow    // 着いたら鳴き続ける
        case sleep   // 着いたら寝る
        case play    // 着いたら毛糸にじゃれる
    }

    private enum Activity {
        case walking(to: CGPoint, then: ArrivalGoal)
        case sitting(until: Int)
        case grooming(until: Int)
        case meowing
        case sleeping
        case playing(until: Int)
    }

    private final class Cat {
        let sessionID: String
        let paletteIndex: Int
        let speed: CGFloat       // 歩速 px/tick（個性 ±20% 込み）
        let phase: Int           // アニメ位相（全員の足並みが揃わないように）
        var rng: UInt64
        var pos: CGPoint
        var facingLeft = false
        var activity: Activity = .sitting(until: 0)
        var category: Session.StatusCategory = .idle
        var label = ""
        var emote: EmoteKind?
        var emoteUntil: Int?     // nil = 永続（waiting の ❗ / 寝ている間の 💤）
        var cushionIndex: Int?

        init(sessionID: String, pos: CGPoint) {
            self.sessionID = sessionID
            self.paletteIndex = SpriteRenderer.paletteIndex(for: sessionID)
            self.speed = 0.8 * SpriteRenderer.speedFactor(for: sessionID)
            self.phase = Int(SpriteRenderer.fnv1a(sessionID) >> 24 & 0x7)
            self.rng = SpriteRenderer.rngSeed(for: sessionID)
            self.pos = pos
        }
    }

    private var cats: [String: Cat] = [:]
    private var tickCount = 0
    private var hoveredID: String?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private var yarnPos = Scene.yarnHome
    private var yarnVel = CGVector(dx: 0, dy: 0)
    private var yarnRoll: CGFloat = 0   // 転がり量の累積（糸筋フレームの切替に使う）

    // MARK: - ライフサイクル

    init() {
        SpriteData.validateAll()
        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    /// SessionStore の変化を購読する（StatusBarController と同じ流儀）。
    func bind(to store: SessionStore) {
        store.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] sessions in self?.sync(sessions) }
            .store(in: &cancellables)
    }

    /// パネル非表示/オクルージョン時に tick を止めて CPU を使わない。
    func setPaused(_ paused: Bool) {
        if paused {
            timer?.invalidate()
            timer = nil
        } else {
            startTimer()
        }
    }

    /// ホバー中の猫は移動を止める（動く的だとクリックの mouseDown/Up が外れるため）。
    func setHovered(_ sessionID: String?) {
        hoveredID = sessionID
    }

    private func startTimer() {
        guard timer == nil else { return }
        // scheduledTimer は .default のみ登録で窓ドラッグ中に止まるため、
        // 未スケジュール生成 → .common へ追加する（追加後の二重登録はしない）。
        let t = Timer(timeInterval: 0.125, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - セッション同期

    private func sync(_ sessions: [Session]) {
        let ids = Set(sessions.map { $0.id })
        for session in sessions {
            if let cat = cats[session.id] {
                cat.label = session.label
                if cat.category != session.category {
                    apply(category: session.category, to: cat)
                }
            } else {
                spawn(session)
            }
        }
        // 消滅したセッションの猫は即削除（全終了時はアプリごと terminate するので退場アニメ不要）。
        for id in cats.keys where !ids.contains(id) {
            if let cushion = cats[id]?.cushionIndex { cushionOwners[cushion] = nil }
            cats[id] = nil
        }
        retargetWaiting()
        publish()
    }

    /// 新規セッション: ハッシュ由来のホーム位置へ画面端から歩いて入場する。
    private func spawn(_ session: Session) {
        let hash = SpriteRenderer.fnv1a(session.id)
        let homeX = 20 + CGFloat(hash % 120)                  // 20...140
        let homeY = Scene.minY + CGFloat((hash >> 16) % 36)   // 58...94
        let entryX: CGFloat = homeX < Scene.frontCenterX ? -10 : Scene.width + 10
        let cat = Cat(sessionID: session.id, pos: CGPoint(x: entryX, y: homeY))
        cat.label = session.label
        cat.activity = .walking(to: CGPoint(x: homeX, y: homeY), then: .rest)
        cats[session.id] = cat
        apply(category: session.category, to: cat)
    }

    /// 状態遷移エッジ。行動とエモートを切り替える。
    private func apply(category: Session.StatusCategory, to cat: Cat) {
        cat.category = category
        if category != .idle { releaseCushion(cat) }
        switch category {
        case .waiting:
            cat.emote = .alert
            cat.emoteUntil = nil
            onWaitingEdge?()
            // 行き先スロットは retargetWaiting()（waiting 全員ぶん再配分）で決める。
        case .done:
            cat.emote = .sparkle
            cat.emoteUntil = tickCount + 16   // ✨ 2秒
            if case .walking(let target, _) = cat.activity {
                // 入場ウォーク中なら行き先まで歩き切ってから座る（画面外で座り込まない）。
                cat.activity = .walking(to: target, then: .rest)
            } else if abs(cat.pos.x - Scene.frontCenterX) < 30 && cat.pos.y > 82 {
                // 前列スロット帯に居座ると次の waiting 猫と完全に重なるので、少し脇へ避けてから座る。
                let aside: CGFloat = cat.pos.x < Scene.frontCenterX ? -1 : 1
                let target = clampToField(CGPoint(x: cat.pos.x + aside * CGFloat(randInt(cat, 18...30)),
                                                  y: cat.pos.y - CGFloat(randInt(cat, 4...12))))
                cat.activity = .walking(to: target, then: .rest)
            } else {
                cat.activity = .sitting(until: tickCount + randInt(cat, 24...40))
            }
        case .processing:
            cat.emote = nil
            cat.emoteUntil = nil
            decideNext(cat)
        case .idle:
            cat.emote = nil   // 💤 は寝付いてから（クッションへの歩行中は出さない）
            cat.emoteUntil = nil
            headToBed(cat)
        }
    }

    // MARK: - tick

    private func tick() {
        tickCount += 1
        for cat in cats.values {
            step(cat)
        }
        stepYarn()
        publish()
    }

    private func step(_ cat: Cat) {
        switch cat.activity {
        case .walking(let target, let goal):
            if cat.sessionID == hoveredID { return }   // ホバー中は静止
            if moveToward(cat, target) { arrive(cat, goal) }
        case .sitting(let until):
            if tickCount >= until {
                if cat.category == .done {
                    cat.activity = .grooming(until: tickCount + randInt(cat, 24...40))
                } else {
                    decideNext(cat)
                }
            }
        case .grooming(let until):
            if tickCount >= until {
                if cat.category == .done {
                    cat.activity = .sitting(until: tickCount + randInt(cat, 24...40))
                } else {
                    decideNext(cat)
                }
            }
        case .playing(let until):
            nudgeYarn(by: cat)
            if tickCount >= until { decideNext(cat) }
        case .meowing, .sleeping:
            break   // 永続。状態遷移エッジでのみ抜ける。
        }
    }

    /// カテゴリに応じて次の行動を選ぶ（タイマー失効・到着後に呼ばれる）。
    private func decideNext(_ cat: Cat) {
        switch cat.category {
        case .waiting:
            break   // retargetWaiting() が管理する
        case .processing:
            if randInt(cat, 0...99) < 25 {
                // 毛糸玉へ寄ってじゃれる。
                let side: CGFloat = cat.pos.x < yarnPos.x ? -10 : 10
                let target = clampToField(CGPoint(x: yarnPos.x + side, y: yarnPos.y + 2))
                cat.activity = .walking(to: target, then: .play)
            } else {
                cat.activity = .walking(to: randomPoint(cat), then: .rest)
            }
        case .done:
            cat.activity = .sitting(until: tickCount + randInt(cat, 24...40))
        case .idle:
            headToBed(cat)
        }
    }

    private func arrive(_ cat: Cat, _ goal: ArrivalGoal) {
        switch goal {
        case .rest:
            cat.activity = .sitting(until: tickCount + randInt(cat, 16...32))
        case .meow:
            cat.activity = .meowing
        case .sleep:
            cat.activity = .sleeping
            cat.emote = .zzz
            cat.emoteUntil = nil
        case .play:
            cat.facingLeft = yarnPos.x < cat.pos.x
            cat.activity = .playing(until: tickCount + randInt(cat, 16...32))
        }
    }

    /// 空きクッションへ歩いて寝る（sticky 割当）。空きが無ければその場で寝る。
    private var cushionOwners: [Int: String] = [:]

    private func headToBed(_ cat: Cat) {
        if cat.cushionIndex == nil {
            for (i, _) in Scene.cushions.enumerated() where cushionOwners[i] == nil {
                cushionOwners[i] = cat.sessionID
                cat.cushionIndex = i
                break
            }
        }
        if let i = cat.cushionIndex {
            let target = Scene.cushions[i]
            if distance(cat.pos, target) < 1 {
                arrive(cat, .sleep)
            } else {
                cat.activity = .walking(to: target, then: .sleep)
            }
        } else {
            arrive(cat, .sleep)
        }
    }

    private func releaseCushion(_ cat: Cat) {
        if let i = cat.cushionIndex {
            cushionOwners[i] = nil
            cat.cushionIndex = nil
        }
    }

    /// waiting の猫を前列中央帯のスロットへ再配分する（membership 変化時に呼ぶ）。
    private func retargetWaiting() {
        let waiting = cats.values
            .filter { $0.category == .waiting }
            .sorted { $0.sessionID < $1.sessionID }
        for (i, cat) in waiting.enumerated() {
            let offset = CGFloat((i + 1) / 2 * 14) * (i % 2 == 0 ? 1 : -1)
            let slot = clampToField(CGPoint(x: Scene.frontCenterX + offset, y: Scene.frontY))
            if distance(cat.pos, slot) < 1 {
                if case .meowing = cat.activity {} else { cat.activity = .meowing }
            } else {
                // 既に同じスロットへ歩行中なら維持（毎 sync での再設定で歩き直さない）。
                if case .walking(let t, .meow) = cat.activity, t == slot { continue }
                cat.activity = .walking(to: slot, then: .meow)
            }
        }
    }

    // MARK: - 移動・毛糸玉

    /// 1tick ぶん target へ進む。到着したら true。
    private func moveToward(_ cat: Cat, _ target: CGPoint) -> Bool {
        let dx = target.x - cat.pos.x
        let dy = target.y - cat.pos.y
        let dist = (dx * dx + dy * dy).squareRoot()
        if dist <= cat.speed {
            cat.pos = target
            return true
        }
        cat.pos.x += dx / dist * cat.speed
        cat.pos.y += dy / dist * cat.speed
        if abs(dx) > 0.5 { cat.facingLeft = dx < 0 }
        return false
    }

    private func randomPoint(_ cat: Cat) -> CGPoint {
        CGPoint(
            x: CGFloat(randInt(cat, Int(Scene.minX)...Int(Scene.maxX))),
            y: CGFloat(randInt(cat, Int(Scene.minY)...Int(Scene.maxY)))
        )
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private func clampToField(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, Scene.minX), Scene.maxX),
                y: min(max(p.y, Scene.minY), Scene.maxY))
    }

    /// じゃれている猫が周期的に毛糸玉を突く。
    private func nudgeYarn(by cat: Cat) {
        guard (tickCount + cat.phase) % 8 == 0 else { return }
        let away: CGFloat = cat.facingLeft ? -1 : 1
        yarnVel.dx += away * CGFloat(randInt(cat, 4...10)) / 10
        yarnVel.dy += CGFloat(randInt(cat, -3...3)) / 10
    }

    private func stepYarn() {
        guard abs(yarnVel.dx) > 0.02 || abs(yarnVel.dy) > 0.02 else { return }
        yarnPos.x += yarnVel.dx
        yarnPos.y += yarnVel.dy
        yarnRoll += abs(yarnVel.dx) + abs(yarnVel.dy)
        // 床バンド内にクランプ。
        yarnPos.x = min(max(yarnPos.x, 14), Scene.width - 14)
        yarnPos.y = min(max(yarnPos.y, Scene.skyBottom + 8), Scene.maxY)
        yarnVel.dx *= 0.8
        yarnVel.dy *= 0.8
    }

    // MARK: - スナップショット

    private func publish() {
        // y 昇順（奥→手前）。同 y は waiting（要対応）を手前に、最後は ID で安定化。
        let sorted = cats.values.sorted { a, b in
            if a.pos.y != b.pos.y { return a.pos.y < b.pos.y }
            let aWaiting = a.category == .waiting, bWaiting = b.category == .waiting
            if aWaiting != bWaiting { return bWaiting }
            return a.sessionID < b.sessionID
        }
        let next = Snapshot(
            cats: sorted.map { snap($0) },
            yarnPos: yarnPos,
            yarnFrame: Int(yarnRoll / 4) % SpriteData.yarn.count,
            twinkle: tickCount / 4
        )
        // 静止シーン（全員 座る/寝る で 2fps）では大半の tick が無変化。
        // publish を省いて SwiftUI の再描画ごと止める。
        if next != snapshot { snapshot = next }
    }

    private func snap(_ cat: Cat) -> CatSnapshot {
        let anim: CatAnim
        let frame: Int
        switch cat.activity {
        case .walking:
            anim = .walk
            frame = (tickCount + cat.phase) % 4          // 歩行は毎 tick（8fps）
        case .sitting:
            anim = .sit
            frame = slowFrame(cat)
        case .grooming:
            anim = .groom
            frame = slowFrame(cat)
        case .meowing:
            anim = .meow
            frame = slowFrame(cat)
        case .sleeping:
            anim = .sleep
            frame = (tickCount / 8 + cat.phase) % 2      // 呼吸はさらにゆっくり（1fps）
        case .playing:
            anim = .playYarn
            frame = slowFrame(cat)
        }

        var emote: EmoteKind?
        var emoteVisible = false
        var emoteFrame = 0
        if let until = cat.emoteUntil, tickCount >= until {
            cat.emote = nil
            cat.emoteUntil = nil
        }
        if let e = cat.emote {
            emote = e
            switch e {
            case .alert:
                emoteVisible = tickCount % 6 < 5          // 常時表示・短いブリンク
            case .sparkle:
                emoteVisible = true
                emoteFrame = (tickCount / 3) % 2
            case .zzz:
                emoteVisible = tickCount % 16 < 12        // 点滅
                emoteFrame = (tickCount / 8) % 2
            }
        }

        return CatSnapshot(
            id: cat.sessionID, pos: cat.pos, facingLeft: cat.facingLeft,
            anim: anim, frame: frame, paletteIndex: cat.paletteIndex,
            label: cat.label, category: cat.category,
            emote: emote, emoteVisible: emoteVisible, emoteFrame: emoteFrame
        )
    }

    /// 静止系アニメは 4tick に 1 コマ（2fps）。
    private func slowFrame(_ cat: Cat) -> Int {
        (tickCount / 4 + cat.phase) % 2
    }

    #if DEBUG
    /// 検証用: 内部状態のテキストダンプ（SIGUSR2 で /tmp に書き出す）。
    func debugDump() -> String {
        var lines = ["tick=\(tickCount) paused=\(timer == nil)"]
        for cat in cats.values.sorted(by: { $0.sessionID < $1.sessionID }) {
            lines.append("\(cat.sessionID): category=\(cat.category) activity=\(cat.activity) "
                + "emote=\(String(describing: cat.emote)) until=\(String(describing: cat.emoteUntil)) "
                + "pos=(\(Int(cat.pos.x)),\(Int(cat.pos.y))) cushion=\(String(describing: cat.cushionIndex))")
        }
        return lines.joined(separator: "\n")
    }
    #endif

    // MARK: - 決定論的乱数（猫ごとの LCG。個性はハッシュ種から生まれる）

    private func randInt(_ cat: Cat, _ range: ClosedRange<Int>) -> Int {
        cat.rng = cat.rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int((cat.rng >> 33) % span)
    }
}
