---
name: app-respawn
description: 外部モニターを外した時に、プリセット指定した macOS の GUI アプリを graceful quit する個人ツール app-respawn の使い方・設定・launchd 常駐。「モニターを外すとウィンドウが散る/重なる」「アプリを一括終了したい」「バーチャルデスクトップ(Space)」「ディスプレイ切断で自動実行」の話題、force_quit やプリセットの編集、および macOS の Apple Event(自動化)権限・launchd 常駐・CoreGraphics でのディスプレイ判定を扱う時に参照。
---

# `app-respawn` — プリセットのアプリを graceful quit（既定は終了のみ）

実体: `~/projects/app-respawn/`（本体・設定・plist テンプレート・`setup` を同階層に置いた自己完結ディレクトリ）

外部モニターを外すと、そこに置いていたウィンドウが1画面に大量に重なったり、別の Space に
散らばって毎回探すことになる。macOS の Space（バーチャルデスクトップ）はプライベートAPI
（`SkyLight.framework`）＋ Dock への注入（SIP 部分無効化）でしか操作できず、SIP を切る前提の
ツールは採れない（SIP は有効なままにする方針）。そこで**ウィンドウを追いかけるのをやめて、対象アプリを
きれいに終了する**アプローチを取る。既定は**終了だけ**で、開き直しは手作業。
`--relaunch` を付けたときだけ、いまアクティブな画面/Space で自動的に起動し直す。

## セットアップ

`setup` が LaunchAgent の生成と PATH へのリンク作成をまとめて行う。既定はドライラン。

```bash
~/projects/app-respawn/setup            # 生成先/リンク先の確認
~/projects/app-respawn/setup --apply    # 実行
```

リンク先は `/opt/homebrew/bin` → `/usr/local/bin` → `~/bin` の順に、**PATH に入っていて
書き込めるものを1つ**選ぶ（`setup` の `LINK_CANDIDATES`）。PATH を総当たりしないのは、
rbenv/pyenv の shims や conda の bin が書き込み可能なまま先頭に来ており、そこへ置くと
rehash や環境切り替えで消えるため。同名のファイルが既にある場合は**上書きせず警告だけ**出す。

> [!NOTE]
> Homebrew の prefix に置くので `brew doctor` が "Unbrewed symlinks" として警告する。実害はない。
> 気になるなら `--no-link` を付けてリンクを作らず、フルパスで実行する。

## 使い方

```bash
app-respawn --list                      # 起動中の GUI アプリと bundle id を確認
app-respawn                             # ドライラン(対象の確認だけ)
app-respawn --apply                     # 終了のみ実行(確認プロンプトあり)
app-respawn --apply --relaunch          # 終了して現在の画面で開き直す
app-respawn --preset all --apply        # 別プリセット
app-respawn --config                    # 対話的にプリセットを編集(絞り込み UI)
app-respawn --init                      # いま起動中のアプリから設定を生成(表示のみ)
app-respawn --init --apply              # 設定ファイルに書き込み
```

その他: `--stagger SEC`(再起動間隔, 既定0.8) / `--timeout SEC`(終了待ち, 既定20) /
`--term-fallback` / `--require-single-display`(ディスプレイが1枚のときだけ動く)

exit: 0=全て終了できた / 1=ドライラン or 残存・失敗あり / 2=エラー

## 設定ファイル `app-respawn.json`

`presets` にプリセット名 → bundle id の配列。並び順は終了/起動の順序で、
`--relaunch` 時は**先頭のアプリが最後に前面へ戻る**。既定のプリセット名は `default`。
環境変数 `APP_RESPAWN_CONFIG` でパスを上書き可能。

> [!IMPORTANT]
> `app-respawn.json` は**手元のアプリ構成そのもの**なので `.gitignore` 済み。
> リポジトリに入るのは雛形の `app-respawn.example.json` だけ。
> 設定の書式を変えたときは雛形も直すこと（`--init` の生成結果とズレる）。
> 実際のプリセット内容をこの skill や README に転記しないこと（public リポジトリのため）。

clone 直後は `--init --apply`（起動中のアプリから生成）か、雛形のコピーで用意する:

```bash
cp app-respawn.example.json app-respawn.json
```

パスは**スクリプトの実体位置から相対で解決**している（設置場所を直書きしていない）ので、
ディレクトリごとどこへ移動しても動く。PATH に置く `app-respawn` はシンボリックリンクなので、
`File.realpath(__FILE__)` を挟んでからルートを求める。これを忘れると設定ファイルを見失う。

## 対話設定 `--config`

インストール済みアプリを絞り込みながら選ぶ fzf 風 TUI。bundle id を手で調べなくて済む。
保存すると `presets[--preset で指定した名前]` と `force_quit` を書き換える。
**他のプリセット・設定にあるがインストールされていない bundle id は保持する**
（未検出のものは一覧の先頭に `(アプリ未検出)` として出し、黙って消さない）。

**アプリの列挙**: `APP_DIRS`（`/Applications`・`/System/Applications`・
`/System/Library/CoreServices`・`~/Applications`）を **maxdepth 3 相当**で走査し、
各 `Contents/Info.plist` を `plutil -convert json` で読む。実測 250件前後で約1.3秒。

- **CoreServices を入れるのは Finder がそこにいるため**。`/Applications` だけ見ると
  プリセットの主要アプリを列挙できない
- 深く辿らないのは Xcode.app のように**内部に大量の .app を抱える**アプリがあるため。
  加えて親ディレクトリに `.app/` を含むパスも弾く
- `LSUIElement` / `LSBackgroundOnly` が立つものは除外（250件 → 112件）。
  メニューバー常駐やデーモンは quit しても意味がない
- `System Events` を使わないのが要点。**設定を編集するだけで自動化の許可ダイアログを
  出したくない**ため。起動中マーク（`●`）も Apple Event ではなく
  `ps -axo comm=` が返すパス（`.../Foo.app/Contents/MacOS/Foo`）から判定している

> [!NOTE]
> `plutil -extract` を**キーごとに呼ばない**こと。アプリ数 × キー数だけプロセスが増え、
> 体感できるほど遅くなる。1アプリ1回の `-convert json` で全部読んで Ruby 側で拾う。
> `system_profiler SPApplicationsDataType` は1回で済むが桁違いに遅いので論外。

> [!CAUTION]
> **`mdls` に複数ファイルを渡す一括取得を使ってはいけない。** 存在しないパスが混ざると
> その分の出力ブロックが丸ごと欠落し、stderr へ `<直前のパス>: could not find <パス>` という
> 紛らわしい形で出る。結果と入力の対応が**ずれたまま気付けない**。実測で確認済み。

**キー割り当て**: 印字文字は全て検索クエリに吸われるので、トグルを文字キーに割り当てられない。
`f` を `force_quit` に使うと **"Finder" が検索できなくなる**。そのため選択は `space`、
`force_quit` は `Ctrl-F`。`space` を使う都合上、**検索クエリに空白は入れられない**。
判定はソースに制御文字を直接書かずに済むよう、文字列ではなく序数（`ch.ord`）で行う。

`Ctrl-F` で `force_quit` を付けると**プリセットにも同時に追加**する。`force_quit` は
プリセットに対する修飾で、単独では効かないため（上の NOTE と同じ理由）。

> [!IMPORTANT]
> **`IO.console` は nil を返すことがある。** 制御端末を掴めない状況（擬似端末経由での起動など）で
> 起きる。`IO.console.winsize` を直接呼ぶと `NoMethodError` で落ちるので、`term_rows` で
> `$stdout.winsize` へフォールバックさせている。通常のターミナルでは再現しないため、
> PTY を使った自動テストで初めて表面化した。

> [!NOTE]
> 矢印キー（`\e[A`）と Esc 単独（取消）は先頭が同じなので、「続きが即座に来ているか」で見分ける
> （`ESC_SEQ_WAIT` = 0.1秒）。短くしすぎると低速な接続で矢印を取消と誤認し、長くすると
> Esc の反応が鈍く感じる。
>
> テストで PTY を使う場合、**エスケープシーケンスは1バイトずつ書いてはいけない**。
> 実端末は一括で送るので、分割して送ると必ず Esc 単独と誤判定される。

## リリース

方式はワークスペース共通（Keep a Changelog + SemVer、`CHANGELOG.md` の `[Unreleased]`、
**注釈付きタグ・`v` なしの数字のみ**）。手順は `projects-workspace` skill の **ルール4** を見ること。

このプロジェクト固有の点:

- Chrome 拡張の `manifest.json` にあたるものが無いので、**バージョンは `app-respawn` 冒頭の
  `VERSION` 定数**が持つ（`--version` で表示）。リリース時は定数・CHANGELOG・タグの3つを揃える
- **1.0.0 はブートストラップリリース**。それ以前にバージョンを切っていないため、全機能を
  「初回リリース」の1エントリにまとめた。`[x.y.z]: <url>` の比較リンク定義は置いていない

## 安全装置

- **自ターミナルの自動除外**: 親プロセスを遡って実行元アプリ（iTerm2 等）を特定し対象から外す。
  これを終了すると待機中にスクリプトごと殺され、後続処理に到達できないため
- **OS コンポーネントの除外**: Dock / SystemUIServer / ControlCenter / loginwindow は
  プリセットに書いても quit しない（`DENY_BUNDLE_IDS`）。メニューバーや Space の操作系が壊れるため。
  Finder は当初除外していたが、終了してもデータを失わず再起動も速いので対象に戻した
- **既定では強制終了しない**: `quit`（Apple Event）のみ。`--timeout` 内に終了しないアプリは
  保存ダイアログが出ている可能性があるものとして「要対応」に出し、**開き直しもしない**
- 既定ドライラン。`--apply` + 確認プロンプト（`--yes` で省略）

## `force_quit` — 未保存でも構わず閉じるアプリ

> [!NOTE]
> `force_quit` は**プリセットに対する修飾**であって、終了対象のリストではない。
> ここに書いただけでは何も起きず、`presets` 側にも入っていて初めて効く。

保存確認ダイアログで止まりやすく、かつ「止められるくらいなら破棄したい」アプリを bundle id で
指定する（Office 系・Preview・JetBrains IDE などが典型）。段階的に上げる:

1. **`quit saving no`**（Apple Event）— 保存ダイアログを出さずに破棄して**正常終了**する。
   Excel / Word / Numbers は `CocoaStandard.sdef` を include、Preview は独自 sdef を持たない
   （＝Cocoa 標準 Suite のみ）ため、いずれも `saving` パラメータに対応している
2. それでも残る場合 **SIGTERM** → 3秒待つ
3. まだ残る場合 **SIGKILL**

いきなり kill しないのは、**Office 系を強制 kill すると次回起動時に「ドキュメントの回復」
ダイアログが出て**、ウィンドウを畳み直す目的が台無しになるため。

ただし quit が **`-128`（終了確認ダイアログでキャンセルされた）** を返した場合は、待っても
状況が変わらないので `--timeout` を待たずに即 2. へ進む。RubyMine のように
*Confirm before exiting the IDE* が有効なアプリがこれに該当する。実測:

```
quit を拒否されました: rubymine (... ユーザによってキャンセルされました。 (-128))
終了を拒否されたまま動かないため、タイムアウトを待たずに強制終了へ移ります
強制終了に切り替えます(force_quit 指定)...
  SIGTERM: rubymine (pid 95424)
→ exit 0 / 所要 5秒（SIGKILL までは不要だった）
```

JetBrains IDE は sdef を持たないので `saving no` は効かず、確実に SIGTERM 経路になる。
JVM のシャットダウンフックが走るため状態は保存される（SIGKILL まで上がると保存されない）。

## 実行中のログをターミナルに出す（`--log-window`）

発火した瞬間に Terminal.app が開いてログが流れ、完了 5 秒後に自動で閉じる。普段は何も出ない。
plist に `--log-window` を渡してあるので自動実行時は既定で有効。

- ウィンドウ本体: `app-respawn-log.command`
- 追尾するファイル: `~/Library/Logs/app-respawn-current.log`（**その回専用**。毎回切り詰める）
- 起動判定マーカー: `~/Library/Logs/app-respawn-quit-terminal`

ウィンドウを閉じた後、**Terminal.app 本体も終了させる**。ただし元から Terminal を使っていた場合に
巻き込まないよう、`pgrep -x Terminal` で**未起動だった回だけ**マーカーを置き、その回に限って quit する。
さらに quit 直前に「他に可視ウィンドウが残っていない」ことも確認する（二重の歯止め）。

| 状況 | ウィンドウ | Terminal.app |
|---|---|---|
| Terminal 未起動から開いた | 閉じる | **終了する** |
| 既に Terminal を使っていた | 自分の窓だけ閉じる | 残す |

**共有ログを `tail -n 0` で追ってはいけない。** Terminal のコールドスタートは実測で約8秒かかり、
その間に本体が走り終わると、貼り付いた時には何も流れてこない（実際にこれで空振りした）。
その回専用ファイルを毎回作り直し、`tail -n +1` で**先頭から**読めば起動の遅れに影響されない。
本体の出力も `Open3.capture2e`（完了後にまとめて）ではなく `popen2e` で**逐次**流している。

> [!IMPORTANT]
> ウィンドウを閉じる `osascript` は、**自分のシェルが生きているうちに投げても効かない**。
> Terminal が「このウィンドウで実行中のプロセスを終了しますか?」を出して閉じずに止まる
> （エラーも返さないので気付きにくい）。`nohup bash -c "sleep 1; osascript ..." &` で
> バックグラウンドへ逃がし、先に `exit` してシェルを終わらせてから閉じさせること。

> [!NOTE]
> tail はプロセス置換 `< <(tail ...)` にすると pid が取れず、ウィンドウを閉じても残り続けて
> 実行のたびに1個ずつ溜まる。FIFO 経由にして pid を握り `trap ... EXIT HUP INT TERM` で始末する。
> `/bin/bash` は 3.2 なので `coproc` は使えない。
>
> 検証時の注意: Terminal の `count windows` は**閉じた後も 1 を返す**ことがある（幽霊オブジェクト）。
> 実際の有無は `count of (every window whose visible is true)` か System Events 側で見る。

## 外部モニター切断時の自動実行（launchd）

`--watch` で常駐し、**外部ディスプレイが全て外れて内蔵のみになった瞬間**に本体を自動実行する。
plist は `--relaunch` を渡していないので、**自動実行も「終了のみ」**。開き直しは自分で行う。

| 項目 | 値 |
|---|---|
| Label | `local.app-respawn` |
| plist テンプレート | `local.app-respawn.plist.template` |
| 生成先 | `~/Library/LaunchAgents/local.app-respawn.plist` |
| ログ | `~/Library/Logs/app-respawn.log` |
| 監視間隔 | 3秒（`--interval`）/ 検出後の待ち 5秒（`--settle`）/ 連続実行抑止 120秒（`--cooldown`） |

plist は **`setup` がテンプレートから生成する**。ruby の実体パスとスクリプトの絶対パスを
埋める必要があり、静的ファイルでは別マシンへ持ち運べないため。

```bash
# 停止して削除(PATH のリンクも消える)
~/projects/app-respawn/setup --uninstall --apply

# 状態確認 / ログ追尾
launchctl print gui/$(id -u)/local.app-respawn | grep -E 'state|pid'
tail -f ~/Library/Logs/app-respawn.log

# 設定変更後の再起動
launchctl kickstart -k gui/$(id -u)/local.app-respawn
```

プリセットの中身を変えるだけなら再起動不要（発火のたびに設定を読み直す）。ただし
**新しく追加したアプリへの Apple Event 許可の事前取得は常駐の起動時にしか行わない**ので、
アプリを足したら一度 `kickstart -k` しておくと、実際に外した時に許可ダイアログで詰まらない。

**検出方法**: `CGGetOnlineDisplayList` / `CGDisplayIsBuiltin` を Fiddle（標準ライブラリ）で直接呼ぶ。
`system_profiler` は遅く、System Events（Apple Event）は数秒ごとに投げたくない上に自動化の許可が要る。
CoreGraphics なら**許可不要・1回あたり1ms未満**で、しかも内蔵/外部を区別できるので
「枚数が1になった」ではなく「**外部が0になった**」を正確に判定できる。

## 踏んだ罠（同種のツールを作る時に必ず効く）

> [!IMPORTANT]
> **`CGGetActiveDisplayList` ではなく `CGGetOnlineDisplayList` を使うこと。**
> active は「いま描画可能」なので、**モニターがスリープしただけで一覧から外れる**。
> これで判定すると省電力で画面が消えた瞬間に「全部引き抜かれた」と誤認して暴発する。
> online は接続されていればスリープ中・ミラー中でも残るので、「物理的に外れたか」を正しく表す。

> [!IMPORTANT]
> **Apple Event の許可は (呼び出し元, 対象アプリ) の組ごと**に必要。ターミナルから手で実行したときの
> 許可は iTerm2 に対して付くので、launchd 配下の ruby には引き継がれない。そのため `--watch` は
> **起動時に対象アプリへ無害なイベントを1回ずつ投げて許可状態を確定させる**（未起動アプリは
> tell すると起動してしまうので対象外）。結果はログに出る:
> ```
> 自動化(Apple Event)の許可: OK
> 対象アプリへの Apple Event 許可: OK (起動中 9件を確認)
> ```
> ここが NG のまま放置すると、実際にモニターを外した瞬間に許可ダイアログが並んで終了に失敗する。

> [!CAUTION]
> **launchd 配下は `LANG` が渡らない。** 何も対策しないと Ruby の `Encoding.default_external` が
> `US-ASCII` になり、osascript が返す日本語のエラー文（例: `-609 接続は無効です`）を掴んだ瞬間に
> `String#strip` すら `Encoding::CompatibilityError` で落ちる。これで初回の自動実行が
> 「全アプリに quit は送ったが、待機もせず異常終了」した。対策は二重に入れてある:
> 1. スクリプト冒頭で `Encoding.default_external = Encoding::UTF_8`、外部コマンド出力は
>    すべて `utf8()`（`force_encoding` + `scrub`）を通す
> 2. plist の `EnvironmentVariables` に `LANG=ja_JP.UTF-8`
>
> 動作確認は `env -u LANG -u LC_ALL -u LC_CTYPE app-respawn ...` で launchd 相当を再現できる。
> ターミナルから普通に実行しても `LANG` があるため、この不具合は絶対に再現しない。

> [!CAUTION]
> **終了待ちの生存確認に System Events を使ってはいけない。** 一覧を
> `repeat with p in (every application process ...)` で舐めている最中にアプリが終了すると、
> `item N を取り出せません (-1719)` で落ちる。終了処理中は毎回この状況なので高確率で踏む。
> 生存確認は `Process.kill(0, pid)`（シグナル0＝権限チェックのみ、プロセスには何もしない）で行う。
> Apple Event の往復も無くなるので速い。一覧取得側も1件ずつ `try` で囲み、3回までリトライする。

> [!NOTE]
> Chrome は「前回開いていたタブを復元」設定でないと、終了でタブが失われる（`Cmd+Shift+T` か
> 「履歴 > 最近閉じたタブ」で手動復元は可能）。また RubyMine / iTerm2 のように**ウィンドウ位置を
> 自前で復元する**アプリは、外部モニター時代の座標を覚えていて期待した位置に来ないことがある。
