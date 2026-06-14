# Agent Manager

複数の Claude Code セッションを、**常時最前面のフローティングウィンドウ**で一覧するツール。ドット絵の部屋の窓辺にセッションが並び、行をクリックすると対応するターミナルにジャンプする。

| 昼 | 夜 |
|----|----|
| ![昼の表示](docs/images/screenshot-day.png) | ![夜の表示](docs/images/screenshot-night.png) |

- ステータスランプが状態を示す（🟡 確認待ち / 🟢 応答完了 / 🔵 処理中 / ⚪ 待機）
- 確認待ち・応答完了のセッションが出ると自動表示、すべて解消すると自動で隠れる
- 部屋の床には猫がおり、セッション数と状態に連動して振る舞う
- 時刻に合わせて昼・夕・夜の景色が変わる

---

## セットアップ

**必要なもの**: macOS、Swift (Xcode Command Line Tools)、Python 3（macOS 標準）、[gh CLI](https://cli.github.com/)（PR 作成時のみ）

```sh
git clone https://github.com/umechanhika/agent-manager.git ~/agent-manager
bash ~/agent-manager/scripts/create-signing-cert.sh  # 署名証明書の作成（初回のみ・対話あり）
bash ~/agent-manager/scripts/build-app.sh            # .app をビルド
```

`create-signing-cert.sh` は通常のターミナル（Terminal.app / iTerm2）で実行すること（Claude セッションの `!` 実行は対話入力ができないため不可）。

### hooks の登録

`~/.claude/settings.json` の `hooks` セクションに追加する。

```json
"hooks": {
  "SessionStart": [
    { "hooks": [
      { "type": "command", "command": "$HOME/agent-manager/hooks/agent-manager-hook.sh" },
      { "type": "command", "command": "$HOME/agent-manager/hooks/agent-manager-launch.sh" }
    ]}
  ],
  "UserPromptSubmit": [
    { "hooks": [{ "type": "command", "command": "$HOME/agent-manager/hooks/agent-manager-hook.sh" }]}
  ],
  "PreToolUse":  [{ "matcher": "*", "hooks": [{ "type": "command", "command": "$HOME/agent-manager/hooks/agent-manager-hook.sh" }]}],
  "PostToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "$HOME/agent-manager/hooks/agent-manager-hook.sh" }]}],
  "Notification": [{ "hooks": [{ "type": "command", "command": "$HOME/agent-manager/hooks/agent-manager-hook.sh" }]}],
  "Stop":        [{ "hooks": [{ "type": "command", "command": "$HOME/agent-manager/hooks/agent-manager-hook.sh" }]}],
  "SessionEnd":  [{ "hooks": [{ "type": "command", "command": "$HOME/agent-manager/hooks/agent-manager-hook.sh" }]}]
}
```

登録後、新規 Claude Code セッションを開始するとアプリが自動で起動する。

### 権限

- **iTerm2**: 初回クリック時に表示されるダイアログで「許可」
- **Android Studio 等**: `システム設定 > プライバシーとセキュリティ > アクセシビリティ` で AgentManager を ON

### アップデート

```sh
cd ~/agent-manager && git pull
pkill -f AgentManager.app
bash ~/agent-manager/scripts/build-app.sh
open -g ~/agent-manager/.build/AgentManager.app
```

---

## 仕組み

```
Claude Code の各セッション
  │ hooks (SessionStart / UserPromptSubmit / PreToolUse / ...)
  ▼
hooks/agent-manager-hook.sh
  │ JSON を atomic write
  ▼
~/.claude/agent-manager/sessions/<session_id>.json
  │ FSEvents で監視
  ▼
AgentManager（SwiftUI フローティング NSPanel）
  │ クリック
  ▼
iTerm2: AppleScript でペイン選択 / その他: AXRaise でウィンドウ前面化
```

hook とアプリはファイル経由の疎結合。状態ファイルはマシンローカルで、リポジトリには含まれない。

### 状態の対応

| 色 | state | 発火イベント |
|----|-------|------------|
| 🟡 黄（確認待ち） | `waiting` | `Notification` (`permission_prompt`) |
| 🟢 緑（応答完了） | `done` | `Stop` / `Notification` (`idle_prompt`) |
| 🔵 青（処理中） | `processing` | `UserPromptSubmit` / `PreToolUse` / `PostToolUse` |
| ⚪ 灰（待機） | `idle` | `SessionStart` |

### ターミナルへのジャンプ

| ホスト | 方法 |
|--------|------|
| iTerm2 | `ITERM_SESSION_ID` で該当ペインを AppleScript 選択 |
| その他 (Android Studio 等) | System Events でウィンドウタイトルを走査し、`cwd` フルパスまたはプロジェクト名の境界一致で一意に特定できたときのみ前面化 |

フォーカスの成否は `~/.claude/agent-manager/focus.log` に記録される。

### コード署名について

`scripts/create-signing-cert.sh` で作成した自己署名証明書（`AgentManager Code Signing`）でビルドすることで、リビルドをしても TCC の権限（Automation・アクセシビリティ）が失われない。ad-hoc 署名へのフォールバックはせず、証明書がなければビルドは失敗する（`~/.claude/agent-manager/build.log` にエラーが残る）。

---

## ファイル構成

```
hooks/agent-manager-hook.sh      状態ファイルの upsert（全 hook から呼ばれる）
hooks/agent-manager-launch.sh    SessionStart 用: 未起動なら build & 起動（冪等）
scripts/build-app.sh             release build → .app バンドル生成
scripts/create-signing-cert.sh   コード署名証明書の作成（初回のみ）
Sources/AgentManager/
  main.swift                     NSPanel の構成・中身追従リサイズ
  ContentView.swift              セッション一覧（ガラスボード・ステータスランプ）
  SessionStore.swift             FSEvents 監視 + JSON 読み込み
  StatusBarController.swift      メニューバー常駐・自動表示制御
  ITermFocus.swift               ホスト別フォーカス + focus.log
  Cat/SandboxView.swift          ドット絵の部屋（窓背景・猫の床ストリップ）
  Cat/CatSimulation.swift        猫の行動シミュレーション（状態連動・8Hz）
  Pixel/SpriteRenderer.swift     スプライト描画
  Pixel/SpriteData.swift         スプライトデータ
  Sound/MeowPlayer.swift         確認待ちエッジでの鳴き声
```
