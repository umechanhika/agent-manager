import Cocoa
import SwiftUI

/// 非アクティブなフローティング窓でも「最初のクリック」を中身に届けるための
/// NSHostingView サブクラス。これがないと、窓が key でないときの1クリック目が
/// ウィンドウ活性化に吸われ、2クリック目でやっとタップが反応してしまう。
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: Content) { super.init(rootView: rootView) }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private let store = SessionStore()
    /// メニューバー常駐（ステータス別件数の表示／窓の表示トグル）。
    private var statusBar: StatusBarController?
    /// 箱庭シミュレーション（8Hz tick）。パネル非表示時は止めて CPU を使わない。
    private var simulation: CatSimulation?
    #if DEBUG
    /// 検証用スナップショット（SIGUSR1）/ 状態ダンプ（SIGUSR2）のシグナルソース保持。
    private var snapshotSignalSource: DispatchSourceSignal?
    private var stateSignalSource: DispatchSourceSignal?
    #endif

    /// 上端固定リサイズの基準（窓の上端 y = frame.maxY）。中身追従で高さが変わっても
    /// この上端を保つよう origin.y を詰め直し、左下原点リサイズによる上下動を防ぐ。
    private var anchorTopY: CGFloat?
    /// 自前の setFrame 起因の didResize 通知を無視する再入ガード。
    private var isAdjustingFrame = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        // 全セッションが終了したらアプリ自体を終了する。
        // 次回の SessionStart フックでまた起動するため、常駐し続ける必要はない。
        store.onAllSessionsEnded = { NSApp.terminate(nil) }
        let simulation = CatSimulation()
        simulation.onWaitingEdge = { MeowPlayer.shared.meow() }
        simulation.bind(to: store)
        self.simulation = simulation
        let hosting = ClickThroughHostingView(rootView: RootView(store: store, simulation: simulation))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 260),
            styleMask: [.nonactivatingPanel, .titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        // 標準タイトルバーに "AgentManager" を表示。トラフィックライト（赤=閉じる/黄=最小化/緑=zoom）は左上。
        // ※ fullSizeContentView は使わない（コンテンツ高さにタイトルバーが上乗せされ上部が分厚くなるため）。
        panel.title = "AgentManager"
        panel.titleVisibility = .visible
        panel.titlebarSeparatorStyle = .none   // タイトルバー下の濃い区切り線を消す
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false   // 赤で閉じても解放しない（Dockクリックで再表示するため）

        // 常時最前面・全 Space・半透明。
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        panel.contentView = hosting
        // 幅は固定（RootView の 240pt）。高さはメインのセッション一覧の中身に追従して伸縮し、
        // 下部の猫ストリップは固定高。辺ドラッグでのリサイズは不可（高さはセッション数だけが動かす）。
        panel.setFrameAutosaveName("AgentManagerPanel")

        // レイアウトを確定させてから中身に合うサイズへ（起動直後は fittingSize が 0 になりうる）。
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        if size.width < 50 || size.height < 30 { size = NSSize(width: 240, height: 260) }
        // 前回の位置だけ復元する。保存フレームにはサイズも含まれるが、サイズは中身追従に
        // 戻したいので「保存フレームの左上」を採って、中身サイズで上端固定に置き直す。
        let hadSaved = panel.setFrameUsingName("AgentManagerPanel")
        let savedTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        panel.setContentSize(size)
        if hadSaved {
            panel.setFrameTopLeftPoint(savedTopLeft)
        } else {
            placeTopRight(panel)
        }

        // 初期表示はしない（waiting 連動）。waiting があれば StatusBarController が表示側へ倒す。
        self.panel = panel

        // 上端固定の基準を、初期配置後の実フレーム上端に合わせる（表示前でも setFrameOrigin 済みで有効）。
        anchorTopY = panel.frame.maxY
        // 中身追従で高さが変わったとき上端(maxY)を保つようフレームを張り直す。
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelDidResize(_:)),
            name: NSWindow.didResizeNotification, object: panel)
        // ユーザーがドラッグで窓を動かしたら、その位置を新しい上端基準として採用する。
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelDidMove(_:)),
            name: NSWindow.didMoveNotification, object: panel)
        // パネルの可視状態（orderOut/最小化/被覆）に連動してシミュレーションを止める。
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelOcclusionChanged(_:)),
            name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        // 初期表示は waiting 連動なので、表示されるまで tick を止めておく。
        simulation.setPaused(true)

        #if DEBUG
        // 検証用: SIGUSR1 で窓の中身を /tmp/agent-manager-snap.png に書き出す。
        // 自プロセスの view 描画なので画面収録の TCC 権限が不要（screencapture の代替）。
        signal(SIGUSR1, SIG_IGN)
        let snapSource = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        snapSource.setEventHandler { [weak self] in
            guard let view = self?.panel?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/agent-manager-snap.png"))
            }
        }
        snapSource.resume()
        self.snapshotSignalSource = snapSource

        // 検証用: SIGUSR2 でシミュレーション内部状態を /tmp/agent-manager-state.txt に書き出す。
        signal(SIGUSR2, SIG_IGN)
        let stateSource = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
        stateSource.setEventHandler { [weak self] in
            guard let self = self else { return }
            var text = self.simulation?.debugDump() ?? "(no simulation)"
            text += "\nstore: " + self.store.sessions
                .map { "\($0.session_id)=\($0.state)" }.joined(separator: " ")
            try? text.write(toFile: "/tmp/agent-manager-state.txt", atomically: true, encoding: .utf8)
        }
        stateSource.resume()
        self.stateSignalSource = stateSource
        #endif

        // メニューバー常駐を起動。窓の表示/非表示はクロージャ経由で AppDelegate に委ねる。
        let sb = StatusBarController(store: store)
        sb.setWindowVisible = { [weak self] visible in
            guard let panel = self?.panel else { return }
            if visible {
                if panel.isMiniaturized { panel.deminiaturize(nil) }
                panel.orderFrontRegardless()
            } else {
                panel.orderOut(nil)
            }
        }
        // 左クリックのトグル判定用。最小化中は「非表示」扱いにして次クリックで復帰させる。
        sb.isWindowVisible = { [weak self] in
            guard let panel = self?.panel else { return false }
            return panel.isVisible && !panel.isMiniaturized
        }
        self.statusBar = sb
    }

    /// メイン画面の右上あたりに配置する（確定サイズに対して計算する）。
    private func placeTopRight(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.maxX - panel.frame.width - 20,
                                     y: f.maxY - panel.frame.height - 20))
    }

    /// 中身追従で高さが変わったとき、上端(maxY)を固定したままリサイズする。
    /// NSPanel は左下原点なので、何もしないと高さ変化で窓が上下にずれて見える。
    @objc private func panelDidResize(_ note: Notification) {
        guard let panel = panel, !isAdjustingFrame else { return }
        // サイズは固定だが、最小化からの復帰など高さが動いた場合に上端(maxY)を保つ。
        guard let top = anchorTopY else { anchorTopY = panel.frame.maxY; return }
        let newOriginY = top - panel.frame.height
        if abs(panel.frame.origin.y - newOriginY) < 0.5 { return }  // 既に上端維持済み
        var frame = panel.frame
        frame.origin.y = newOriginY
        isAdjustingFrame = true
        panel.setFrame(frame, display: true)   // animate せず即時反映
        isAdjustingFrame = false
    }

    /// ドラッグ等で窓を動かしたら、以降のリサイズ基準を現在の上端に更新する。
    /// （isMovableByWindowBackground=true なので背景ドラッグ移動が日常的に起こる）
    @objc private func panelDidMove(_ note: Notification) {
        guard let panel = panel, !isAdjustingFrame else { return }
        anchorTopY = panel.frame.maxY
    }

    /// パネルが見えなくなったら（orderOut / 最小化 / 完全被覆）tick を止め、
    /// 再び見えたら再開する。floating レベルなので実質 orderOut/最小化の検出器として働く。
    @objc private func panelOcclusionChanged(_ note: Notification) {
        guard let panel = panel else { return }
        simulation?.setPaused(!panel.occlusionState.contains(.visible))
    }

    /// Dock アイコンのクリックで（閉じた/最小化した後も、メニューバーで非表示にした後も）小窓を再表示する。
    /// 状態の二重管理を避けるため StatusBarController 経由（userWantsWindow=true）で表示する。
    /// メニューバーがはみ出して押せない状況からの確実な復帰口でもある。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBar?.forceShow()
        return true
    }

    /// 最小限のメインメニュー（⌘H 非表示 / ⌘Q 終了）。
    private func setupMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "非表示", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "AgentManager を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)   // Dock アイコンを表示
app.run()
