import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class AppRepository {
  // v1はCSV表記ゆれをそのまま楽曲として追加していた旧保存形式。
  // この更新で一度破棄し、登録済み楽曲マスタだけを基準に再取込する。
  static const _legacyPlayRecordsKey = 'play_records_v1';
  static const _playRecordsKey = 'play_records_v2';
  static const _rivalDataKey = 'rival_data_v1';
  AppRepository({String? playerDjName}) : _playerDjName = playerDjName;

  String? _playerDjName;
  String? get playerDjName => _playerDjName;

  void setPlayerDjName(String? value) {
    _playerDjName = _sanitizeDjName(value);
  }

  /// DJ NAMEは公式の入力形式に合わせ、空白を含まない半角の表示可能文字だけを保持する。
  String? _sanitizeDjName(String? value) {
    final ascii = String.fromCharCodes((value ?? '')
        .codeUnits
        .where((code) => code >= 0x21 && code <= 0x7e)).toUpperCase();
    final normalized = ascii.length > 6 ? ascii.substring(0, 6) : ascii;
    return normalized.isEmpty ? null : normalized;
  }

  final List<Chart> charts = [
    Chart(
      id: 'blue-sp-b',
      songTitle: 'BLUE HORIZON',
      genre: 'FUTURE SKY TRANCE',
      artist: 'AURORA LANE',
      version: 'EPOLIS',
      bpm: '150 BPM',
      style: PlayStyle.sp,
      type: ChartType.beginner,
      level: 3,
      maxScore: 1200,
      maxRadar: RadarValues(
          notes: 78.12,
          chord: 55.91,
          peak: 64.30,
          charge: 26.18,
          scratch: 18.42,
          sofLan: 10.00),
    ),
    Chart(
      id: 'blue-sp-n',
      songTitle: 'BLUE HORIZON',
      genre: 'FUTURE SKY TRANCE',
      artist: 'AURORA LANE',
      version: 'EPOLIS',
      bpm: '150 BPM',
      style: PlayStyle.sp,
      type: ChartType.normal,
      level: 7,
      maxScore: 2200,
      maxRadar: RadarValues(
          notes: 112.63,
          chord: 98.41,
          peak: 101.20,
          charge: 49.12,
          scratch: 52.31,
          sofLan: 72.20),
    ),
    Chart(
      id: 'blue-sp-h',
      songTitle: 'BLUE HORIZON',
      genre: 'FUTURE SKY TRANCE',
      artist: 'AURORA LANE',
      version: 'EPOLIS',
      bpm: '150 BPM',
      style: PlayStyle.sp,
      type: ChartType.hyper,
      level: 10,
      maxScore: 2800,
      maxRadar: RadarValues(
          notes: 146.05,
          chord: 133.20,
          peak: 151.80,
          charge: 84.32,
          scratch: 81.00,
          sofLan: 104.22),
    ),
    Chart(
      id: 'blue-sp-a',
      songTitle: 'BLUE HORIZON',
      genre: 'FUTURE SKY TRANCE',
      artist: 'AURORA LANE',
      version: 'EPOLIS',
      bpm: '150 BPM',
      style: PlayStyle.sp,
      type: ChartType.another,
      level: 12,
      maxScore: 3200,
      maxRadar: RadarValues(
          notes: 170.12,
          chord: 160.75,
          peak: 184.23,
          charge: 110.22,
          scratch: 95.80,
          sofLan: 130.45),
    ),
    Chart(
      id: 'blue-sp-l',
      songTitle: 'BLUE HORIZON',
      genre: 'FUTURE SKY TRANCE',
      artist: 'AURORA LANE',
      version: 'EPOLIS',
      bpm: '150 BPM',
      style: PlayStyle.sp,
      type: ChartType.leggendaria,
      level: 12,
      maxScore: 3500,
      maxRadar: RadarValues(
          notes: 191.40,
          chord: 170.75,
          peak: 197.60,
          charge: 142.22,
          scratch: 128.00,
          sofLan: 155.55),
    ),
    Chart(
      id: 'blue-dp-a',
      songTitle: 'BLUE HORIZON',
      genre: 'FUTURE SKY TRANCE',
      artist: 'AURORA LANE',
      version: 'EPOLIS',
      bpm: '150 BPM',
      style: PlayStyle.dp,
      type: ChartType.another,
      level: 12,
      maxScore: 3600,
      maxRadar: RadarValues(
          notes: 177.20,
          chord: 157.60,
          peak: 181.10,
          charge: 130.30,
          scratch: 125.40,
          sofLan: 138.00),
    ),
  ];

  final List<PlayRecord> _records = [];
  final List<RivalRecord> _rivalRecords = [];
  Map<String, String> _titleAliases = const {};
  // フォルダ展開時に全レコードを何度も走査しないための参照索引。
  // CSV取込・削除時だけ無効化して、通常表示は O(1) で引けるようにする。
  Map<String, PlayRecord>? _latestPlayRecordByChartId;
  Map<String, PlayRecord>? _bestPlayRecordByChartId;
  Map<String, PlayRecord>? _historicalBestPlayRecordByChartId;
  Map<String, RivalRecord>? _latestRivalRecordByChart;
  // 旧版が作成した未一致CSV行を退避しておく領域。以後は表示用マスタへ
  // 追加しないため、表記ゆれによる重複楽曲を画面に出さない。
  final List<Chart> _userCharts = [];
  final List<RivalProfile> rivals = List.generate(
      10,
      (index) => index < 3
          ? RivalProfile(
              slot: index + 1,
              djName: const ['AURORA', 'SOLAR', 'LUNAR'][index],
              spImported: true,
              dpImported: true)
          : RivalProfile(slot: index + 1, djName: null));

  void _invalidateRecordIndexes() {
    _latestPlayRecordByChartId = null;
    _bestPlayRecordByChartId = null;
    _historicalBestPlayRecordByChartId = null;
    _latestRivalRecordByChart = null;
  }

  /// 旧実装で残っている可能性があるライバルの複数世代を整理する。
  /// ライバルは各枠・SP/DPごとに最新1世代だけを保持する仕様。
  void _trimRivalHistories() {
    final latestBySlotAndStyle = <String, String>{};
    for (final record in _rivalRecords) {
      final key = '${record.slot}|${record.style.name}';
      final version = record.dataVersion ?? record.version;
      final current = latestBySlotAndStyle[key];
      if (current == null || _compareIidxVersions(version, current) > 0) {
        latestBySlotAndStyle[key] = version;
      }
    }
    _rivalRecords.removeWhere((record) {
      final key = '${record.slot}|${record.style.name}';
      return (record.dataVersion ?? record.version) !=
          latestBySlotAndStyle[key];
    });
  }

  Map<String, PlayRecord> get _playRecordIndex {
    final existing = _latestPlayRecordByChartId;
    if (existing != null) return existing;
    final index = <String, PlayRecord>{};
    for (final record in _records) {
      final current = index[record.chartId];
      if (current == null ||
          _compareIidxVersions(record.dataVersion ?? record.version,
                  current.dataVersion ?? current.version) >
              0) {
        index[record.chartId] = record;
      }
    }
    return _latestPlayRecordByChartId = index;
  }

  /// 同一譜面の歴代データから最高スコアを返す。同点なら古い版を採用する。
  Map<String, PlayRecord> get _bestPlayRecordIndex {
    final existing = _bestPlayRecordByChartId;
    if (existing != null) return existing;
    final index = <String, PlayRecord>{};
    for (final record in _records) {
      final current = index[record.chartId];
      if (current == null ||
          record.score > current.score ||
          (record.score == current.score &&
              _compareIidxVersions(record.dataVersion ?? record.version,
                      current.dataVersion ?? current.version) <
                  0)) {
        index[record.chartId] = record;
      }
    }
    return _bestPlayRecordByChartId = index;
  }

  /// 現行（取込み済みCSVのうち最も新しい版）を除いた、過去版だけの
  /// 自己ベスト。MY BEST は現行スコアと比較するため、この索引を使う。
  Map<String, PlayRecord> get _historicalBestPlayRecordIndex {
    final existing = _historicalBestPlayRecordByChartId;
    if (existing != null) return existing;
    final latestVersion = latestPlayerDataVersion;
    if (latestVersion == null) return const {};
    final index = <String, PlayRecord>{};
    for (final record in _records) {
      final version = record.dataVersion ?? record.version;
      if (_compareIidxVersions(version, latestVersion) >= 0) continue;
      final current = index[record.chartId];
      if (current == null ||
          record.score > current.score ||
          (record.score == current.score &&
              _compareIidxVersions(version,
                      current.dataVersion ?? current.version) <
                  0)) {
        index[record.chartId] = record;
      }
    }
    return _historicalBestPlayRecordByChartId = index;
  }

  String _rivalChartKey(int slot, PlayStyle style, String version,
          String songTitle, ChartType type) =>
      '$slot|${style.name}|$version|$songTitle|${type.name}';

  Map<String, RivalRecord> get _rivalRecordIndex {
    final existing = _latestRivalRecordByChart;
    if (existing != null) return existing;
    final index = <String, RivalRecord>{};
    for (final record in _rivalRecords) {
      final key = _rivalChartKey(record.slot, record.style, record.version,
          record.songTitle, record.type);
      final current = index[key];
      if (current == null ||
          _compareIidxVersions(record.dataVersion ?? record.version,
                  current.dataVersion ?? current.version) >
              0) {
        index[key] = record;
      }
    }
    return _latestRivalRecordByChart = index;
  }

  /// Excelの「SP楽曲情報」「DP楽曲情報」から生成した同梱マスタを読み込む。
  /// モックのBLUE HORIZON／ライバル情報はここで完全に置き換える。
  Future<void> loadBundledMusicData() async {
    final decoded =
        jsonDecode(await rootBundle.loadString('assets/data/music_master.json'))
            as Map;
    final aliases = jsonDecode(
        await rootBundle.loadString('assets/data/title_aliases.json')) as Map;
    _titleAliases = (aliases['aliases'] as Map? ?? const {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
    final sourceCharts = (decoded['charts'] as List).cast<Map>();
    charts
      ..clear()
      ..addAll(sourceCharts.map(_chartFromMaster));
    _records.clear();
    _rivalRecords.clear();
    _userCharts.clear();
    for (var index = 0; index < rivals.length; index++) {
      rivals[index] = RivalProfile(slot: index + 1, djName: null);
    }
    _invalidateRecordIndexes();
  }

  /// 自分のCSV、ライバルCSV、ライバル枠をローカル設定領域から復元する。
  /// 楽曲マスタを読み込んだ後に一度だけ呼び出す。
  Future<void> restorePersistedUserData() async {
    final preferences = await SharedPreferences.getInstance();
    try {
      await preferences.remove(_legacyPlayRecordsKey);
      final rawPlay = preferences.getString(_playRecordsKey);
      if (rawPlay != null && rawPlay.isNotEmpty) {
        final data = jsonDecode(rawPlay) as Map<String, dynamic>;
        final extraCharts = (data['userCharts'] as List? ?? const [])
            .whereType<Map>()
            .map(_chartFromStorage)
            .toList();
        _userCharts
          ..clear()
          ..addAll(extraCharts);
        _records
          ..clear()
          ..addAll((data['records'] as List? ?? const [])
              .whereType<Map>()
              .map(_playRecordFromStorage));
      }

      final rawRivals = preferences.getString(_rivalDataKey);
      if (rawRivals != null && rawRivals.isNotEmpty) {
        final data = jsonDecode(rawRivals) as Map<String, dynamic>;
        for (var index = 0; index < rivals.length; index++) {
          rivals[index] = RivalProfile(slot: index + 1, djName: null);
        }
        for (final source
            in (data['profiles'] as List? ?? const []).whereType<Map>()) {
          final profile = _rivalProfileFromStorage(source);
          if (profile.slot >= 1 && profile.slot <= rivals.length) {
            rivals[profile.slot - 1] = profile;
          }
        }
        _rivalRecords
          ..clear()
          ..addAll((data['records'] as List? ?? const [])
              .whereType<Map>()
              .map(_rivalRecordFromStorage));
        _trimRivalHistories();
      }
    } catch (_) {
      // 壊れた保存データは読込対象にせず、同梱マスタのみで安全に起動する。
      _records.clear();
      _rivalRecords.clear();
      _userCharts.clear();
      for (var index = 0; index < rivals.length; index++) {
        rivals[index] = RivalProfile(slot: index + 1, djName: null);
      }
    }
    _invalidateRecordIndexes();
  }

  /// 自分のCSV、ライバルCSV、ライバル枠を永続化する。
  Future<void> savePersistedUserData() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
        _playRecordsKey,
        jsonEncode({
          'records': _records.map(_playRecordToStorage).toList(),
          'userCharts': _userCharts.map(_chartToStorage).toList(),
        }));
    await preferences.setString(
        _rivalDataKey,
        jsonEncode({
          'profiles': rivals.map(_rivalProfileToStorage).toList(),
          'records': _rivalRecords.map(_rivalRecordToStorage).toList(),
        }));
  }

  /// 自分のCSVから取込んだプレイデータだけを削除する。DJ NAMEは保持する。
  void deletePlayerData() {
    _records.clear();
    _userCharts.clear();
    _invalidateRecordIndexes();
  }

  Map<String, dynamic> _playRecordToStorage(PlayRecord value) => {
        'chartId': value.chartId,
        'score': value.score,
        'clear': value.clear.name,
        'version': value.version,
        'dataVersion': value.dataVersion,
        'pGreat': value.pGreat,
        'great': value.great,
        'missCount': value.missCount,
        'officialDjLevel': value.officialDjLevel,
        'lastPlayedAt': value.lastPlayedAt?.toIso8601String(),
      };

  PlayRecord _playRecordFromStorage(Map value) => PlayRecord(
        chartId: value['chartId'] as String,
        score: (value['score'] as num).toInt(),
        clear: ClearType.values.byName(value['clear'] as String),
        version: value['version'] as String,
        dataVersion:
            value['dataVersion'] as String? ?? value['version'] as String,
        pGreat: (value['pGreat'] as num?)?.toInt() ?? 0,
        great: (value['great'] as num?)?.toInt() ?? 0,
        missCount: (value['missCount'] as num?)?.toInt(),
        officialDjLevel: value['officialDjLevel'] as String?,
        lastPlayedAt: value['lastPlayedAt'] == null
            ? null
            : DateTime.tryParse(value['lastPlayedAt'] as String),
      );

  Map<String, dynamic> _rivalProfileToStorage(RivalProfile value) => {
        'slot': value.slot,
        'djName': value.djName,
        'spImported': value.spImported,
        'dpImported': value.dpImported,
      };

  RivalProfile _rivalProfileFromStorage(Map value) => RivalProfile(
        slot: (value['slot'] as num).toInt(),
        djName: value['djName'] as String?,
        spImported: value['spImported'] == true,
        dpImported: value['dpImported'] == true,
      );

  Map<String, dynamic> _rivalRecordToStorage(RivalRecord value) => {
        'slot': value.slot,
        'style': value.style.name,
        'version': value.version,
        'dataVersion': value.dataVersion,
        'songTitle': value.songTitle,
        'type': value.type.name,
        'score': value.score,
        'clear': value.clear.name,
      };

  RivalRecord _rivalRecordFromStorage(Map value) => RivalRecord(
        slot: (value['slot'] as num).toInt(),
        style: PlayStyle.values.byName(value['style'] as String),
        version: value['version'] as String,
        dataVersion:
            value['dataVersion'] as String? ?? value['version'] as String,
        songTitle: value['songTitle'] as String,
        type: ChartType.values.byName(value['type'] as String),
        score: (value['score'] as num).toInt(),
        clear: ClearType.values.byName(value['clear'] as String),
      );

  Map<String, dynamic> _chartToStorage(Chart value) => {
        'id': value.id,
        'songTitle': value.songTitle,
        'genre': value.genre,
        'artist': value.artist,
        'version': value.version,
        'bpm': value.bpm,
        'style': value.style.name,
        'type': value.type.name,
        'level': value.level,
        'maxScore': value.maxScore,
        'hasRadarData': value.hasRadarData,
        'maxRadar': {
          'notes': value.maxRadar.notes,
          'chord': value.maxRadar.chord,
          'peak': value.maxRadar.peak,
          'charge': value.maxRadar.charge,
          'scratch': value.maxRadar.scratch,
          'sofLan': value.maxRadar.sofLan,
        },
      };

  Chart _chartFromStorage(Map value) {
    final radar = (value['maxRadar'] as Map).cast<String, dynamic>();
    double radarValue(String key) => (radar[key] as num?)?.toDouble() ?? 0;
    return Chart(
      id: value['id'] as String,
      songTitle: value['songTitle'] as String,
      genre: value['genre'] as String,
      artist: value['artist'] as String,
      version: value['version'] as String,
      bpm: value['bpm'] as String,
      style: PlayStyle.values.byName(value['style'] as String),
      type: ChartType.values.byName(value['type'] as String),
      level: (value['level'] as num).toInt(),
      maxScore: (value['maxScore'] as num).toInt(),
      hasRadarData: value['hasRadarData'] == true,
      maxRadar: RadarValues(
        notes: radarValue('notes'),
        chord: radarValue('chord'),
        peak: radarValue('peak'),
        charge: radarValue('charge'),
        scratch: radarValue('scratch'),
        sofLan: radarValue('sofLan'),
      ),
    );
  }

  Chart _chartFromMaster(Map source) {
    final radar = (source['maxRadar'] as Map).cast<String, dynamic>();
    double value(String key) => (radar[key] as num?)?.toDouble() ?? 0;
    return Chart(
      id: source['id'] as String,
      songTitle: source['songTitle'] as String,
      genre: source['genre'] as String,
      artist: source['artist'] as String,
      version: source['version'] as String,
      bpm: source['bpm'] as String,
      style: PlayStyle.values.byName(source['style'] as String),
      type: ChartType.values.byName(source['type'] as String),
      level: (source['level'] as num).toInt(),
      maxScore: (source['maxScore'] as num).toInt(),
      hasRadarData: source['radarAvailable'] == true,
      maxRadar: RadarValues(
        notes: value('notes'),
        chord: value('chord'),
        peak: value('peak'),
        charge: value('charge'),
        scratch: value('scratch'),
        sofLan: value('sofLan'),
      ),
    );
  }

  void registerRival(
      {required int slot, required String djName, required PlayStyle style}) {
    final index = rivals.indexWhere((item) => item.slot == slot);
    if (index < 0) return;
    final previous = rivals[index];
    rivals[index] = RivalProfile(
        slot: slot,
        djName: _sanitizeDjName(djName),
        spImported: previous.spImported || style == PlayStyle.sp,
        dpImported: previous.dpImported || style == PlayStyle.dp);
  }

  /// 取込済みフラグを変えずに、ライバルの表示名だけを更新する。
  void setRivalDjName({required int slot, required String djName}) {
    final index = rivals.indexWhere((item) => item.slot == slot);
    if (index < 0) return;
    final previous = rivals[index];
    rivals[index] = RivalProfile(
      slot: slot,
      djName: _sanitizeDjName(djName),
      spImported: previous.spImported,
      dpImported: previous.dpImported,
    );
  }

  void deleteRival(int slot) {
    final index = rivals.indexWhere((item) => item.slot == slot);
    if (index < 0) return;
    rivals[index] = RivalProfile(slot: slot, djName: null);
    _rivalRecords.removeWhere((record) => record.slot == slot);
    _invalidateRecordIndexes();
  }

  List<RivalProfile> importedRivalsForStyle(PlayStyle style) =>
      rivals.where((rival) => rival.hasImported(style)).toList();

  CsvImportSummary importRivalOfficialCsv(
    String text, {
    required int slot,
    required PlayStyle style,
  }) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) {
      return const CsvImportSummary(
          songCount: 0,
          chartCount: 0,
          skippedRows: 0,
          errors: ['CSVのヘッダーと1行以上のデータが必要です。']);
    }
    final header = _splitCsvLine(lines.first);
    const required = ['バージョン', 'タイトル', 'BEGINNER 難易度', 'ANOTHER スコア'];
    final missing =
        required.where((column) => !header.contains(column)).toList();
    if (missing.isNotEmpty) {
      return CsvImportSummary(
          songCount: 0,
          chartCount: 0,
          skippedRows: 0,
          errors: ['公式スコアCSVの形式ではありません。不足列: ${missing.join(' / ')}']);
    }
    final dataVersion = _detectCsvDataVersion(lines);

    const chartTypes = [
      ChartType.beginner,
      ChartType.normal,
      ChartType.hyper,
      ChartType.another,
      ChartType.leggendaria,
    ];
    const starts = [5, 12, 19, 26, 33];
    var songs = 0;
    var chartCount = 0;
    var skipped = 0;
    final errors = <String>[];
    final imported = <RivalRecord>[];
    for (var lineNumber = 1; lineNumber < lines.length; lineNumber++) {
      final columns = _splitCsvLine(lines[lineNumber]);
      if (columns.length != 41) {
        skipped++;
        if (errors.length < 8) {
          errors.add('${lineNumber + 1}行目: 列数が${columns.length}です（41列必要）。');
        }
        continue;
      }
      final version = columns[0].trim();
      final csvTitle = columns[1].trim();
      final title = _resolveCsvSongTitle(csvTitle);
      if (version.isEmpty || title.isEmpty) {
        skipped++;
        continue;
      }
      songs++;
      for (var index = 0; index < chartTypes.length; index++) {
        final start = starts[index];
        if ((int.tryParse(columns[start].trim()) ?? 0) <= 0) continue;
        final type = chartTypes[index];
        final chart = charts
            .where((item) =>
                item.style == style &&
                item.type == type &&
                item.songTitle == title)
            .firstOrNull;
        if (chart == null) {
          skipped++;
          if (errors.length < 8) {
            errors.add('${lineNumber + 1}行目: 楽曲マスタに一致しません '
                '（$csvTitle / ${type.label}）。');
          }
          continue;
        }
        imported.add(RivalRecord(
            slot: slot,
            style: style,
            version: chart.version,
            dataVersion: dataVersion,
            songTitle: chart.songTitle,
            type: type,
            score: int.tryParse(columns[start + 1].trim()) ?? 0,
            clear: _clearFromOfficial(columns[start + 5])));
        chartCount++;
      }
    }
    if (chartCount > 0) {
      // ライバルは歴代データを保持しない。対象SP/DPの既存データを
      // まるごと置換して、常にCSV 1世代分だけを保存する。
      _rivalRecords.removeWhere(
          (record) => record.slot == slot && record.style == style);
      _rivalRecords.addAll(imported);
      _invalidateRecordIndexes();
    }
    return CsvImportSummary(
        songCount: songs,
        chartCount: chartCount,
        skippedRows: skipped,
        errors: errors,
        dataVersion: dataVersion);
  }

  List<Chart> forStyle(PlayStyle style) =>
      charts.where((chart) => chart.style == style).toList();
  PlayRecord? recordFor(String chartId) => _playRecordIndex[chartId];
  PlayRecord? bestRecordFor(String chartId) => _bestPlayRecordIndex[chartId];
  PlayRecord? historicalBestRecordFor(String chartId) =>
      _historicalBestPlayRecordIndex[chartId];

  /// 取り込み済み自分データのうち、CSV取得時点が最も新しい版。
  String? get latestPlayerDataVersion {
    String? latest;
    for (final record in _records) {
      final version = record.dataVersion ?? record.version;
      if (latest == null || _compareIidxVersions(version, latest) > 0) {
        latest = version;
      }
    }
    return latest;
  }

  bool get hasPlayerData => _records.isNotEmpty;

  /// 異なる取得時点のCSVが2世代以上ある場合だけ、MY BESTを表示する。
  bool get hasHistoricalPlayerData =>
      _records
          .map((record) => record.dataVersion ?? record.version)
          .toSet()
          .length >=
      2;

  String playerBestNameFor(String chartId) {
    final record = historicalBestRecordFor(chartId);
    final version = record?.dataVersion ?? record?.version;
    return version == null
        ? 'MY BEST'
        : 'MY BEST（${_iidxVersionAbbreviation(version)}）';
  }

  String? detectCsvDataVersion(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .toList();
    return _detectCsvDataVersion(lines);
  }

  String? rivalDataVersion(int slot, PlayStyle style) {
    String? latest;
    for (final record in _rivalRecords
        .where((record) => record.slot == slot && record.style == style)) {
      final version = record.dataVersion ?? record.version;
      if (latest == null || _compareIidxVersions(version, latest) > 0) {
        latest = version;
      }
    }
    return latest;
  }

  bool isOlderVersion(String candidate, String current) =>
      _compareIidxVersions(candidate, current) < 0;

  void importRecord(PlayRecord record) {
    _records.removeWhere((item) =>
        item.chartId == record.chartId &&
        item.dataVersion == record.dataVersion);
    _records.add(record);
    _invalidateRecordIndexes();
  }

  /// 公式CSVの表記を、同梱した確認済み対応表でマスター楽曲名へ正規化する。
  /// 未登録の表記は推測変換せず、そのまま照合に進める。
  String _resolveCsvSongTitle(String csvTitle) =>
      _titleAliases[csvTitle] ?? csvTitle;

  CsvImportSummary importOfficialCsv(
    String text, {
    required PlayStyle style,
  }) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) {
      return const CsvImportSummary(
          songCount: 0,
          chartCount: 0,
          skippedRows: 0,
          errors: ['CSVのヘッダーと1行以上のデータが必要です。']);
    }
    final header = _splitCsvLine(lines.first);
    const required = [
      'バージョン',
      'タイトル',
      'BEGINNER 難易度',
      'ANOTHER スコア',
      'LEGGENDARIA DJ LEVEL'
    ];
    final missing =
        required.where((column) => !header.contains(column)).toList();
    if (missing.isNotEmpty) {
      return CsvImportSummary(
          songCount: 0,
          chartCount: 0,
          skippedRows: 0,
          errors: ['公式スコアCSVの形式ではありません。不足列: ${missing.join(' / ')}']);
    }
    final dataVersion = _detectCsvDataVersion(lines);

    var songs = 0;
    var chartsImported = 0;
    var skipped = 0;
    final errors = <String>[];
    final imported = <PlayRecord>[];
    const chartTypes = [
      ChartType.beginner,
      ChartType.normal,
      ChartType.hyper,
      ChartType.another,
      ChartType.leggendaria
    ];
    const starts = [5, 12, 19, 26, 33];

    for (var lineNumber = 1; lineNumber < lines.length; lineNumber++) {
      final columns = _splitCsvLine(lines[lineNumber]);
      if (columns.length != 41) {
        skipped++;
        if (errors.length < 8) {
          errors.add('${lineNumber + 1}行目: 列数が${columns.length}です（41列必要）。');
        }
        continue;
      }
      final version = columns[0].trim();
      final csvTitle = columns[1].trim();
      final title = _resolveCsvSongTitle(csvTitle);
      final lastPlayedAt =
          DateTime.tryParse(columns[40].trim().replaceFirst(' ', 'T'));
      if (version.isEmpty || title.isEmpty) {
        skipped++;
        if (errors.length < 8) {
          errors.add('${lineNumber + 1}行目: バージョンまたはタイトルが空です。');
        }
        continue;
      }
      songs++;
      for (var index = 0; index < chartTypes.length; index++) {
        final start = starts[index];
        final level = int.tryParse(columns[start].trim()) ?? 0;
        if (level <= 0) continue;
        final score = int.tryParse(columns[start + 1].trim()) ?? 0;
        final pGreat = int.tryParse(columns[start + 2].trim()) ?? 0;
        final great = int.tryParse(columns[start + 3].trim()) ?? 0;
        final miss = int.tryParse(columns[start + 4].trim());
        final clear = _clearFromOfficial(columns[start + 5]);
        final officialDjLevel = columns[start + 6].trim();
        final type = chartTypes[index];
        // CSVの表記から楽曲を新規作成しない。登録済み楽曲マスタの曲名・
        // プレースタイル・譜面種類だけを正として照合する。表記ゆれは
        // ここでは推測補正せず、後から明示的な対応表を追加できるようにする。
        final existing = charts.indexWhere((chart) =>
            chart.style == style &&
            chart.type == type &&
            chart.songTitle == title);
        if (existing < 0) {
          skipped++;
          if (errors.length < 8) {
            errors.add('${lineNumber + 1}行目: 楽曲マスタに一致しません '
                '（$csvTitle / ${type.label}）。');
          }
          continue;
        }
        final chart = charts[existing];
        imported.add(PlayRecord(
            chartId: chart.id,
            score: score,
            clear: clear,
            version: chart.version,
            dataVersion: dataVersion,
            pGreat: pGreat,
            great: great,
            missCount: miss,
            officialDjLevel: officialDjLevel == '---' ? null : officialDjLevel,
            lastPlayedAt: lastPlayedAt));
        chartsImported++;
      }
    }
    // 同じ時点のCSVを再取込する場合は、CSVから消えた古い行も残さない。
    // 照合できた譜面がないCSVでは既存データを消さない。
    if (chartsImported > 0) {
      final styleChartIds = charts
          .where((chart) => chart.style == style)
          .map((chart) => chart.id)
          .toSet();
      // 同じ版でもSPとDPは別CSVとして保持するため、今回のプレースタイル
      // に属する履歴だけを置き換える。
      _records.removeWhere((record) =>
          record.dataVersion == dataVersion &&
          styleChartIds.contains(record.chartId));
      _records.addAll(imported);
      _invalidateRecordIndexes();
    }
    return CsvImportSummary(
        songCount: songs,
        chartCount: chartsImported,
        skippedRows: skipped,
        errors: errors,
        dataVersion: dataVersion);
  }

  List<RivalScore> rivalScores(Chart chart) {
    final mine = recordFor(chart.id)?.score ?? 0;
    final scores = <RivalScore>[
      for (final rival in importedRivalsForStyle(chart.style))
        _rivalScoreFor(rival, chart),
    ];
    // DJ NAME未登録の状態では、自分の仮行（PLAYER）を表示しない。
    // ノーツレーダーだけを確認する利用では、登録データなしで空表示にする。
    final name = playerDjName?.trim();
    if (name != null && name.isNotEmpty) {
      scores.add(RivalScore(
          name: name,
          score: mine,
          clear: recordFor(chart.id)?.clear ?? ClearType.noPlay,
          isMe: true));
      // 最新版の自分の行とは別に、過去版だけの最高スコアを表示する。
      final best = historicalBestRecordFor(chart.id);
      if (hasHistoricalPlayerData && best != null) {
        scores.add(RivalScore(
            name: playerBestNameFor(chart.id),
            score: best.score,
            clear: best.clear,
            isPersonalBest: true));
      }
    }
    scores.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      // 双方0点はスコアだけでは順序を決められないため、CLEARランクが
      // 高い方（FULL COMBO → … → NO PLAY）を上に表示する。
      if (a.score == 0 && b.score == 0) {
        final byClear = a.clear.index.compareTo(b.clear.index);
        if (byClear != 0) return byClear;
      }
      // プレイ済みで同点なら、MY BEST を含む比較相手を自分より上に置く。
      // 0点同士は未プレイとして、上の CLEAR ランクによる順序を維持する。
      if (a.score > 0 && b.score > 0 && a.isMe != b.isMe) {
        return a.isMe ? 1 : -1;
      }
      // 0点で CLEAR も同じ場合は、最新版の自分を MY BEST より先にする。
      if (a.isMe && b.isPersonalBest) return -1;
      if (b.isMe && a.isPersonalBest) return 1;
      if (a.isMe != b.isMe) return a.isMe ? 1 : -1;
      return a.name.compareTo(b.name);
    });
    return scores;
  }

  RivalScore? rivalScoreForSlot(Chart chart, int slot) {
    final rival = rivals
        .where((item) => item.slot == slot && item.hasImported(chart.style))
        .firstOrNull;
    return rival == null ? null : _rivalScoreFor(rival, chart);
  }

  RivalScore _rivalScoreFor(RivalProfile rival, Chart chart) {
    final record = _rivalRecordIndex[_rivalChartKey(
        rival.slot, chart.style, chart.version, chart.songTitle, chart.type)];
    return RivalScore(
        name: rival.djName ?? 'RIVAL ${rival.slot}',
        score: record?.score ?? 0,
        clear: record?.clear ?? ClearType.noPlay);
  }
}

int mathMax(int a, int b) => a > b ? a : b;

/// CSVの各行にある「バージョン」は楽曲の初出バージョンであり、CSVを
/// ダウンロードした時点のバージョンではない。CSV中で最も新しい初出
/// バージョンを、そのCSVファイル単位の歴代データの識別子として扱う。
String? _detectCsvDataVersion(List<String> lines) {
  String? latest;
  for (final line in lines.skip(1)) {
    final columns = _splitCsvLine(line);
    if (columns.length < 2) continue;
    final version = columns.first.trim();
    if (version.isEmpty) continue;
    if (latest == null || _compareIidxVersions(version, latest) > 0) {
      latest = version;
    }
  }
  return latest;
}

/// 過去CSVも含めたデータ世代の前後関係。未知の将来バージョンは文字列順で
/// 安全に扱うため、マスタ更新前でもCSVの取込自体は止めない。
const _iidxVersionOrder = <String>[
  '1st style',
  'substream',
  '2nd style',
  '3rd style',
  '4th style',
  '5th style',
  '6th style',
  '7th style',
  '8th style',
  '9th style',
  '10th style',
  'IIDX RED',
  'HAPPY SKY',
  'DistorteD',
  'GOLD',
  'DJ TROOPERS',
  'EMPRESS',
  'SIRIUS',
  'Resort Anthem',
  'Lincle',
  'tricoro',
  'SPADA',
  'PENDUAL',
  'copula',
  'SINOBUZ',
  'CANNON BALLERS',
  'Rootage',
  'HEROIC VERSE',
  'BISTROVER',
  'CastHour',
  'RESIDENT',
  'EPOLIS',
  'Pinky Crush',
  'Sparkle Shower',
];

const _iidxVersionAbbreviations = <String, String>{
  '1st style': '1st',
  'substream': 'sub',
  '2nd style': '2nd',
  '3rd style': '3rd',
  '4th style': '4th',
  '5th style': '5th',
  '6th style': '6th',
  '7th style': '7th',
  '8th style': '8th',
  '9th style': '9th',
  '10th style': '10th',
  'IIDX RED': 'RED',
  'HAPPY SKY': 'SKY',
  'DistorteD': 'DD',
  'GOLD': 'GOLD',
  'DJ TROOPERS': 'DJT',
  'EMPRESS': 'EMP',
  'SIRIUS': 'SIR',
  'Resort Anthem': 'RA',
  'Lincle': 'LC',
  'tricoro': 'tri',
  'SPADA': 'SPA',
  'PENDUAL': 'PEN',
  'copula': 'cop',
  'SINOBUZ': 'SINO',
  'CANNON BALLERS': 'CAN',
  'Rootage': 'Root',
  'HEROIC VERSE': 'HERO',
  'BISTROVER': 'BIS',
  'CastHour': 'Cast',
  'RESIDENT': 'RESI',
  'EPOLIS': 'EPO',
  'Pinky Crush': 'Pink',
  'Sparkle Shower': 'SPS',
};

String _iidxVersionAbbreviation(String version) =>
    _iidxVersionAbbreviations.entries
        .where((entry) => entry.key.toLowerCase() == version.toLowerCase())
        .map((entry) => entry.value)
        .firstOrNull ??
    version;

int _compareIidxVersions(String left, String right) {
  int indexOf(String value) => _iidxVersionOrder
      .indexWhere((item) => item.toLowerCase() == value.toLowerCase());
  final leftIndex = indexOf(left);
  final rightIndex = indexOf(right);
  if (leftIndex >= 0 && rightIndex >= 0) return leftIndex.compareTo(rightIndex);
  if (leftIndex >= 0) return 1;
  if (rightIndex >= 0) return -1;
  return left.toLowerCase().compareTo(right.toLowerCase());
}

List<String> _splitCsvLine(String line) {
  // 公式CSVはカンマを含む値を出力しない仕様。楽曲名中の二重引用符は囲みではないため、単純分割する。
  return line.split(',');
}

ClearType _clearFromOfficial(String raw) {
  final value = raw.trim().toUpperCase();
  if (value.contains('FULLCOMBO')) return ClearType.fullCombo;
  if (value.contains('EX HARD')) return ClearType.exHard;
  if (value.contains('HARD')) return ClearType.hard;
  if (value == 'CLEAR') return ClearType.clear;
  if (value.contains('ASSIST')) return ClearType.assistEasy;
  if (value.contains('EASY')) return ClearType.easy;
  if (value.contains('FAILED')) return ClearType.failed;
  return ClearType.noPlay;
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
