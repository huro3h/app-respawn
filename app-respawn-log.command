#!/bin/bash
# app-respawn の実行ログを追尾する使い捨てウィンドウ。
# launchd 配下の app-respawn --watch が発火時に open -a Terminal で開く。
#
# 追尾先は「その回の実行専用ファイル」で、app-respawn 側が毎回切り詰めてから開く。
# 共有ログを tail -n 0 で追うと、Terminal のコールドスタート(実測8秒)の間に本体が
# 走り終わり、貼り付いた時には何も流れてこない。先頭から読めばこの競合が消える。

LOG="$HOME/Library/Logs/app-respawn-current.log"
QUIT_MARKER="$HOME/Library/Logs/app-respawn-quit-terminal"
# 窓のタイトル。閉じる窓を見分けるのに使う。終了済みの窓は使い回された tty 名を返し続けるので、
# tty だけでは自分の窓と、隔離属性で止まった回に app-respawn が出した説明の窓を区別できない。
TITLE="app-respawn 実行ログ"
NOTICE_TITLE="app-respawn 隔離属性"   # app-respawn の QUARANTINE_TITLE と揃える
MYTTY=$(tty)
FIFO=$(mktemp -u -t app-respawn-fifo) || exit 1
TAIL_PID=""

# tail をプロセス置換にすると pid が取れず、ウィンドウが閉じた後も残り続ける。
# FIFO 経由にして pid を握り、どの抜け方をしても必ず落とす。
cleanup() {
  [ -n "$TAIL_PID" ] && kill "$TAIL_PID" 2>/dev/null
  rm -f "$FIFO"
}
trap cleanup EXIT HUP INT TERM

mkfifo "$FIFO" || exit 1
tail -n +1 -F "$LOG" > "$FIFO" 2>/dev/null &
TAIL_PID=$!

printf '\033]0;%s\007' "$TITLE"
echo "app-respawn — 実行ログ"
printf '%.0s─' {1..64}; echo

while IFS= read -r line; do
  echo "$line"
  case "$line" in
    *"respawn 終了"*) break ;;
  esac
done < "$FIFO"

cleanup
trap - EXIT

printf '%.0s─' {1..64}; echo
echo "完了しました。1秒後にこのウィンドウを閉じます (Ctrl-C で残す)"
sleep 1

# app-respawn が Terminal を起動した回だけマーカーが置かれる。元から使っていた Terminal を
# 巻き込まないための印。念のため「他にウィンドウが残っていない」ことも確かめてから quit する。
# 中身が preset なら、プリセットに Terminal が入っているので他の窓が残っていても終わらせる。
QUIT_APP=""
if [ -f "$QUIT_MARKER" ]; then
  QUIT_APP=yes
  [ "$(cat "$QUIT_MARKER")" = "preset" ] && QUIT_APP=preset
  rm -f "$QUIT_MARKER"
fi

# close はバックグラウンドに逃がして先に exit する。自分のシェルが生きている間に投げると
# Terminal は「このウィンドウで実行中のプロセスを終了しますか?」を出して閉じない
# (しかもエラーを返さないので成功したように見える)。
CLOSER=$(mktemp -t app-respawn-close)
{
  cat <<EOF
tell application "Terminal"
  -- 自分の窓に加えて、属性を外す前の回に出た説明の窓も閉じる
  set victims to {}
  repeat with w in windows
    if name of w contains "$NOTICE_TITLE" then set end of victims to id of w
    if name of w contains "$TITLE" then
      repeat with t in tabs of w
        if tty of t is "$MYTTY" then set end of victims to id of w
      end repeat
    end if
  end repeat
  -- 閉じると windows の並びが変わるので、参照ではなく id で閉じる
  repeat with vid in victims
    close (first window whose id is vid)
  end repeat
EOF
  if [ "$QUIT_APP" = "preset" ]; then
    cat <<'EOF'
  delay 0.5
  quit
EOF
  elif [ -n "$QUIT_APP" ]; then
    cat <<'EOF'
  delay 0.5
  if (count of (every window whose visible is true)) is 0 then quit
EOF
  fi
  echo "end tell"
} > "$CLOSER"

nohup bash -c "sleep 1; osascript '$CLOSER' >/dev/null 2>&1; rm -f '$CLOSER'" >/dev/null 2>&1 &
exit 0
