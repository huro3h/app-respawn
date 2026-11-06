# app-respawn

外部モニターを外したときに、プリセットで指定した macOS の GUI アプリをまとめて graceful quit する個人用ツール。

外部ディスプレイを抜くと、そこに置いていたウィンドウが1画面に重なったり別の Space に散らばって毎回探すことになる。
macOS の Space はプライベート API 経由でしか操作できず、既存ツールは SIP の部分無効化を前提とする。
SIP を有効なままにしたいので、この方針は採れない。
そこで**ウィンドウを追いかけるのをやめて、対象アプリをきれいに終了する**アプローチを取っている。

既定は**終了のみ**で、開き直しは手作業。`--relaunch` を付けたときだけ現在の画面で起動し直す。

## 主な機能

- プリセット（bundle id の配列）単位でアプリを一括終了。既定はドライラン
- 未保存を破棄してよいアプリだけ `force_quit` 指定で段階的に強制終了（`quit saving no` → SIGTERM → SIGKILL）
- 実行元のターミナルや Dock などの OS コンポーネントは、プリセットに書かれていても対象外
- `--watch` で常駐し、**外部ディスプレイが全て外れた瞬間**に自動実行（launchd LaunchAgent）
- `--log-window` で実行時に Terminal を開いて進捗を表示、完了後に自動で閉じる
- `--config` でインストール済みアプリを絞り込みながら対話的にプリセットを編集
- `--max-spaces N` で、アプリを終了させた後に操作スペース（Space / バーチャルデスクトップ）を N 枚以下に減らす

## セットアップ

```bash
./setup            # 生成先/リンク先の確認(ドライラン)
./setup --apply    # LaunchAgent の登録と PATH へのリンク作成
```

`setup --apply` は以下を行う。

1. `~/Library/LaunchAgents/local.app-respawn.plist` をテンプレートから生成して `launchctl` に読み込ませる
2. PATH の通ったディレクトリ（`/opt/homebrew/bin` → `/usr/local/bin` → `~/bin` の順で最初に書き込めるもの）に本体へのシンボリックリンクを張る

リンクが不要なら `--no-link`、まとめて解除するなら `./setup --uninstall --apply`。

設定ファイルは手元の環境に固有なのでリポジトリに含まれない。雛形から作る。

```bash
app-respawn --config                           # 対話的に選ぶ(おすすめ)
cp app-respawn.example.json app-respawn.json   # 雛形をコピーして手で編集
app-respawn --init --apply                     # 起動中のアプリからまとめて生成
```

### 必要な許可

| 許可 | 何に要るか | 場所 |
|---|---|---|
| 自動化（Apple Event） | アプリの終了 | プライバシーとセキュリティ > 自動化 |
| アクセシビリティ | `--max-spaces` の操作スペース削減のみ | プライバシーとセキュリティ > アクセシビリティ |

常駐(launchd)で動くときの許可は、入口の `app-respawn-launcher`(`setup` が `build/` にビルドする)に付く。
アクセシビリティは**別枠**で、`app-respawn-launcher` と `osascript` の**両方**の登録が要る。詳細は
[操作スペースの削減](#操作スペースの削減)を参照。無くても終了処理は動き、削減だけがスキップされる。

### ダウンロードで持ち込んだ場合は隔離属性を外す

Slack や zip で受け取ったファイル、および Sourcetree が clone したファイルには
`com.apple.quarantine` が付く（コマンドラインの `git clone` では付かない）。`--log-window` は
`app-respawn-log.command` を `open` で開くため、この属性が残っていると Gatekeeper に止められ、
「開いていません／マルウェアが含まれていないことを検証できませんでした」のダイアログが出て
**ログウィンドウが開かない**（本体の終了処理自体は動く）。

```bash
xattr -dr com.apple.quarantine .    # このディレクトリ配下から削除
```

`.git/objects` は read-only なので `Permission denied` で失敗するが、git object は実行されないため
放置してよい。`~/Downloads` など出所の混ざる場所に同じ操作をしないこと。

### 設置後の確認

`--watch` は起動時に許可状態を確定させ、結果をログに残す。3行とも OK になっていれば設置は完了。

```bash
launchctl kickstart -k gui/$(id -u)/local.app-respawn
tail -4 ~/Library/Logs/app-respawn.log
```

```
watch 開始: ディスプレイ 2枚(外部 1枚) preset=default interval=3.0s settle=5.0s
自動化(Apple Event)の許可: OK
対象アプリへの Apple Event 許可: OK (起動中 9件を確認)
アクセシビリティ(UI スクリプティング)の許可: OK
```

## 使い方

```bash
app-respawn --list                 # 起動中の GUI アプリと bundle id を確認
app-respawn                        # ドライラン(対象の確認だけ)
app-respawn --apply                # 終了のみ実行(確認プロンプトあり)
app-respawn --apply --relaunch     # 終了して現在の画面で開き直す
app-respawn --apply --max-spaces 3 # 終了後、操作スペースを3枚以下に減らす
app-respawn --config               # 対話的にプリセットを編集
app-respawn --init --apply         # いま起動中のアプリから設定ファイルを生成
```

終了コード: `0` = 全て終了できた / `1` = ドライラン、または残存・失敗あり / `2` = エラー

## 設定

`app-respawn.json`（`.gitignore` 済み）の `presets` にプリセット名 → bundle id の配列を書く。
リポジトリに入っているのは雛形の `app-respawn.example.json` だけなので、それをコピーするか
`--config` / `--init` で生成する。

### `--config` — 対話的に編集する

インストール済みアプリを一覧して、絞り込みながら選ぶ。bundle id を自分で調べる必要がない。

```
検索: chrome    4/124件   選択 6件   [default]

 > [x]   Google Chrome           com.google.Chrome          ●
   [ ]   Google Chrome Beta      com.google.Chrome.beta
   [ ] F Google Chrome Canary    com.google.Chrome.canary
   [ ]   Google Chrome Dev       com.google.Chrome.dev      ●
```

| キー | 動作 |
|---|---|
| 文字入力 | 絞り込み（アプリ名と bundle id の両方が対象） |
| ↑↓ / `^P` `^N` | カーソル移動 |
| `space` | プリセットへの追加/削除 |
| `^F` | `force_quit` の指定/解除（未指定ならプリセットにも同時に追加） |
| `^U` | 検索クリア |
| `Enter` | 保存 |
| `Esc` / `^C` | 取消（ファイルは変更しない） |

絞り込みに文字入力を使う都合上、トグルは制御キーに割り当てている（`f` を使うと "Finder" が
検索できなくなるため）。同じ理由で検索クエリに空白は入れられない。

`--preset NAME` で編集対象のプリセットを選べる。指定しなければ `default`。
他のプリセットや、設定にあるがインストールされていない bundle id はそのまま保持される。
並び順（＝終了/起動の順序）を変えたいときは JSON を直接編集する。
並び順が終了/起動の順序で、`--relaunch` 時は先頭のアプリが最後に前面へ戻る。
`force_quit` は「プリセットに入っているアプリのうち、未保存を破棄してよいもの」の指定で、
ここに書くだけでは終了対象にはならない。

環境変数 `APP_RESPAWN_CONFIG` でパスを上書きできる。

プリセットの中身を変えるだけなら常駐の再起動は不要（発火のたびに読み直す）。
ただし**新しく追加したアプリへの Apple Event 許可の事前取得は常駐の起動時にしか行わない**ので、
アプリを足したら一度だけ以下を実行しておくと、実際にモニターを外したときに許可ダイアログで詰まらない。

```bash
launchctl kickstart -k gui/$(id -u)/local.app-respawn
```

```bash
# 状態確認 / ログ追尾
launchctl print gui/$(id -u)/local.app-respawn | grep -E 'state|pid'
tail -f ~/Library/Logs/app-respawn.log
```

## 操作スペースの削減

`--max-spaces N` を付けると、アプリの終了処理が終わった後に各ディスプレイの通常デスクトップを
N 枚以下に減らす。先にアプリを終了させているので、閉じる操作スペースは空になっており、
行き場を失うウィンドウが出ない。

**フルスクリーンのアプリは対象外**。フルスクリーンの操作スペースを閉じるとフルスクリーンが
解除されてしまうため、通常のデスクトップだけを末尾から減らす。

**アクセシビリティの許可が別に要る。** Mission Control の UI を叩くので、自動化（Apple Event）とは
別枠で「アクセシビリティ」の許可が必要になる。システム設定 > プライバシーとセキュリティ >
アクセシビリティ に、**app-respawn-launcher と osascript の両方**を追加する。

```
/Users/<user>/projects/app-respawn/build/app-respawn-launcher
/usr/bin/osascript
```

`+` を押して `Cmd+Shift+G` でパスを貼り付ける。osascript だけでは通らない。TCC は**責任プロセス**で
可否を判定し、launchd ジョブの子プロセスはジョブ先頭のプロセス（＝app-respawn-launcher）を責任プロセスとして
引き継ぐため、launcher が一覧に無いと子の ruby・osascript ごと拒否される。エラーは `osascript` を名乗るが、
見られているのは先頭の方。

launcher を挟んでいるのは、**Ruby を上げても許可が切れないようにするため**。ruby をジョブの先頭にすると、
ad-hoc 署名の識別子がバイナリのハッシュなので、rbenv で Ruby を上げるたびに許可が無効になる。
launcher は rbenv の shim 経由で ruby を起動するので、Ruby を上げても plist も許可もそのままでよい。
逆に **launcher を作り直すとハッシュが変わり、許可が切れる**。`setup` はソースが変わったときだけビルドする。

許可がないと `--watch` の起動時ログに次が出て、**削減だけがスキップされる**（アプリの終了は動く）。

```
アクセシビリティ(UI スクリプティング)の許可: NG — ... osascriptには補助アクセスは許可されません。 (-25211)
```

LaunchAgent は `--max-spaces 3` を渡しているので、外部モニターを外したときの自動実行にも適用される。
枚数を変えたい場合は `local.app-respawn.plist.template` を編集して `./setup --apply` をやり直す。

## 構成

| ファイル | 役割 |
|---|---|
| `app-respawn` | 本体（Ruby、標準ライブラリのみ） |
| `app-respawn.example.json` | プリセット定義の雛形（実体の `app-respawn.json` は `.gitignore`） |
| `app-respawn-log.command` | `--log-window` で開くログ追尾ウィンドウ |
| `app-respawn-launcher.swift` | LaunchAgent の入口。ruby を子として起動する（TCC の許可はこれに付く） |
| `local.app-respawn.plist.template` | LaunchAgent のテンプレート |
| `setup` | launcher のビルド、LaunchAgent の登録と PATH リンクの作成/削除 |

パスはスクリプトの実体位置から相対で解決しているので、ディレクトリごとどこへ移動しても動く。

実装の詳細・設計判断・ハマりどころは `.claude/skills/app-respawn/SKILL.md` を参照。

## 要件

macOS / Ruby（追加の gem は不要）

## ライセンス

[MIT License](LICENSE)
