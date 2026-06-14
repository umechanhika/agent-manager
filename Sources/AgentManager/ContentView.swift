import AppKit
import SwiftUI

/// アプリの主役＝セッション一覧。全面窓ガラス（外の景色）の前に浮かぶ「1枚のガラスボード」に
/// 全セッションを載せる（区切り線なし・背景の景色の層が自然な仕切りになる）。
/// 各行はステータスランプ＋名前のみ（状態文言・経過は出さない）。
/// store のみを購読し、下部の床ストリップ（8Hz）とは別ビューなので 8Hz の再描画に巻き込まれない。
struct SessionPlatesView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        let theme = SkyTheme.current()
        return Group {
            if store.sessions.isEmpty {
                Text("セッションなし")
                    .font(.system(size: 11))
                    .foregroundStyle(.black.opacity(0.45))
                    .shadow(color: .white.opacity(0.4), radius: 1)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.sessions) { session in
                        PlateRow(session: session, theme: theme)
                    }
                }
                .background(boardBackground)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 8)
            }
        }
    }

    /// 全セッションをまとめて載せる 1 枚の磨りガラスボード（背後の窓＝外の景色が透ける）。
    private var boardBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.white.opacity(GlassStyle.opacity))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.55), lineWidth: 1))
    }
}

/// ガラスボード上の1行＝1セッション。左にステータスランプ、右に名前（可読）。地は透明（ボードに任せる）。
/// ホバーで明るく＋ポインタカーソルにして「タップでターミナルへ飛べる」と一目で分かるようにする。
private struct PlateRow: View {
    let session: Session
    let theme: SkyTheme
    @State private var hovering = false
    @State private var pressed = false
    @State private var flash: Double = 0   // ステータス変化時のハイライト強度（0…1）

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(session: session)
            Text(session.label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
                // 背後の景色に文字が埋もれないよう影で締める（特に夜）。
                .shadow(color: nameShadow, radius: 1, x: 0, y: 0)
            Spacer(minLength: 4)
            if hovering {
                Text("↗")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(textColor.opacity(0.85))
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(rowBackground)
        // 確認待ちの行は左端のアクセントストライプで焦点化する。
        .overlay(alignment: .leading) {
            if session.needsAttention {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(session.color)
                    .frame(width: 3)
                    .padding(.vertical, 5)
                    .padding(.leading, 3)
            }
        }
        .contentShape(Rectangle())
        .scaleEffect(pressed ? 0.99 : 1)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.08)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeOut(duration: 0.12)) { pressed = false }
            }
            ITermFocus.focus(session: session)
        }
        .onChange(of: session.state) { _ in flashHighlight() }
        .help(SessionTooltip.text(for: session))
    }

    /// 行の地は透明（地はボードのガラスに任せる）。状態変化フラッシュとホバーだけ薄く光らせる。
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(session.color.opacity(flash * 0.25))
            .overlay(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(hovering ? 0.16 : 0)))
            .padding(.horizontal, 2)
    }

    /// 名前テキスト色。景色に映えるよう、昼は濃色・夜は明色。
    private var textColor: Color {
        theme.isNight ? Color(red: 0.97, green: 0.96, blue: 0.92)
                      : Color(red: 0.11, green: 0.09, blue: 0.07)
    }
    /// 文字影（夜は濃く・昼は薄く）。背後の景色からの可読性を担保する。
    private var nameShadow: Color {
        theme.isNight ? .black.opacity(0.6) : .black.opacity(0.18)
    }

    /// ステータスが変わった行をステータス色で数回明滅させてから消す。
    private func flashHighlight() {
        flash = 1
        withAnimation(.easeInOut(duration: 0.4).repeatCount(3, autoreverses: true)) {
            flash = 0.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 * 3) {
            withAnimation(.easeOut(duration: 0.35)) { flash = 0 }
        }
    }
}

/// 状態に応じて振る舞いが変わるステータスランプ。
/// - 確認待ち: ユーザー操作が必要な唯一の状態なので、広がって消えるハロー（脈動）で注意を引く。
/// - 処理中:   "動いている" ことが伝わる穏やかな呼吸アニメ。
/// - 完了/待機: 静止。
private struct StatusDot: View {
    let session: Session
    @State private var animate = false

    var body: some View {
        ZStack {
            // 確認待ちのときだけ出る、広がって薄くなるハロー。
            if session.needsAttention {
                Circle()
                    .fill(session.color)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animate ? 2.2 : 1)
                    .opacity(animate ? 0 : 0.55)
            }
            Circle()
                .fill(session.color)
                .frame(width: 8, height: 8)
                .scaleEffect(session.isActive && animate ? 0.8 : 1)
                .opacity(session.isActive && animate ? 0.45 : 1)
        }
        .frame(width: 8, height: 8)
        .shadow(color: .black.opacity(0.25), radius: 1)   // 景色の上でもランプを締める
        .onAppear { restartAnimation() }
        .onChange(of: session.state) { _ in restartAnimation() }
    }

    private func restartAnimation() {
        // いったん止めてから状態に応じたアニメを張り直す。
        withAnimation(.easeOut(duration: 0.2)) { animate = false }
        if session.needsAttention {
            withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) {
                animate = true
            }
        } else if session.isActive {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}
