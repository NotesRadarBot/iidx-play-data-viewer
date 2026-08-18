# 実装状況

## 実装済みの試作

- 横画面固定のFlutterアプリ本体
- TOP、PLAY DATA、NOTES RADAR LIST、SETTING TOP
- PLAY DATA / RIVAL DATA / CONFIG / NOTES RADAR IMPORTの各設定画面
- SP・DP切替、譜面表示、DJ LEVEL・CLEAR色、ライバル順位表示
- ノーツレーダー六角形（基準150.00、最大値と自分の値の2行表示）
- MUSIC SELECTフォルダ、ソートメニュー、フォルダ表示ON/OFF
- CSVテキスト貼付による試作取込と取込確認

## 次の実装段階

1. `flutter create .` によるWindows / Android / iOSプロジェクト生成
2. SQLite（drift等）による端末内永続化
3. `file_picker` によるCSVファイル選択
4. 公式CSVの実サンプルに沿った列マッピングとエラー表示
5. Cloudflare R2の実ドメイン確定後、manifest.json / ZIP / SHA-256検証を接続
6. Android SDK・Xcodeを用いた各端末ビルド

## 現在のローカル環境

Flutter SDKは `C:\Users\tachi\scoop\apps\flutter\current` に導入済みです。
SDKキャッシュの一時ロックが残っている場合は、実行中のFlutter/Dartプロセスが無いことを確認したうえで、次を一度実行してください。

```powershell
Remove-Item 'C:\Users\tachi\scoop\apps\flutter\current\bin\cache\lockfile'
flutter create .
flutter pub get
flutter run -d windows
```

この作業ディレクトリの実行環境にはSDK外のロックファイルを削除する権限がないため、ここだけはローカルの所有者アカウントで実行する必要があります。
