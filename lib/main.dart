import 'dart:math' as math;
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'repository.dart';
import 'play_data_mock_screen.dart';

const _musicSelectFoldersKey = 'music_select_visible_folders';
const _playerDjNameKey = 'player_dj_name';

String _normalizeDjNameInput(String value) => String.fromCharCodes(
        value.codeUnits.where((code) => code >= 0x21 && code <= 0x7e))
    .toUpperCase();

final _djNameInputFormatter = TextInputFormatter.withFunction(
  (oldValue, newValue) {
    final normalized = _normalizeDjNameInput(newValue.text);
    final selectionOffset = math.min(normalized.length,
        newValue.selection.baseOffset.clamp(0, newValue.text.length));
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: selectionOffset),
      composing: TextRange.empty,
    );
  },
);

const _musicSelectFolderGroups = <String>[
  'LEVEL',
  'LEGGENDARIA',
  'バージョン',
  '属性',
  'INITIAL',
  'DJ LEVEL',
  'CLEAR',
  'RIVAL WIN／LOSE',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  final preferences = await SharedPreferences.getInstance();
  final savedFolders = preferences.getStringList(_musicSelectFoldersKey);
  final visibleFolders = savedFolders == null || savedFolders.isEmpty
      ? _musicSelectFolderGroups.toSet()
      : savedFolders.toSet();
  final repository =
      AppRepository(playerDjName: preferences.getString(_playerDjNameKey));
  await repository.loadBundledMusicData();
  await repository.restorePersistedUserData();
  runApp(IidxPlayDataApp(
      initialVisibleFolderGroups: visibleFolders, repository: repository));
}

const _navy = Color(0xff041c34);
const _panel = Color(0xe9072948);
const _cyan = Color(0xff36dcff);
const _pink = Color(0xffff4db8);
// PLAY DATA画面のフォルダ行と同じ、ゴチカクット用の黒い縁取り。
const _gochikakuttoOutline = <Shadow>[
  Shadow(color: Colors.black, offset: Offset(-1, -1)),
  Shadow(color: Colors.black, offset: Offset(1, -1)),
  Shadow(color: Colors.black, offset: Offset(-1, 1)),
  Shadow(color: Colors.black, offset: Offset(1, 1)),
];

class IidxPlayDataApp extends StatefulWidget {
  const IidxPlayDataApp(
      {required this.initialVisibleFolderGroups,
      required this.repository,
      super.key});
  final Set<String> initialVisibleFolderGroups;
  final AppRepository repository;

  @override
  State<IidxPlayDataApp> createState() => _IidxPlayDataAppState();
}

class _IidxPlayDataAppState extends State<IidxPlayDataApp> {
  AppPage page = AppPage.home;
  late Set<String> _visibleFolderGroups;

  @override
  void initState() {
    super.initState();
    _visibleFolderGroups = {...widget.initialVisibleFolderGroups};
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IIDX PLAY DATA VIEWER',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          useMaterial3: true, brightness: Brightness.dark, fontFamily: 'Arial'),
      home: SkyScaffold(
        child: switch (page) {
          AppPage.home => HomeScreen(
              playerDjName: widget.repository.playerDjName,
              dataVersion: widget.repository.latestPlayerDataVersion,
              onOpen: (next) => setState(() => page = next)),
          AppPage.playData => PlayDataMockScreen(
              repository: widget.repository,
              visibleFolderGroups: _visibleFolderGroups,
              onBack: () => setState(() => page = AppPage.home)),
          AppPage.settings => _SettingsTypography(
              child: SettingsHome(
                  onOpen: (next) => setState(() => page = next),
                  onBack: () => setState(() => page = AppPage.home))),
          AppPage.playImport => _SettingsTypography(
              child: PlayImportScreen(
                  repository: widget.repository,
                  onBack: () => setState(() => page = AppPage.settings))),
          AppPage.rivalImport => _SettingsTypography(
              child: RivalImportScreen(
                  repository: widget.repository,
                  onBack: () => setState(() => page = AppPage.settings))),
          AppPage.config => _SettingsTypography(
              child: ConfigScreen(
                  visibleFolderGroups: _visibleFolderGroups,
                  onSaved: (groups) =>
                      setState(() => _visibleFolderGroups = {...groups}),
                  onBack: () => setState(() => page = AppPage.settings))),
          AppPage.radarImport => _SettingsTypography(
              child: RadarImportScreen(
                  onBack: () => setState(() => page = AppPage.settings))),
        },
      ),
    );
  }
}

enum AppPage {
  home,
  playData,
  settings,
  playImport,
  rivalImport,
  config,
  radarImport
}

/// SETTING配下だけに適用する、画面全体の文字トーンです。
/// PLAY DATA画面の通常テキストへは影響させません。
class _SettingsTypography extends StatelessWidget {
  const _SettingsTypography({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
      style: const TextStyle(
          fontFamily: 'Gochikakutto', shadows: _gochikakuttoOutline),
      child: child);
}

class SkyScaffold extends StatelessWidget {
  const SkyScaffold({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: Stack(children: [
        Positioned.fill(
            child: Image.asset('assets/images/blue_sky_clean.png',
                fit: BoxFit.cover)),
        const Positioned.fill(
            child: IgnorePointer(
                child: DecoratedBox(
                    decoration: BoxDecoration(color: Color(0x2200144a))))),
        SafeArea(child: child),
      ]),
    );
  }
}

class Header extends StatelessWidget {
  const Header({required this.title, this.onBack, super.key});
  final String title;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
        child: Row(children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 23,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w300,
                  shadows: [Shadow(blurRadius: 3, color: Colors.black)])),
          const Spacer(),
          if (onBack != null) BackButtonGlass(onPressed: onBack!),
        ]),
      );
}

class BackButtonGlass extends StatelessWidget {
  const BackButtonGlass({required this.onPressed, super.key});
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 170,
        height: 55,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.close_rounded, color: Color(0xffffaf45)),
          label: const Text('BACK',
              style: TextStyle(
                  fontFamily: 'Gochikakutto',
                  letterSpacing: 2,
                  shadows: _gochikakuttoOutline)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xcc05253d),
            foregroundColor: Colors.white,
            side: const BorderSide(color: _cyan),
            shape: const BeveledRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(8))),
          ),
        ),
      );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen(
      {required this.playerDjName,
      required this.dataVersion,
      required this.onOpen,
      super.key});
  final String? playerDjName;
  final String? dataVersion;
  final ValueChanged<AppPage> onOpen;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 820;
          final titleSize = compact ? 29.0 : 52.0;
          final horizontal = compact ? 24.0 : 72.0;
          final now = DateTime.now();
          return Stack(children: [
            Positioned.fill(
                child: Image.asset('assets/images/blue_sky_clean.png',
                    fit: BoxFit.cover)),
            Positioned.fill(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                  const Color(0xbf001d59),
                  const Color(0x22001850),
                  const Color(0x11002150)
                ])))),
            SafeArea(
                child: Padding(
              padding: EdgeInsets.fromLTRB(
                  horizontal, compact ? 24 : 35, horizontal, compact ? 20 : 26),
              child: Column(children: [
                Align(
                    alignment: Alignment.centerLeft,
                    child: _HomeBrand(titleSize: titleSize)),
                const Spacer(),
                Flex(
                  direction: compact ? Axis.vertical : Axis.horizontal,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                        flex: compact ? 0 : 12,
                        child: HomeTile(
                            label: 'PLAY DATA',
                            subtitle: 'MY DATA · RIVALS · ALL-TIME BEST',
                            icon: Icons.bar_chart_rounded,
                            color: _cyan,
                            emphasized: true,
                            onTap: () => onOpen(AppPage.playData))),
                    SizedBox(width: compact ? 0 : 34, height: compact ? 18 : 0),
                    Expanded(
                        flex: compact ? 0 : 9,
                        child: HomeTile(
                            label: 'SETTING',
                            subtitle: 'IMPORT · CONFIGURATION',
                            icon: Icons.settings_rounded,
                            color: const Color(0xffaa7cff),
                            onTap: () => onOpen(AppPage.settings))),
                  ],
                ),
                const Spacer(),
                _HomeStatusBar(
                    playerDjName: playerDjName,
                    dataVersion: dataVersion,
                    lastImport: _homeDateTime(now)),
              ]),
            )),
          ]);
        },
      );
}

class HomeTile extends StatelessWidget {
  const HomeTile(
      {required this.label,
      required this.subtitle,
      required this.icon,
      required this.color,
      this.emphasized = false,
      required this.onTap,
      super.key});
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool emphasized;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            constraints: const BoxConstraints(minHeight: 200),
            decoration: BoxDecoration(
                color: const Color(0xd9051d38),
                border: Border.all(color: color, width: emphasized ? 2.8 : 1.7),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: .42), blurRadius: 24)
                ]),
            child: Stack(children: [
              Positioned(
                  top: 0,
                  left: 58,
                  right: 58,
                  child: Container(height: 7, color: color)),
              Positioned(
                  right: 20,
                  bottom: 18,
                  child: Container(width: 32, height: 7, color: color)),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 25),
                child: Row(children: [
                  Icon(icon, size: emphasized ? 84 : 72, color: Colors.white),
                  const SizedBox(width: 28),
                  Expanded(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(label,
                            style: TextStyle(
                                fontSize: emphasized ? 45 : 39,
                                fontWeight: FontWeight.w900,
                                fontStyle: FontStyle.italic,
                                letterSpacing: 2.2,
                                fontFamily: 'Gochikakutto',
                                shadows: _gochikakuttoOutline)),
                        const SizedBox(height: 15),
                        Container(
                            height: 3, width: double.infinity, color: color),
                        const SizedBox(height: 15),
                        Text(subtitle,
                            style: TextStyle(
                                color: color,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                                fontFamily: 'Gochikakutto',
                                shadows: _gochikakuttoOutline))
                      ]))
                ]),
              )
            ]),
          ),
        ),
      );
}

class _HomeBrand extends StatelessWidget {
  const _HomeBrand({required this.titleSize});
  final double titleSize;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 7, height: titleSize * 1.05, color: _cyan),
            const SizedBox(width: 13),
            Text('IIDX PLAY DATA VIEWER',
                style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w900,
                    letterSpacing: titleSize * .06,
                    fontFamily: 'Gochikakutto',
                    shadows: _gochikakuttoOutline))
          ]),
          const SizedBox(height: 11),
          Container(
              width: titleSize * 10.7,
              height: 2,
              color: const Color(0xff91b9ff)),
          const SizedBox(height: 8),
          Container(width: titleSize * 2.7, height: 6, color: _cyan),
        ],
      );
}

class _HomeStatusBar extends StatelessWidget {
  const _HomeStatusBar(
      {required this.playerDjName,
      required this.dataVersion,
      required this.lastImport});
  final String? playerDjName;
  final String? dataVersion;
  final String lastImport;
  @override
  Widget build(BuildContext context) => Container(
        height: 100,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        decoration: BoxDecoration(
            color: const Color(0xd9051d38),
            border: Border.all(color: _cyan.withValues(alpha: .8)),
            borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Expanded(
              child: _StatusItem(
                  icon: Icons.person_outline_rounded,
                  label: 'DJ NAME',
                  value: playerDjName ?? '未登録')),
          _StatusDivider(),
          Expanded(
              child: _StatusItem(
                  icon: Icons.album_outlined,
                  label: 'VERSION',
                  // 未取込時は同梱マスターの現行版を表示する。CSVを複数
                  // 取り込んだ後は、リポジトリが判定した最新の世代を優先する。
                  value: dataVersion ?? 'Sparkle Shower')),
          const _StatusDivider(),
          Expanded(
              child: _StatusItem(
                  icon: Icons.calendar_month_outlined,
                  label: 'LAST IMPORT',
                  value: lastImport)),
        ]),
      );
}

String _homeDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}/${two(value.month)}/${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

class _StatusDivider extends StatelessWidget {
  const _StatusDivider();
  @override
  Widget build(BuildContext context) => const SizedBox(
      height: 54, child: VerticalDivider(color: Color(0xffa8c8eb), width: 34));
}

class _StatusItem extends StatelessWidget {
  const _StatusItem(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 43, color: _cyan),
        const SizedBox(width: 15),
        // ゴチカクットは横幅が広いため、各ステータス枠内でだけ横方向へ
        // 縮小して、日時などが隣の枠へはみ出さないようにする。
        Expanded(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(label,
                          maxLines: 1,
                          style: const TextStyle(
                              color: _cyan,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              fontFamily: 'Gochikakutto',
                              shadows: _gochikakuttoOutline)))),
              const SizedBox(height: 5),
              SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value,
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                              fontFamily: 'Gochikakutto',
                              shadows: _gochikakuttoOutline)))),
            ]))
      ]);
}

class PlayDataScreen extends StatefulWidget {
  const PlayDataScreen(
      {required this.repository, required this.onBack, super.key});
  final AppRepository repository;
  final VoidCallback onBack;
  @override
  State<PlayDataScreen> createState() => _PlayDataScreenState();
}

class _PlayDataScreenState extends State<PlayDataScreen> {
  PlayStyle style = PlayStyle.sp;
  ChartType selectedType = ChartType.another;
  String selectedFolder = 'ABCD';
  String sort = 'デフォルト';
  bool folderOpen = false;

  Chart get chart =>
      widget.repository
          .forStyle(style)
          .where((item) => item.type == selectedType)
          .firstOrNull ??
      widget.repository.forStyle(style).first;
  PlayRecord? get record => widget.repository.recordFor(chart.id);

  @override
  Widget build(BuildContext context) => Column(children: [
        Header(title: 'IIDX PLAY DATA', onBack: widget.onBack),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(38, 2, 28, 20),
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                  flex: 44,
                  child: _SongInformation(
                      style: style,
                      chart: chart,
                      record: record,
                      rivalScores: widget.repository.rivalScores(chart),
                      onStyle: (value) => setState(() {
                            style = value;
                            selectedType = ChartType.another;
                          }),
                      onChart: (value) =>
                          setState(() => selectedType = value))),
              const SizedBox(width: 10),
              Expanded(
                  flex: 31, child: _RadarPanel(chart: chart, record: record)),
              const SizedBox(width: 20),
              Expanded(
                  flex: 42,
                  child: _MusicSelect(
                    selected: selectedFolder,
                    folderOpen: folderOpen,
                    sort: sort,
                    onFolder: (folder) => setState(() {
                      selectedFolder = folder;
                      folderOpen = true;
                    }),
                    onSort: (value) => setState(() => sort = value),
                    onRadarList: () => showDialog<void>(
                        context: context,
                        builder: (_) =>
                            RadarListDialog(repository: widget.repository)),
                  )),
            ]),
          ),
        ),
      ]);
}

class _SongInformation extends StatelessWidget {
  const _SongInformation(
      {required this.style,
      required this.chart,
      required this.record,
      required this.rivalScores,
      required this.onStyle,
      required this.onChart});
  final PlayStyle style;
  final Chart chart;
  final PlayRecord? record;
  final List<RivalScore> rivalScores;
  final ValueChanged<PlayStyle> onStyle;
  final ValueChanged<ChartType> onChart;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StyleSwitch(value: style, onChanged: onStyle),
        const SizedBox(height: 24),
        Center(
            child: Text(chart.version,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    letterSpacing: 2,
                    shadows: [Shadow(blurRadius: 2, color: Colors.black)]))),
        const SizedBox(height: 7),
        Text(chart.genre,
            style: const TextStyle(
                fontSize: 18,
                letterSpacing: 2,
                shadows: [Shadow(blurRadius: 2, color: Colors.black)])),
        const SizedBox(height: 6),
        Text(chart.songTitle,
            style: const TextStyle(
                fontSize: 42,
                letterSpacing: 1,
                fontWeight: FontWeight.w300,
                shadows: [Shadow(blurRadius: 3, color: Colors.black)])),
        Text(chart.artist,
            style: const TextStyle(
                fontSize: 19,
                letterSpacing: 2,
                shadows: [Shadow(blurRadius: 2, color: Colors.black)])),
        const SizedBox(height: 16),
        Center(
            child: Text(chart.bpm,
                style: const TextStyle(
                    fontSize: 19,
                    shadows: [Shadow(blurRadius: 2, color: Colors.black)]))),
        const SizedBox(height: 14),
        Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ChartType.values.map((type) {
              final enabled =
                  style == PlayStyle.sp || type == ChartType.another;
              return ChartChip(
                  type: type,
                  level: enabled ? [3, 7, 10, 12, 12][type.index] : null,
                  selected: type == chart.type,
                  enabled: enabled,
                  onTap: () => onChart(type));
            }).toList()),
        const SizedBox(height: 18),
        _StatusPanel(chart: chart, record: record),
        const Spacer(),
        _RivalPanel(chart: chart, scores: rivalScores),
      ]);
}

class StyleSwitch extends StatelessWidget {
  const StyleSwitch({required this.value, required this.onChanged, super.key});
  final PlayStyle value;
  final ValueChanged<PlayStyle> onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 282,
        child: Row(
            children: PlayStyle.values
                .map((style) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: OutlinedButton(
                          onPressed: () => onChanged(style),
                          style: OutlinedButton.styleFrom(
                              backgroundColor: value == style
                                  ? const Color(0xff168ff1)
                                  : _panel,
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                  color:
                                      value == style ? _cyan : Colors.white54),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14)),
                          child: Text(style.label,
                              style: const TextStyle(
                                  fontFamily: 'Gochikakutto',
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  shadows: _gochikakuttoOutline)),
                        ),
                      ),
                    ))
                .toList()),
      );
}

class ChartChip extends StatelessWidget {
  const ChartChip(
      {required this.type,
      required this.level,
      required this.selected,
      required this.enabled,
      required this.onTap,
      super.key});
  final ChartType type;
  final int? level;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  Color get color => switch (type) {
        ChartType.beginner => const Color(0xff18a946),
        ChartType.normal => const Color(0xff2299db),
        ChartType.hyper => const Color(0xffffb400),
        ChartType.another => const Color(0xffe43643),
        ChartType.leggendaria => const Color(0xff9a45d5),
      };
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: enabled ? 1 : .35,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Container(
            width: type == ChartType.leggendaria ? 166 : 132,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: color,
                border: Border.all(
                    color:
                        selected ? Colors.white : color.withValues(alpha: .8),
                    width: selected ? 2 : 1),
                borderRadius: BorderRadius.circular(24)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Expanded(
                  child: Text(type.label,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold))),
              if (level != null)
                Text('$level',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold))
            ]),
          ),
        ),
      );
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.chart, required this.record});
  final Chart chart;
  final PlayRecord? record;
  @override
  Widget build(BuildContext context) {
    final score = record?.score ?? 0;
    final rate = chart.maxScore == 0 ? 0.0 : score / chart.maxScore * 100;
    final rank = djLevel(rate);
    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
          color: _panel,
          border: Border.all(color: _cyan, width: 2),
          borderRadius: BorderRadius.circular(5)),
      child: Column(children: [
        StatusRow(label: 'DJ LEVEL', value: rank, valueColor: rankColor(rank)),
        StatusRow(
            label: 'SCORE',
            value: '$score',
            extra:
                '${rank == 'AAA' ? 'MAX' : 'AAA'}-${(3200 - score).abs()}   (${rate.toStringAsFixed(1)}%)',
            valueColor: _cyan),
        StatusRow(
            label: 'CLEAR',
            value: record?.clear.label ?? ClearType.noPlay.label,
            valueColor: clearColor(record?.clear ?? ClearType.noPlay)),
      ]),
    );
  }
}

class StatusRow extends StatelessWidget {
  const StatusRow(
      {required this.label,
      required this.value,
      required this.valueColor,
      this.extra,
      super.key});
  final String label;
  final String value;
  final String? extra;
  final Color valueColor;
  @override
  Widget build(BuildContext context) => Container(
        height: 43,
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0x6645dfff)))),
        child: Row(children: [
          const SizedBox(width: 5),
          Container(width: 4, height: 27, color: _cyan),
          const SizedBox(width: 12),
          SizedBox(
              width: 120,
              child: Text(label, style: const TextStyle(letterSpacing: 1))),
          Text(value,
              style: TextStyle(
                  fontSize: 23,
                  color: valueColor,
                  fontWeight: FontWeight.bold,
                  shadows: const [Shadow(blurRadius: 1, color: Colors.black)])),
          if (extra != null) ...[
            const SizedBox(width: 22),
            Text(extra!,
                style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 1, color: Colors.black)])),
          ],
        ]),
      );
}

class _RivalPanel extends StatelessWidget {
  const _RivalPanel({required this.chart, required this.scores});
  final Chart chart;
  final List<RivalScore> scores;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 205,
      constraints: const BoxConstraints(maxWidth: 590),
      decoration: BoxDecoration(
          color: _panel,
          border: Border.all(color: const Color(0xff06263d), width: 3),
          borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        const Padding(
            padding: EdgeInsets.all(6),
            child: Text('RIVAL SCORE DATA',
                style: TextStyle(fontSize: 18, letterSpacing: 2))),
        const Divider(height: 1, color: _cyan),
        Expanded(
            child: ListView.builder(
          itemCount: scores.length,
          itemBuilder: (context, index) {
            final item = scores[index];
            return Container(
                color: item.isMe ? const Color(0xff118fb7) : Colors.transparent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
                child: Row(children: [
                  SizedBox(
                      width: 28,
                      child: Text('${index + 1}',
                          style: TextStyle(
                              color: index < 3
                                  ? const Color(0xffffcd38)
                                  : Colors.white))),
                  SizedBox(width: 125, child: Text(item.name)),
                  SizedBox(width: 68, child: Text('${item.score}')),
                  SizedBox(
                      width: 58,
                      child: Text(djLevel(item.score / chart.maxScore * 100),
                          style: TextStyle(
                              color: rankColor(
                                  djLevel(item.score / chart.maxScore * 100)),
                              fontWeight: FontWeight.bold))),
                  SizedBox(
                      width: 75,
                      child: Text('(AAA-${(3200 - item.score).abs()})',
                          style: const TextStyle(fontSize: 12))),
                  SizedBox(
                      width: 56,
                      child: Text(item.isMe ? '±0' : '+${item.score - 2847}')),
                  Text(item.clear.label,
                      style: TextStyle(
                          color: clearColor(item.clear),
                          fontWeight: FontWeight.bold)),
                ]));
          },
        )),
      ]),
    );
  }
}

class _RadarPanel extends StatelessWidget {
  const _RadarPanel({required this.chart, required this.record});
  final Chart chart;
  final PlayRecord? record;
  @override
  Widget build(BuildContext context) {
    final ratio = record == null || chart.maxScore <= 0
        ? 0.0
        : (record!.score / chart.maxScore).clamp(0.0, 1.0).toDouble();
    return Column(children: [
      const Text('NOTES RADAR',
          style: TextStyle(
              fontSize: 25,
              letterSpacing: 2,
              shadows: [Shadow(blurRadius: 2, color: Colors.black)])),
      Expanded(
          child: CustomPaint(
              painter: RadarPainter(max: chart.maxRadar, ratio: ratio),
              child: const SizedBox.expand())),
    ]);
  }
}

class RadarPainter extends CustomPainter {
  RadarPainter({required this.max, required this.ratio});
  final RadarValues max;
  final double ratio;
  static const colors = [
    _pink,
    Color(0xff69e92c),
    Color(0xffffa125),
    Color(0xffb258ff),
    Color(0xffff4b50),
    _cyan
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .49);
    final radius = math.min(size.width, size.height) * .27;
    final text = TextPainter(
        textDirection: TextDirection.ltr, textAlign: TextAlign.center);
    final vertices = List.generate(6, (i) => _point(center, radius, i));
    final ref = Path()..addPolygon(vertices, true);
    canvas.drawPath(
        ref,
        Paint()
          ..style = PaintingStyle.fill
          ..color = const Color(0xff085365).withValues(alpha: .80));
    canvas.drawPath(
        ref,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _cyan);
    for (var r = 1; r <= 2; r++) {
      final points = List.generate(6, (i) => _point(center, radius * r / 3, i));
      canvas.drawPath(
          Path()..addPolygon(points, true),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = const Color(0xffffe493).withValues(alpha: .75));
    }
    for (final vertex in vertices)
      canvas.drawLine(center, vertex,
          Paint()..color = const Color(0xffffe493).withValues(alpha: .75));
    final values = RadarAttribute.values.map(max.by).toList();
    final dataPoints =
        List.generate(6, (i) => _point(center, radius * values[i] / 150, i));
    final strongest = max.strongest.index;
    final color = colors[strongest];
    canvas.drawPath(
        Path()..addPolygon(dataPoints, true),
        Paint()
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: .30));
    canvas.drawPath(
        Path()..addPolygon(dataPoints, true),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = color);
    for (var i = 0; i < 6; i++) {
      canvas.drawCircle(dataPoints[i], 4, Paint()..color = color);
      final labelPoint = _point(center, radius * 1.4, i);
      final label =
          '${max.isStrongest(RadarAttribute.values[i]) ? '★ ' : ''}${RadarAttribute.values[i].label}\n${(values[i] * ratio).toStringAsFixed(2)}\n(/${values[i].toStringAsFixed(2)})';
      text.text = TextSpan(
          text: label,
          style: TextStyle(
              color: colors[i],
              fontSize: 15,
              fontWeight: FontWeight.bold,
              shadows: const [Shadow(color: Colors.black, blurRadius: 1.5)]));
      text.layout(maxWidth: 130);
      text.paint(canvas, labelPoint - Offset(text.width / 2, text.height / 2));
    }
  }

  Offset _point(Offset center, double radius, int index) {
    final angle = -math.pi / 2 + index * math.pi / 3;
    return center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  }

  @override
  bool shouldRepaint(covariant RadarPainter old) =>
      old.max != max || old.ratio != ratio;
}

class _MusicSelect extends StatelessWidget {
  const _MusicSelect(
      {required this.selected,
      required this.folderOpen,
      required this.sort,
      required this.onFolder,
      required this.onSort,
      required this.onRadarList});
  final String selected;
  final bool folderOpen;
  final String sort;
  final ValueChanged<String> onFolder;
  final ValueChanged<String> onSort;
  final VoidCallback onRadarList;
  @override
  Widget build(BuildContext context) {
    const folders = [
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
      'FULL COMBO',
      'EX HARD',
      'HARD',
      'CLEAR',
      'EASY',
      'AURORA SCORE WIN',
      'AURORA SCORE LOSE'
    ];
    return Container(
      decoration: BoxDecoration(
          color: _panel,
          border: Border.all(color: _cyan, width: 2),
          borderRadius: BorderRadius.circular(7)),
      child: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 14, 8),
            child: Row(children: [
              const Expanded(
                  child: Center(
                      child: Text('MUSIC SELECT',
                          style: TextStyle(fontSize: 25, letterSpacing: 2)))),
              DropdownButton<String>(
                  value: sort,
                  dropdownColor: _navy,
                  underline: const SizedBox(),
                  items: const [
                    'デフォルト',
                    '曲名',
                    'レベル',
                    '譜面難易度',
                    'DJ LEVEL',
                    'スコア',
                    'クリアランプ',
                    'BPM',
                    '初回収録',
                    'ミスカウント'
                  ]
                      .map((value) => DropdownMenuItem(
                          value: value, child: Text('SORT：$value')))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onSort(value);
                  }),
            ])),
        const Divider(height: 2, color: _cyan),
        Expanded(
            child: ListView.builder(
                itemCount: folders.length,
                itemBuilder: (context, index) {
                  final folder = folders[index];
                  final color = folder.startsWith('LEVEL')
                      ? const Color(0xff1e8ca1)
                      : folder == 'LEGGENDARIA'
                          ? const Color(0xff7945b7)
                          : ['EPOLIS', 'PINKY CRUSH', 'SPARKLE SHOWER']
                                  .contains(folder)
                              ? const Color(0xff238ed8)
                              : [
                                  'NOTES',
                                  'CHORD',
                                  'PEAK',
                                  'CHARGE',
                                  'SCRATCH',
                                  'SOF-LAN'
                                ].contains(folder)
                                  ? const Color(0xffb1842a)
                                  : folder.startsWith('DJ')
                                      ? const Color(0xffb98922)
                                      : folder.contains('AURORA')
                                          ? const Color(0xff5b329e)
                                          : const Color(0xff08747a);
                  return InkWell(
                      onTap: () => onFolder(folder),
                      child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          color: folder == selected
                              ? const Color(0xff16a9c2)
                              : color,
                          alignment: Alignment.centerLeft,
                          child: Text(folder,
                              style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: folder == selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  shadows: const [
                                    Shadow(blurRadius: 1, color: Colors.black)
                                  ]))));
                })),
        Padding(
          padding: const EdgeInsets.all(9),
          child: OutlinedButton.icon(
            onPressed: onRadarList,
            icon: const Icon(Icons.leaderboard),
            label: const Text('NOTES RADAR LIST'),
            style: OutlinedButton.styleFrom(
                foregroundColor: _cyan, side: const BorderSide(color: _cyan)),
          ),
        ),
      ]),
    );
  }
}

class RadarListDialog extends StatefulWidget {
  const RadarListDialog({required this.repository, super.key});
  final AppRepository repository;
  @override
  State<RadarListDialog> createState() => _RadarListDialogState();
}

class _RadarListDialogState extends State<RadarListDialog> {
  PlayStyle style = PlayStyle.sp;
  RadarAttribute attribute = RadarAttribute.notes;
  @override
  Widget build(BuildContext context) {
    final items = widget.repository
        .forStyle(style)
        .where((chart) => chart.maxRadar.by(attribute) >= 135)
        .toList()
      ..sort((a, b) =>
          b.maxRadar.by(attribute).compareTo(a.maxRadar.by(attribute)));
    return Dialog(
        backgroundColor: _navy,
        insetPadding: const EdgeInsets.symmetric(horizontal: 70, vertical: 45),
        child: Container(
          decoration: BoxDecoration(
              border: Border.all(color: _cyan, width: 2),
              borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Row(children: [
              StyleSwitch(
                  value: style,
                  onChanged: (value) => setState(() => style = value)),
              const Spacer(),
              const Text('NOTES RADAR LIST',
                  style: TextStyle(fontSize: 28, letterSpacing: 2)),
              const Spacer(),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close))
            ]),
            const SizedBox(height: 18),
            Row(
              children: RadarAttribute.values.map((item) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: OutlinedButton(
                      onPressed: () => setState(() => attribute = item),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: item == attribute
                            ? radarColor(item)
                            : Colors.transparent,
                        side: BorderSide(color: radarColor(item)),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: Text(item.label,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Expanded(
                child: Container(
                    decoration: BoxDecoration(border: Border.all(color: _cyan)),
                    child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: _cyan),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 11),
                              child: Row(children: [
                                SizedBox(
                                    width: 60,
                                    child: Text('${index + 1}',
                                        style: const TextStyle(
                                            fontSize: 21,
                                            color: Color(0xffffd23a)))),
                                Expanded(
                                    flex: 3,
                                    child: Text(item.songTitle,
                                        style: const TextStyle(fontSize: 20))),
                                Expanded(
                                    child: Text(
                                        item.type == ChartType.leggendaria
                                            ? 'L'
                                            : 'A')),
                                Expanded(child: Text('${item.maxScore}')),
                                Text(
                                    item.maxRadar
                                        .by(attribute)
                                        .toStringAsFixed(2),
                                    style: TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.bold,
                                        color: radarColor(attribute)))
                              ]));
                        }))),
            const SizedBox(height: 9),
            Text('${items.length} CHARTS（MAX RADAR 135.00以上）',
                style: const TextStyle(color: _cyan)),
          ]),
        ));
  }
}

class SettingsHome extends StatelessWidget {
  const SettingsHome({required this.onOpen, required this.onBack, super.key});
  final ValueChanged<AppPage> onOpen;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(
            child: Image.asset('assets/images/blue_sky_clean.png',
                fit: BoxFit.cover)),
        Positioned.fill(
            child: const DecoratedBox(
                decoration: BoxDecoration(color: Color(0x3000144a)))),
        SafeArea(
            child: Column(children: [
          Header(title: 'IIDX PLAY DATA VIEWER', onBack: onBack),
          const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                  padding: EdgeInsets.only(left: 46),
                  child: _SettingsMenuLabel())),
          const _SettingsHeading(),
          const SizedBox(height: 18),
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            final panelHeight =
                ((constraints.maxHeight - 54) / 4).clamp(78.0, 112.0);
            return Center(
                child: SizedBox(
                    width: math.min(570, constraints.maxWidth - 76),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SettingTile(
                              height: panelHeight,
                              title: 'PLAY DATA IMPORT',
                              detail: 'IMPORT · VERSION DATA · PERSONAL BEST',
                              icon: Icons.grid_view_rounded,
                              color: _cyan,
                              onTap: () => onOpen(AppPage.playImport)),
                          const SizedBox(height: 18),
                          SettingTile(
                              height: panelHeight,
                              title: 'RIVAL DATA IMPORT',
                              detail: 'REGISTER · IMPORT · RIVAL MANAGEMENT',
                              icon: Icons.diamond_outlined,
                              color: const Color(0xffa966ff),
                              onTap: () => onOpen(AppPage.rivalImport)),
                          const SizedBox(height: 18),
                          SettingTile(
                              height: panelHeight,
                              title: 'CONFIG',
                              detail: 'BACKGROUND · DISPLAY · APP SETTINGS',
                              icon: Icons.crop_square_rounded,
                              color: const Color(0xff29d8c1),
                              onTap: () => onOpen(AppPage.config)),
                          const SizedBox(height: 18),
                          SettingTile(
                              height: panelHeight,
                              title: 'MUSIC DATA IMPORT',
                              detail: 'CHECK SERVER · DATA USAGE · DOWNLOAD',
                              icon: Icons.radio_button_unchecked_rounded,
                              color: const Color(0xffff5aa9),
                              onTap: () => onOpen(AppPage.radarImport)),
                        ])));
          })),
          const Padding(
              padding: EdgeInsets.only(bottom: 24),
              child: Text('TAP A PANEL TO OPEN ITS SETTINGS',
                  style: TextStyle(
                      color: Color(0xffb9f3ff),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.3,
                      shadows: [Shadow(blurRadius: 2, color: Colors.black)]))),
        ]))
      ]);
}

class SettingTile extends StatelessWidget {
  const SettingTile(
      {required this.height,
      required this.title,
      required this.detail,
      required this.icon,
      required this.color,
      required this.onTap,
      super.key});
  final double height;
  final String title;
  final String detail;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      height: height,
      child: Material(
          color: Colors.transparent,
          child: InkWell(
              onTap: onTap,
              child: Container(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        color.withValues(alpha: .93),
                        color.withValues(alpha: .60)
                      ]),
                      border: Border.all(
                          color: color.withValues(alpha: .95), width: 2),
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: [
                        BoxShadow(
                            color: color.withValues(alpha: .22), blurRadius: 12)
                      ]),
                  child: Stack(children: [
                    Positioned(
                        left: 30,
                        top: 14,
                        right: 68,
                        child: Container(height: 1, color: Colors.white70)),
                    Positioned(
                        left: 28,
                        top: 21,
                        bottom: 21,
                        width: 86,
                        child: Container(
                            decoration: BoxDecoration(
                                color: const Color(0xff031b36),
                                border: Border.all(color: Colors.white70),
                                borderRadius: BorderRadius.circular(10)),
                            child: Icon(icon, color: Colors.white, size: 35))),
                    Padding(
                        padding: EdgeInsets.fromLTRB(150,
                            height < 100 ? 12 : 22, 76, height < 100 ? 8 : 15),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                  width: double.infinity,
                                  height: height < 100 ? 29 : 35,
                                  child: FittedBox(
                                      alignment: Alignment.centerLeft,
                                      fit: BoxFit.scaleDown,
                                      child: Text(title,
                                          maxLines: 1,
                                          softWrap: false,
                                          style: TextStyle(
                                              fontFamily: 'Gochikakutto',
                                              fontSize: height < 100 ? 25 : 30,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 1.1,
                                              shadows: _gochikakuttoOutline)))),
                              SizedBox(height: height < 100 ? 1 : 3),
                              SizedBox(
                                  width: double.infinity,
                                  height: height < 100 ? 15 : 19,
                                  child: FittedBox(
                                      alignment: Alignment.centerLeft,
                                      fit: BoxFit.scaleDown,
                                      child: Text(detail,
                                          maxLines: 1,
                                          softWrap: false,
                                          style: TextStyle(
                                              fontFamily: 'Gochikakutto',
                                              color: Color(0xffd8f8ff),
                                              fontWeight: FontWeight.bold,
                                              fontSize: height < 100 ? 12 : 14,
                                              letterSpacing: .7,
                                              shadows: _gochikakuttoOutline))))
                            ])),
                    Positioned(
                        right: 30,
                        top: 0,
                        bottom: 0,
                        child: Center(
                            child: Icon(Icons.chevron_right_rounded,
                                color: Colors.white, size: 42)))
                  ])))));
}

class _SettingsHeading extends StatelessWidget {
  const _SettingsHeading();
  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('SETTING',
            style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w300,
                letterSpacing: 2,
                shadows: [Shadow(blurRadius: 3, color: Colors.black)])),
        const SizedBox(height: 8),
        const Text('SELECT A CATEGORY',
            style: TextStyle(
                color: _cyan,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                shadows: [Shadow(blurRadius: 2, color: Colors.black)])),
        const SizedBox(height: 17),
        Container(
            width: 320,
            height: 2,
            color: const Color(0xff8bdfff).withValues(alpha: .7))
      ]);
}

class _SettingsMenuLabel extends StatelessWidget {
  const _SettingsMenuLabel();

  @override
  Widget build(BuildContext context) => Container(
      width: 320,
      height: 62,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: const Color(0xd9052545),
          border: Border.all(color: _cyan),
          borderRadius: BorderRadius.circular(10)),
      child: const Text('SETTINGS MENU',
          style: TextStyle(
              color: Color(0xffb9f3ff),
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1)));
}

class PlayImportScreen extends StatefulWidget {
  const PlayImportScreen(
      {required this.repository, required this.onBack, super.key});
  final AppRepository repository;
  final VoidCallback onBack;
  @override
  State<PlayImportScreen> createState() => _PlayImportScreenState();
}

class _PlayImportScreenState extends State<PlayImportScreen> {
  static const _importMethodKey = 'play_data_import_paste_method';
  PlayStyle style = PlayStyle.sp;
  bool paste = false;
  String? selectedFileName;
  final controller = TextEditingController();
  final playerDjNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    playerDjNameController.text =
        _normalizeDjNameInput(widget.repository.playerDjName ?? '');
    _restoreImportMethod();
  }

  Future<void> _restoreImportMethod() async {
    final preferences = await SharedPreferences.getInstance();
    final previous = preferences.getBool(_importMethodKey);
    if (mounted && previous != null) setState(() => paste = previous);
  }

  Future<void> _setImportMethod(bool usePaste) async {
    setState(() => paste = usePaste);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_importMethodKey, usePaste);
  }

  Future<void> _savePlayerDjName() async {
    final normalized = _normalizeDjNameInput(playerDjNameController.text);
    final name =
        normalized.length > 6 ? normalized.substring(0, 6) : normalized;
    playerDjNameController.value = TextEditingValue(
        text: name, selection: TextSelection.collapsed(offset: name.length));
    widget.repository.setPlayerDjName(name);
    final preferences = await SharedPreferences.getInstance();
    final storedName = widget.repository.playerDjName;
    if (storedName == null) {
      await preferences.remove(_playerDjNameKey);
    } else {
      await preferences.setString(_playerDjNameKey, storedName);
    }
    if (mounted) {
      _message(name.isEmpty ? 'DJ NAMEを未登録にしました。' : 'DJ NAMEを保存しました。');
    }
  }

  Future<void> _chooseCsvFile() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true);
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    String? text;
    if (file.bytes != null) {
      text = utf8.decode(file.bytes!, allowMalformed: true);
    } else if (file.path != null) {
      text = await File(file.path!).readAsString();
    }
    if (text == null || text.trim().isEmpty) {
      if (mounted) _message('CSVファイルを読み込めませんでした。');
      return;
    }
    if (!mounted) return;
    setState(() {
      controller.text = text!;
      selectedFileName = file.name;
    });
  }

  @override
  void dispose() {
    controller.dispose();
    playerDjNameController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (controller.text.trim().isEmpty) {
      _message(paste ? '公式CSVテキストを貼り付けてください。' : 'CSVファイルを選択してください。');
      return;
    }
    final summary = widget.repository.importOfficialCsv(
      controller.text,
      style: style,
    );
    if (summary.errors.isNotEmpty && summary.chartCount == 0) {
      _message(summary.errors.first);
      return;
    }
    await widget.repository.savePersistedUserData();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PLAY DATA IMPORT'),
        content: Text('${style.label}データを取り込みました。\n'
            'データバージョン: ${summary.dataVersion ?? '判定できませんでした'}\n'
            '楽曲: ${summary.songCount}曲\n譜面: ${summary.chartCount}件\nスキップ: ${summary.skippedRows}行'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(context), child: const Text('完了'))
        ],
      ),
    );
  }

  Future<void> _deletePlayerData() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PLAY DATAを削除'),
        content: const Text('取り込んだ自分のプレイデータをすべて削除します。\nDJ NAMEは保持されます。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('戻る')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('削除')),
        ],
      ),
    );
    if (accepted != true) return;
    widget.repository.deletePlayerData();
    await widget.repository.savePersistedUserData();
    if (!mounted) return;
    setState(() {
      controller.clear();
      selectedFileName = null;
    });
    _message('PLAY DATAを削除しました。');
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  @override
  Widget build(BuildContext context) => ImportLayout(
      title: 'PLAY DATA',
      onBack: widget.onBack,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('PLAY DATA IMPORT',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        const Text('DJ NAME', style: TextStyle(color: _cyan)),
        const SizedBox(height: 6),
        Row(children: [
          SizedBox(
              width: 210,
              child: TextField(
                  controller: playerDjNameController,
                  maxLength: 6,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [_djNameInputFormatter],
                  style: const TextStyle(
                      fontFamily: 'Gochikakutto',
                      shadows: _gochikakuttoOutline),
                  decoration: inputDecoration().copyWith(
                      counterStyle: const TextStyle(
                          fontFamily: 'Gochikakutto',
                          shadows: _gochikakuttoOutline)))),
          const SizedBox(width: 14),
          FilledButton(
              onPressed: _savePlayerDjName,
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff167fae)),
              child: const Text('保存',
                  style: TextStyle(
                      fontFamily: 'Gochikakutto',
                      color: Colors.white,
                      shadows: _gochikakuttoOutline))),
          const SizedBox(width: 16),
          const Text('プレイデータ未登録でも、楽曲情報とノーツレーダー値を参照できます。',
              style: TextStyle(
                  fontFamily: 'Arial',
                  color: Color(0xffb9dbea),
                  fontSize: 13,
                  shadows: <Shadow>[])),
        ]),
        const SizedBox(height: 12),
        const Text('プレースタイル', style: TextStyle(color: _cyan)),
        const SizedBox(height: 6),
        SizedBox(
            width: 310,
            child: StyleSwitch(
                value: style,
                onChanged: (value) => setState(() => style = value))),
        const SizedBox(height: 12),
        const Text('CSVよりバージョンを自動判別し、歴代自己ベストスコアとして集計します。',
            style: TextStyle(
                fontFamily: 'Arial',
                color: Color(0xffb9dbea),
                fontSize: 13,
                shadows: <Shadow>[])),
        const SizedBox(height: 18),
        const Text('取込方法', style: TextStyle(color: _cyan)),
        Row(children: [
          Radio<bool>(
              value: false,
              groupValue: paste,
              onChanged: (value) => _setImportMethod(value!)),
          const Text('ファイル'),
          const SizedBox(width: 40),
          Radio<bool>(
              value: true,
              groupValue: paste,
              onChanged: (value) => _setImportMethod(value!)),
          const Text('テキスト貼付')
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: paste
              ? TextField(
                  controller: controller,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: inputDecoration(label: '公式CSVテキストをここに貼り付け'),
                )
              : Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: _chooseCsvFile,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: Text(
                          selectedFileName == null
                              ? 'CSVファイルを選択'
                              : selectedFileName!,
                          style: const TextStyle(
                              fontFamily: 'Gochikakutto',
                              shadows: _gochikakuttoOutline)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: _cyan, width: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 22),
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 15),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          OutlinedButton.icon(
              onPressed: _deletePlayerData,
              icon: const Icon(Icons.delete_outline),
              label: const Text('PLAY DATAを削除',
                  style: TextStyle(
                      fontFamily: 'Gochikakutto',
                      shadows: _gochikakuttoOutline)),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent))),
          FilledButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.file_download_done),
              label: const Text('PLAY DATA IMPORT',
                  style: TextStyle(
                      fontFamily: 'Gochikakutto',
                      color: Colors.white,
                      shadows: _gochikakuttoOutline)),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff16a9ca),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 40, vertical: 17))),
        ]),
      ]));
}

class RivalImportScreen extends StatefulWidget {
  const RivalImportScreen(
      {required this.repository, required this.onBack, super.key});
  final AppRepository repository;
  final VoidCallback onBack;
  @override
  State<RivalImportScreen> createState() => _RivalImportScreenState();
}

class _RivalImportScreenState extends State<RivalImportScreen> {
  static const _importMethodKey = 'rival_data_import_paste_method';
  late RivalProfile selected;
  PlayStyle style = PlayStyle.sp;
  bool paste = false;
  String? selectedFileName;
  final djNameController = TextEditingController();
  final csvController = TextEditingController();

  @override
  void initState() {
    super.initState();
    selected = widget.repository.rivals.first;
    _syncDjName();
    _restoreImportMethod();
  }

  @override
  void dispose() {
    djNameController.dispose();
    csvController.dispose();
    super.dispose();
  }

  void _syncDjName() =>
      djNameController.text = _normalizeDjNameInput(selected.djName ?? '');

  Future<void> _restoreImportMethod() async {
    final preferences = await SharedPreferences.getInstance();
    final previous = preferences.getBool(_importMethodKey);
    if (mounted && previous != null) setState(() => paste = previous);
  }

  Future<void> _setImportMethod(bool usePaste) async {
    setState(() => paste = usePaste);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_importMethodKey, usePaste);
  }

  /// 取込済みかどうかに関係なく、DJ NAMEだけをいつでも更新できる。
  Future<void> _saveDjName() async {
    final normalized = _normalizeDjNameInput(djNameController.text);
    final djName =
        normalized.length > 6 ? normalized.substring(0, 6) : normalized;
    if (djName.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('DJ NAMEを入力してください。')));
      return;
    }
    widget.repository.setRivalDjName(slot: selected.slot, djName: djName);
    await widget.repository.savePersistedUserData();
    if (!mounted) return;
    setState(() {
      selected = widget.repository.rivals
          .firstWhere((item) => item.slot == selected.slot);
      _syncDjName();
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('DJ NAMEを保存しました。')));
  }

  Future<void> _chooseCsvFile() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    String? text;
    if (file.bytes != null) {
      text = utf8.decode(file.bytes!, allowMalformed: true);
    } else if (file.path != null) {
      text = await File(file.path!).readAsString();
    }
    if (text == null || text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('CSVファイルを読み込めませんでした。')));
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      csvController.text = text!;
      selectedFileName = file.name;
    });
  }

  Future<void> _import() async {
    final normalized = _normalizeDjNameInput(djNameController.text);
    final djName =
        normalized.length > 6 ? normalized.substring(0, 6) : normalized;
    djNameController.value = TextEditingValue(
        text: djName,
        selection: TextSelection.collapsed(offset: djName.length));
    if (djName.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('DJ NAMEを入力してください。')));
      return;
    }
    if (csvController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(paste ? 'ライバルのCSVテキストを貼り付けてください。' : 'CSVファイルを選択してください。')));
      return;
    }
    final incomingVersion =
        widget.repository.detectCsvDataVersion(csvController.text);
    final registeredVersion =
        widget.repository.rivalDataVersion(selected.slot, style);
    if (incomingVersion != null &&
        registeredVersion != null &&
        widget.repository.isOlderVersion(incomingVersion, registeredVersion)) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('古いバージョンのCSVです'),
          content: Text('現在登録されている${style.label}データは $registeredVersion です。\n'
              '$incomingVersion を取り込むと、ライバルの${style.label}データは古い内容で置き換えられます。\n\n取り込みますか？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('戻る')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('取り込む')),
          ],
        ),
      );
      if (accepted != true) return;
    }
    final summary = widget.repository.importRivalOfficialCsv(csvController.text,
        slot: selected.slot, style: style);
    if (summary.errors.isNotEmpty && summary.chartCount == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(summary.errors.first)));
      return;
    }
    widget.repository
        .registerRival(slot: selected.slot, djName: djName, style: style);
    await widget.repository.savePersistedUserData();
    if (!mounted) return;
    setState(() {
      selected = widget.repository.rivals
          .firstWhere((item) => item.slot == selected.slot);
      _syncDjName();
    });
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('RIVAL DATA IMPORT'),
                content: Text('${selected.label}の${style.label}データを取り込みました。\n'
                    'データバージョン: ${summary.dataVersion ?? '判定できませんでした'}\n'
                    '楽曲: ${summary.songCount}曲 / 譜面: ${summary.chartCount}件'),
                actions: [
                  FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('完了'))
                ]));
  }

  Future<void> _deleteSelectedRival() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('RIVAL DATA DELETE'),
        content: Text('${selected.label}の登録データを削除しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('戻る')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('削除')),
        ],
      ),
    );
    if (accepted != true) return;
    widget.repository.deleteRival(selected.slot);
    await widget.repository.savePersistedUserData();
    if (!mounted) return;
    setState(() {
      selected = widget.repository.rivals
          .firstWhere((item) => item.slot == selected.slot);
      _syncDjName();
      selectedFileName = null;
      csvController.clear();
    });
  }

  @override
  Widget build(BuildContext context) => ImportLayout(
      title: 'RIVAL DATA',
      onBack: widget.onBack,
      child: SizedBox(
          height: 500,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('RIVAL DATA IMPORT',
                style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            const Text('プレースタイル', style: TextStyle(color: _cyan)),
            const SizedBox(height: 6),
            SizedBox(
                width: 310,
                child: StyleSwitch(
                    value: style,
                    onChanged: (value) => setState(() => style = value))),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: 300,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('RIVAL', style: TextStyle(color: _cyan)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<RivalProfile>(
                            value: selected,
                            dropdownColor: _navy,
                            decoration: inputDecoration(),
                            items: widget.repository.rivals
                                .map((item) => DropdownMenuItem(
                                    value: item, child: Text(item.label)))
                                .toList(),
                            onChanged: (value) => setState(() {
                                  selected = value!;
                                  _syncDjName();
                                  selectedFileName = null;
                                  csvController.clear();
                                })),
                      ])),
              const SizedBox(width: 22),
              SizedBox(
                  width: 210,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('DJ NAME', style: TextStyle(color: _cyan)),
                        const SizedBox(height: 6),
                        TextField(
                            controller: djNameController,
                            maxLength: 6,
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [_djNameInputFormatter],
                            style: const TextStyle(
                                fontFamily: 'Gochikakutto',
                                shadows: _gochikakuttoOutline),
                            decoration: inputDecoration().copyWith(
                                counterStyle: const TextStyle(
                                    fontFamily: 'Gochikakutto',
                                    shadows: _gochikakuttoOutline))),
                      ])),
              const SizedBox(width: 12),
              Padding(
                  padding: const EdgeInsets.only(top: 30),
                  child: FilledButton(
                      onPressed: _saveDjName,
                      style:
                          FilledButton.styleFrom(foregroundColor: Colors.white),
                      child: const Text('保存',
                          style: TextStyle(
                              fontFamily: 'Gochikakutto',
                              color: Colors.white,
                              shadows: _gochikakuttoOutline)))),
            ]),
            const SizedBox(height: 6),
            const Text('取込方法', style: TextStyle(color: _cyan)),
            Row(children: [
              Radio<bool>(
                  value: false,
                  groupValue: paste,
                  onChanged: (value) => _setImportMethod(value!)),
              const Text('ファイル'),
              const SizedBox(width: 40),
              Radio<bool>(
                  value: true,
                  groupValue: paste,
                  onChanged: (value) => _setImportMethod(value!)),
              const Text('テキスト貼付')
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 135,
              child: paste
                  ? TextField(
                      controller: csvController,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: inputDecoration(label: 'ライバルのCSVデータをここに貼り付け'),
                    )
                  : Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton.icon(
                          onPressed: _chooseCsvFile,
                          icon: const Icon(Icons.folder_open_rounded),
                          label: Text(
                              selectedFileName == null
                                  ? 'CSVファイルを選択'
                                  : selectedFileName!,
                              style: const TextStyle(
                                  fontFamily: 'Gochikakutto',
                                  shadows: _gochikakuttoOutline)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: _cyan, width: 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 32, vertical: 22),
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              if (selected.isImported) ...[
                OutlinedButton.icon(
                    onPressed: _deleteSelectedRival,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('RIVAL DATAを削除',
                        style: TextStyle(
                            fontFamily: 'Gochikakutto',
                            shadows: _gochikakuttoOutline)),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 15))),
              ],
              FilledButton.icon(
                  onPressed: _import,
                  icon: const Icon(Icons.file_download_done),
                  label: const Text('RIVAL DATA IMPORT',
                      style: TextStyle(
                          fontFamily: 'Gochikakutto',
                          color: Colors.white,
                          shadows: _gochikakuttoOutline)),
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xff8d54ca),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 15))),
            ]),
          ])));
}

class ImportLayout extends StatelessWidget {
  const ImportLayout(
      {required this.title,
      required this.onBack,
      required this.child,
      super.key});
  final String title;
  final VoidCallback onBack;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(children: [
        Header(title: title, onBack: onBack),
        Expanded(
            child: Center(
                child: Container(
                    width: 970,
                    margin: const EdgeInsets.only(bottom: 30),
                    padding: const EdgeInsets.fromLTRB(42, 30, 42, 22),
                    decoration: BoxDecoration(
                        color: _panel,
                        border: Border.all(color: _cyan, width: 2),
                        borderRadius: BorderRadius.circular(16)),
                    child: child)))
      ]);
}

class ConfigScreen extends StatefulWidget {
  const ConfigScreen(
      {required this.visibleFolderGroups,
      required this.onSaved,
      required this.onBack,
      super.key});
  final Set<String> visibleFolderGroups;
  final ValueChanged<Set<String>> onSaved;
  final VoidCallback onBack;
  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  late final Map<String, bool> groups;
  final _backgroundThemeScrollController = ScrollController();
  bool _folderListDirty = false;

  @override
  void initState() {
    super.initState();
    groups = {
      for (final group in _musicSelectFolderGroups)
        group: widget.visibleFolderGroups.contains(group)
    };
  }

  Future<void> _saveMusicSelectFolders() async {
    final preferences = await SharedPreferences.getInstance();
    final enabledFolders = groups.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
    await preferences.setStringList(_musicSelectFoldersKey, enabledFolders);
    if (!mounted) return;
    widget.onSaved(enabledFolders.toSet());
    setState(() => _folderListDirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MUSIC SELECT LISTの設定を保存しました。')));
  }

  void _scrollBackgroundThemes(PointerScrollEvent event) {
    if (!_backgroundThemeScrollController.hasClients) return;
    final position = _backgroundThemeScrollController.position;
    final target = (position.pixels + event.scrollDelta.dy)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _backgroundThemeScrollController.jumpTo(target);
  }

  @override
  void dispose() {
    _backgroundThemeScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Header(title: 'CONFIG', onBack: widget.onBack),
        Expanded(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(110, 30, 110, 35),
                child: Row(children: [
                  Expanded(
                      child: _ConfigCard(
                          title: 'BACKGROUND THEME',
                          child: Column(children: [
                            Expanded(
                                child: Listener(
                                    onPointerSignal: (event) {
                                      if (event is PointerScrollEvent) {
                                        GestureBinding
                                            .instance.pointerSignalResolver
                                            .register(event, (signal) {
                                          if (signal is PointerScrollEvent) {
                                            _scrollBackgroundThemes(signal);
                                          }
                                        });
                                      }
                                    },
                                    child: Scrollbar(
                                        controller:
                                            _backgroundThemeScrollController,
                                        thumbVisibility: true,
                                        child: ListView.separated(
                                            controller:
                                                _backgroundThemeScrollController,
                                            itemCount: 3,
                                            separatorBuilder: (_, __) =>
                                                const SizedBox(height: 14),
                                            itemBuilder: (context, index) =>
                                                AspectRatio(
                                                    aspectRatio: 16 / 9,
                                                    child: _ThemeCard(
                                                        label: index == 0
                                                            ? 'BLUE SKY'
                                                            : 'COMING SOON',
                                                        selected:
                                                            index == 0)))))),
                            const SizedBox(height: 15),
                            const Text('アプリの背景テーマを選択します。',
                                style: TextStyle(
                                    fontFamily: 'Arial',
                                    color: Color(0xffcef2ff),
                                    shadows: <Shadow>[])),
                            const SizedBox(height: 12),
                            OutlinedButton(
                                onPressed: () {},
                                child: const Text('背景を変更',
                                    style: TextStyle(
                                        fontFamily: 'Gochikakutto',
                                        shadows: _gochikakuttoOutline)))
                          ]))),
                  const SizedBox(width: 30),
                  Expanded(
                      flex: 2,
                      child: _ConfigCard(
                          title: 'MUSIC SELECT LIST',
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('MUSIC SELECTに表示するフォルダを選択します。',
                                    style: TextStyle(
                                        fontFamily: 'Arial',
                                        color: Color(0xffcef2ff),
                                        shadows: <Shadow>[])),
                                const SizedBox(height: 14),
                                Expanded(
                                    child: GridView.count(
                                        crossAxisCount: 2,
                                        childAspectRatio: 4.4,
                                        mainAxisSpacing: 10,
                                        crossAxisSpacing: 28,
                                        children: groups.entries
                                            .map((item) => Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 14),
                                                decoration: BoxDecoration(
                                                    color:
                                                        const Color(0xff06405c),
                                                    border: Border.all(
                                                        color: _cyan)),
                                                child: Row(children: [
                                                  Expanded(
                                                      child: Text(item.key,
                                                          style: const TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold))),
                                                  Switch(
                                                      value: item.value,
                                                      onChanged: (value) {
                                                        if (!value &&
                                                            groups.values
                                                                    .where(
                                                                        (v) =>
                                                                            v)
                                                                    .length ==
                                                                1) {
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                                  const SnackBar(
                                                                      content: Text(
                                                                          '最低1つのフォルダはONにしてください。')));
                                                          return;
                                                        }
                                                        setState(() {
                                                          groups[item.key] =
                                                              value;
                                                          _folderListDirty =
                                                              true;
                                                        });
                                                      })
                                                ])))
                                            .toList())),
                                Row(children: [
                                  const Expanded(
                                      child: Text('最低1つのフォルダをONにしてください。',
                                          style: TextStyle(
                                              fontFamily: 'Arial',
                                              color: Color(0xffffce4d),
                                              fontWeight: FontWeight.bold,
                                              shadows: <Shadow>[]))),
                                  FilledButton(
                                      onPressed: _folderListDirty
                                          ? _saveMusicSelectFolders
                                          : null,
                                      style: FilledButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          disabledForegroundColor:
                                              Colors.white),
                                      child: const Text('保存',
                                          style: TextStyle(
                                              fontFamily: 'Gochikakutto',
                                              color: Colors.white,
                                              shadows: _gochikakuttoOutline)))
                                ])
                              ]))),
                ])))
      ]);
}

class _ConfigCard extends StatelessWidget {
  const _ConfigCard({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: _panel,
          border: Border.all(color: _cyan),
          borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const Divider(color: _cyan),
        Expanded(child: child)
      ]));
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.label, required this.selected});
  final String label;
  final bool selected;
  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
          image: label == 'BLUE SKY'
              ? const DecorationImage(
                  image: AssetImage('assets/images/blue_sky_clean.png'),
                  fit: BoxFit.cover)
              : null,
          gradient: label == 'BLUE SKY'
              ? null
              : const LinearGradient(
                  colors: [Color(0xff304a75), Color(0xff91a7d0)]),
          border: Border.all(
              color: selected ? _cyan : Colors.white54,
              width: selected ? 3 : 1),
          borderRadius: BorderRadius.circular(10)),
      alignment: Alignment.center,
      child: Text(label,
          style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(blurRadius: 1, color: Colors.black)])));
}

class RadarImportScreen extends StatelessWidget {
  const RadarImportScreen({required this.onBack, super.key});
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => Column(children: [
        Header(title: 'NOTES RADAR IMPORT', onBack: onBack),
        Expanded(
            child: Center(
                child: Container(
                    width: 860,
                    padding: const EdgeInsets.all(38),
                    decoration: BoxDecoration(
                        color: _panel,
                        border: Border.all(color: _cyan, width: 2),
                        borderRadius: BorderRadius.circular(16)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_download_outlined,
                              size: 58, color: _cyan),
                          const SizedBox(height: 20),
                          const Text('ノーツレーダーマスターを確認',
                              style: TextStyle(
                                  fontFamily: 'Arial',
                                  fontSize: 27,
                                  fontWeight: FontWeight.bold,
                                  shadows: <Shadow>[])),
                          const SizedBox(height: 10),
                          const Text(
                              'Cloudflare R2上のmanifest.jsonを確認し、更新日・通信量・更新内容を表示してからダウンロードします。',
                              style: TextStyle(
                                  fontFamily: 'Arial', shadows: <Shadow>[])),
                          const SizedBox(height: 28),
                          Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                  color: const Color(0xff063553),
                                  border: Border.all(color: _cyan)),
                              child: const Row(children: [
                                Expanded(
                                    child: _ManifestDetail(
                                        label: '現在のバージョン', value: '未取得')),
                                Expanded(
                                    child: _ManifestDetail(
                                        label: '更新後', value: '2026.07.26')),
                                Expanded(
                                    child: _ManifestDetail(
                                        label: '通信量（予定）', value: '1.24 MB')),
                                Expanded(
                                    child: _ManifestDetail(
                                        label: '検証', value: 'SHA-256'))
                              ])),
                          const SizedBox(height: 30),
                          Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                  onPressed: () => showDialog<void>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                              title: const Text('ダウンロード確認'),
                                              content: const Text(
                                                  '1.24 MBのノーツレーダーマスターを取得します。\n通信を開始しますか？'),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(context),
                                                    child: const Text('キャンセル')),
                                                FilledButton(
                                                    onPressed: () {
                                                      Navigator.pop(context);
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                              const SnackBar(
                                                                  content: Text(
                                                                      'サーバーURL確定後にダウンロードを開始します。')));
                                                    },
                                                    child: const Text('ダウンロード'))
                                              ])),
                                  icon: const Icon(Icons.download),
                                  label: const Text('CHECK & IMPORT',
                                      style: TextStyle(
                                          fontFamily: 'Gochikakutto',
                                          color: Colors.black)),
                                  style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xffffa526),
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 33, vertical: 17))))
                        ]))))
      ]);
}

class _ManifestDetail extends StatelessWidget {
  const _ManifestDetail({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontFamily: 'Arial',
                color: _cyan,
                fontSize: 13,
                shadows: <Shadow>[])),
        const SizedBox(height: 5),
        Text(value,
            style: const TextStyle(
                fontFamily: 'Arial',
                fontWeight: FontWeight.bold,
                fontSize: 17,
                shadows: <Shadow>[]))
      ]);
}

InputDecoration inputDecoration({String? label}) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: _cyan),
    filled: true,
    fillColor: const Color(0xff042640),
    border: OutlineInputBorder(
        borderSide: const BorderSide(color: _cyan),
        borderRadius: BorderRadius.circular(7)),
    enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: _cyan),
        borderRadius: BorderRadius.circular(7)));

String djLevel(double percent) => percent >= 100
    ? 'MAX'
    : percent >= 88.89
        ? 'AAA'
        : percent >= 77.78
            ? 'AA'
            : percent >= 66.67
                ? 'A'
                : percent >= 55.56
                    ? 'B'
                    : percent >= 44.45
                        ? 'C'
                        : 'F';
Color rankColor(String value) => value == 'MAX' || value == 'AAA'
    ? const Color(0xffffd33d)
    : value == 'AA'
        ? const Color(0xffe1e6ee)
        : value == 'A'
            ? const Color(0xffdd9b4b)
            : Colors.white;
Color clearColor(ClearType value) => switch (value) {
      ClearType.fullCombo => const Color(0xffb7f8ff),
      ClearType.exHard => const Color(0xffffa229),
      ClearType.hard => const Color(0xffff4a52),
      ClearType.clear => const Color(0xff45dfff),
      ClearType.easy => const Color(0xff61df82),
      ClearType.assistEasy => const Color(0xffbe68ff),
      ClearType.failed => const Color(0xff951e2d),
      ClearType.noPlay => Colors.grey
    };
Color radarColor(RadarAttribute value) => switch (value) {
      RadarAttribute.notes => _pink,
      RadarAttribute.chord => const Color(0xff69e92c),
      RadarAttribute.peak => const Color(0xffffa125),
      RadarAttribute.charge => const Color(0xffb258ff),
      RadarAttribute.scratch => const Color(0xffff4b50),
      RadarAttribute.sofLan => _cyan
    };
ClearType parseClear(String value) =>
    ClearType.values.firstWhere((item) => item.label == value.toUpperCase(),
        orElse: () => ClearType.noPlay);
