# EdgeAppSwitcher

macOSで起動中のアプリを切り替える、画面端の縦型アイコンバーです。個別ウィンドウではなくアプリ単位で表示します。

- 左右の画面端から表示し、外部ディスプレイではマウスを寄せた画面に表示します。
- 起動中の通常GUIアプリを最近使った順で表示します。表示中は並び順を固定し、多数のアプリはスクロールできます。
- 設定した2つのアプリを行き来するペア切替も利用できます。終了しているアプリは起動しません。
- ホバー時のアプリ名表示はありません。メニューバーの「切替バーを表示」からキーボードで操作できます。上下矢印／Home／Endで選択、Return／Spaceで切替、Escapeで閉じます。
- 設定では左右の選択、一時停止、アプリペアの登録ができます。

## 開発環境とビルド

最低対応OSの設定はmacOS 14です。AppKit／SwiftUIとAppleの標準フレームワークを使用し、外部依存パッケージはありません。XcodeとmacOS SDKが必要です。現在の動作確認環境はApple SiliconのmacOS 27.2です。macOS 14実機とIntel Macでの動作は未確認です。

リポジトリのルートで実行します。

```sh
xcodebuild -project EdgeAppSwitcher.xcodeproj -scheme EdgeAppSwitcher -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/Debug test
xcodebuild -project EdgeAppSwitcher.xcodeproj -scheme EdgeAppSwitcher -configuration Release -destination 'generic/platform=macOS' -derivedDataPath .build/Release ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
```

Releaseのアプリは `.build/Release/Build/Products/Release/EdgeAppSwitcher.app` に生成されます。元の開発環境ではDebugの120テストが成功し、arm64とx86_64を含むReleaseをビルドしました。配布版の試験結果は各Releaseの説明を参照してください。

## 動作範囲と配布上の注意

アプリ一覧の取得、ポインター位置の確認、アプリの通常のactivation、非表示アプリのunhideには標準APIを使用します。本アプリの現在の実装はアクセシビリティ・画面収録・Input Monitoringの権限を要求しません。OSの権限設定を変更する処理もありません。

非表示にしたアプリは再表示を試みます。最小化した個別ウィンドウをDockから復元する処理はありません。Spaces、フルスクリーン、Stage Manager、標準Dock、ホットコーナーとの組合せはmacOSの通常のactivationに従い、ウィンドウ配置を変更しません。あらゆる組合せでの表示・切替は保証されておらず、実機確認が必要です。VoiceOverの実際の読み上げを含むGUI受け入れ確認にも未確認項目があります。

ReleaseはHardened Runtimeを有効にしたad-hoc署名です。Developer ID署名・Appleによる公証は行っていません。一般配布向けにGatekeeperで受け入れられる成果物であることは保証できません。

## 権利とアイコン

このプロジェクトはMITライセンスで提供します。全文は `LICENSE` を参照してください。

アイコンは本アプリのために生成したAI画像で、由来と元画像のハッシュは `Artwork/README.md` に記載しています。この説明は法的な著作権判断ではありません。

## アプリのダウンロード

[GitHub Releases](https://github.com/hhlebe-png/EdgeAppSwitcher/releases) にアプリZIPを配布します。0.1.1はアニメーション・スクロールの修正版で、再配置時の位置保持、操作中の早すぎる収納、スクロールバーの隠れた余白を修正しています。

ダウンロード後にZIPを展開してアプリを任意のフォルダへコピーしてください。Developer ID署名・Apple公証はなく、Gatekeeperが起動を拒否する場合があります。セキュリティ保護の無効化やquarantine削除を求める配布ではありません。必要であれば公開ソースを確認してXcodeで自分のMac向けにビルドできます。
