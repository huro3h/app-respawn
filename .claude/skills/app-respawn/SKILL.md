---
name: app-respawn
description: 外部モニターを外した時に、プリセット指定した macOS の GUI アプリを graceful quit する個人ツール app-respawn の使い方・設定・launchd 常駐。「モニターを外すとウィンドウが散る/重なる」「アプリを一括終了したい」「バーチャルデスクトップ(Space)」「ディスプレイ切断で自動実行」の話題、force_quit やプリセットの編集、および macOS の Apple Event(自動化)権限・launchd 常駐・CoreGraphics でのディスプレイ判定を扱う時に参照。
---

# `app-respawn` — プリセットのアプリを graceful quit（既定は終了のみ）

実体: `~/projects/app-respawn/`（本体・設定・plist テンプレート・`setup` を同階層に置いた自己完結ディレクトリ）

> [!IMPORTANT]
> **現状（2026-09-02 時点）**
>
> 1.1.0 をリリース済み（タグと push まで完了）。LaunchAgent は `--max-spaces 3` を渡す形で稼働し、
> 起動時ログの許可3行はすべて OK。**積み残しは無い。**
>
> `--watch` からの発火で削減まで通ることを、実際に外部モニターを抜いて確認済み（02:00:31）。
> 13枚 → 3枚が 12 秒で完了した。うち先頭の約5秒は plist が UI に追いつくのを待つ時間で、
> 削除10回は約6秒。
>
> **教訓: この機能は手動実行では検証できない。** 1.1.0 の開発で踏んだ4件は、すべて
> 「launchd 配下」「外部モニターを外した直後」という本番条件でしか出なかった。
> ターミナルから `--max-spaces` を直接叩く検証は全て通っていたので、実装した当日は
> 「実機で検証済み」と判断していた。詳細は下の「操作スペースの削減」と「踏んだ罠」に集約してある。
>
> 検討したが**採用しなかった**代替案: AeroSpace（ネイティブ Space を使わないため散乱自体が
> 起きないが、タイル型で作業様式が変わる。フローティング主体の運用は既知の弱点）、
> yabai（SIP の部分無効化と macOS 更新ごとの `--load-sa` 再実行が必要）。

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

設置後は常駐を入れ直して、起動時ログの許可3行を見る。ここが揃っていれば設置は完了。

```bash
launchctl kickstart -k gui/$(id -u)/local.app-respawn && tail -4 ~/Library/Logs/app-respawn.log
```

```
watch 開始: ディスプレイ 2枚(外部 1枚) preset=default interval=3.0s settle=5.0s
自動化(Apple Event)の許可: OK
対象アプリへの Apple Event 許可: OK (起動中 9件を確認)
アクセシビリティ(UI スクリプティング)の許可: OK
```

必要な許可は2種類で、**アクセシビリティは `--max-spaces` を使う時だけ**要る（無くても終了処理は
動き、削減だけがスキップされる）。ダウンロードで持ち込んだ場合は `com.apple.quarantine` も外す。
それぞれ「操作スペースの削減」「実行中のログをターミナルに出す」の節を参照。

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

## 操作スペースの削減 `--max-spaces`

アプリの終了が終わった後に、各ディスプレイの通常デスクトップを N 枚以下に減らす。
終了を先に済ませてあるので閉じる Space は空で、行き場を失うウィンドウが出ない。
LaunchAgent には `--max-spaces 3` を渡してある。

> **アクセシビリティ（UI スクリプティング）の許可は自動化とは別枠**で、`ruby` と `osascript` の
> **両方**を許可する必要がある。2026-09-02 に踏んだ。切り分けの実測はこうだった。
>
> | 経路 | 結果 |
> |---|---|
> | launchd → `osascript` を直接 | OK |
> | launchd → `ruby` → `osascript` | `-25211 osascriptには補助アクセスは許可されません` |
>
> TCC は**責任プロセス**で判定し、launchd ジョブの子はジョブ先頭のプロセスを責任プロセスと
> して引き継ぐ。よって osascript だけ許可しても通らない。エラーは osascript を名乗るので紛らわしい。
> ターミナルから手で実行すると責任プロセスは iTerm2 になるため、**手動検証では再現しない**。
>
> **ジョブの先頭は `build/app-respawn-launcher`(Swift)にしてある**(2026-11-06〜)。以前は ruby を先頭にしていて、
> Ruby を上げるたびに許可が切れていた。ローカルでビルドした ruby は ad-hoc 署名で、指定要件が
> `cdhash H"..."`(バイナリのハッシュ)なので、パスを shim やシンボリックリンクにしても防げない。
> launcher は rbenv の shim(`~/.rbenv/shims/ruby`)経由で ruby を子として起動し、SIGTERM/INT/HUP を子へ渡す。
> 許可(自動化・アクセシビリティ)は launcher に付くので、Ruby を上げても plist も許可もそのままでよい。
> **launcher を作り直すとハッシュが変わって許可が切れる**ので、`setup` は未ビルドかソースが新しいときだけビルドする。
> 許可の状態は `--watch` の起動時に1回読んでログへ残すので、作り直した後は起動時ログを見ること。

**Space を作成・削除する公開 API は存在しない**（2007年の導入以来ずっと）。非公開の
`SkyLight` は WindowServer が Dock からの要求しか受け付けず、yabai が SIP の部分無効化を
要求するのはこのため。そこで **Mission Control の UI をアクセシビリティ経由で叩く**。

> [!NOTE]
> 各デスクトップのタイルは **`AXRemoveDesktop` アクション**を持っている。サムネイルに
> ホバーして「×」の座標をクリックする、といった再現は不要。UI 階層は:
> ```
> process "Dock" → group 1 ("Mission Control")
>   └ UI element i          ← ディスプレイごと
>       ├ [1] AXGroup "Exposéウインドウ"
>       └ [2] AXGroup "スペースバー"
>             ├ list 1      ← 子要素が各デスクトップのタイル
>             └ AXButton "デスクトップを追加"
> ```

> [!CAUTION]
> **フルスクリーンのタイルも `AXRemoveDesktop` を持つ。** アクションの有無では判別できない。
> 閉じるとアプリのフルスクリーンが解除されるので、**`com.apple.spaces.plist` の `type`**
> （0 = 通常のデスクトップ / 4 = フルスクリーン）で除外する。plist の並び順は
> Mission Control のタイル順と一致する。UI 側の名前も判別に使える（通常は "デスクトップN"、
> フルスクリーンはアプリ名）が、ローカライズ依存なので照合の保険としてのみ使う。
> plist と UI で枚数が食い違ったら、対応がずれている証拠なので**必ず中断する**。
>
> ただし**外部ディスプレイを外した直後は、必ず食い違う**。Mission Control は全ての Space を
> 1画面にまとめて表示するのに対し、plist は外したモニターの分をぶら下げたまま残す
> （実測: UI 1画面12枚 / plist `[5, 7]`）。この瞬間こそがこのツールの本番なので、
> `align_layout` は**合計が一致するなら連結して1画面に対応させる**。並び順は推定になるため、
> まとめ表示のときだけ「名前から数えたデスクトップ数」と突き合わせて裏を取る。

> [!CAUTION]
> **成否の判定に plist を使ってはいけない。** Dock はファイルへの書き込みを遅延させる。
> 実測で、UI 上は既に 2枚になっているのにファイルはまだ 4枚のままだった。
> 削除できたかどうかは **UI 上のタイル数が1つ減ったか**で判定すること。
>
> **遅延は対応づけにも効く。** 追いつくまでを計ったら **6.65 秒**かかった。UI と plist の
> 枚数を突き合わせる安全装置は、この間ずっと不一致を見ることになり、待たずに判定すると
> 「構成が一致しないため中断」で毎回終わる。`await_layout` が最大 15 秒、0.5 秒間隔で
> plist を読み直して一致を待つ（Mission Control を開いたままでも Dock は書き出す）。

> [!IMPORTANT]
> **Mission Control の開閉はトグル。** 既に開いている状態で `open -a "Mission Control"` を
> 投げると閉じてしまい、直後の `group 1` 参照が `-1719` で落ちる。開く前に必ず
> `count of groups` で状態を見る。エラー経路でも必ず閉じること（`ensure`）。

> [!CAUTION]
> **操作間隔を詰めると画面が固まる。** 0.4秒間隔かつ削除のたびに開き直す実装で、
> WindowServer が詰まって Mac が操作不能になった（`killall Dock` で復帰）。
> **Mission Control は1回だけ開いて中で全部済ませる**のが大前提。
>
> 待ち方は固定秒ではなく、**タイル数が実際に減るのを 0.1 秒間隔で見張り、減ってから 0.2 秒
> 置いて次を投げる**（`SPACE_REMOVE_TIMEOUT` / `SPACE_POLL_INTERVAL` / `SPACE_REMOVE_SETTLE`）。
> UI の更新を確認してから次に進むので、アニメーションを追い越して詰まらせることがない。
> 固定1秒より速く、かつ遅いマシンでは自動的に待つ。実測 A/B（12枚 → 3枚、削除9回）:
>
> | 実装 | 所要 |
> |---|---|
> | 固定 1.0 秒 | 12.9 秒 |
> | 減るまで待つ | 6.5 秒 |

> [!NOTE]
> AppleScript の予約語に注意。`before` と `row` は変数名に使えない
> （`row` は「テーブル行」と解釈され `-10003 アクセスが許可されていません` になる）。
> 原因が分かりにくいので、詰まったら変数名を疑う。

UI 階層に依存するので **macOS の更新で壊れうる**。壊れたときに黙って進まないよう、
枚数が減らなければ即中断し、削除前にタイル名を照合している。

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

発火した瞬間に Terminal.app が開いてログが流れ、完了 1 秒後に自動で閉じる。普段は何も出ない。
plist に `--log-window` を渡してあるので自動実行時は既定で有効。

- ウィンドウ本体: `app-respawn-log.command`
- 追尾するファイル: `~/Library/Logs/app-respawn-current.log`（**その回専用**。毎回切り詰める）
- 起動判定マーカー: `~/Library/Logs/app-respawn-quit-terminal`

> [!CAUTION]
> **`com.apple.quarantine` が付いているとウィンドウが開かない。** `open` 経由で `.command` を
> 起動するので Gatekeeper の検査対象になり、「開いていません／検証できませんでした」の
> ダイアログで止まる。本体は `ruby app-respawn` として直接動くため同じ属性があっても素通りし、
> **ログウィンドウだけが出ない**という分かりにくい壊れ方をする。
> `xattr -dr com.apple.quarantine <ディレクトリ>` で外す。Slack や zip で受け取った場合のほか、
> **Sourcetree が clone したファイルにも付く**（コマンドラインの `git clone` では付かない）。
>
> なお `File.executable?(LOG_WINDOW)` のガードがあるので、ファイル自体が無い場合も
> **黙ってスキップ**される。ログにも何も出ないので、開かない時はまずファイルの有無と属性を見る。

ウィンドウを閉じた後、**Terminal.app 本体も終了させる**。ただし元から Terminal を使っていた場合に
巻き込まないよう、`pgrep -x Terminal` で**未起動だった回だけ**マーカーを置き、その回に限って quit する。
さらに quit 直前に「他に可視ウィンドウが残っていない」ことも確認する（二重の歯止め）。

| 状況 | ウィンドウ | Terminal.app |
|---|---|---|
| Terminal 未起動から開いた | 閉じる | **終了する** |
| 既に Terminal を使っていた | 自分の窓だけ閉じる | 残す |
| プリセットに Terminal が入っている | 閉じる | **他の窓があっても終了する**（マーカーの中身が `preset`） |

> [!CAUTION]
> **プリセットに Terminal があっても、子プロセスに Terminal を quit させてはいけない。** ログ窓の bash が
> 動いているので「このウインドウで実行中のプロセスを終了しますか?」で止まり、終了待ちのまま進まなくなる
> （issue #1）。自ターミナルの除外は親プロセスを遡る方式なので、launchd 起動ではログ窓の Terminal を検出できない。
> そこで `--log-window` の回は子へ `--keep com.apple.Terminal` を渡して外し、ログ窓が閉じたあとに
> `app-respawn-log.command` 側で quit する。なお判定に使うプリセットは**常駐の起動時に読んだもの**なので、
> プリセットへ Terminal を足したら `kickstart -k` すること（しないと Terminal は残ったままになる）。

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

plist は **`setup` がテンプレートから生成する**。launcher・ruby(rbenv の shim)・スクリプトの絶対パスを
埋める必要があり、静的ファイルでは別マシンへ持ち運べないため。shim は rbenv 本体を絶対パスで呼ぶので、
launchd の痩せた PATH でも global のバージョンに解決できる(2026-11-06 に `launchctl submit` で確認)。

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
> **手動実行では再現しない不具合が繰り返し出る。** このツールの本番は「launchd 配下」かつ
> 「外部モニターを外した直後」で、ターミナルからの手動実行はそのどちらも満たさない。
> 実際に踏んだのは `LANG` が渡らない件、Apple Event の許可主体、アクセシビリティの責任プロセス、
> 切断直後の UI と plist のずれ、plist の書き出し遅延で、**いずれも手動実行では全て通っていた**。
> 検証は `launchctl submit` などで launchd 相当の文脈を作るか、実際にモニターを抜いて行うこと。
> `--watch` の起動時チェックがログに残す3行は、この文脈でしか分からない情報を先出しするためにある。

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
