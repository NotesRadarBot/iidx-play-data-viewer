# IIDX PLAY DATA

個人用のbeatmania IIDXプレイデータ閲覧アプリです。FlutterでiOS・Android・Windowsを対象にします。

## 現在実装済み（試作）

- PLAY DATA：SP/DP、譜面切替、スコア・DJ LEVEL・CLEAR・ノーツレーダー・ライバル比較
- MUSIC SELECT：フォルダ循環、ソート選択、レーダー一覧への導線
- NOTES RADAR LIST：SP/DP、属性タブ、135.00以上の一覧
- SETTING：PLAY DATA取込、RIVAL DATA取込、CONFIG、NOTES RADAR IMPORT
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
title,chart,score,clear,maxScore
BLUE HORIZON,ANOTHER,2847,EX HARD,3200
```
