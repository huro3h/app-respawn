#!/bin/bash
# app-respawn の実行ログを追尾する使い捨てウィンドウ。
# launchd 配下の app-respawn --watch が発火時に open -a Terminal で開く。
#
# 追尾先は「その回の実行専用ファイル」で、app-respawn 側が毎回切り詰めてから開く。
# 共有ログを tail -n 0 で追うと、Terminal のコールドスタート(実測8秒)の間に本体が
# 走り終わり、貼り付いた時には何も流れてこない。先頭から読めばこの競合が消える。

LOG="$HOME/Library/Logs/app-respawn-current.log"
QUIT_MARKER="$HOME/Library/Logs/app-respawn-quit-terminal"
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

printf '\033]0;app-respawn\007'
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
echo "完了しました。5秒後にこのウィンドウを閉じます (Ctrl-C で残す)"
sleep 5

# app-respawn が Terminal を起動した回だけマーカーが置かれる。元から使っていた Terminal を
# 巻き込まないための印。念のため「他にウィンドウが残っていない」ことも確かめてから quit する。
QUIT_APP=""
if [ -f "$QUIT_MARKER" ]; then
  QUIT_APP=yes
  rm -f "$QUIT_MARKER"
fi

# close はバックグラウンドに逃がして先に exit する。自分のシェルが生きている間に投げると
# Terminal は「このウィンドウで実行中のプロセスを終了しますか?」を出して閉じない
# (しかもエラーを返さないので成功したように見える)。
CLOSER=$(mktemp -t app-respawn-close)
{
  cat <<EOF
tell application "Terminal"
  set victim to missing value
  repeat with w in windows
    repeat with t in tabs of w
      if tty of t is "$MYTTY" then set victim to w
    end repeat
  end repeat
  if victim is not missing value then close victim
EOF
  if [ -n "$QUIT_APP" ]; then
    cat <<'EOF'
  delay 0.5
  if (count of (every window whose visible is true)) is 0 then quit
EOF
  fi
  echo "end tell"
} > "$CLOSER"

nohup bash -c "sleep 1; osascript '$CLOSER' >/dev/null 2>&1; rm -f '$CLOSER'" >/dev/null 2>&1 &
exit 0
