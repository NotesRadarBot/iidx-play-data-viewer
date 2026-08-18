import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'repository.dart';

/// PLAY DATAの確定モック（1680 x 944）を基準にした実装。
/// FittedBoxで画面サイズに追従させ、配置・余白・領域比を固定する。
class PlayDataMockScreen extends StatefulWidget {
  const PlayDataMockScreen(
      {required this.repository,
      required this.visibleFolderGroups,
      required this.onBack,
      super.key});

  final AppRepository repository;
  final Set<String> visibleFolderGroups;
  final VoidCallback onBack;

  @override
  State<PlayDataMockScreen> createState() => _PlayDataMockScreenState();
}

class _PlayDataMockScreenState extends State<PlayDataMockScreen> {
  static const _canvas = Size(1680, 944);
  PlayStyle _style = PlayStyle.sp;
  ChartType _chartType = ChartType.another;
  late String _folder;
  String _sort = 'デフォルト';
  bool _folderSelected = true;
  String? _expandedFolder;
  // VERSION／INITIALフォルダでは、開いた時点で指定されていた譜面種類を
  // 保持する。譜面がない曲で代替譜面を表示しても、この指定は失わない。
  ChartType? _folderChartType;
  ChartType? _chartTypeBeforeFolder;
  List<Chart> _expandedSongs = const [];
  int? _selectedExpandedIndex;
  String? _selectedSongTitle;
  // 楽曲選択中に左側の譜面種類を切り替えた時だけ、選択行に表示する
  // クリアランプ／譜面ラベル／レベルバッジを差し替えるための一時値。
  String? _selectedRowBaseChartId;
  Chart? _selectedRowChartOverride;
  bool _transientSongFocus = false;
  late List<_RivalWinLossSummary> _rivalWinLossSummaries;
  late RadarValues _overallRadar;
  late bool _hasOverallRadar;
  // 展開対象はフォルダ・譜面種類ごとに固定できるため、毎回全譜面を
  // 抽出／ソートし直さない。PLAY DATA画面を離れた時点でStateごと破棄され、
  // CSV取込後に古い内容を使い続けることもない。
  final Map<String, List<Chart>> _folderSongsCache = {};
  // フォルダ行のクリアランプは、フォルダ内容を毎フレーム集計せずに保持する。
  // この画面を閉じてCSVを取り込んだ場合はStateごと作り直される。
  final Map<String, ClearType?> _folderClearCache = {};
  final Map<PlayStyle, List<Chart>> _styleChartsCache = {};
  final GlobalKey<_MusicSelectPanelState> _musicSelectKey =
      GlobalKey<_MusicSelectPanelState>();
  Timer? _arrowRepeatDelayTimer;
  Timer? _arrowRepeatTimer;
  LogicalKeyboardKey? _heldArrowKey;

  @override
  void initState() {
    super.initState();
    // Focus階層やScrollableの標準キー処理より前に受け取る。これにより
    // Page Up/Downが1行スクロールへ置き換わることを防ぐ。
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
    _folder = _MusicSelectPanel.firstVisibleFolder(
        widget.visibleFolderGroups, _rivalProfiles,
        showMyBest: widget.repository.hasHistoricalPlayerData);
    // 勝敗数は描画のたびに再集計せず、PLAY DATA画面を開いた時点で
    // 一度だけ算出して保持する。
    _rivalWinLossSummaries = _calculateRivalWinLossSummaries();
    _refreshOverallRadar();
  }

  List<Chart> get _styleCharts => _styleChartsCache.putIfAbsent(
      _style, () => List.unmodifiable(widget.repository.forStyle(_style)));
  List<Chart> get _selectedSongCharts => _selectedSongTitle == null
      ? _styleCharts
      : _styleCharts
          .where((item) => item.songTitle == _selectedSongTitle)
          .toList();
  Chart get _chart =>
      _selectedSongCharts
          .where((item) => item.type == _chartType)
          .firstOrNull ??
      _selectedSongCharts.first;
  PlayRecord? get _record => widget.repository.recordFor(_chart.id);
  List<RivalProfile> get _rivalProfiles =>
      widget.repository.importedRivalsForStyle(_style);
  Map<int, String> get _rivalNames =>
      {for (final rival in _rivalProfiles) rival.slot: rival.djName ?? ''};

  List<_RivalWinLossSummary> _calculateRivalWinLossSummaries() {
    // フォルダ選択時の勝敗数は、選択中フォルダの内容ではなく
    // 現在のプレースタイル（SP／DP）に存在する全譜面で集計する。
    final charts = _styleCharts;
    final summaries = <_RivalWinLossSummary>[
      if (widget.repository.hasHistoricalPlayerData)
        () {
          var wins = 0;
          var losses = 0;
          for (final chart in charts) {
            final latest = _recordFor(chart);
            final best = widget.repository.bestRecordFor(chart.id);
            if (latest.score <= 0 || best == null || best.score <= 0) continue;
            // 同点はライバル比較と同様に負けとして扱う。
            if (latest.score > best.score) {
              wins++;
            } else {
              losses++;
            }
          }
          return _RivalWinLossSummary(
              slot: 0, name: 'MY BEST', wins: wins, losses: losses);
        }(),
      for (final rival in _rivalProfiles)
        () {
          var wins = 0;
          var losses = 0;
          for (final chart in charts) {
            final rivalScore =
                widget.repository.rivalScoreForSlot(chart, rival.slot);
            // 自分・ライバルのどちらかが未プレイの譜面は、
            // 勝敗数に含めない。
            if (rivalScore == null || rivalScore.score <= 0) continue;
            final myScore = _recordFor(chart).score;
            if (myScore <= 0) continue;
            // 同点はRIVAL SCORE LOSEと同じく負けとして扱う。
            if (myScore > rivalScore.score) {
              wins++;
            } else {
              losses++;
            }
          }
          return _RivalWinLossSummary(
              slot: rival.slot,
              name: rival.djName ?? 'RIVAL ${rival.slot}',
              wins: wins,
              losses: losses);
        }(),
    ];
    return summaries;
  }

  /// フォルダ選択時に固定表示する総合ノーツレーダー。
  /// 属性ごとに同一曲の最高譜面だけを採用し、上位10曲の平均を求める。
  void _refreshOverallRadar() {
    final valuesByAttribute = <RadarAttribute, Map<String, double>>{
      for (final attribute in RadarAttribute.values) attribute: {},
    };
    for (final chart in _styleCharts) {
      if (!chart.hasRadarData || chart.maxScore <= 0) continue;
      final score = _recordFor(chart).score;
      if (score <= 0) continue;
      // マスタのMAX SCOREが未確定でも、実レーダー値はMAX値を超えない。
      final ratio = (score / chart.maxScore).clamp(0.0, 1.0).toDouble();
      for (final attribute in RadarAttribute.values) {
        final actual = chart.maxRadar.by(attribute) * ratio;
        final perSong = valuesByAttribute[attribute]!;
        final current = perSong[chart.songTitle];
        if (current == null || actual > current) {
          perSong[chart.songTitle] = actual;
        }
      }
    }

    double averageTopTen(RadarAttribute attribute) {
      final values = valuesByAttribute[attribute]!.values.toList()
        ..sort((a, b) => b.compareTo(a));
      final top = values.take(10).toList();
      if (top.isEmpty) return 0;
      return top.reduce((sum, value) => sum + value) / top.length;
    }

    _overallRadar = RadarValues(
      notes: averageTopTen(RadarAttribute.notes),
      chord: averageTopTen(RadarAttribute.chord),
      peak: averageTopTen(RadarAttribute.peak),
      charge: averageTopTen(RadarAttribute.charge),
      scratch: averageTopTen(RadarAttribute.scratch),
      sofLan: averageTopTen(RadarAttribute.sofLan),
    );
    _hasOverallRadar =
        valuesByAttribute.values.any((values) => values.isNotEmpty);
  }

  void _selectStyle(PlayStyle value) {
    if (_style == value) return;
    final previousFolder = _folder;
    final previousExpandedFolder = _expandedFolder;
    final previousSongTitle = _selectedSongTitle;
    final previousChartType = _chartType;
    final previousFolderChartType = _folderChartType;
    final previousChartTypeBeforeFolder = _chartTypeBeforeFolder;
    setState(() {
      _style = value;
      // SP／DPは別々の譜面・登録データを対象にするため、切替時だけ
      // そのスタイル分を再集計する。
      _rivalWinLossSummaries = _calculateRivalWinLossSummaries();
      _refreshOverallRadar();
      final nextFolders = _MusicSelectPanel.visibleFolders(
          widget.visibleFolderGroups, _rivalProfiles,
          showMyBest: widget.repository.hasHistoricalPlayerData);
      _folder = nextFolders.contains(previousFolder)
          ? previousFolder
          : _MusicSelectPanel.firstVisibleFolder(
              widget.visibleFolderGroups, _rivalProfiles,
              showMyBest: widget.repository.hasHistoricalPlayerData);
      // 切替前に選んでいた譜面種類を優先する。該当譜面がない曲では既存の
      // 代替譜面表示規則に従い、次の曲で該当譜面があれば再び復帰する。
      _chartType = _styleCharts.any((item) => item.type == previousChartType)
          ? previousChartType
          : _styleCharts.first.type;
      _expandedFolder = previousExpandedFolder != null &&
              nextFolders.contains(previousExpandedFolder)
          ? previousExpandedFolder
          : null;
      _folderChartType =
          _expandedFolder == null ? null : previousFolderChartType;
      _chartTypeBeforeFolder =
          _expandedFolder == null ? null : previousChartTypeBeforeFolder;
      _expandedSongs = const [];
      _selectedExpandedIndex = null;
      _selectedSongTitle = null;
      _selectedRowBaseChartId = null;
      _selectedRowChartOverride = null;
      _folderSelected = true;

      if (_expandedFolder != null) {
        final preferredType = _folderChartType ?? _chartType;
        _expandedSongs = List.unmodifiable(
            _folderSongsFor(_expandedFolder!, preferredType: preferredType));
        final displayed = _usesSelectedChartForFolder(_expandedFolder!)
            ? _folderSongsFor(_expandedFolder!, preferredType: preferredType)
            : _expandedSongs;
        final selectedIndex = displayed.indexWhere((chart) =>
            chart.songTitle == previousSongTitle &&
            (chart.type == previousChartType ||
                !displayed.any((item) =>
                    item.songTitle == previousSongTitle &&
                    item.type == previousChartType)));
        if (selectedIndex >= 0) {
          _selectedSongTitle = displayed[selectedIndex].songTitle;
          _selectedExpandedIndex = selectedIndex;
          _selectedRowBaseChartId = displayed[selectedIndex].id;
          _folderSelected = false;
        }
      }
    });
  }

  void _openFolder(String folder) {
    if (_expandedFolder == folder) {
      setState(() {
        final chartTypeBeforeFolder = _chartTypeBeforeFolder;
        _expandedFolder = null;
        _folderChartType = null;
        _chartTypeBeforeFolder = null;
        _expandedSongs = const [];
        _selectedExpandedIndex = null;
        _selectedSongTitle = null;
        _selectedRowBaseChartId = null;
        _selectedRowChartOverride = null;
        _folderSelected = true;
        if (chartTypeBeforeFolder != null) {
          _chartType = chartTypeBeforeFolder;
        }
      });
      return;
    }

    final songs = _folderSongsFor(folder, preferredType: _chartType);
    // 空フォルダは展開せず、通常のフォルダ選択状態を維持する。
    if (songs.isEmpty) return;

    setState(() {
      _chartTypeBeforeFolder ??= _chartType;
      _folder = folder;
      _expandedFolder = folder;
      _folderChartType = _chartType;
      // 展開した時点で、フォルダ条件に該当する譜面を確定する。
      // 以後の譜面種類切替で、この一覧は差し替えない。
      _expandedSongs = List.unmodifiable(songs);
      _selectedExpandedIndex = null;
      _folderSelected = true;
      _selectedSongTitle = null;
      _selectedRowBaseChartId = null;
      _selectedRowChartOverride = null;
    });
  }

  void _focusFolder(String folder) {
    if (_folderSelected && _folder == folder && _selectedSongTitle == null) {
      return;
    }
    setState(() {
      _folder = folder;
      _folderSelected = true;
      _selectedExpandedIndex = null;
      _selectedSongTitle = null;
      _selectedRowBaseChartId = null;
      _selectedRowChartOverride = null;
    });
  }

  bool _isInitialFolder(String folder) => const {
        'ABCD',
        'EFGH',
        'IJKL',
        'MNOP',
        'QRST',
        'UVWXYZ',
        '0-9',
        'OTHERS'
      }.contains(folder);

  bool _usesSelectedChartForFolder(String folder) =>
      _isInitialFolder(folder) ||
      _MusicSelectPanel.versionFolders.contains(folder);

  List<Chart> get _visibleExpandedSongs =>
      _expandedFolder != null && _usesSelectedChartForFolder(_expandedFolder!)
          ? _folderSongsFor(_expandedFolder!,
              preferredType: _folderChartType ?? _chartType)
          : _expandedSongs;

  /// フォルダ選択時に表示する曲数。VERSION／INITIALは譜面種類の選択に
  /// 応じて1曲1譜面、LEVELやCLEAR等は譜面単位で数える。
  int get _selectedFolderSongCount => _folderSongsFor(_folder,
          preferredType: _expandedFolder == _folder
              ? (_folderChartType ?? _chartType)
              : _chartType)
      .length;

  Chart _displayChartForList(Chart chart) {
    final override = _selectedRowChartOverride;
    return !_folderSelected &&
            override != null &&
            chart.id == _selectedRowBaseChartId
        ? override
        : chart;
  }

  void _selectSongAt(int index) {
    if (index < 0 || index >= _visibleExpandedSongs.length) return;
    final chart = _visibleExpandedSongs[index];
    if (!_folderSelected &&
        _selectedExpandedIndex == index &&
        _chartType == chart.type) {
      return;
    }
    setState(() {
      _selectedSongTitle = chart.songTitle;
      _selectedExpandedIndex = index;
      _selectedRowBaseChartId = chart.id;
      _selectedRowChartOverride = null;
      _folderSelected = false;
      _chartType = chart.type;
    });
  }

  /// ホイール／ドラッグの途中で選択行に最も近い楽曲を反映する。
  /// リスト座標の再固定を抑止するため、スクロールは中断しない。
  void _focusSongAt(int index) {
    if (index < 0 || index >= _visibleExpandedSongs.length) return;
    final chart = _visibleExpandedSongs[index];
    if (!_folderSelected &&
        _selectedExpandedIndex == index &&
        _chartType == chart.type) {
      return;
    }
    setState(() {
      _selectedSongTitle = chart.songTitle;
      _selectedExpandedIndex = index;
      _selectedRowBaseChartId = chart.id;
      _selectedRowChartOverride = null;
      _folderSelected = false;
      _chartType = chart.type;
      _transientSongFocus = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_transientSongFocus) return;
      setState(() => _transientSongFocus = false);
    });
  }

  void _handleBack() => widget.onBack();

  void _changeSort(String value) {
    if (_sort == value) return;
    // 楽曲選択中に譜面だけを一時切替している場合も、ソート対象として
    // 追跡すべきなのはフォルダ展開時の元リスト行。
    final selectedChartId =
        _folderSelected ? null : (_selectedRowBaseChartId ?? _chart.id);
    setState(() {
      _sort = value;
      // VERSION／INITIAL以外は展開時の譜面一覧を保持しているため、
      // ソート変更時にここで作り直す。選択中の譜面があれば同じ譜面を
      // 新しい並びでも選択し続ける。
      final folder = _expandedFolder;
      if (folder == null) return;
      final preferredType = _folderChartType ?? _chartType;
      _expandedSongs = List.unmodifiable(
          _folderSongsFor(folder, preferredType: preferredType));
      final displayed = _usesSelectedChartForFolder(folder)
          ? _folderSongsFor(folder, preferredType: preferredType)
          : _expandedSongs;
      final index = selectedChartId == null
          ? -1
          : displayed.indexWhere((chart) => chart.id == selectedChartId);
      if (index >= 0) {
        _selectedExpandedIndex = index;
        _selectedSongTitle = displayed[index].songTitle;
        _selectedRowBaseChartId = displayed[index].id;
        _selectedRowChartOverride = null;
        _folderSelected = false;
        _chartType = displayed[index].type;
      } else {
        _selectedExpandedIndex = null;
        _selectedSongTitle = null;
        _selectedRowBaseChartId = null;
        _selectedRowChartOverride = null;
        _folderSelected = true;
      }
    });
  }

  List<Chart> _folderSongsFor(String folder, {ChartType? preferredType}) {
    final effectiveType = preferredType ?? _chartType;
    // フォルダ抽出条件を変更した際、Hot Reload 後にも旧条件の一覧を
    // 再利用しないよう、キャッシュ仕様の世代をキーに含める。
    // v2: DJ LEVEL F はスコア1点以上の譜面だけを格納する。
    final key = 'v2|${_style.name}|$folder|${effectiveType.name}|$_sort';
    return _folderSongsCache.putIfAbsent(
      key,
      () => List.unmodifiable(
          _buildFolderSongsFor(folder, preferredType: effectiveType)),
    );
  }

  /// フォルダ内にNO PLAYが1譜面でもあればランプなし。全譜面がプレイ済みの
  /// 場合は、最も低い（一覧上で最も下の）クリア状況をフォルダ行へ表示する。
  ClearType? _folderClearFor(String folder) {
    final key = '${_style.name}|$folder|${_chartType.name}|$_sort';
    return _folderClearCache.putIfAbsent(key, () {
      final charts = _folderSongsFor(folder);
      if (charts.isEmpty) return null;
      final clears = charts.map((chart) => _recordFor(chart).clear).toList();
      if (clears.any((clear) => clear == ClearType.noPlay)) return null;
      return clears.reduce((lowest, clear) =>
          _clearOrder(clear) < _clearOrder(lowest) ? clear : lowest);
    });
  }

  List<Chart> _buildFolderSongsFor(String folder,
      {required ChartType preferredType}) {
    var filtered = _styleCharts;
    if (folder.startsWith('LEVEL ')) {
      final level = int.tryParse(folder.substring(6));
      filtered = filtered.where((item) => item.level == level).toList();
    } else if (folder == 'LEGGENDARIA') {
      filtered =
          filtered.where((item) => item.type == ChartType.leggendaria).toList();
    } else if (folder == 'ABCD' ||
        folder == 'EFGH' ||
        folder == 'IJKL' ||
        folder == 'MNOP' ||
        folder == 'QRST' ||
        folder == 'UVWXYZ') {
      final ranges = {
        'ABCD': 'ABCD',
        'EFGH': 'EFGH',
        'IJKL': 'IJKL',
        'MNOP': 'MNOP',
        'QRST': 'QRST',
        'UVWXYZ': 'UVWXYZ',
      };
      final initials = ranges[folder]!;
      filtered = filtered
          .where((item) =>
              item.songTitle.isNotEmpty &&
              initials.contains(item.songTitle[0].toUpperCase()))
          .toList();
    } else if (folder == '0-9') {
      filtered = filtered
          .where((item) => RegExp(r'^[0-9]').hasMatch(item.songTitle))
          .toList();
    } else if (folder == 'OTHERS') {
      filtered = filtered
          .where((item) => !RegExp(r'^[A-Za-z0-9]').hasMatch(item.songTitle))
          .toList();
    } else if (_MusicSelectPanel.versionFolders.contains(folder)) {
      // マスタは公式表記（例: "Sparkle Shower"）を保持し、フォルダは
      // デザイン用の大文字表記（例: "SPARKLE SHOWER"）を使うため、大文字・
      // 小文字を区別せずに照合する。
      filtered = filtered
          .where((item) => item.version.toUpperCase() == folder.toUpperCase())
          .toList();
    }

    final attribute = _radarFolderAttribute(folder);
    if (attribute != null) return _applySort(_topRadarCharts(attribute));
    if (folder.startsWith('DJ LEVEL ')) {
      final target = folder.substring('DJ LEVEL '.length);
      filtered = filtered
          .where((item) =>
              _djLevel(_recordFor(item).score, item.maxScore) == target &&
              // DJ LEVEL Fは、未プレイ（0点）ではなくプレイ済みの
              // 1点以上だけを表示する。
              (target != 'F' || _recordFor(item).score > 0))
          .toList();
    } else if (folder.startsWith('RIVAL') || folder.startsWith('MY BEST')) {
      filtered = filtered
          .where((chart) => _matchesRivalFolder(chart, folder))
          .toList();
    } else {
      final clear = _clearForFolder(folder);
      if (clear != null) {
        filtered =
            filtered.where((item) => _recordFor(item).clear == clear).toList();
      }
    }

    if (folder.startsWith('LEVEL ')) {
      final charts = filtered.toList()
        ..sort((a, b) => _compareDefaultTitle(a.songTitle, b.songTitle));
      return _applySort(charts);
    }
    if (folder == 'LEGGENDARIA' ||
        folder.startsWith('DJ LEVEL ') ||
        folder.startsWith('RIVAL') ||
        folder.startsWith('MY BEST') ||
        _clearForFolder(folder) != null) {
      final charts = filtered.toList()..sort(_compareByLevelThenTitle);
      return _applySort(charts);
    }
    return _applySort(_oneChartPerSong(
      filtered,
      preferredType,
      sortByLevel: _MusicSelectPanel.versionFolders.contains(folder),
    ));
  }

  /// 「デフォルト」は各フォルダ固有の既定順を維持する。
  /// それ以外は選択した基準で並べ、同値時は楽曲名・譜面種類で安定化する。
  List<Chart> _applySort(List<Chart> defaults) {
    if (_sort == 'デフォルト') return defaults;
    final charts = defaults.toList();
    int byTitleThenChart(Chart a, Chart b) {
      final title = _compareDefaultTitle(a.songTitle, b.songTitle);
      return title != 0 ? title : a.type.index.compareTo(b.type.index);
    }

    // 変化BPM（例: 100～180 BPM）は上限値で比較する。
    int bpmMaximum(Chart chart) {
      final values = RegExp(r'\d+')
          .allMatches(chart.bpm)
          .map((match) => int.tryParse(match.group(0)!) ?? 0);
      return values.isEmpty ? 0 : values.reduce(math.max);
    }

    int scoreRateAscending(Chart a, Chart b) {
      // 小数へ丸めず、score / maxScore を通分して比較する。
      // 同率の譜面は後段の曲名・譜面種類による安定ソートへ渡す。
      final aMax = a.maxScore > 0 ? a.maxScore : 1;
      final bMax = b.maxScore > 0 ? b.maxScore : 1;
      return (_recordFor(a).score * bMax).compareTo(_recordFor(b).score * aMax);
    }

    charts.sort((a, b) {
      int result;
      switch (_sort) {
        case '曲名':
          result = _compareDefaultTitle(a.songTitle, b.songTitle);
        case 'レベル':
          result = a.level.compareTo(b.level);
        case '譜面難易度':
          result = a.type.index.compareTo(b.type.index);
        case 'スコアレート':
          result = scoreRateAscending(a, b);
        case 'クリアランプ':
          // クリアランプは弱い順。同一ランプ内はMISS COUNTの多い順。
          result = _clearOrder(_recordFor(a).clear)
              .compareTo(_clearOrder(_recordFor(b).clear));
          if (result == 0) {
            result = (_recordFor(b).missCount ?? -1)
                .compareTo(_recordFor(a).missCount ?? -1);
          }
        case 'BPM':
          result = bpmMaximum(a).compareTo(bpmMaximum(b));
        default:
          result = 0;
      }
      return result != 0 ? result : byTitleThenChart(a, b);
    });
    return charts;
  }

  PlayRecord _recordFor(Chart chart) =>
      widget.repository.recordFor(chart.id) ??
      PlayRecord(
          chartId: chart.id,
          score: 0,
          clear: ClearType.noPlay,
          version: chart.version);

  List<Chart> _oneChartPerSong(
    Iterable<Chart> charts,
    ChartType preferredType, {
    bool sortByLevel = false,
  }) {
    final grouped = <String, List<Chart>>{};
    for (final chart in charts) {
      (grouped[chart.songTitle] ??= []).add(chart);
    }
    final selected = grouped.values.map((variants) {
      Chart? byType(ChartType type) =>
          variants.where((item) => item.type == type).firstOrNull;
      return switch (preferredType) {
        ChartType.beginner => byType(ChartType.beginner) ??
            byType(ChartType.hyper) ??
            variants.first,
        ChartType.another => byType(ChartType.another) ??
            byType(ChartType.hyper) ??
            variants.first,
        ChartType.leggendaria => byType(ChartType.leggendaria) ??
            byType(ChartType.another) ??
            variants.first,
        _ => byType(preferredType) ?? variants.first,
      };
    }).toList()
      ..sort(sortByLevel
          ? _compareByLevelThenTitle
          : (a, b) => _compareDefaultTitle(a.songTitle, b.songTitle));
    return selected;
  }

  /// レベル値の昇順。同じレベル内では楽曲名の昇順にする。
  int _compareByLevelThenTitle(Chart a, Chart b) {
    final byLevel = a.level.compareTo(b.level);
    return byLevel != 0
        ? byLevel
        : _compareDefaultTitle(a.songTitle, b.songTitle);
  }

  /// デフォルトの曲名順は INITIAL フォルダと同じ分類にする。
  /// 英字 A-Z を先頭に、数字、記号・日本語などの OTHER を最後へ並べる。
  int _compareDefaultTitle(String a, String b) {
    int groupOf(String title) {
      if (title.isEmpty) return 2;
      final first = title.codeUnitAt(0);
      if ((first >= 65 && first <= 90) || (first >= 97 && first <= 122)) {
        return 0;
      }
      if (first >= 48 && first <= 57) return 1;
      return 2;
    }

    final group = groupOf(a).compareTo(groupOf(b));
    if (group != 0) return group;
    return a.toUpperCase().compareTo(b.toUpperCase());
  }

  List<Chart> _topRadarCharts(RadarAttribute attribute) {
    // 属性フォルダは楽曲単位ではなく譜面単位。
    // その譜面で最も高い属性にだけ所属させるため、
    // 同一曲でも譜面ごとに異なる属性フォルダへ表示できる。
    final charts = _styleCharts
        .where((chart) =>
            chart.hasRadarData &&
            chart.maxRadar.isStrongest(attribute) &&
            _recordFor(chart).score > 0)
        .toList()
      ..sort((a, b) {
        // 属性フォルダのデフォルト順は、自分のスコア率を反映した
        // 実レーダー値の降順。
        final radarOrder = _actualRadarValue(b, attribute)
            .compareTo(_actualRadarValue(a, attribute));
        if (radarOrder != 0) return radarOrder;
        final titleOrder = a.songTitle.compareTo(b.songTitle);
        if (titleOrder != 0) return titleOrder;
        return a.type.index.compareTo(b.type.index);
      });
    return charts.take(20).toList();
  }

  double _actualRadarValue(Chart chart, RadarAttribute attribute) {
    if (chart.maxScore <= 0) return 0;
    final ratio =
        (_recordFor(chart).score / chart.maxScore).clamp(0.0, 1.0).toDouble();
    return chart.maxRadar.by(attribute) * ratio;
  }

  bool _matchesRivalFolder(Chart chart, String folder) {
    final match = RegExp(r'^(MY BEST|RIVAL(\d+)) (SCORE|CLEAR) (WIN|LOSE)$')
        .firstMatch(folder);
    if (match == null) return false;
    final isMyBest = match.group(1) == 'MY BEST';
    final best = isMyBest ? widget.repository.bestRecordFor(chart.id) : null;
    final rival = isMyBest
        ? null
        : widget.repository
            .rivalScoreForSlot(chart, int.parse(match.group(2)!));
    final opponentScore = isMyBest ? best?.score ?? 0 : rival?.score ?? 0;
    final opponentClear = isMyBest
        ? best?.clear ?? ClearType.noPlay
        : rival?.clear ?? ClearType.noPlay;
    // 未プレイ（スコア0）の譜面は、SCORE／CLEARいずれの勝敗フォルダにも
    // 入れない。未登録・NO PLAYを敗北として大量に表示しないための条件。
    if (opponentScore <= 0) return false;
    final mine = _recordFor(chart);
    final category = match.group(3)!;
    final result = match.group(4)!;
    if (category == 'CLEAR' &&
        result == 'LOSE' &&
        mine.clear == ClearType.fullCombo) {
      return false;
    }
    final comparison = category == 'SCORE'
        ? mine.score.compareTo(opponentScore)
        : _clearOrder(mine.clear).compareTo(_clearOrder(opponentClear));
    return result == 'WIN' ? comparison > 0 : comparison <= 0;
  }

  @override
  Widget build(BuildContext context) => Focus(
        autofocus: true,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          // リスト外にカーソルがあっても、PLAY DATA画面上のホイール操作は
          // MUSIC SELECTへ渡す。内部で従来どおり1ノッチ＝1行へ正規化する。
          onPointerSignal: (event) =>
              _musicSelectKey.currentState?.handleExternalPointerSignal(event),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewport = constraints.biggest;
              final scale = math.min(viewport.width / _canvas.width,
                  viewport.height / _canvas.height);
              final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
              final contentWidth = _canvas.width * scale;
              final contentHeight = _canvas.height * scale;
              final offsetX = (viewport.width - contentWidth) / 2;
              final offsetY = (viewport.height - contentHeight) / 2;
              double snap(double value) =>
                  (value * devicePixelRatio).roundToDouble() / devicePixelRatio;

              return Stack(children: [
                Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: _canvas.width,
                      height: _canvas.height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset('assets/images/blue_sky_clean.png',
                              fit: BoxFit.cover),
                          const Positioned(
                              left: 22,
                              top: 16,
                              child: _OutlineText('IIDX PLAY DATA',
                                  fontSize: 20,
                                  fontFamily: 'Gochikakutto',
                                  letterSpacing: 1.5,
                                  color: Color(0xffffd45a))),
                          Positioned(
                              left: 16,
                              top: 48,
                              width: 340,
                              height: 91,
                              child: _TopLeftChrome(
                                  selected: _style,
                                  onSp: () => _selectStyle(PlayStyle.sp),
                                  onDp: () => _selectStyle(PlayStyle.dp))),
                          Positioned(
                              left: 62,
                              top: 158,
                              width: 480,
                              child: _folderSelected
                                  ? _FolderSongCount(
                                      count: _selectedFolderSongCount)
                                  : _SongBlock(chart: _chart)),
                          Positioned(
                              left: 62,
                              top: 370,
                              width: 470,
                              child: _ChartSelector(
                                  selected: _chartType,
                                  available: _folderSelected
                                      ? ChartType.values.toSet()
                                      : _selectedSongCharts
                                          .map((item) => item.type)
                                          .toSet(),
                                  levels: {
                                    for (final item in _selectedSongCharts)
                                      item.type: item.level
                                  },
                                  showLevels: !_folderSelected,
                                  onSelect: (value) => setState(() {
                                        // 楽曲選択中の譜面切替は、左側の表示だけを
                                        // 切り替える。一覧のソート／選択行や、
                                        // フォルダを開いた時点の基準譜面は変更しない。
                                        // 次の楽曲へ選択行を移すと、一覧に表示している
                                        // 基準譜面（_folderChartType）へ戻る。
                                        _chartType = value;
                                        if (!_folderSelected) {
                                          // 選択行だけは、切替後の譜面の情報を表示する。
                                          // それ以外の行はフォルダ展開時の表示を保つ。
                                          _selectedRowChartOverride =
                                              _selectedSongCharts
                                                  .where((chart) =>
                                                      chart.type == value)
                                                  .firstOrNull;
                                        } else if (_expandedFolder != null) {
                                          // フォルダ行を選択中の切替は、従来どおり
                                          // フォルダを開いた基準譜面として扱う。
                                          _folderChartType = value;
                                        }
                                      }))),
                          Positioned(
                              left: 56,
                              top: 470,
                              width: 555,
                              height: 181,
                              child: _folderSelected
                                  ? const _PlayStatus.empty()
                                  : _PlayStatus(
                                      chart: _chart, record: _record)),
                          Positioned(
                              left: 55,
                              top: 666,
                              width: 783,
                              height: 260,
                              child: _RivalScorePanel(
                                  chart: _chart,
                                  scores: widget.repository.rivalScores(_chart),
                                  summaries: _rivalWinLossSummaries,
                                  folderSelected: _folderSelected)),
                          Positioned(
                              left: 545,
                              top: 64,
                              width: 420,
                              height: 445,
                              child: _RadarBlock(
                                  chart: _chart,
                                  record: _record,
                                  overallRadar:
                                      _folderSelected ? _overallRadar : null,
                                  hasOverallRadar: _hasOverallRadar)),
                          Positioned(
                              left: 1034,
                              top: 22,
                              width: 348,
                              height: 47,
                              child: _RadarListButton(onTap: _openRadarList)),
                          Positioned(
                              left: 1455,
                              top: 20,
                              width: 203,
                              height: 54,
                              child: _BackButton(onTap: _handleBack)),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: snap(offsetX + 1038 * scale),
                  top: snap(offsetY + 106 * scale),
                  width: snap(622 * scale),
                  height: snap(816 * scale),
                  child: _MusicSelectPanel(
                      key: _musicSelectKey,
                      selected: _folder,
                      sort: _sort,
                      scale: scale,
                      devicePixelRatio: devicePixelRatio,
                      expandedFolder: _expandedFolder,
                      songs: _visibleExpandedSongs,
                      selectedSongTitle: _selectedSongTitle,
                      selectedSongIndex: _selectedExpandedIndex,
                      transientSongFocus: _transientSongFocus,
                      rivalNames: _rivalNames,
                      rivalProfiles: _rivalProfiles,
                      showMyBest: widget.repository.hasHistoricalPlayerData,
                      displayChartForRow: _displayChartForList,
                      clearForChart: (chart) => _recordFor(chart).clear,
                      folderClearFor: _folderClearFor,
                      visibleFolderGroups: widget.visibleFolderGroups,
                      onOpenFolder: _openFolder,
                      onSelectSong: _selectSongAt,
                      onFocusFolder: _focusFolder,
                      onFocusSong: _focusSongAt,
                      onSort: _changeSort),
                ),
              ]);
            },
          ),
        ),
      );

  bool _handleHardwareKeyEvent(KeyEvent event) {
    final pageDirection = switch (event.logicalKey) {
      LogicalKeyboardKey.pageUp => -1,
      LogicalKeyboardKey.pageDown => 1,
      _ => 0,
    };
    if (pageDirection != 0) {
      if (event is KeyDownEvent) {
        _musicSelectKey.currentState?.scrollByPage(pageDirection);
      }
      // KeyRepeatEventもここで消費して、OSの既定スクロール処理へ渡さない。
      return true;
    }
    return _handleListKeyEvent(event) == KeyEventResult.handled;
  }

  KeyEventResult _handleListKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
    final arrowDirection = switch (key) {
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.arrowDown => 1,
      _ => 0,
    };
    if (arrowDirection == 0) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      // OS側のリピート間隔には依存せず、最初の1行移動の後に少し待ち、
      // そこから一定速度で送る、一般的なキーリピートを再現する。
      if (_heldArrowKey == key) return KeyEventResult.handled;
      _stopArrowRepeat();
      _heldArrowKey = key;
      _musicSelectKey.currentState?.scrollByKeyboardRows(arrowDirection);
      _arrowRepeatDelayTimer = Timer(const Duration(milliseconds: 340), () {
        if (!mounted || _heldArrowKey != key) return;
        _arrowRepeatTimer =
            Timer.periodic(const Duration(milliseconds: 10), (_) {
          _musicSelectKey.currentState?.scrollByKeyboardRows(arrowDirection);
        });
      });
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent && _heldArrowKey == key) {
      _stopArrowRepeat();
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  void _stopArrowRepeat() {
    _arrowRepeatDelayTimer?.cancel();
    _arrowRepeatDelayTimer = null;
    _arrowRepeatTimer?.cancel();
    _arrowRepeatTimer = null;
    _heldArrowKey = null;
  }

  @override
  void dispose() {
    _stopArrowRepeat();
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    super.dispose();
  }

  void _openRadarList() => showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => _RadarListOverlay(repository: widget.repository));
}

const _kPanel = Color(0xe9051f3c);
const _kCyan = Color(0xff35dcff);
const _kLine = Color(0xff2ec8ed);

class _TopLeftChrome extends StatelessWidget {
  const _TopLeftChrome(
      {required this.selected, required this.onSp, required this.onDp});
  final PlayStyle selected;
  final VoidCallback onSp;
  final VoidCallback onDp;

  @override
  Widget build(BuildContext context) => ClipPath(
        clipper: const _CutCornerClipper(cut: 13),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xdd0a4167), Color(0xcc05213b)]),
            border: Border.all(color: _kCyan.withValues(alpha: .9), width: 1.3),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x66000000), blurRadius: 7, offset: Offset(1, 3))
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _OutlineText('PLAY STYLE',
                fontSize: 14,
                fontFamily: 'Gochikakutto',
                letterSpacing: 1.4,
                color: Color(0xffb9f5ff)),
            const SizedBox(height: 6),
            Row(children: [
              _StyleButton(
                  label: 'SP', selected: selected == PlayStyle.sp, onTap: onSp),
              const SizedBox(width: 9),
              _StyleButton(
                  label: 'DP', selected: selected == PlayStyle.dp, onTap: onDp),
            ]),
          ]),
        ),
      );
}

class _StyleButton extends StatelessWidget {
  const _StyleButton(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: selected
                  ? const LinearGradient(
                      colors: [Color(0xff209dff), Color(0xff0573d7)])
                  : const LinearGradient(
                      colors: [Color(0xff18324a), Color(0xff071d30)]),
              border: Border.all(
                  color: selected ? _kCyan : const Color(0xffffb52f),
                  width: 1.6),
              borderRadius: BorderRadius.circular(7),
              boxShadow: selected
                  ? const [BoxShadow(color: Color(0x9935dcff), blurRadius: 9)]
                  : null,
            ),
            child: _OutlineText(label,
                fontSize: 18,
                weight: FontWeight.bold,
                fontFamily: 'Gochikakutto'),
          ),
        ),
      );
}

/// フォルダを選択している間だけ、BPMの位置を曲数表示へ置き換える。
/// 左側ラベルと数値の構成はPLAY DATA欄と揃え、選択対象が曲ではないことを
/// ひと目で分かるようにする。
class _FolderSongCount extends StatelessWidget {
  const _FolderSongCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 188,
        child: Padding(
          // SongBlock内のBPM行と同じ高さへ合わせる。
          padding: const EdgeInsets.only(top: 160),
          child: Align(
            // 左側の譜面種類（幅470）の中央へ合わせる。
            alignment: const Alignment(-.02, 0),
            child: ClipPath(
              clipper: const _CountPanelClipper(cut: 14),
              child: Container(
                width: 240,
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Color(0x99093855),
                    Color(0xa6001229),
                  ]),
                ),
                child: Row(children: [
                  const SizedBox(
                      width: 62,
                      child: _OutlineText('曲数',
                          fontSize: 22,
                          fontFamily: 'Gochikakutto',
                          letterSpacing: 1.2)),
                  const SizedBox(width: 14),
                  Transform.translate(
                    offset: const Offset(0, -2),
                    child: _OutlineText(count.toString().padLeft(4, '0'),
                        fontSize: 26,
                        weight: FontWeight.w500,
                        fontFamily: 'Gochikakutto',
                        letterSpacing: 1.4),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// 曲数表示用の、左右が＜ ＞になる小型パネル。
class _CountPanelClipper extends CustomClipper<Path> {
  const _CountPanelClipper({required this.cut});

  final double cut;

  @override
  Path getClip(Size size) => Path()
    ..moveTo(cut, 0)
    ..lineTo(size.width - cut, 0)
    ..lineTo(size.width, size.height / 2)
    ..lineTo(size.width - cut, size.height)
    ..lineTo(cut, size.height)
    ..lineTo(0, size.height / 2)
    ..close();

  @override
  bool shouldReclip(covariant _CountPanelClipper oldClipper) =>
      cut != oldClipper.cut;
}

class _SongBlock extends StatelessWidget {
  const _SongBlock({required this.chart});
  final Chart chart;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 438,
          child: Center(
              child: _OutlineText(chart.version,
                  fontSize: 18, letterSpacing: 1.5)),
        ),
        const SizedBox(height: 6),
        _OutlineText(chart.genre, fontSize: 19, letterSpacing: 1.3),
        const SizedBox(height: 4),
        // タイトルだけは右方向へ広げる。バージョン名・BPMの中央揃え位置は
        // 既存の楽曲情報幅のまま維持する。
        _TitleText(chart.songTitle,
            fontSize: 60,
            weight: FontWeight.w300,
            letterSpacing: 1.5,
            leggendariaGradient: chart.type == ChartType.leggendaria),
        const SizedBox(height: 4),
        _OutlineText(chart.artist, fontSize: 20, letterSpacing: 1.7),
        const SizedBox(height: 6),
        SizedBox(
          width: 438,
          child: Center(child: _OutlineText(chart.bpm, fontSize: 18)),
        ),
      ]);
}

class _ChartSelector extends StatelessWidget {
  const _ChartSelector(
      {required this.selected,
      required this.available,
      required this.levels,
      required this.showLevels,
      required this.onSelect});
  final ChartType selected;
  final Set<ChartType> available;
  final Map<ChartType, int> levels;
  final bool showLevels;
  final ValueChanged<ChartType> onSelect;
  @override
  Widget build(BuildContext context) {
    _button(ChartType type) => _ChartButton(
        type: type,
        level: showLevels ? levels[type] : null,
        selected: selected == type,
        enabled: available.contains(type),
        onTap: () => onSelect(type));
    return SizedBox(
      width: 470,
      // 1列表示でもプレビューと同じ厚みを保てる高さを確保する。
      height: 80,
      child: Row(
        children: [
          for (final type in ChartType.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _button(type),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChartButton extends StatelessWidget {
  const _ChartButton(
      {required this.type,
      required this.level,
      required this.selected,
      required this.enabled,
      required this.onTap});
  final ChartType type;
  final int? level;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  /// 譜面種別セレクタ専用の、原色寄りで明るい配色。
  Color get _color => switch (type) {
        ChartType.beginner => const Color(0xff18b44d),
        ChartType.normal => const Color(0xff198bda),
        ChartType.hyper => const Color(0xffd89c00),
        ChartType.another => const Color(0xffcc2a3e),
        ChartType.leggendaria => const Color(0xff7a30b8),
      };

  @override
  Widget build(BuildContext context) => Opacity(
        // 譜面が存在しない時は、従来どおり見た目も操作も無効化する。
        opacity: enabled ? 1 : .34,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: SizedBox(
              // Stack配下のContainerが横0幅へ縮まないよう、プレビューと
              // 同じ横長比率を明示する。
              width: 88,
              height: 76,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Transform.translate(
                    // レベル数値の位置は固定したまま、楕円だけ少し下げる。
                    offset: const Offset(0, 6),
                    child: Transform.rotate(
                      // Flutterの正方向は画面上で右下がりになるため、プレビューと
                      // 同じ「左下→右上」の向きには負の角度を使う。
                      angle: -.19,
                      child: SizedBox(
                        width: 88,
                        height: 50,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CustomPaint(
                              painter: _ChartOvalPainter(
                                  color: _color, selected: selected),
                            ),
                            _ChartTypeLabel(
                                label: type.label, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (level != null)
                    Transform.translate(
                      offset: const Offset(0, 11),
                      child: Text(
                        '$level',
                        maxLines: 1,
                        style: const TextStyle(
                          fontFamily: 'Gochikakutto',
                          fontSize: 54,
                          height: 1,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Colors.black, offset: Offset(-1, -1)),
                            Shadow(color: Colors.black, offset: Offset(1, -1)),
                            Shadow(color: Colors.black, offset: Offset(-1, 1)),
                            Shadow(color: Colors.black, offset: Offset(1, 1)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ChartTypeLabel extends StatelessWidget {
  const _ChartTypeLabel({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
          width: 70,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .35,
                color: color,
                shadows: const [
                  Shadow(color: Color(0xcc00101e), blurRadius: 1.2),
                ],
              ),
            ),
          ),
        ),
      );
}

/// 横長の実楕円を描く。BoxDecorationのcircleは短辺基準の円になってしまうため、
/// ここではCanvasのdrawOvalでプレビューと同じ形状を固定する。
class _ChartOvalPainter extends CustomPainter {
  const _ChartOvalPainter({required this.color, required this.selected});
  final Color color;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Offset.zero & size;
    if (selected) {
      canvas.drawOval(
          outer.inflate(2),
          Paint()
            ..color = const Color(0xaa43e5ff)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    }
    canvas.drawOval(outer, Paint()..color = color);
    canvas.drawOval(
        outer.deflate(selected ? 1.4 : 1),
        Paint()
          ..color = selected ? const Color(0xffeafdff) : Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.8 : 2);
    canvas.drawOval(
        outer.deflate(6),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8);
  }

  @override
  bool shouldRepaint(covariant _ChartOvalPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.selected != selected;
}

class _PlayStatus extends StatelessWidget {
  const _PlayStatus({required this.chart, required this.record});
  const _PlayStatus.empty()
      : chart = null,
        record = null;
  final Chart? chart;
  final PlayRecord? record;
  @override
  Widget build(BuildContext context) {
    final isEmpty = chart == null;
    final score = record?.score ?? 0;
    final percent = chart == null || chart!.maxScore <= 1
        ? 0.0
        : score / chart!.maxScore * 100;
    final rank = _normaliseDjLevel(record?.officialDjLevel) ??
        (chart == null ? '' : _djLevel(score, chart!.maxScore));
    final clear = record?.clear ?? ClearType.noPlay;
    return ClipPath(
      clipper: const _CutCornerClipper(cut: 18),
      child: Container(
        color: _kPanel,
        padding: const EdgeInsets.fromLTRB(16, 8, 26, 10),
        child: Column(children: [
          _StatusLine(
              label: 'DJ LEVEL',
              value: isEmpty ? '' : rank,
              color: isEmpty ? Colors.white : _rankColor(rank)),
          _StatusLine(
              label: 'SCORE',
              value: isEmpty ? '' : '$score',
              color: _kCyan,
              extra: isEmpty ? null : _rankDelta(score, chart!.maxScore),
              extraColor: isEmpty
                  ? null
                  : _isNegativeRankDelta(_rankDelta(score, chart!.maxScore))
                      ? const Color(0xffff4b4b)
                      : Colors.white,
              extraSuffix: isEmpty ? null : '(${percent.toStringAsFixed(1)}%)'),
          _StatusLine(
              label: 'MISS COUNT',
              value: isEmpty ? '' : '${record?.missCount ?? '-'}',
              color: const Color(0xffd8f3ff)),
          _StatusLine(
              label: 'CLEAR',
              value: isEmpty ? '' : clear.label,
              color: _clearColor(clear)),
          const SizedBox(height: 5),
          _DjLevelGauge(
              score: score,
              maxScore: chart?.maxScore ?? 0,
              rank: rank,
              fullCombo: clear == ClearType.fullCombo,
              enabled: !isEmpty),
        ]),
      ),
    );
  }
}

/// SCORE DATA下部のDJ LEVELゲージ。達成率に応じて左から伸びる。
class _DjLevelGauge extends StatelessWidget {
  const _DjLevelGauge(
      {required this.score,
      required this.maxScore,
      required this.rank,
      required this.fullCombo,
      required this.enabled});

  final int score;
  final int maxScore;
  final String rank;
  final bool fullCombo;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final gaugeRate = _djLevelGaugeRate(score, maxScore);
    final fill = switch (rank) {
      'AAA' when fullCombo => null,
      // AAA帯はコーラル寄りではなく、くっきりした赤で表示する。
      'AAA' => const Color(0xffec424d),
      'AA' => const Color(0xffe18b39),
      'A' => const Color(0xff33c6e7),
      // B以下は実機のE帯と同系統の黄緑で統一する。
      _ => const Color(0xff85ae3d),
    };
    final labels = const ['F', 'E', 'D', 'C', 'B', 'A', 'AA', 'AAA'];
    return SizedBox(
      height: 26,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xff122d47),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Stack(children: [
          if (enabled && gaugeRate > 0)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) => Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: constraints.maxWidth * gaugeRate,
                    height: constraints.maxHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: fill,
                        gradient: fullCombo && rank == 'AAA'
                            ? const LinearGradient(colors: [
                                Color(0xffff6e90),
                                Color(0xffffcf58),
                                Color(0xff6ee9d7),
                                Color(0xff8d78ff),
                              ])
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // 外枠とランク境界線は、塗りゲージより必ず前面に置く。
          const Positioned.fill(
              child: CustomPaint(
            painter: _DjLevelGaugeFramePainter(),
          )),
          Row(
              children: labels
                  .map((label) => Expanded(
                      child: Center(
                          child: _OutlineText(label,
                              fontSize: label.length == 3 ? 13 : 15,
                              color: Colors.white,
                              weight: FontWeight.bold))))
                  .toList()),
        ]),
      ),
    );
  }
}

class _DjLevelGaugeFramePainter extends CustomPainter {
  const _DjLevelGaugeFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xffb9e9ff)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final halfStroke = paint.strokeWidth / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          halfStroke,
          halfStroke,
          size.width - paint.strokeWidth,
          size.height - paint.strokeWidth,
        ),
        const Radius.circular(2),
      ),
      paint,
    );
    for (var index = 1; index < 8; index++) {
      final x = size.width * index / 8;
      canvas.drawLine(
        Offset(x, halfStroke),
        Offset(x, size.height - halfStroke),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DjLevelGaugeFramePainter oldDelegate) => false;
}

class _StatusLine extends StatelessWidget {
  const _StatusLine(
      {required this.label,
      required this.value,
      required this.color,
      this.extra,
      this.extraColor,
      this.extraSuffix});
  final String label;
  final String value;
  final Color color;
  final String? extra;
  final Color? extraColor;
  final String? extraSuffix;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _kLine, width: 1.2))),
          child: Row(children: [
            Container(width: 4, height: 31, color: _kCyan),
            const SizedBox(width: 10),
            SizedBox(width: 138, child: _OutlineText(label, fontSize: 17)),
            _OutlineText(value,
                fontSize: 26, color: color, weight: FontWeight.bold),
            if (extra != null) ...[
              const SizedBox(width: 34),
              _OutlineText(extra!,
                  fontSize: 19, color: extraColor ?? Colors.white),
              if (extraSuffix != null) ...[
                const SizedBox(width: 18),
                _OutlineText(extraSuffix!, fontSize: 19, color: Colors.white),
              ],
            ],
          ]),
        ),
      );
}

class _RivalScorePanel extends StatelessWidget {
  const _RivalScorePanel(
      {required this.chart,
      required this.scores,
      required this.summaries,
      required this.folderSelected});
  final Chart chart;
  final List<RivalScore> scores;
  final List<_RivalWinLossSummary> summaries;
  final bool folderSelected;
  @override
  Widget build(BuildContext context) {
    var myScore = 0;
    var hasMyScore = false;
    for (final score in scores) {
      if (score.isMe) {
        myScore = score.score;
        hasMyScore = true;
        break;
      }
    }
    String scoreDifferenceLabel(RivalScore item) {
      if (item.isMe) return '±0';
      // 未プレイのライバルは点差比較の対象外。
      if (item.score == 0) return '-';
      if (!hasMyScore) return '--';
      final difference = item.score - myScore;
      // 自分以外（MY BEST を含む）が同点の場合は、比較相手として
      // 自分の上に並ぶため +0 と表示する。
      if (difference == 0) return '+0';
      return difference > 0 ? '+$difference' : '$difference';
    }

    Color scoreDifferenceColor(RivalScore item) {
      if (item.isMe) return const Color(0xffffff51);
      if (item.score == 0) return Colors.white;
      if (hasMyScore && item.score < myScore) {
        return const Color(0xffff535a);
      }
      return Colors.white;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(17),
      child: Container(
        color: _kPanel,
        padding: const EdgeInsets.fromLTRB(16, 5, 16, 12),
        child: Column(children: [
          const SizedBox(
              height: 25,
              child: Center(
                  child: _OutlineText('RIVAL SCORE DATA',
                      fontSize: 21, letterSpacing: 2))),
          const Divider(height: 2, color: _kLine),
          Expanded(
              child: folderSelected
                  ? _RivalWinLossList(summaries: summaries)
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      physics: const BouncingScrollPhysics(),
                      itemCount: scores.length,
                      itemBuilder: (context, index) {
                        final item = scores[index];
                        final rank = _djLevel(item.score, chart.maxScore);
                        final rankDelta =
                            _rankDelta(item.score, chart.maxScore);
                        final rankDeltaLabel = !item.isMe && item.score == 0
                            ? '-'
                            : '（ $rankDelta ）';
                        return Container(
                          height: 28,
                          color: item.isMe
                              ? const Color(0xff159bbb).withValues(alpha: .86)
                              : Colors.transparent,
                          child: Row(children: [
                            SizedBox(
                                width: 74,
                                child: Center(
                                    child: _OutlineText('${index + 1}',
                                        fontSize: 16,
                                        color: index < 3
                                            ? const Color(0xffffd33c)
                                            : Colors.white))),
                            SizedBox(
                                width: 190,
                                child: _OutlineText(item.name, fontSize: 17)),
                            SizedBox(
                                width: 82,
                                child: _OutlineText('${item.score}',
                                    fontSize: 17)),
                            SizedBox(
                                width: 57,
                                child: _OutlineText(rank,
                                    fontSize: 16,
                                    color: _rankColor(rank),
                                    weight: FontWeight.w400)),
                            SizedBox(
                                width: 110,
                                child: _OutlineText(rankDeltaLabel,
                                    fontSize: 13,
                                    color: item.score > 0 &&
                                            _isNegativeRankDelta(rankDelta)
                                        ? const Color(0xffff535a)
                                        : Colors.white)),
                            SizedBox(
                                width: 70,
                                child: _OutlineText(scoreDifferenceLabel(item),
                                    fontSize: 14,
                                    color: scoreDifferenceColor(item))),
                            _OutlineText(item.clear.label,
                                fontSize: 15,
                                color: _clearColor(item.clear),
                                weight: FontWeight.w400),
                          ]),
                        );
                      })),
        ]),
      ),
    );
  }
}

/// フォルダ選択時のRIVAL SCORE DATA。各ライバルのスコア勝敗だけを
/// 10マスの横棒（勝ち＝黄、負け＝水色）として表示する。
class _RivalWinLossList extends StatelessWidget {
  const _RivalWinLossList({required this.summaries});
  final List<_RivalWinLossSummary> summaries;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4),
      physics: const BouncingScrollPhysics(),
      // MY BESTはライバル10人とは別枠。11行目以降は従来どおりスクロールで参照する。
      itemCount: summaries.length,
      itemBuilder: (context, index) {
        final summary = summaries[index];
        final total = summary.wins + summary.losses;
        final loseRatio = total == 0 ? 0.0 : summary.losses / total;
        return SizedBox(
          height: 28,
          child: Row(children: [
            SizedBox(
                width: 42,
                child: Center(
                    child: _OutlineText('${index + 1}',
                        fontSize: 14, color: const Color(0xffffd33c)))),
            SizedBox(
                width: 150, child: _OutlineText(summary.name, fontSize: 15)),
            Expanded(
              child: SizedBox(
                width: double.infinity,
                height: 20,
                child: Stack(alignment: Alignment.center, children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: total == 0
                            ? const Color(0xff23465d)
                            : const Color(0xffffd33c),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: loseRatio,
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(color: _kCyan),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: .45),
                          width: .8),
                    ))),
                  ),
                  Positioned.fill(
                    child: Center(
                      // 数字の見た目の重心を、ゲージの縦中央へ補正する。
                      child: Transform.translate(
                        offset: const Offset(0, -1.5),
                        child: Text(
                          '${summary.wins} : ${summary.losses}',
                          textAlign: TextAlign.center,
                          strutStyle: const StrutStyle(
                              fontSize: 17, height: 1, forceStrutHeight: true),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            height: 1,
                            fontWeight: FontWeight.w400,
                            shadows: [
                              Shadow(
                                  color: Colors.black,
                                  blurRadius: 0,
                                  offset: Offset(-1, -1)),
                              Shadow(
                                  color: Colors.black,
                                  blurRadius: 0,
                                  offset: Offset(1, -1)),
                              Shadow(
                                  color: Colors.black,
                                  blurRadius: 0,
                                  offset: Offset(-1, 1)),
                              Shadow(
                                  color: Colors.black,
                                  blurRadius: 0,
                                  offset: Offset(1, 1)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _RivalWinLossSummary {
  const _RivalWinLossSummary({
    required this.slot,
    required this.name,
    required this.wins,
    required this.losses,
  });

  final int slot;
  final String name;
  final int wins;
  final int losses;
}

class _RadarBlock extends StatelessWidget {
  const _RadarBlock(
      {required this.chart,
      required this.record,
      required this.overallRadar,
      required this.hasOverallRadar});
  final Chart chart;
  final PlayRecord? record;
  final RadarValues? overallRadar;
  final bool hasOverallRadar;
  @override
  Widget build(BuildContext context) => Column(children: [
        const SizedBox(height: 4),
        const _OutlineText('NOTES RADAR', fontSize: 26, letterSpacing: 1.5),
        Expanded(
            child: SizedBox.expand(
          child: CustomPaint(
              painter: _MockRadarPainter(
                  max: overallRadar ?? chart.maxRadar,
                  hasData: overallRadar != null
                      ? hasOverallRadar
                      : chart.hasRadarData,
                  ratio: overallRadar != null
                      ? 1
                      : record == null || chart.maxScore <= 1
                          ? 0
                          : (record!.score / chart.maxScore)
                              .clamp(0.0, 1.0)
                              .toDouble(),
                  showMaxValues: overallRadar == null,
                  showStars: overallRadar == null)),
        )),
      ]);
}

class _MockRadarPainter extends CustomPainter {
  _MockRadarPainter(
      {required this.max,
      required this.hasData,
      required this.ratio,
      required this.showMaxValues,
      required this.showStars});
  final RadarValues max;
  final bool hasData;
  final double ratio;
  final bool showMaxValues;
  final bool showStars;
  static const _colors = [
    Color(0xffff4fb4),
    Color(0xff77e33c),
    Color(0xffff9e25),
    Color(0xffb75cf0),
    Color(0xffff3e47),
    _kCyan
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .5, size.height * .50);
    // 150.00の基準六角形。200.00まで伸びても属性ラベルへ届かない
    // ように、グラフ本体を十分コンパクトに保つ。
    final radius = math.min(size.width, size.height) * .24;
    final reference =
        List.generate(6, (index) => _point(center, radius, index));
    canvas.drawPath(
        Path()..addPolygon(reference, true),
        Paint()
          ..style = PaintingStyle.fill
          ..color = const Color(0xff052b46).withValues(alpha: .76));
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = _kCyan.withValues(alpha: .94);
    canvas.drawPath(Path()..addPolygon(reference, true), gridPaint);
    for (var ring = 1; ring <= 2; ring++) {
      final inner =
          List.generate(6, (index) => _point(center, radius * ring / 3, index));
      canvas.drawPath(
          Path()..addPolygon(inner, true),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xffffe3a7).withValues(alpha: .7));
    }
    for (final point in reference) {
      canvas.drawLine(
          center,
          point,
          Paint()
            ..strokeWidth = 1
            ..color = const Color(0xffffe3a7).withValues(alpha: .72));
    }
    if (!hasData) {
      final text = TextPainter(
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          text: const TextSpan(
              text: 'NO DATA',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  shadows: [
                    Shadow(color: Colors.black, blurRadius: 3),
                  ])));
      text.layout();
      text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
      return;
    }
    final values = RadarAttribute.values.map(max.by).toList();
    final strong = max.strongest.index;
    final data = List.generate(
        6, (index) => _point(center, radius * values[index] / 150, index));
    final color = _colors[strong];
    canvas.drawPath(
        Path()..addPolygon(data, true),
        Paint()
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: .27));
    canvas.drawPath(
        Path()..addPolygon(data, true),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = color);
    for (var index = 0; index < 6; index++) {
      canvas.drawCircle(data[index], 4.8, Paint()..color = color);
      // 200.00 (= 基準の4/3) の頂点より外側に固定する。
      final textPoint = _point(center, radius * 1.65, index);
      final text = TextPainter(
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          text: TextSpan(children: [
            TextSpan(
                text:
                    '${showStars && max.isStrongest(RadarAttribute.values[index]) ? '★ ' : ''}${RadarAttribute.values[index].label}\n',
                style: TextStyle(
                    fontSize: 15.5,
                    height: 1.05,
                    fontWeight: FontWeight.bold,
                    color: _colors[index],
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 2),
                    ])),
            TextSpan(
                text: showMaxValues
                    ? '${(values[index] * ratio).toStringAsFixed(2)}\n(/${values[index].toStringAsFixed(2)})'
                    : values[index].toStringAsFixed(2),
                style: const TextStyle(
                    fontSize: 16.5,
                    height: 1.05,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                          color: Colors.black,
                          blurRadius: .3,
                          offset: Offset(-1.35, -1.35)),
                      Shadow(
                          color: Colors.black,
                          blurRadius: .3,
                          offset: Offset(1.35, -1.35)),
                      Shadow(
                          color: Colors.black,
                          blurRadius: .3,
                          offset: Offset(-1.35, 1.35)),
                      Shadow(
                          color: Colors.black,
                          blurRadius: .3,
                          offset: Offset(1.35, 1.35)),
                    ])),
          ]));
      text.layout(maxWidth: 128);
      text.paint(canvas, textPoint - Offset(text.width / 2, text.height / 2));
    }
  }

  Offset _point(Offset center, double radius, int index) {
    final angle = -math.pi / 2 + math.pi / 3 * index;
    return center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  }

  @override
  bool shouldRepaint(covariant _MockRadarPainter oldDelegate) =>
      oldDelegate.max != max ||
      oldDelegate.hasData != hasData ||
      oldDelegate.ratio != ratio ||
      oldDelegate.showMaxValues != showMaxValues ||
      oldDelegate.showStars != showStars;
}

class _MusicSelectPanel extends StatefulWidget {
  const _MusicSelectPanel(
      {required this.selected,
      required this.sort,
      required this.scale,
      required this.devicePixelRatio,
      required this.expandedFolder,
      required this.songs,
      required this.selectedSongTitle,
      required this.selectedSongIndex,
      required this.transientSongFocus,
      required this.rivalNames,
      required this.rivalProfiles,
      required this.showMyBest,
      required this.displayChartForRow,
      required this.clearForChart,
      required this.folderClearFor,
      required this.visibleFolderGroups,
      required this.onOpenFolder,
      required this.onSelectSong,
      required this.onFocusFolder,
      required this.onFocusSong,
      required this.onSort,
      super.key});
  final String selected;
  final String sort;
  final double scale;
  final double devicePixelRatio;
  final String? expandedFolder;
  final List<Chart> songs;
  final String? selectedSongTitle;
  final int? selectedSongIndex;
  final bool transientSongFocus;
  final Map<int, String> rivalNames;
  final List<RivalProfile> rivalProfiles;
  final bool showMyBest;
  final Chart Function(Chart chart) displayChartForRow;
  final ClearType Function(Chart chart) clearForChart;
  final ClearType? Function(String folder) folderClearFor;
  final Set<String> visibleFolderGroups;
  final ValueChanged<String> onOpenFolder;
  final ValueChanged<int> onSelectSong;
  final ValueChanged<String> onFocusFolder;
  final ValueChanged<int> onFocusSong;
  final ValueChanged<String> onSort;
  static final _folders = [
    'LEVEL 1',
    'LEVEL 2',
    'LEVEL 3',
    'LEVEL 4',
    'LEVEL 5',
    'LEVEL 6',
    'LEVEL 7',
    'LEVEL 8',
    'LEVEL 9',
    'LEVEL 10',
    'LEVEL 11',
    'LEVEL 12',
    'LEGGENDARIA',
    '1ST STYLE',
    'SUBSTREAM',
    '2ND STYLE',
    '3RD STYLE',
    '4TH STYLE',
    '5TH STYLE',
    '6TH STYLE',
    '7TH STYLE',
    '8TH STYLE',
    '9TH STYLE',
    '10TH STYLE',
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
    'PINKY CRUSH',
    'SPARKLE SHOWER',
    'NOTES',
    'CHORD',
    'PEAK',
    'CHARGE',
    'SCRATCH',
    'SOF-LAN',
    'ABCD',
    'EFGH',
    'IJKL',
    'MNOP',
    'QRST',
    'UVWXYZ',
    '0-9',
    'OTHERS',
    'DJ LEVEL AAA',
    'DJ LEVEL AA',
    'DJ LEVEL A',
    'DJ LEVEL B',
    'DJ LEVEL C',
    'DJ LEVEL D',
    'DJ LEVEL E',
    'DJ LEVEL F',
    ...List.generate(9, (index) => 'RIVAL${index + 1} SCORE WIN'),
    ...List.generate(9, (index) => 'RIVAL${index + 1} SCORE LOSE'),
    ...List.generate(9, (index) => 'RIVAL${index + 1} CLEAR WIN'),
    ...List.generate(9, (index) => 'RIVAL${index + 1} CLEAR LOSE'),
    'FULL COMBO',
    'EX HARD CLEAR',
    'HARD CLEAR',
    'CLEAR',
    'EASY',
    'ASSIST EASY',
    'FAILED',
    'NO PLAY'
  ];

  static const _initialFolders = {
    'ABCD',
    'EFGH',
    'IJKL',
    'MNOP',
    'QRST',
    'UVWXYZ',
    '0-9',
    'OTHERS',
  };
  static const _attributeFolders = {
    'NOTES',
    'CHORD',
    'PEAK',
    'CHARGE',
    'SCRATCH',
    'SOF-LAN',
  };
  static const _clearFolders = {
    'FULL COMBO',
    'EX HARD CLEAR',
    'HARD CLEAR',
    'CLEAR',
    'EASY',
    'ASSIST EASY',
    'FAILED',
    'NO PLAY',
  };

  static String _groupForFolder(String folder) {
    if (folder.startsWith('LEVEL ')) return 'LEVEL';
    if (folder == 'LEGGENDARIA') return 'LEGGENDARIA';
    if (versionFolders.contains(folder)) return 'バージョン';
    if (_attributeFolders.contains(folder)) return '属性';
    if (_initialFolders.contains(folder)) return 'INITIAL';
    if (folder.startsWith('DJ LEVEL ')) return 'DJ LEVEL';
    if (folder.startsWith('RIVAL') || folder.startsWith('MY BEST')) {
      return 'RIVAL WIN／LOSE';
    }
    if (_clearFolders.contains(folder)) return 'CLEAR';
    return 'LEVEL';
  }

  static List<String> visibleFolders(
      Set<String> visibleGroups, List<RivalProfile> rivalProfiles,
      {bool showMyBest = false}) {
    final folders = _folders
        .where((folder) =>
            !folder.startsWith('RIVAL') &&
            visibleGroups.contains(_groupForFolder(folder)))
        .toList();
    if (visibleGroups.contains('RIVAL WIN／LOSE')) {
      final rivalFolders = <String>[];
      for (final condition in const [
        'SCORE WIN',
        'SCORE LOSE',
        'CLEAR WIN',
        'CLEAR LOSE',
      ]) {
        if (showMyBest) rivalFolders.add('MY BEST $condition');
        for (final rival in rivalProfiles) {
          rivalFolders.add('RIVAL${rival.slot} $condition');
        }
      }
      final clearIndex = folders.indexWhere(_clearFolders.contains);
      folders.insertAll(
          clearIndex < 0 ? folders.length : clearIndex, rivalFolders);
    }
    return folders;
  }

  static String firstVisibleFolder(
      Set<String> visibleGroups, List<RivalProfile> rivalProfiles,
      {bool showMyBest = false}) {
    final folders =
        visibleFolders(visibleGroups, rivalProfiles, showMyBest: showMyBest);
    return folders.isEmpty ? _folders.first : folders.first;
  }

  static const versionFolders = {
    '1ST STYLE',
    'SUBSTREAM',
    '2ND STYLE',
    '3RD STYLE',
    '4TH STYLE',
    '5TH STYLE',
    '6TH STYLE',
    '7TH STYLE',
    '8TH STYLE',
    '9TH STYLE',
    '10TH STYLE',
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
    'PINKY CRUSH',
    'SPARKLE SHOWER',
  };
  @override
  State<_MusicSelectPanel> createState() => _MusicSelectPanelState();
}

class _MusicSelectPanelState extends State<_MusicSelectPanel> {
  // 1曲だけのフォルダでも、画面を空白にせず循環させるための周回数。
  // 行はListView.builderで遅延生成されるため、通常フォルダ一覧への負荷は増えない。
  // 曲数が1〜数曲しかないフォルダでも、画面の表示行数より十分大きい
  // スクロール範囲を確保する。ListView.builder は可視範囲だけを遅延生成する
  // ため、周回数を増やしても描画負荷は増えない。
  static const _loopCopies = 101;
  static const _selectionRowIndex = 5;
  late final ScrollController _controller;
  bool _isLoopJumping = false;
  bool _isSnapping = false;
  bool _suppressFocusNotifications = false;
  bool _isReflowing = false;
  bool _isDraggingList = false;
  Timer? _scrollStopTimer;
  Timer? _wheelCoalesceTimer;
  int _pendingWheelDirection = 0;
  int _queuedWheelSteps = 0;
  bool _isProcessingWheel = false;
  int _queuedKeyboardSteps = 0;
  bool _isProcessingKeyboard = false;
  int _folderOperationEpoch = 0;
  int _songSelectionEpoch = 0;
  List<_MusicSelectEntry>? _frozenEntries;
  // _frozenEntries を表示している間は、行だけでなく「どのフォルダが
  // 展開中か」も旧状態のまま保持する。ここを新Widgetの値で描画すると、
  // 旧フォルダの楽曲行と新フォルダの選択色が1フレーム混在してしまう。
  String? _frozenExpandedFolder;
  int _frozenIndexShift = 0;
  int? _frozenItemCountEntries;
  String? _lastFocusedKey;
  late List<_MusicSelectEntry> _cachedEntries;

  double _snap(double value) =>
      (value * widget.scale * widget.devicePixelRatio).roundToDouble() /
      widget.devicePixelRatio;
  double get _rowHeight => _snap(47);
  double get _dividerHeight => 1 / widget.devicePixelRatio;

  List<_MusicSelectEntry> _entriesForExpanded(String? expandedFolder) {
    // 展開中は、そのフォルダと配下の楽曲だけを表示する。
    // ほかのフォルダを同居させないことで、曲一覧そのものを1周する
    // MUSIC SELECTらしい循環リストにする。
    if (expandedFolder != null) {
      return [
        _MusicSelectEntry.folder(expandedFolder),
        for (var index = 0; index < widget.songs.length; index++)
          _MusicSelectEntry.song(widget.songs[index], index),
      ];
    }
    final result = <_MusicSelectEntry>[];
    for (final folder in _MusicSelectPanel.visibleFolders(
        widget.visibleFolderGroups, widget.rivalProfiles,
        showMyBest: widget.showMyBest)) {
      result.add(_MusicSelectEntry.folder(folder));
    }
    return result;
  }

  List<_MusicSelectEntry> get _entries => _cachedEntries;

  void _refreshEntries() {
    _cachedEntries =
        List.unmodifiable(_entriesForExpanded(widget.expandedFolder));
  }

  bool _sameRivalProfiles(List<RivalProfile> first, List<RivalProfile> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      final a = first[index];
      final b = second[index];
      if (a.slot != b.slot ||
          a.djName != b.djName ||
          a.spImported != b.spImported ||
          a.dpImported != b.dpImported) {
        return false;
      }
    }
    return true;
  }

  /// 親画面の setState では、同じ内容でも songs が新しい List として渡る。
  /// identity だけで判定すると、ホイール移動中に選択曲が変わるたび
  /// 「一覧構成が変化した」と誤認して循環リストを組み直してしまう。
  /// 表示順を決める譜面ID列が同一なら、スクロール中の同一一覧として扱う。
  bool _sameCharts(List<Chart> first, List<Chart> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index].id != second[index].id) return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _refreshEntries();
    // 少ないフォルダ数でも表示領域の外側に十分な余白を確保し、
    // 上下どちらへスクロールしても中央周へ戻せるようにする。
    final folderCount = _MusicSelectPanel.visibleFolders(
            widget.visibleFolderGroups, widget.rivalProfiles,
            showMyBest: widget.showMyBest)
        .length;
    _controller = ScrollController(
        initialScrollOffset:
            math.max(0, _rowHeight * (folderCount * 3 - _selectionRowIndex)));
    _controller.addListener(_keepFolderLooping);
  }

  @override
  void didUpdateWidget(covariant _MusicSelectPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 大量の楽曲行を毎フレーム作り直すと、展開・スクロールが重くなる。
    // 行構成が変化した場合だけ作り直し、通常の描画・スクロールでは再利用する。
    final entriesChanged = oldWidget.expandedFolder != widget.expandedFolder ||
        !_sameCharts(oldWidget.songs, widget.songs) ||
        oldWidget.visibleFolderGroups != widget.visibleFolderGroups ||
        oldWidget.showMyBest != widget.showMyBest ||
        !_sameRivalProfiles(oldWidget.rivalProfiles, widget.rivalProfiles);
    // SP／DP切替では、ライバル登録状況などによってフォルダ総数が変わる。
    // 旧スクロール座標のまま新しい行構成を解釈すると別フォルダへ移るため、
    // 旧行を凍結表示したまま、切替前に選ばれていたフォルダを新しい周回の
    // 選択行へ移し替える。これにより新旧の行構成が混ざる1フレームを出さない。
    // 曲を選択中でも同じ方式で旧行を固定する。楽曲選択時だけ後から
    // _pinSongToSelectionLine を呼ぶと、新しい一覧が一度だけ旧座標で描画される。
    final preserveSelection =
        entriesChanged && oldWidget.expandedFolder == widget.expandedFolder;
    final preserveSong = preserveSelection &&
        widget.selectedSongTitle != null &&
        widget.selectedSongIndex != null;
    final folderToPreserve = widget.selected;
    final previousEntries = _cachedEntries;
    final previousAnchor = preserveSelection && previousEntries.isNotEmpty
        ? _selectedVirtualIndex(previousEntries)
        : 0;
    if (preserveSelection) {
      _isReflowing = true;
      _frozenEntries = List<_MusicSelectEntry>.of(previousEntries);
      _frozenExpandedFolder = oldWidget.expandedFolder;
      _frozenIndexShift = 0;
      // DP側に該当譜面がなく、展開済み行が一気に減る場合でも、旧スクロール
      // 位置をFlutterに強制クランプさせない。新旧の大きい方を一時採用する。
      final nextEntryCount = _entriesForExpanded(widget.expandedFolder).length;
      _frozenItemCountEntries =
          math.max(previousEntries.length, nextEntryCount);
    }
    if (entriesChanged) {
      _refreshEntries();
      // フォルダ開閉中は _toggleFolderAtSelection で旧行を凍結している。
      // ここで新しい行数へ即座に縮めると、ScrollController が現在位置を
      // 強制クランプして別の行を一瞬描画する。新旧で大きい方を維持し、
      // 選択行へ移動し終えた最後のフレームでのみ凍結を解除する。
      final frozenEntries = _frozenEntries;
      if (_isReflowing && frozenEntries != null) {
        _frozenItemCountEntries =
            math.max(frozenEntries.length, _cachedEntries.length);
      }
    }
    if (!preserveSelection &&
        !widget.transientSongFocus &&
        widget.selectedSongIndex != null &&
        (oldWidget.selectedSongIndex != widget.selectedSongIndex ||
            oldWidget.selectedSongTitle != widget.selectedSongTitle)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.selectedSongIndex != null) {
          _pinSongToSelectionLine(widget.selectedSongIndex!);
        }
      });
    }
    if (preserveSelection) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        final newEntries = _entries;
        final selectedEntryIndex = preserveSong
            ? newEntries.indexWhere(
                (entry) => entry.songIndex == widget.selectedSongIndex)
            : newEntries
                .indexWhere((entry) => entry.folder == folderToPreserve);
        if (selectedEntryIndex < 0 || newEntries.isEmpty) {
          setState(() {
            _frozenEntries = null;
            _frozenExpandedFolder = null;
            _frozenIndexShift = 0;
            _frozenItemCountEntries = null;
            _isReflowing = false;
          });
          return;
        }
        final newAnchor =
            (_loopCopies ~/ 2) * newEntries.length + selectedEntryIndex;
        final target = (newAnchor - _selectionRowIndex) * _rowHeight;
        setState(() {
          // 凍結している旧リストも、選択行には同じフォルダが見えるよう
          // 仮想インデックスを新しい周回に合わせる。
          _frozenIndexShift = newAnchor - previousAnchor;
          _frozenItemCountEntries =
              math.max(previousEntries.length, newEntries.length);
        });
        _jumpToLoopOffset(
            target.clamp(0.0, _controller.position.maxScrollExtent));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (preserveSong) {
            _pinSongToSelectionLine(widget.selectedSongIndex!);
          } else {
            _pinFolderToSelectionLine(folderToPreserve);
          }
          setState(() {
            _frozenEntries = null;
            _frozenExpandedFolder = null;
            _frozenIndexShift = 0;
            _frozenItemCountEntries = null;
            _isReflowing = false;
          });
          _lastFocusedKey = null;
          _notifyFocusedEntry();
        });
      });
    }
  }

  void _keepFolderLooping() {
    if (!_controller.hasClients || _isLoopJumping || _isReflowing) return;
    final entries = _entries;
    if (entries.isEmpty) return;

    // 循環補正は raw offset ではなく、選択行が属する「仮想周回」を基準に
    // 判定する。固定選択行ぶんのオフセットを考慮せず raw offset だけで判定
    // すると、3行程度の短いフォルダを開いた直後にも境界に近いと誤認し、
    // ホイール中に不要なジャンプと一瞬の重複描画が発生していた。
    final selectedVirtualIndex = _selectedVirtualIndex(entries);
    // ListView の末尾は表示領域の高さぶん手前で実質的に到達する。
    // そのため単純に「最終周回の2周前」で判定すると、短いリストでは
    // 終端に着いてからでないと補正されず、下スクロールが止まってしまう。
    final viewportRows =
        (_controller.position.viewportDimension / _rowHeight).ceil();
    final lowerGuardIndex = entries.length * 2 + _selectionRowIndex;
    final upperGuardIndex =
        entries.length * _loopCopies - viewportRows - entries.length * 2;
    final atLowerGuard = selectedVirtualIndex <= lowerGuardIndex;
    final atUpperGuard = selectedVirtualIndex >= upperGuardIndex;
    if (atLowerGuard || atUpperGuard) {
      final itemIndex = selectedVirtualIndex % entries.length;
      final centeredVirtualIndex =
          (_loopCopies ~/ 2) * entries.length + itemIndex;
      final target = (centeredVirtualIndex - _selectionRowIndex) * _rowHeight;
      final clamped = target.clamp(0.0, _controller.position.maxScrollExtent);
      if ((clamped - _controller.offset).abs() > 0.01) {
        _jumpToLoopOffset(clamped);
      }
    }
    _notifyFocusedEntry();
    _scheduleSnap();
  }

  void _jumpToLoopOffset(double offset) {
    _isLoopJumping = true;
    _controller.jumpTo(offset);
    _isLoopJumping = false;
  }

  /// フォルダ展開・閉鎖の座標計算前に、ホイールやスナップで残っている
  /// ScrollActivity を止める。特に「移動直後に右クリック」の場合に、
  /// 古い animateTo が後から走って選択行をずらすことを防ぐ。
  void _cancelPendingListMotion() {
    _scrollStopTimer?.cancel();
    _scrollStopTimer = null;
    _wheelCoalesceTimer?.cancel();
    _wheelCoalesceTimer = null;
    _pendingWheelDirection = 0;
    _queuedWheelSteps = 0;
    _queuedKeyboardSteps = 0;
    if (_controller.hasClients) {
      _jumpToLoopOffset(_controller.offset);
    }
  }

  /// 現在の行構成を基準に、指定フォルダを選択行へ固定する。
  /// 展開・閉鎖で周回ごとの行数が変わった直後にも使うため、古い仮想番号は
  /// 受け取らず、毎回現在の entries から再計算する。
  void _pinFolderToSelectionLine(String folder) {
    if (!_controller.hasClients) return;
    final entries = _entries;
    final folderIndex = entries.indexWhere((entry) => entry.folder == folder);
    if (folderIndex < 0 || entries.isEmpty) return;
    final anchorIndex = (_loopCopies ~/ 2) * entries.length + folderIndex;
    final target = (anchorIndex - _selectionRowIndex) * _rowHeight;
    _jumpToLoopOffset(target.clamp(0.0, _controller.position.maxScrollExtent));
  }

  /// SP／DP切替後も、同じ楽曲を選択行に保つ。
  /// 選択ラインは固定で、リスト内容だけを該当行へ即時合わせる。
  void _pinSongToSelectionLine(int songIndex) {
    if (!_controller.hasClients) return;
    final entries = _entries;
    final songEntryIndex =
        entries.indexWhere((entry) => entry.songIndex == songIndex);
    if (songEntryIndex < 0 || entries.isEmpty) return;
    final currentCycle = _selectedVirtualIndex(entries) ~/ entries.length;
    final targetIndex = currentCycle * entries.length + songEntryIndex;
    final target = (targetIndex - _selectionRowIndex) * _rowHeight;
    _jumpToLoopOffset(target.clamp(0.0, _controller.position.maxScrollExtent));
  }

  int _selectedVirtualIndex(List<_MusicSelectEntry> entries) {
    if (!_controller.hasClients || entries.isEmpty) return 0;
    final index =
        ((_controller.offset / _rowHeight) + _selectionRowIndex).round();
    return index.clamp(0, entries.length * _loopCopies - 1);
  }

  void _notifyFocusedEntry() {
    // ページ移動・キーリピートでは親側の再配置を止める。一方、ホイールと
    // ドラッグでは選択行に最も近い楽曲情報を移動中から表示する。
    if (_isReflowing || _suppressFocusNotifications) return;
    final entries = _entries;
    if (entries.isEmpty) return;
    final entry = entries[_selectedVirtualIndex(entries) % entries.length];
    final key = entry.song == null
        ? 'folder:${entry.folder}'
        : 'song:${entry.songIndex}';
    if (_lastFocusedKey == key) return;
    _lastFocusedKey = key;
    if (entry.song != null) {
      widget.onFocusSong(entry.songIndex!);
    } else {
      widget.onFocusFolder(entry.folder!);
    }
  }

  Future<void> _moveToSelection(int virtualIndex,
      {VoidCallback? afterMove,
      Duration duration = const Duration(milliseconds: 230)}) async {
    if (!_controller.hasClients) return;
    final target = (virtualIndex - _selectionRowIndex) * _rowHeight;
    final clamped = target.clamp(0.0, _controller.position.maxScrollExtent);
    if ((clamped - _controller.offset).abs() > 0.5) {
      await _controller.animateTo(clamped,
          duration: duration, curve: Curves.easeOutCubic);
    }
    if (mounted) afterMove?.call();
  }

  Future<void> _snapToSelectionRow() async {
    if (!_controller.hasClients ||
        _isLoopJumping ||
        _isSnapping ||
        _isReflowing) {
      return;
    }
    _scrollStopTimer?.cancel();
    final current = _controller.offset;
    final target = (current / _rowHeight).round() * _rowHeight;
    final clamped = target.clamp(0.0, _controller.position.maxScrollExtent);
    // 選択ラインと行の境界は物理ピクセル単位まで一致させる。
    if ((clamped - current).abs() <= 0.01) return;
    _isSnapping = true;
    await _controller.animateTo(clamped,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic);
    if (_controller.hasClients && (_controller.offset - clamped).abs() > 0.01) {
      _controller.jumpTo(clamped);
    }
    _isSnapping = false;
    _notifyFocusedEntry();
  }

  void _scheduleSnap() {
    if (_isLoopJumping || _isSnapping || _isReflowing) return;
    _scrollStopTimer?.cancel();
    _scrollStopTimer =
        Timer(const Duration(milliseconds: 120), _snapToSelectionRow);
  }

  void _tapFolder(
      String folder, int virtualIndex, List<_MusicSelectEntry> entries) {
    final operation = ++_folderOperationEpoch;
    if (_selectedVirtualIndex(entries) == virtualIndex) {
      _toggleFolderAtSelection(folder, entries, operation);
      return;
    }
    // 選択行外は、展開前の行構成のまま先に選択行へ移動してから開く。
    _moveToSelection(virtualIndex, afterMove: () {
      if (!mounted || operation != _folderOperationEpoch) return;
      _toggleFolderAtSelection(folder, _entries, operation);
    });
  }

  /// フォルダ展開で1周あたりの行数が変わっても、選択行にあるフォルダを
  /// 画面上で一切ずらさずに切り替える。
  ///
  /// 一時的に旧行を「新しい仮想行番号」に対応付けて描画してから新リストへ
  /// 切り替えるため、展開瞬間に別の曲やフォルダが1フレームだけ出る現象を
  /// 防止する。
  void _toggleFolderAtSelection(
      String folder, List<_MusicSelectEntry> oldEntries, int operation) {
    if (oldEntries.isEmpty || operation != _folderOperationEpoch) return;
    _cancelPendingListMotion();
    final oldAnchor = _selectedVirtualIndex(oldEntries);
    setState(() {
      _isReflowing = true;
      _frozenEntries = List<_MusicSelectEntry>.of(oldEntries);
      _frozenExpandedFolder = widget.expandedFolder;
      _frozenIndexShift = 0;
      // 既に別フォルダを展開中の状態で新しいフォルダを開く場合も、
      // 新フォルダの曲数が少なければ行数は減る。そのため開閉の方向に
      // 関係なく旧行数を維持し、強制クランプを防ぐ。
      _frozenItemCountEntries = oldEntries.length;
    });
    widget.onOpenFolder(folder);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          operation != _folderOperationEpoch ||
          !_controller.hasClients) {
        return;
      }
      final newEntries = _entries;
      final folderIndex =
          newEntries.indexWhere((entry) => entry.folder == folder);
      if (folderIndex < 0 || newEntries.isEmpty) {
        setState(() {
          _isReflowing = false;
          _frozenEntries = null;
          _frozenExpandedFolder = null;
          _frozenItemCountEntries = null;
        });
        return;
      }
      final newAnchor = (_loopCopies ~/ 2) * newEntries.length + folderIndex;
      final target = (newAnchor - _selectionRowIndex) * _rowHeight;
      // controller の座標を新しい周回へ移しつつ、旧リスト側も同じフォルダを
      // 指すように仮想インデックスをずらす。
      setState(() => _frozenIndexShift = newAnchor - oldAnchor);
      _jumpToLoopOffset(
          target.clamp(0.0, _controller.position.maxScrollExtent));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || operation != _folderOperationEpoch) return;
        // 凍結表示から実リストへ戻す直前に、展開後／閉鎖後の行数で
        // 選択位置を再計算する。連続操作でも古い周回位置を残さない。
        _pinFolderToSelectionLine(folder);
        setState(() {
          _frozenEntries = null;
          _frozenExpandedFolder = null;
          _frozenIndexShift = 0;
          _frozenItemCountEntries = null;
          _isReflowing = false;
        });
        _notifyFocusedEntry();
      });
    });
  }

  /// Windowsの右クリックは、クリックした行や選択行に関係なく、
  /// 現在展開中のフォルダを閉じる操作にする。
  /// 閉じた後は展開していたフォルダ自体を選択行へ固定する。
  void _secondaryTapCloseExpandedFolder() {
    final operation = ++_folderOperationEpoch;
    final folder = widget.expandedFolder;
    if (folder == null) return;
    // 右クリック直後の最初の描画から、閉鎖後の一覧だけを使う。
    // 展開中の一覧でフォルダ行へ移動する中間状態は一切作らない。
    final collapsedEntries = _entriesForExpanded(null);
    final folderIndex =
        collapsedEntries.indexWhere((entry) => entry.folder == folder);
    if (folderIndex < 0 || collapsedEntries.isEmpty) return;

    _cancelPendingListMotion();
    setState(() {
      _isReflowing = true;
      _frozenEntries = List<_MusicSelectEntry>.of(collapsedEntries);
      _frozenExpandedFolder = null;
      _frozenIndexShift = 0;
      _frozenItemCountEntries = collapsedEntries.length;
    });
    // 閉鎖後の周回におけるフォルダ位置へ、同一フレームで配置する。
    final targetIndex =
        (_loopCopies ~/ 2) * collapsedEntries.length + folderIndex;
    if (_controller.hasClients) {
      final targetOffset = (targetIndex - _selectionRowIndex) * _rowHeight;
      _jumpToLoopOffset(
          targetOffset.clamp(0.0, _controller.position.maxScrollExtent));
    }
    // 親の展開状態も同一フレームで閉じる。これで次フレームに旧楽曲行が
    // 混在する余地をなくす。
    widget.onOpenFolder(folder);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || operation != _folderOperationEpoch) return;
      _pinFolderToSelectionLine(folder);
      setState(() {
        _frozenEntries = null;
        _frozenExpandedFolder = null;
        _frozenIndexShift = 0;
        _frozenItemCountEntries = null;
        _isReflowing = false;
      });
      _lastFocusedKey = null;
      _notifyFocusedEntry();
    });
  }

  /// 楽曲行の左クリックは、スクロール通知への依存ではなく、移動完了時に
  /// 対象譜面を明示的に選択する。これにより選択行へ確実に揃い、左側の
  /// 楽曲情報・スコア情報も同じ譜面へ切り替わる。
  void _tapSong(int virtualIndex) {
    final entries = _entries;
    if (entries.isEmpty) return;
    final entry = entries[virtualIndex % entries.length];
    final songIndex = entry.songIndex;
    if (songIndex == null) return;
    final operation = ++_songSelectionEpoch;
    _moveToSelection(virtualIndex, afterMove: () {
      if (!mounted || operation != _songSelectionEpoch) return;
      _lastFocusedKey = 'song:$songIndex';
      widget.onSelectSong(songIndex);
    });
  }

  // 楽曲行のクリックとWindowsのマウスドラッグが競合しないよう、一覧全体で
  // 縦ドラッグを受ける。ドラッグとして認識された場合は子行の onTap が
  // キャンセルされるため、クリックだけが楽曲選択として扱われる。
  void _startListDrag(DragStartDetails details) {
    if (_isReflowing || !_controller.hasClients) return;
    _cancelPendingListMotion();
    _isDraggingList = true;
    _isSnapping = true;
  }

  void _updateListDrag(DragUpdateDetails details) {
    if (!_isDraggingList || !_controller.hasClients) return;
    final target = (_controller.offset - details.delta.dy)
        .clamp(0.0, _controller.position.maxScrollExtent);
    _jumpToLoopOffset(target);
    // _jumpToLoopOffset 中はリスナーを抑止しているため、ドラッグ時だけは
    // 完了後に明示的に循環境界の補正を行う。
    _keepFolderLooping();
  }

  void _finishListDrag([DragEndDetails? details]) {
    if (!_isDraggingList) return;
    _isDraggingList = false;
    final velocity = details?.velocity.pixelsPerSecond.dy ?? 0.0;
    // 指を離した時の速度を少し先の移動距離へ換算して、放り投げた時だけ
    // 慣性スクロールを行う。通常の短いドラッグは従来どおり即スナップする。
    if (velocity.abs() < 300 || !_controller.hasClients) {
      _isSnapping = false;
      _snapToSelectionRow();
      return;
    }
    _continueDragFling(velocity);
  }

  Future<void> _continueDragFling(double verticalVelocity) async {
    if (!mounted || !_controller.hasClients) return;
    // 上へ放る（負のY速度）とリストは下方向へ進むので、スクロール座標は
    // 速度と逆向きに動かす。過度な速度は上限を設けて見失わないようにする。
    final travel = (-verticalVelocity * 0.28).clamp(-1500.0, 1500.0);
    final current = _controller.offset;
    final target =
        (current + travel).clamp(0.0, _controller.position.maxScrollExtent);
    if ((target - current).abs() > 0.01) {
      await _controller.animateTo(
        target,
        duration: Duration(
          milliseconds:
              (240 + verticalVelocity.abs() * 0.12).round().clamp(260, 700),
        ),
        curve: Curves.easeOutCubic,
      );
    }
    if (!mounted || !_controller.hasClients) {
      _isSnapping = false;
      return;
    }
    _isSnapping = false;
    _keepFolderLooping();
    await _snapToSelectionRow();
    if (mounted) _notifyFocusedEntry();
  }

  /// ScrollPosition.pointerScroll は Windows のシステム設定（例: 3行）を
  /// 直接ピクセル量へ変換するため、各行でシグナルを先に解決して抑止する。
  /// 同じノッチ由来の連続シグナルは 18ms 内で一つにまとめる。
  void _handlePointerSignal(PointerSignalEvent event) {
    if (_isReflowing ||
        event is! PointerScrollEvent ||
        event.scrollDelta.dy == 0) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      if (resolved is! PointerScrollEvent) return;
      _pendingWheelDirection = resolved.scrollDelta.dy.isNegative ? -1 : 1;
      _wheelCoalesceTimer ??= Timer(const Duration(milliseconds: 18), () {
        _wheelCoalesceTimer = null;
        final direction = _pendingWheelDirection;
        _pendingWheelDirection = 0;
        if (direction == 0) return;
        _queuedWheelSteps += direction;
        _drainWheelSteps();
      });
    });
  }

  /// 親画面が受け取ったホイール入力の入口。リスト上の操作と同じ経路へ流す。
  void handleExternalPointerSignal(PointerSignalEvent event) =>
      _handlePointerSignal(event);

  /// Page Up / Page Down は、現在の表示領域に収まる行数から1行引いた分だけ
  /// 移動する。ホイールと同じく、移動完了後に選択行へぴったり揃える。
  Future<void> scrollByPage(int direction) async {
    if (direction == 0 ||
        _isReflowing ||
        _isDraggingList ||
        _isProcessingWheel ||
        !_controller.hasClients) {
      return;
    }

    _cancelPendingListMotion();
    _isSnapping = true;
    _suppressFocusNotifications = true;
    // レイアウト更新直後は viewportDimension が1行分として報告される場合が
    // ある。その場合でも Page Up/Down が1行移動にならないよう、通常画面の
    // 表示行数相当を下限として使う。
    final measuredRows =
        (_controller.position.viewportDimension / _rowHeight).floor();
    final visibleRows = math.max(10, measuredRows - 1);
    final currentOffset = _controller.offset;
    final target = (currentOffset + direction * visibleRows * _rowHeight)
        .clamp(0.0, _controller.position.maxScrollExtent);
    if ((target - currentOffset).abs() > 0.01) {
      await _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 230),
        curve: Curves.easeInOutCubic,
      );
    }
    if (!mounted || !_controller.hasClients) {
      _isSnapping = false;
      _suppressFocusNotifications = false;
      return;
    }
    _isSnapping = false;
    _suppressFocusNotifications = false;
    _keepFolderLooping();
    await _snapToSelectionRow();
    if (mounted) _notifyFocusedEntry();
  }

  /// キーリピート用の1行移動。短い間隔で届いた入力はまとめ、見た目は
  /// なめらかなまま、選択行の単位では必ず1行ずつ進める。
  void scrollByKeyboardRows(int direction) {
    if (direction == 0 ||
        _isReflowing ||
        _isDraggingList ||
        !_controller.hasClients) {
      return;
    }
    _queuedKeyboardSteps += direction;
    _drainKeyboardSteps();
  }

  Future<void> _drainKeyboardSteps() async {
    if (_isProcessingKeyboard || !_controller.hasClients) return;
    _isProcessingKeyboard = true;
    _isSnapping = true;
    while (mounted && _queuedKeyboardSteps != 0 && _controller.hasClients) {
      final steps = _queuedKeyboardSteps;
      _queuedKeyboardSteps = 0;
      final currentRow = (_controller.offset / _rowHeight).round();
      final target = ((currentRow + steps) * _rowHeight)
          .clamp(0.0, _controller.position.maxScrollExtent);
      await _controller.animateTo(
        target,
        duration: Duration(
          milliseconds: (47 + (steps.abs() - 1) * 14).clamp(47, 100),
        ),
        curve: Curves.easeOutCubic,
      );
    }
    _isSnapping = false;
    _isProcessingKeyboard = false;
    if (!mounted || !_controller.hasClients) return;
    _keepFolderLooping();
    await _snapToSelectionRow();
    if (mounted) _notifyFocusedEntry();
  }

  Future<void> _drainWheelSteps() async {
    if (_isProcessingWheel || _isReflowing || !_controller.hasClients) return;
    _isProcessingWheel = true;
    _isSnapping = true;
    while (mounted && _queuedWheelSteps != 0 && _controller.hasClients) {
      // 連続入力は一つの移動先へまとめる。1行ごとにアニメーションを
      // 止めないことで、速く回したときにもカクつかずに流れる。
      final steps = _queuedWheelSteps;
      _queuedWheelSteps = 0;
      final currentRow = (_controller.offset / _rowHeight).round();
      final target = ((currentRow + steps) * _rowHeight)
          .clamp(0.0, _controller.position.maxScrollExtent);
      final duration = Duration(
          milliseconds: (175 + (steps.abs() - 1) * 55).clamp(175, 360));
      await _controller.animateTo(target,
          duration: duration, curve: Curves.easeInOutCubic);
    }
    _isSnapping = false;
    _isProcessingWheel = false;
    // ホイールのアニメーション中は通常のスナップを抑止しているため、
    // 完了後に必ず行境界へ合わせ直す。これが無いと中間位置が残る。
    await _snapToSelectionRow();
    if (mounted) _notifyFocusedEntry();
  }

  @override
  void dispose() {
    _scrollStopTimer?.cancel();
    _wheelCoalesceTimer?.cancel();
    _controller.removeListener(_keepFolderLooping);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
              child: ClipPath(
                  clipper: _CutCornerClipper(cut: 14 * widget.scale),
                  child: const ColoredBox(color: _kPanel))),
          Column(children: [
            SizedBox(
              height: _snap(61),
              child: Row(children: [
                Expanded(
                    child: Center(
                        child: _OutlineText('MUSIC SELECT',
                            fontSize: 25 * widget.scale,
                            fontFamily: 'Gochikakutto',
                            letterSpacing: 1.5 * widget.scale))),
                SizedBox(
                  width: _snap(230),
                  child: Padding(
                    padding: EdgeInsets.all(_snap(13)),
                    child: DropdownButtonFormField<String>(
                      value: widget.sort,
                      isDense: true,
                      // ゴチカクットは横幅が広いため、選択値に残り幅を
                      // 割り当て、右端の矢印と競合させない。
                      isExpanded: true,
                      iconSize: 16 * widget.scale,
                      dropdownColor: const Color(0xff05233d),
                      style: TextStyle(
                          // ゴチカクットは太字にすると漢字の画が潰れるため、
                          // 通常ウェイトで枠内に収まる大きさにする。
                          fontSize: 17 * widget.scale,
                          fontWeight: FontWeight.w400,
                          fontFamily: 'Gochikakutto',
                          color: Colors.white,
                          shadows: const [
                            Shadow(color: Colors.black, offset: Offset(-1, -1)),
                            Shadow(color: Colors.black, offset: Offset(1, -1)),
                            Shadow(color: Colors.black, offset: Offset(-1, 1)),
                            Shadow(color: Colors.black, offset: Offset(1, 1)),
                          ]),
                      decoration: InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: _snap(13), vertical: _snap(4)),
                        filled: true,
                        fillColor: const Color(0xff063b59),
                        enabledBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: _kCyan),
                            borderRadius: BorderRadius.circular(_snap(5))),
                        border: OutlineInputBorder(
                            borderSide: const BorderSide(color: _kCyan),
                            borderRadius: BorderRadius.circular(_snap(5))),
                      ),
                      items: const [
                        'デフォルト',
                        '曲名',
                        'レベル',
                        '譜面難易度',
                        'スコアレート',
                        'クリアランプ',
                        'BPM'
                      ]
                          .map((item) => DropdownMenuItem(
                              value: item,
                              child: Text(item,
                                  style: TextStyle(
                                      // 展開メニューは一覧として読みやすい大きさを
                                      // 優先し、閉じた入力枠より一段大きくする。
                                      fontSize: 24 * widget.scale,
                                      fontWeight: FontWeight.w400,
                                      fontFamily: 'Gochikakutto',
                                      shadows: const [
                                        Shadow(
                                            color: Colors.black,
                                            offset: Offset(-1, -1)),
                                        Shadow(
                                            color: Colors.black,
                                            offset: Offset(1, -1)),
                                        Shadow(
                                            color: Colors.black,
                                            offset: Offset(-1, 1)),
                                        Shadow(
                                            color: Colors.black,
                                            offset: Offset(1, 1)),
                                      ]))))
                          .toList(),
                      onChanged: (value) => widget.onSort(value!),
                    ),
                  ),
                ),
              ]),
            ),
            SizedBox(
                height: _dividerHeight, child: const ColoredBox(color: _kCyan)),
            Expanded(
                child: ClipPath(
              clipper:
                  _MusicListViewportClipper(leftOverflow: 36 * widget.scale),
              child: Stack(clipBehavior: Clip.none, children: [
                NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.depth != 0) return false;
                      if (notification is ScrollUpdateNotification) {
                        _scheduleSnap();
                      } else if (notification is ScrollEndNotification) {
                        _snapToSelectionRow();
                      }
                      return false;
                    },
                    child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                          scrollbars: false,
                          // Windowsでは既定でマウスドラッグがスクロール対象に
                          // 含まれないため、リスト上の任意の位置を左ドラッグして
                          // 上下へ動かせるよう明示する。ホイール入力の処理には触れない。
                          dragDevices: const {
                            PointerDeviceKind.touch,
                            PointerDeviceKind.stylus,
                            PointerDeviceKind.mouse,
                            PointerDeviceKind.trackpad,
                          },
                        ),
                        child: Builder(builder: (context) {
                          final frozenEntries = _frozenEntries;
                          final entries = frozenEntries ?? _entries;
                          // 凍結中も itemCount は展開後の行数にする。これにより
                          // 新しい周回位置へ移動してもスクロール範囲が縮まらない。
                          final itemCountEntryLength = frozenEntries == null
                              ? entries.length
                              : (_frozenItemCountEntries ?? _entries.length);
                          return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onVerticalDragStart: _startListDrag,
                              onVerticalDragUpdate: _updateListDrag,
                              onVerticalDragEnd: _finishListDrag,
                              onVerticalDragCancel: () => _finishListDrag(),
                              child: ListView.builder(
                                  controller: _controller,
                                  // ドラッグは上の GestureDetector が一元的に扱う。
                                  // ホイールは従来どおり _handlePointerSignal のまま。
                                  physics: const NeverScrollableScrollPhysics(),
                                  clipBehavior: Clip.none,
                                  padding: EdgeInsets.zero,
                                  itemExtent: _rowHeight,
                                  itemCount: itemCountEntryLength * _loopCopies,
                                  itemBuilder: (context, index) {
                                    final displayIndex = frozenEntries == null
                                        ? index
                                        : index - _frozenIndexShift;
                                    final entry = entries[
                                        displayIndex % entries.length < 0
                                            ? displayIndex % entries.length +
                                                entries.length
                                            : displayIndex % entries.length];
                                    final isSelectedRow =
                                        index == _selectedVirtualIndex(entries);
                                    late final Widget row;
                                    if (entry.song case final song?) {
                                      final displaySong =
                                          widget.displayChartForRow(song);
                                      row = Listener(
                                          behavior: HitTestBehavior.opaque,
                                          onPointerSignal: _handlePointerSignal,
                                          child: GestureDetector(
                                              onTap: () => _tapSong(index),
                                              onSecondaryTap:
                                                  _secondaryTapCloseExpandedFolder,
                                              child: _SongRow(
                                                  chart: displaySong,
                                                  clear: widget.clearForChart(
                                                      displaySong),
                                                  selected: isSelectedRow,
                                                  height: _rowHeight,
                                                  scale: widget.scale,
                                                  dividerHeight:
                                                      _dividerHeight)));
                                    } else {
                                      final folder = entry.folder!;
                                      row = Listener(
                                          behavior: HitTestBehavior.opaque,
                                          onPointerSignal: _handlePointerSignal,
                                          child: GestureDetector(
                                              onTap: () => _tapFolder(
                                                  folder, index, entries),
                                              onSecondaryTap:
                                                  _secondaryTapCloseExpandedFolder,
                                              child: _FolderRow(
                                                  label: folder,
                                                  clear: widget
                                                      .folderClearFor(folder),
                                                  selected: isSelectedRow,
                                                  height: _rowHeight,
                                                  scale: widget.scale,
                                                  rivalNames: widget.rivalNames,
                                                  dividerHeight:
                                                      _dividerHeight)));
                                    }
                                    return row;
                                  }));
                        }))),
                Positioned(
                    top: _rowHeight * _selectionRowIndex,
                    left: -27 * widget.scale,
                    right: 0,
                    height: _rowHeight,
                    child: IgnorePointer(
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                border: Border.all(
                                    color: _kCyan, width: _snap(3))))))
              ]),
            )),
          ]),
        ],
      );
}

/// MUSIC SELECTの表示領域は上下だけを確実に切り取り、選択行の左張り出し
/// 分だけ横方向の描画を許可するクリッパー。
class _MusicListViewportClipper extends CustomClipper<Path> {
  const _MusicListViewportClipper({required this.leftOverflow});

  final double leftOverflow;

  @override
  Path getClip(Size size) => Path()
    ..addRect(Rect.fromLTWH(
        -leftOverflow, 0, size.width + leftOverflow, size.height));

  @override
  Rect getApproximateClipRect(Size size) =>
      Rect.fromLTWH(-leftOverflow, 0, size.width + leftOverflow, size.height);

  @override
  bool shouldReclip(covariant _MusicListViewportClipper oldClipper) =>
      oldClipper.leftOverflow != leftOverflow;
}

class _MusicSelectEntry {
  const _MusicSelectEntry.folder(this.folder)
      : song = null,
        songIndex = null;
  const _MusicSelectEntry.song(this.song, this.songIndex) : folder = null;

  final String? folder;
  final Chart? song;
  final int? songIndex;
}

class _FolderRow extends StatelessWidget {
  const _FolderRow(
      {required this.label,
      required this.clear,
      required this.selected,
      required this.height,
      required this.scale,
      required this.rivalNames,
      required this.dividerHeight});
  final String label;
  final ClearType? clear;
  final bool selected;
  final double height;
  final double scale;
  final Map<int, String> rivalNames;
  final double dividerHeight;

  String get _rivalName {
    if (label.startsWith('MY BEST ')) return 'MY BEST';
    final match = RegExp(r'^RIVAL(\d+) ').firstMatch(label);
    if (match == null) return 'DJ NAME';
    final slot = int.parse(match.group(1)!);
    return rivalNames[slot]?.isNotEmpty == true ? rivalNames[slot]! : 'DJ NAME';
  }

  List<Color> get gradient {
    const versions = {
      'SUBSTREAM',
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
      'PINKY CRUSH',
      'SPARKLE SHOWER'
    };
    if (label.endsWith('STYLE') || versions.contains(label)) {
      return const [Color(0xff5acfe5), Color(0xff258dc2), Color(0xff09518f)];
    }
    if (label == 'LEGGENDARIA') {
      return const [Color(0xffc879ed), Color(0xff8741c7), Color(0xff471c92)];
    }
    if (label.startsWith('LEVEL')) {
      return const [Color(0xff51d9df), Color(0xff1898bc), Color(0xff0b668c)];
    }
    if (label.startsWith('DJ LEVEL')) {
      return const [Color(0xffffdc51), Color(0xffe0aa1e), Color(0xffa96d05)];
    }
    if (label == 'NOTES') {
      return const [Color(0xffff8ecb), Color(0xffdd3a9d), Color(0xff8d155f)];
    }
    if (label == 'CHORD') {
      return const [Color(0xffb6ef61), Color(0xff599e37), Color(0xff1c542c)];
    }
    if (label == 'PEAK') {
      return const [Color(0xffffd069), Color(0xffdc7b20), Color(0xff93400e)];
    }
    if (label == 'CHARGE') {
      return const [Color(0xffd99aff), Color(0xff8542c8), Color(0xff432183)];
    }
    if (label == 'SCRATCH') {
      return const [Color(0xffff8e8e), Color(0xffd33c43), Color(0xff821f2f)];
    }
    if (label == 'SOF-LAN') {
      return const [Color(0xff8de9ff), Color(0xff219dc6), Color(0xff0b557b)];
    }
    if (label.contains('SCORE WIN') || label.contains('CLEAR WIN')) {
      return const [Color(0xff69d9d3), Color(0xff1a9e9c), Color(0xff0a626b)];
    }
    if (label.contains('SCORE LOSE') || label.contains('CLEAR LOSE')) {
      return const [Color(0xff76bdf0), Color(0xff237dc6), Color(0xff0e4387)];
    }
    if (label == 'FULL COMBO') {
      return const [Color(0xffe9fbff), Color(0xff80deea), Color(0xff348eae)];
    }
    if (label == 'EX HARD CLEAR') {
      return const [Color(0xffffcb7e), Color(0xffdf7825), Color(0xff89360d)];
    }
    if (label == 'HARD CLEAR') {
      return const [Color(0xffff9d93), Color(0xffca3c3d), Color(0xff7c1d2b)];
    }
    if (label == 'CLEAR') {
      return const [Color(0xff92f3f3), Color(0xff29aebc), Color(0xff136b83)];
    }
    if (label == 'EASY') {
      return const [Color(0xffb5ef7f), Color(0xff4aa33c), Color(0xff1b5d2b)];
    }
    if (label == 'ASSIST EASY') {
      return const [Color(0xffdf9cff), Color(0xff8844be), Color(0xff472079)];
    }
    if (label == 'FAILED') {
      return const [Color(0xffe98888), Color(0xffa23540), Color(0xff5d1b2c)];
    }
    if (label == 'NO PLAY') {
      return const [Color(0xffc5d1d8), Color(0xff72818c), Color(0xff34434e)];
    }
    // INITIAL folders use the blue-violet treatment from the reference movie.
    return const [Color(0xff91acef), Color(0xff586fc2), Color(0xff2c3d83)];
  }

  @override
  Widget build(BuildContext context) => Transform.translate(
        // 選択行だけをリスト左端から少し張り出させる。
        offset: Offset(selected ? -27 * scale : 0, 0),
        child: Container(
          height: height,
          color: const Color(0xff06243d),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipPath(
                clipper: _FolderRowClipper(scale: scale),
                child: Container(
                  padding: EdgeInsets.only(left: 30 * scale, right: 50 * scale),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gradient),
                  ),
                  alignment: Alignment.centerLeft,
                  child:
                      label.startsWith('RIVAL') || label.startsWith('MY BEST')
                          ? Row(children: [
                              Expanded(
                                  child: _OutlineText(label,
                                      fontSize: 20 * scale,
                                      weight: FontWeight.normal,
                                      fontFamily: 'Gochikakutto',
                                      blackOutline: true)),
                              SizedBox(width: 12 * scale),
                              ClipPath(
                                clipper: _RivalNameClipper(scale: scale),
                                child: Container(
                                  width: 122 * scale,
                                  height: double.infinity,
                                  color: const Color(0xff06243d),
                                  alignment: Alignment.center,
                                  child: _OutlineText(_rivalName,
                                      fontSize: 14 * scale,
                                      weight: FontWeight.bold,
                                      fontFamily: 'Gochikakutto',
                                      blackOutline: true),
                                ),
                              ),
                            ])
                          : _OutlineText(label,
                              fontSize: 20 * scale,
                              weight: FontWeight.normal,
                              fontFamily: 'Gochikakutto',
                              blackOutline: true),
                ),
              ),
              if (clear != null)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 13 * scale,
                  child: IgnorePointer(
                      child: _ClearLamp(
                          clear: clear!, scale: scale, height: height)),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: dividerHeight,
                child: const DecoratedBox(
                  decoration: BoxDecoration(color: Color(0xffa9ecff)),
                ),
              ),
            ],
          ),
        ),
      );
}

class _SongRow extends StatelessWidget {
  const _SongRow(
      {required this.chart,
      required this.clear,
      required this.selected,
      required this.height,
      required this.scale,
      required this.dividerHeight});

  final Chart chart;
  final ClearType clear;
  final bool selected;
  final double height;
  final double scale;
  final double dividerHeight;

  Color get _levelColor => switch (chart.type) {
        ChartType.beginner => const Color(0xff1aaf4a),
        ChartType.normal => const Color(0xff2b8ce0),
        ChartType.hyper => const Color(0xffd19719),
        ChartType.another => const Color(0xffd23b48),
        ChartType.leggendaria => const Color(0xff9050cf),
      };
  @override
  Widget build(BuildContext context) => Transform.translate(
        // フォルダ行と同じく、選択された楽曲を少し左へ張り出す。
        offset: Offset(selected ? -27 * scale : 0, 0),
        child: Container(
          height: height,
          color: const Color(0xff061f39),
          child: Stack(fit: StackFit.expand, children: [
            Container(
              // クリアランプの右端からレベルバッジを始めるため、ランプ幅を
              // 常に予約する。NO PLAY時もリスト行の基準線がぶれない。
              padding: EdgeInsets.only(left: 13 * scale, right: 24 * scale),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [
                  Color(0xff15597f),
                  Color(0xff0b3558),
                  Color(0xff061f39)
                ]),
              ),
              child: Row(children: [
                Container(
                  width: 58 * scale,
                  // 行高いっぱいの、色を付けない半透明ガラス面。譜面種別は
                  // 数字の色だけで示し、クリアランプと役割を分離する。
                  height: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        // 右側の濃紺より一段淡く見えるガラス面。色そのものは
                        // 持たせず、譜面種別は数字色だけで判別できるようにする。
                        Color(0x66f3fcff),
                        Color(0x338dd9ff),
                        Color(0x220e3d63),
                      ],
                    ),
                    border: Border(
                      left: BorderSide(color: Color(0x99e9fbff)),
                      right: BorderSide(color: Color(0x6685dfff)),
                    ),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 3,
                          offset: Offset(1, 0)),
                    ],
                  ),
                  child: _OutlineText('${chart.level}',
                      fontSize: 22 * scale,
                      color: _levelColor,
                      weight: FontWeight.w500,
                      fontFamily: 'Gochikakutto'),
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                    child: _OutlineText(chart.songTitle,
                        fontSize: 20 * scale,
                        weight: FontWeight.normal,
                        leggendariaGradient:
                            chart.type == ChartType.leggendaria)),
              ]),
            ),
            if (clear != ClearType.noPlay)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 13 * scale,
                child: IgnorePointer(
                    child:
                        _ClearLamp(clear: clear, scale: scale, height: height)),
              ),
            Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: dividerHeight,
                child: const ColoredBox(color: Color(0xff65cdeb))),
          ]),
        ),
      );
}

/// 選曲リスト左端のクリアランプ。
/// 外側の発光フレーム、白い左ハイライト、内側の色面を分けて、
/// 実機の小型インジケーターに近い立体感を作る。
class _ClearLamp extends StatefulWidget {
  const _ClearLamp(
      {required this.clear, required this.scale, required this.height});

  final ClearType clear;
  final double scale;
  final double height;

  @override
  State<_ClearLamp> createState() => _ClearLampState();
}

class _ClearLampState extends State<_ClearLamp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blinkController;

  bool get _shouldBlink => widget.clear == ClearType.fullCombo;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    if (_shouldBlink) _blinkController.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _ClearLamp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_shouldBlink && !_blinkController.isAnimating) {
      _blinkController.repeat(reverse: true);
    } else if (!_shouldBlink && _blinkController.isAnimating) {
      _blinkController.stop();
      _blinkController.value = 0;
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    final base = widget.clear == ClearType.hard
        ? Colors.white
        : _clearColor(widget.clear);
    return AnimatedBuilder(
      animation: _blinkController,
      builder: (context, child) {
        // FULL COMBOだけは水色から白へ往復させ、虹色ではなく
        // 実機の白いフラッシュに近い見え方にする。
        final flash = _shouldBlink ? _blinkController.value : 0.0;
        final face = Color.lerp(base, Colors.white, flash) ?? base;
        final frame =
            Color.lerp(base, Colors.white, .58 + flash * .42) ?? Colors.white;
        return SizedBox(
          width: 13 * s,
          height: widget.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xff071c2d),
              borderRadius: BorderRadius.circular(1.5 * s),
              border: Border.all(color: frame, width: 1.0 * s),
              boxShadow: [
                BoxShadow(
                    color: face.withValues(alpha: .82),
                    blurRadius: 3 * s,
                    spreadRadius: .2 * s),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(1.5 * s),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Colors.white.withValues(alpha: .88),
                    face,
                    face.withValues(alpha: .65),
                  ]),
                  borderRadius: BorderRadius.circular(.7 * s),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 2 * s,
                    margin: EdgeInsets.symmetric(vertical: 3 * s),
                    color: Colors.white.withValues(alpha: .92),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FolderRowClipper extends CustomClipper<Path> {
  const _FolderRowClipper({required this.scale});
  final double scale;

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width - 38 * scale, 0)
    ..lineTo(size.width - 19 * scale, size.height / 2)
    ..lineTo(size.width - 38 * scale, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(covariant _FolderRowClipper oldClipper) =>
      oldClipper.scale != scale;
}

class _RivalNameClipper extends CustomClipper<Path> {
  const _RivalNameClipper({required this.scale});
  final double scale;

  @override
  Path getClip(Size size) => Path()
    ..moveTo(10 * scale, 0)
    ..lineTo(size.width - 19 * scale, 0)
    ..lineTo(size.width, size.height / 2)
    ..lineTo(size.width - 19 * scale, size.height)
    ..lineTo(10 * scale, size.height)
    ..lineTo(0, size.height / 2)
    ..close();

  @override
  bool shouldReclip(covariant _RivalNameClipper oldClipper) =>
      oldClipper.scale != scale;
}

class _RadarListButton extends StatelessWidget {
  const _RadarListButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: ClipPath(
          clipper: const _ArrowClipper(),
          child: Container(
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xff0c4e74), Color(0xff062640)]),
                  border: Border.all(color: _kCyan, width: 1.8),
                  boxShadow: const [
                    BoxShadow(color: Color(0x8835dcff), blurRadius: 8)
                  ]),
              alignment: Alignment.center,
              child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.format_list_numbered_rounded,
                        color: _kCyan, size: 19),
                    SizedBox(width: 9),
                    _OutlineText('NOTES RADAR LIST',
                        fontSize: 17,
                        weight: FontWeight.bold,
                        letterSpacing: 1,
                        fontFamily: 'Gochikakutto'),
                    SizedBox(width: 8),
                    Icon(Icons.chevron_right_rounded, color: _kCyan),
                  ]))));
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: ClipPath(
          clipper: const _CutCornerClipper(cut: 13),
          child: Container(
              color: const Color(0xd6052a42),
              padding: const EdgeInsets.symmetric(horizontal: 23),
              child: const Row(children: [
                Icon(Icons.close_rounded, color: Color(0xffffa72a), size: 29),
                SizedBox(width: 20),
                _OutlineText('BACK',
                    fontSize: 18, letterSpacing: 2, fontFamily: 'Gochikakutto')
              ]))));
}

class _RadarListOverlay extends StatefulWidget {
  const _RadarListOverlay({required this.repository});
  final AppRepository repository;
  @override
  State<_RadarListOverlay> createState() => _RadarListOverlayState();
}

class _RadarListOverlayState extends State<_RadarListOverlay> {
  PlayStyle style = PlayStyle.sp;
  RadarAttribute attribute = RadarAttribute.notes;

  late final ScrollController _listController;

  @override
  void initState() {
    super.initState();
    _listController = ScrollController();
  }

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  void _changeList({PlayStyle? nextStyle, RadarAttribute? nextAttribute}) {
    setState(() {
      if (nextStyle != null) style = nextStyle;
      if (nextAttribute != null) attribute = nextAttribute;
    });
    // 新しい属性／プレースタイルのランキングは常に1位から確認する。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _listController.hasClients) {
        _listController.jumpTo(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.repository
        .forStyle(style)
        .where((item) => item.maxRadar.by(attribute) >= 135)
        .toList()
      ..sort((a, b) =>
          b.maxRadar.by(attribute).compareTo(a.maxRadar.by(attribute)));
    return Dialog(
      backgroundColor: const Color(0xff031d35),
      insetPadding: const EdgeInsets.symmetric(horizontal: 72, vertical: 55),
      child: Container(
        decoration: BoxDecoration(
            border: Border.all(color: _kCyan, width: 2),
            borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Row(children: [
            SizedBox(
              width: 250,
              child: Row(
                children: PlayStyle.values
                    .map((item) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: OutlinedButton(
                              onPressed: () => _changeList(nextStyle: item),
                              style: OutlinedButton.styleFrom(
                                  backgroundColor: style == item
                                      ? const Color(0xff198be9)
                                      : Colors.transparent,
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: _kCyan)),
                              child: Text(item.label,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Gochikakutto',
                                      shadows: [
                                        Shadow(
                                            color: Colors.black,
                                            offset: Offset(-1, -1)),
                                        Shadow(
                                            color: Colors.black,
                                            offset: Offset(1, -1)),
                                        Shadow(
                                            color: Colors.black,
                                            offset: Offset(-1, 1)),
                                        Shadow(
                                            color: Colors.black,
                                            offset: Offset(1, 1)),
                                      ])),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
            const Spacer(),
            const _OutlineText('NOTES RADAR LIST',
                fontSize: 28, fontFamily: 'Gochikakutto'),
            const Spacer(),
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white)),
          ]),
          const SizedBox(height: 18),
          Row(
            children: RadarAttribute.values
                .map((item) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: OutlinedButton(
                          onPressed: () => _changeList(nextAttribute: item),
                          style: OutlinedButton.styleFrom(
                              backgroundColor: attribute == item
                                  ? _radarColor(item)
                                  : Colors.transparent,
                              foregroundColor: attribute == item
                                  ? Colors.white
                                  : _radarColor(item),
                              side: BorderSide(color: _radarColor(item))),
                          child: Text(item.label,
                              style: TextStyle(
                                  color: attribute == item
                                      ? Colors.white
                                      : _radarColor(item),
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Gochikakutto',
                                  shadows: const [
                                    Shadow(
                                        color: Colors.black,
                                        offset: Offset(-1, -1)),
                                    Shadow(
                                        color: Colors.black,
                                        offset: Offset(1, -1)),
                                    Shadow(
                                        color: Colors.black,
                                        offset: Offset(-1, 1)),
                                    Shadow(
                                        color: Colors.black,
                                        offset: Offset(1, 1)),
                                  ])),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: _kCyan)),
              child: Column(children: [
                Container(
                  height: 42,
                  color: const Color(0xff0e5876),
                  child: const Row(children: [
                    SizedBox(
                        width: 74,
                        child: Center(
                            child: _OutlineText('RANK',
                                fontSize: 15, weight: FontWeight.bold))),
                    Expanded(
                        flex: 3,
                        child: Center(
                            child: _OutlineText('MUSIC',
                                fontSize: 15, weight: FontWeight.bold))),
                    Expanded(
                        child: Center(
                            child: _OutlineText('CHART',
                                fontSize: 15, weight: FontWeight.bold))),
                    Expanded(
                        child: Center(
                            child: _OutlineText('NOTES',
                                fontSize: 16, weight: FontWeight.bold))),
                    SizedBox(
                        width: 150,
                        child: Center(
                            child: _OutlineText('MAX RADAR',
                                fontSize: 16, weight: FontWeight.bold))),
                  ]),
                ),
                Expanded(
                  child: ScrollConfiguration(
                    // Windowsでも一覧上を左ドラッグして上下へ移動できるように
                    // する。ホイール／タッチの標準操作もそのまま維持する。
                    behavior: ScrollConfiguration.of(context).copyWith(
                      scrollbars: false,
                      dragDevices: const {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.stylus,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                      },
                    ),
                    child: ListView.separated(
                      controller: _listController,
                      itemCount: data.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: _kLine),
                      itemBuilder: (context, index) {
                        final item = data[index];
                        return SizedBox(
                          height: 48,
                          child: Row(children: [
                            SizedBox(
                                width: 74,
                                child: Center(
                                    child: _OutlineText('${index + 1}',
                                        fontSize: 20,
                                        color: const Color(0xffffd134)))),
                            Expanded(
                                flex: 3,
                                child:
                                    _OutlineText(item.songTitle, fontSize: 18)),
                            Expanded(
                                child: Center(
                                    child: _OutlineText(item.type.label,
                                        fontSize: 17,
                                        color: _chartListColor(item.type)))),
                            Expanded(
                                child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Padding(
                                        padding:
                                            const EdgeInsets.only(right: 16),
                                        child: _OutlineText(
                                            _formatNumber(item.maxScore ~/ 2),
                                            fontSize: 18)))),
                            SizedBox(
                                width: 150,
                                child: Center(
                                    child: _OutlineText(
                                        item.maxRadar
                                            .by(attribute)
                                            .toStringAsFixed(2),
                                        fontSize: 18,
                                        color: _radarColor(attribute),
                                        weight: FontWeight.bold))),
                          ]),
                        );
                      },
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _OutlineText extends StatelessWidget {
  const _OutlineText(this.text,
      {required this.fontSize,
      this.color = Colors.white,
      this.weight = FontWeight.normal,
      this.letterSpacing,
      this.fontFamily,
      this.blackOutline = false,
      this.leggendariaGradient = false});
  final String text;
  final double fontSize;
  final Color color;
  final FontWeight weight;
  final double? letterSpacing;
  final String? fontFamily;
  final bool blackOutline;
  final bool leggendariaGradient;
  @override
  Widget build(BuildContext context) {
    final shadows = blackOutline || fontFamily == 'Gochikakutto'
        ? const [
            Shadow(color: Colors.black, blurRadius: 0, offset: Offset(-1, -1)),
            Shadow(color: Colors.black, blurRadius: 0, offset: Offset(1, -1)),
            Shadow(color: Colors.black, blurRadius: 0, offset: Offset(-1, 1)),
            Shadow(color: Colors.black, blurRadius: 0, offset: Offset(1, 1)),
          ]
        : const [
            Shadow(color: Colors.black, blurRadius: 1.8, offset: Offset(.7, .7))
          ];
    final label = Text(text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: fontSize,
            color: leggendariaGradient ? Colors.white : color,
            fontWeight: weight,
            fontFamily: fontFamily,
            letterSpacing: letterSpacing,
            shadows: shadows));
    if (!leggendariaGradient) return label;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        // 上から約3分の1は白を保ち、その後ピンクへ移行させる。
        colors: [Colors.white, Colors.white, Color(0xffc800a7)],
        stops: [0, .24, 1],
      ).createShader(bounds),
      child: label,
    );
  }
}

/// 楽曲タイトル用。行の高さを先に確保し、入り切らない時だけ描画を横方向へ
/// 圧縮するため、曲名が長くても周囲の縦レイアウトを動かさない。
class _TitleText extends StatelessWidget {
  const _TitleText(this.text,
      {required this.fontSize,
      this.weight = FontWeight.normal,
      this.letterSpacing,
      this.fontFamily,
      this.leggendariaGradient = false});

  final String text;
  final double fontSize;
  final FontWeight weight;
  final double? letterSpacing;
  final String? fontFamily;
  final bool leggendariaGradient;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final style = TextStyle(
              fontSize: fontSize,
              fontWeight: weight,
              fontFamily: fontFamily,
              letterSpacing: letterSpacing);
          final painter = TextPainter(
              text: TextSpan(text: text, style: style),
              textDirection: Directionality.of(context),
              maxLines: 1)
            ..layout();
          // Column配下では幅制約が無制限になる経路があるため、縮小判定には
          // 常に有限の描画幅を使う。これにより末尾の一文字も切らない。
          final textWidth = painter.width + 4;
          const maxWidth = 400.0;
          final scaleX = textWidth > maxWidth ? maxWidth / textWidth : 1.0;

          // 横幅圧縮後もグラデーション座標が文字領域と一致するよう、
          // 楽曲タイトルは専用Painterで描画する。
          final title = leggendariaGradient
              ? CustomPaint(
                  size: Size(textWidth, painter.height + 4),
                  painter: _LeggendariaTitlePainter(
                    text: text,
                    fontSize: fontSize,
                    weight: weight,
                    fontFamily: fontFamily,
                    letterSpacing: letterSpacing,
                  ),
                )
              : Text(text,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                      fontSize: fontSize,
                      color: Colors.white,
                      fontWeight: weight,
                      fontFamily: fontFamily,
                      letterSpacing: letterSpacing,
                      shadows: const [
                        Shadow(
                            color: Colors.black,
                            blurRadius: 1.8,
                            offset: Offset(.7, .7))
                      ]));

          return SizedBox(
            // Transformはレイアウト上の寸法を変えないため、タイトル行の高さを
            // 明示してジャンル・アーティスト等が詰まらないようにする。
            height: painter.height + 4,
            width: constraints.maxWidth,
            child: ClipRect(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Transform(
                  alignment: Alignment.centerLeft,
                  transform: Matrix4.diagonal3Values(scaleX, 1, 1),
                  // 親の横幅制約でCustomPaintが先に切り詰められないよう、
                  // 実際の曲名幅では無制限に描画してから横方向だけ縮小する。
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    child: SizedBox(
                      width: textWidth,
                      // タイトルは省略記号を使わない。外側で必要な場合のみ横圧縮する。
                      child: title,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

/// 横幅圧縮中も縦方向の色位置を安定させる、LEGGENDARIA曲名専用Painter。
class _LeggendariaTitlePainter extends CustomPainter {
  const _LeggendariaTitlePainter({
    required this.text,
    required this.fontSize,
    required this.weight,
    required this.fontFamily,
    required this.letterSpacing,
  });

  final String text;
  final double fontSize;
  final FontWeight weight;
  final String? fontFamily;
  final double? letterSpacing;

  @override
  void paint(Canvas canvas, Size size) {
    final foreground = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Colors.white, Color(0xffc800a7)],
        stops: [0, .24, 1],
      ).createShader(Offset.zero & size);
    final painter = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                fontSize: fontSize,
                foreground: foreground,
                fontWeight: weight,
                fontFamily: fontFamily,
                letterSpacing: letterSpacing,
                shadows: const [
                  Shadow(
                      color: Colors.black,
                      blurRadius: 1.8,
                      offset: Offset(.7, .7))
                ])),
        textDirection: TextDirection.ltr,
        maxLines: 1)
      // CustomPaintに渡した幅そのものが曲名の実幅。ここで親パネル幅を
      // maxWidthに使うと、長い曲名だけ末尾が切れてしまう。
      ..layout();
    painter.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(covariant _LeggendariaTitlePainter oldDelegate) =>
      text != oldDelegate.text ||
      fontSize != oldDelegate.fontSize ||
      weight != oldDelegate.weight ||
      fontFamily != oldDelegate.fontFamily ||
      letterSpacing != oldDelegate.letterSpacing;
}

class _CutCornerClipper extends CustomClipper<Path> {
  const _CutCornerClipper({required this.cut});
  final double cut;
  @override
  Path getClip(Size size) => Path()
    ..moveTo(cut, 0)
    ..lineTo(size.width - cut, 0)
    ..lineTo(size.width, cut)
    ..lineTo(size.width, size.height - cut)
    ..lineTo(size.width - cut, size.height)
    ..lineTo(cut, size.height)
    ..lineTo(0, size.height - cut)
    ..lineTo(0, cut)
    ..close();
  @override
  bool shouldReclip(covariant _CutCornerClipper oldClipper) =>
      oldClipper.cut != cut;
}

class _ArrowClipper extends CustomClipper<Path> {
  const _ArrowClipper();
  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width - 24, 0)
    ..lineTo(size.width, size.height / 2)
    ..lineTo(size.width - 24, size.height)
    ..lineTo(0, size.height)
    ..lineTo(13, size.height / 2)
    ..close();
  @override
  bool shouldReclip(covariant _ArrowClipper oldClipper) => false;
}

RadarAttribute? _radarFolderAttribute(String folder) => switch (folder) {
      'NOTES' => RadarAttribute.notes,
      'CHORD' => RadarAttribute.chord,
      'PEAK' => RadarAttribute.peak,
      'CHARGE' => RadarAttribute.charge,
      'SCRATCH' => RadarAttribute.scratch,
      'SOF-LAN' => RadarAttribute.sofLan,
      _ => null,
    };

String _formatNumber(int value) => value
    .toString()
    .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// 紺背景の一覧上で十分なコントラストを確保する譜面種別の文字色。
Color _chartListColor(ChartType type) => switch (type) {
      ChartType.beginner => const Color(0xff69ec91),
      ChartType.normal => const Color(0xff6bc2ff),
      ChartType.hyper => const Color(0xffffd34f),
      ChartType.another => const Color(0xffff6875),
      ChartType.leggendaria => const Color(0xffd797ff),
    };

ClearType? _clearForFolder(String folder) => switch (folder) {
      'FULL COMBO' => ClearType.fullCombo,
      'EX HARD CLEAR' => ClearType.exHard,
      'HARD CLEAR' => ClearType.hard,
      'CLEAR' => ClearType.clear,
      'EASY' => ClearType.easy,
      'ASSIST EASY' => ClearType.assistEasy,
      'FAILED' => ClearType.failed,
      'NO PLAY' => ClearType.noPlay,
      _ => null,
    };

int _clearOrder(ClearType value) => switch (value) {
      ClearType.fullCombo => 7,
      ClearType.exHard => 6,
      ClearType.hard => 5,
      ClearType.clear => 4,
      ClearType.easy => 3,
      ClearType.assistEasy => 2,
      ClearType.failed => 1,
      ClearType.noPlay => 0,
    };

String? _normaliseDjLevel(String? value) => value == 'MAX' ? 'AAA' : value;

int _threshold(int maxScore, int ninths) => (maxScore * ninths + 8) ~/ 9;

/// DJ LEVELゲージ用の達成率。
///
/// ランク表示はMAX SCOREのn/9を切り上げた整数点を境界としている。一方、
/// ゲージの8区画は F / E / D / C / B / A / AA / AAA に対応するため、
/// その整数境界を区画の境界線へ正確に割り当てる。例えばAAA+0点
/// （ceil(MAX×8/9)）は、AAとAAAの間である7/8の位置になる。
double _djLevelGaugeRate(int score, int maxScore) {
  if (maxScore <= 0 || score <= 0) return 0;
  if (score >= maxScore) return 1;

  final scoreStops = <int>[
    0,
    _threshold(maxScore, 2),
    _threshold(maxScore, 3),
    _threshold(maxScore, 4),
    _threshold(maxScore, 5),
    _threshold(maxScore, 6),
    _threshold(maxScore, 7),
    _threshold(maxScore, 8),
    maxScore,
  ];
  for (var index = 0; index < scoreStops.length - 1; index++) {
    final start = scoreStops[index];
    final end = scoreStops[index + 1];
    if (score <= end) {
      final span = end - start;
      final progress = span <= 0 ? 1.0 : (score - start) / span;
      return ((index + progress) / 8).clamp(0.0, 1.0);
    }
  }
  return 1;
}

String _djLevel(int score, int maxScore) {
  if (score >= _threshold(maxScore, 8)) return 'AAA';
  if (score >= _threshold(maxScore, 7)) return 'AA';
  if (score >= _threshold(maxScore, 6)) return 'A';
  if (score >= _threshold(maxScore, 5)) return 'B';
  if (score >= _threshold(maxScore, 4)) return 'C';
  if (score >= _threshold(maxScore, 3)) return 'D';
  if (score >= _threshold(maxScore, 2)) return 'E';
  return 'F';
}

String _rankDelta(int score, int maxScore) {
  if (score >= maxScore) return 'MAX+0';
  final rank = _djLevel(score, maxScore);
  const ninthByRank = {
    'AAA': 8,
    'AA': 7,
    'A': 6,
    'B': 5,
    'C': 4,
    'D': 3,
    'E': 2,
    'F': 0
  };
  const nextRank = {
    'AAA': 'MAX',
    'AA': 'AAA',
    'A': 'AA',
    'B': 'A',
    'C': 'B',
    'D': 'C',
    'E': 'D',
    'F': 'E'
  };
  final lower = _threshold(maxScore, ninthByRank[rank]!);
  final upper = rank == 'AAA'
      ? maxScore
      : _threshold(maxScore, ninthByRank[nextRank[rank]!]!);
  final upDistance = upper - score;
  final downDistance = score - lower;
  return upDistance <= downDistance
      ? '${nextRank[rank]}-$upDistance'
      : '$rank+$downDistance';
}

bool _isNegativeRankDelta(String value) => value.contains('-');

Color _rankColor(String value) => value == 'AAA'
    ? const Color(0xffffd53f)
    : value == 'AA'
        ? const Color(0xffecf2f8)
        : value == 'A'
            ? const Color(0xffe0a046)
            : Colors.white;
Color _clearColor(ClearType value) => switch (value) {
      ClearType.fullCombo => const Color(0xffbdffff),
      ClearType.exHard => const Color(0xffffa329),
      ClearType.hard => const Color(0xffff464f),
      ClearType.clear => _kCyan,
      ClearType.easy => const Color(0xff6ee794),
      ClearType.assistEasy => const Color(0xffbf70f3),
      ClearType.failed => const Color(0xff8d1f2b),
      ClearType.noPlay => Colors.grey
    };
Color _radarColor(RadarAttribute value) => switch (value) {
      RadarAttribute.notes => const Color(0xffff4fb4),
      RadarAttribute.chord => const Color(0xff77e33c),
      RadarAttribute.peak => const Color(0xffff9e25),
      RadarAttribute.charge => const Color(0xffb75cf0),
      RadarAttribute.scratch => const Color(0xffff3e47),
      RadarAttribute.sofLan => _kCyan
    };
