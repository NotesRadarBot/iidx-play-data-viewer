enum PlayStyle { sp, dp }

enum ChartType { beginner, normal, hyper, another, leggendaria }

enum ClearType {
  fullCombo,
  exHard,
  hard,
  clear,
  easy,
  assistEasy,
  failed,
  noPlay
}

enum RadarAttribute { notes, chord, peak, charge, scratch, sofLan }

extension PlayStyleLabel on PlayStyle {
  String get label => this == PlayStyle.sp ? 'SP' : 'DP';
}

extension ChartTypeLabel on ChartType {
  String get label => switch (this) {
        ChartType.beginner => 'BEGINNER',
        ChartType.normal => 'NORMAL',
        ChartType.hyper => 'HYPER',
        ChartType.another => 'ANOTHER',
        ChartType.leggendaria => 'LEGGENDARIA',
      };
}

extension ClearTypeLabel on ClearType {
  String get label => switch (this) {
        ClearType.fullCombo => 'FULL COMBO',
        ClearType.exHard => 'EX HARD',
        ClearType.hard => 'HARD',
        ClearType.clear => 'CLEAR',
        ClearType.easy => 'EASY',
        ClearType.assistEasy => 'ASSIST EASY',
        ClearType.failed => 'FAILED',
        ClearType.noPlay => 'NO PLAY',
      };
}

extension RadarAttributeLabel on RadarAttribute {
  String get label => switch (this) {
        RadarAttribute.notes => 'NOTES',
        RadarAttribute.chord => 'CHORD',
        RadarAttribute.peak => 'PEAK',
        RadarAttribute.charge => 'CHARGE',
        RadarAttribute.scratch => 'SCRATCH',
        RadarAttribute.sofLan => 'SOF-LAN',
      };
}

class RadarValues {
  const RadarValues({
    required this.notes,
    required this.chord,
    required this.peak,
    required this.charge,
    required this.scratch,
    required this.sofLan,
  });

  final double notes;
  final double chord;
  final double peak;
  final double charge;
  final double scratch;
  final double sofLan;

  double by(RadarAttribute attribute) => switch (attribute) {
        RadarAttribute.notes => notes,
        RadarAttribute.chord => chord,
        RadarAttribute.peak => peak,
        RadarAttribute.charge => charge,
        RadarAttribute.scratch => scratch,
        RadarAttribute.sofLan => sofLan,
      };

  RadarAttribute get strongest => RadarAttribute.values.reduce(
        (best, current) => by(current) > by(best) ? current : best,
      );

  /// 同率最大を含め、その譜面で最も高い属性かを判定する。
  bool isStrongest(RadarAttribute attribute) {
    final highest = RadarAttribute.values
        .map(by)
        .reduce((current, next) => current > next ? current : next);
    return (by(attribute) - highest).abs() < 0.000001;
  }
}

class Chart {
  const Chart({
    required this.id,
    required this.songTitle,
    required this.genre,
    required this.artist,
    required this.version,
    required this.bpm,
    required this.style,
    required this.type,
    required this.level,
    required this.maxScore,
    required this.maxRadar,
    this.hasRadarData = true,
  });

  final String id;
  final String songTitle;
  final String genre;
  final String artist;
  final String version;
  final String bpm;
  final PlayStyle style;
  final ChartType type;
  final int level;
  final int maxScore;
  final RadarValues maxRadar;

  /// 6属性のうち一つでも未登録なら false。0.00 の実データとは区別する。
  final bool hasRadarData;
}

class PlayRecord {
  const PlayRecord({
    required this.chartId,
    required this.score,
    required this.clear,
    required this.version,
    this.dataVersion,
    this.pGreat = 0,
    this.great = 0,
    this.missCount,
    this.officialDjLevel,
    this.lastPlayedAt,
  });

  final String chartId;
  final int score;
  final ClearType clear;

  /// 楽曲の初出バージョン。
  final String version;

  /// CSVを取得したIIDXバージョン。CSVファイル単位の歴代データを識別する。
  final String? dataVersion;
  final int pGreat;
  final int great;
  final int? missCount;
  final String? officialDjLevel;
  final DateTime? lastPlayedAt;
}

class CsvImportSummary {
  const CsvImportSummary({
    required this.songCount,
    required this.chartCount,
    required this.skippedRows,
    required this.errors,
    this.dataVersion,
  });

  final int songCount;
  final int chartCount;
  final int skippedRows;
  final List<String> errors;

  /// CSV内の楽曲初出バージョンから自動判定した取得時点のIIDXバージョン。
  final String? dataVersion;
}

class RivalScore {
  const RivalScore({
    required this.name,
    required this.score,
    required this.clear,
    this.isMe = false,
    this.isPersonalBest = false,
  });

  final String name;
  final int score;
  final ClearType clear;
  final bool isMe;

  /// 最新バージョンの自分の行とは別に表示する、歴代自己ベスト行。
  final bool isPersonalBest;
}

class RivalProfile {
  const RivalProfile({
    required this.slot,
    required this.djName,
    this.spImported = false,
    this.dpImported = false,
  });

  final int slot;
  final String? djName;
  final bool spImported;
  final bool dpImported;

  bool get isImported => spImported || dpImported;
  bool hasImported(PlayStyle style) =>
      style == PlayStyle.sp ? spImported : dpImported;

  String get label => isImported ? 'RIVAL $slot（$djName）' : 'RIVAL $slot';
}

class RivalRecord {
  const RivalRecord({
    required this.slot,
    required this.style,
    required this.version,
    this.dataVersion,
    required this.songTitle,
    required this.type,
    required this.score,
    required this.clear,
  });

  final int slot;
  final PlayStyle style;

  /// 楽曲の初出バージョン。
  final String version;

  /// CSVを取得したIIDXバージョン。CSVファイル単位の歴代データを識別する。
  final String? dataVersion;
  final String songTitle;
  final ChartType type;
  final int score;
  final ClearType clear;
}
