# IIDX PLAY DATA

個人用のbeatmania IIDXプレイデータ閲覧アプリです。FlutterでiOS・Android・Windowsを対象にします。
※現在はWindowsのみ動作確認中

## 現在実装済み（試作）

- PLAY DATA：SP/DP、譜面切替、スコア・DJ LEVEL・CLEAR・ノーツレーダー・ライバル比較
- MUSIC SELECT：フォルダ循環、ソート選択、レーダー一覧への導線
- NOTES RADAR LIST：SP/DP、属性タブ、135.00以上の一覧
- SETTING：PLAY DATA取込、RIVAL DATA取込、CONFIG、NOTES RADAR IMPORT（楽曲、ノーツレーダー情報取込）
- CSVテキスト貼付取込の検証・登録（試作フォーマット）

## 起動手順

Flutter SDK導入後、このフォルダで実行します。

```powershell
flutter pub get
flutter create .
flutter run -d windows
```

Android / iOSの実機・エミュレーター設定、ファイル選択によるCSV取込、SQLite永続化、Cloudflare R2の実サーバー連携は次の実装段階です。

## CSV貼付の試作フォーマット

```csv
バージョン,タイトル,ジャンル,アーティスト,プレー回数,BEGINNER 難易度,BEGINNER スコア,BEGINNER PGreat,BEGINNER Great,BEGINNER ミスカウント,BEGINNER クリアタイプ,BEGINNER DJ LEVEL,NORMAL 難易度,NORMAL スコア,NORMAL PGreat,NORMAL Great,NORMAL ミスカウント,NORMAL クリアタイプ,NORMAL DJ LEVEL,HYPER 難易度,HYPER スコア,HYPER PGreat,HYPER Great,HYPER ミスカウント,HYPER クリアタイプ,HYPER DJ LEVEL,ANOTHER 難易度,ANOTHER スコア,ANOTHER PGreat,ANOTHER Great,ANOTHER ミスカウント,ANOTHER クリアタイプ,ANOTHER DJ LEVEL,LEGGENDARIA 難易度,LEGGENDARIA スコア,LEGGENDARIA PGreat,LEGGENDARIA Great,LEGGENDARIA ミスカウント,LEGGENDARIA クリアタイプ,LEGGENDARIA DJ LEVEL,最終プレー日時
1st&substream,22DUNK,TECHNO,SLAKE,0,0,0,0,0,---,NO PLAY,---,3,0,0,0,---,NO PLAY,---,4,0,0,0,---,NO PLAY,---,5,0,0,0,---,FULLCOMBO CLEAR,---,0,0,0,0,---,NO PLAY,---,2025-09-17 13:57
```
