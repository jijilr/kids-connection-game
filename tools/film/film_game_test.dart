// The film "How the game is played".
//
// The game on screen is the game itself: its own screen, in its own theme, with the real
// things, pictures, clues and explanations, played through Flutter's gesture system by
// taps a finger would make, and saved frame by frame at 30 a second. Nothing of the game
// is redrawn. Around it the film draws: a tablet's frame, a soft dot where the finger is,
// the narrator's line, and the words of what the game is saying (for a viewer with the
// sound off). The map near the end is docs/game_map.png, made in Blender from the game's
// own data.
//
// The sound is not made here. This writes events.json beside the frames: on which frame
// the narrator starts each line, and on which frame the game itself plays which clip.
// The game's sound service runs for real, against a player that plays nothing but takes
// as long over each clip as the clip is, so a clip waits for the one before it exactly
// as it does on a device. tools/film/film_make.py lays the sound under the frames.
//
//   python tools/film/film_voice.py
//   flutter test tools/film/film_game_test.dart
//   python tools/film/film_make.py
//
//   --dart-define=SCOUT=30    print the boards seeds 1 to 30 would deal, and film nothing
//   --dart-define=SEED=7      the deal to film
//   --dart-define=EVERY=6 --dart-define=WIDTH=960     a quick look: one frame in six, half size
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
// The two plugin interfaces are the game's dependencies' own; the film only puts
// stand-ins in their place (see _FilmPlayers and _FilmPaths).
// ignore: depend_on_referenced_packages
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:connections_game/main.dart';
import 'package:connections_game/models/dimension.dart';
import 'package:connections_game/models/entity.dart';
import 'package:connections_game/models/game_settings.dart';
import 'package:connections_game/models/group_words.dart';
import 'package:connections_game/providers/engine_provider.dart';
import 'package:connections_game/screens/engine_screen.dart';
import 'package:connections_game/services/board_assembler.dart';
import 'package:connections_game/services/content_repository.dart';
import 'package:connections_game/services/media.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

const _seed = int.fromEnvironment('SEED', defaultValue: 1);
const _scout = int.fromEnvironment('SCOUT');
const _every = int.fromEnvironment('EVERY', defaultValue: 1);
const _width = int.fromEnvironment('WIDTH', defaultValue: 1920);
const _out = 'tools/film/out';

const _fps = 30;
const _frame = Duration(microseconds: 1000000 ~/ _fps);

/// The film's frame in the game's own units, 16 by 9. The tablet's screen is 600 by 960
/// of them, as a small tablet held upright is.
const _stage = Size(1840, 1035);
const _device = Size(600, 960);
const _bezel = 16.0;
final _pixelRatio = _width / _stage.width;

const _paper = Color(0xFFF0E7D4); // the ground of the map, so the map lies on the film's own page
const _ink = Color(0xFF2D3436);
const _soft = Color(0xFF6B7378);
const _purple = Color(0xFF6C5CE7);
const _emoji = 'Segoe UI Emoji';

final _clock = Stopwatch()..start();
// ignore: avoid_print
void _log(String m) => print('[${(_clock.elapsedMilliseconds / 1000).toStringAsFixed(1)}s] $m');

Map<String, dynamic> _read(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

// ---------------------------------------------------------------------------
// The game's content, as shipped.

late final List<Entity> _entities;
late final DimensionRegistry _registry;
late final GroupWordsBook _words;
late final Set<String> _assets;
late final ThemeData _theme;

ContentRepository _repo(int seed) => ContentRepository.fromData(
      _entities,
      _registry,
      GameSettings.fromJson(_read('Assets/data/settings.json')),
      random: Random(seed),
      media: MediaResolver.fromJson(_assets, _read('Assets/data/pictures.json')),
      words: _words,
    );

// ---------------------------------------------------------------------------
// Stand-ins for two plugins a test has no device for.

/// What the game is saying now, for the words shown beside the tablet.
class _Speech {
  const _Speech(this.kind, this.text);
  final String kind;
  final String text;
}

final _speech = ValueNotifier<_Speech?>(null);

/// The audio plugin. It plays nothing; it takes as long over a clip as the clip is, and
/// then reports it complete, so the game's own queue of sounds runs as on a device. Each
/// clip it is asked for is written down with the frame it started on.
class _FilmPlayers extends AudioplayersPlatformInterface {
  final _events = <String, StreamController<AudioEvent>>{};
  final _source = <String, String>{};
  final _ending = <String, Timer>{};
  final Map<String, dynamic> clips = _read('$_out/game_audio.json');

  /// Called with the clip's path as it starts.
  void Function(String asset, double seconds)? onStart;

  bool get playing => _ending.isNotEmpty;

  /// What kind of clip the game is playing now: name, clue 1, explanation, feedback.
  String? saying;

  StreamController<AudioEvent> _channel(String id) =>
      _events.putIfAbsent(id, () => StreamController<AudioEvent>.broadcast());

  @override
  Stream<AudioEvent> getEventStream(String playerId) => _channel(playerId).stream;

  @override
  Future<void> setSourceUrl(String playerId, String url, {bool? isLocal, String? mimeType}) async {
    _source[playerId] = Uri.decodeFull(url);
    scheduleMicrotask(() =>
        _channel(playerId).add(const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true)));
  }

  @override
  Future<void> resume(String playerId) async {
    final asset = _source[playerId]!;
    final clip = clips[asset] as Map<String, dynamic>?;
    if (clip == null) throw StateError('no such clip in the game: $asset');
    final seconds = (clip['seconds'] as num).toDouble();
    onStart?.call(asset, seconds);
    final text = clip['text'] as String;
    saying = clip['kind'] as String;
    if (text.isNotEmpty) _speech.value = _Speech(clip['kind'] as String, text);
    _ending[playerId]?.cancel();
    _ending[playerId] = Timer(Duration(milliseconds: (seconds * 1000).round()), () {
      _ending.remove(playerId);
      saying = null;
      _channel(playerId).add(const AudioEvent(eventType: AudioEventType.complete));
      // the words stay a moment after the voice, then go, unless another clip has begun
      final shown = _speech.value;
      Timer(const Duration(milliseconds: 450), () {
        if (identical(_speech.value, shown) && !playing) _speech.value = null;
      });
    });
  }

  @override
  Future<void> stop(String playerId) async => _ending.remove(playerId)?.cancel();
  @override
  Future<void> pause(String playerId) async => _ending.remove(playerId)?.cancel();
  @override
  Future<void> release(String playerId) async => _ending.remove(playerId)?.cancel();
  @override
  Future<void> dispose(String playerId) async {
    _ending.remove(playerId)?.cancel();
    await _events.remove(playerId)?.close();
  }

  @override
  Future<int?> getDuration(String playerId) async => null;
  @override
  Future<int?> getCurrentPosition(String playerId) async => 0;
  @override
  Future<void> create(String playerId) async {}
  @override
  Future<void> seek(String playerId, Duration position) async {}
  @override
  Future<void> setBalance(String playerId, double balance) async {}
  @override
  Future<void> setVolume(String playerId, double volume) async {}
  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async {}
  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async {}
  @override
  Future<void> setSourceBytes(String playerId, Uint8List bytes, {String? mimeType}) async {}
  @override
  Future<void> setAudioContext(String playerId, AudioContext audioContext) async {}
  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async {}
  @override
  Future<void> emitLog(String playerId, String message) async {}
  @override
  Future<void> emitError(String playerId, String code, String message) async {}
}

class _FilmGlobalAudio implements GlobalAudioplayersPlatformInterface {
  @override
  Future<void> init() async {}
  @override
  Future<void> setGlobalAudioContext(AudioContext ctx) async {}
  @override
  Future<void> emitGlobalLog(String message) async {}
  @override
  Future<void> emitGlobalError(String code, String message) async {}
  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => const Stream.empty();
}

/// The game asks for a clip by its place among the game's files. On a device the plugin
/// copies it out of the bundle first; here the place itself is enough.
class _FilmCache extends AudioCache {
  _FilmCache() : super(prefix: '');
  @override
  Future<Uri> load(String fileName) async => Uri.parse(Uri.encodeFull(fileName));
}

/// Where the game's font package keeps the fonts it has fetched, as it does on a device.
class _FilmPaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => Directory('$_out/fonts').absolute.path;
  @override
  Future<String?> getApplicationDocumentsPath() async => Directory('$_out/fonts').absolute.path;
  @override
  Future<String?> getApplicationCachePath() async => Directory('$_out/fonts').absolute.path;
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

/// The game's two fonts are fetched by its own font package, as they are every time the
/// game runs; the icon font and an emoji font come from this machine.
Future<void> _loadFonts() async {
  Directory('$_out/fonts').createSync(recursive: true);
  for (final weight in const [FontWeight.w400, FontWeight.w500, FontWeight.w600, FontWeight.w700, FontWeight.w800]) {
    GoogleFonts.quicksand(fontWeight: weight);
    GoogleFonts.inter(fontWeight: weight);
  }
  _theme = appTheme();
  await GoogleFonts.pendingFonts().timeout(const Duration(seconds: 90));

  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter';
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(icons.readAsBytes().then(ByteData.sublistView))).load();
  } else {
    _log('no icon font at ${icons.path}: icons will be boxes');
  }
  final emoji = File('C:/Windows/Fonts/seguiemj.ttf');
  if (emoji.existsSync()) {
    await (FontLoader(_emoji)..addFont(emoji.readAsBytes().then(ByteData.sublistView))).load();
  } else {
    _log('no emoji font at ${emoji.path}: the stars will be boxes');
  }
  _log('fonts loaded');
}

Future<void> _preload(WidgetTester tester, Iterable<ImageProvider> images) async {
  await tester.runAsync(() async {
    for (final provider in images) {
      final done = Completer<void>();
      provider.resolve(ImageConfiguration(bundle: rootBundle, devicePixelRatio: _pixelRatio)).addListener(
            ImageStreamListener(
              (_, __) => done.isCompleted ? null : done.complete(),
              onError: (e, _) {
                _log('picture failed: $e');
                if (!done.isCompleted) done.complete();
              },
            ),
          );
      await done.future.timeout(const Duration(seconds: 30));
    }
  });
}

// ---------------------------------------------------------------------------
// What the film draws around the game.

class _Caption {
  const _Caption(this.label, this.text);
  final String label;
  final String text;
}

class _Touch {
  const _Touch(this.at, this.strength);
  final Offset at;
  final double strength;
}

/// Where the map is looked at: the point of the picture in the middle of the panel, how
/// far in (1 is the whole map), and the circles ringed, each with how strongly.
class _MapView {
  const _MapView(this.x, this.y, this.zoom, [this.rings = const {}]);
  final double x, y, zoom;
  final Map<String, double> rings;

  static _MapView lerp(_MapView a, _MapView b, double t) => _MapView(
        ui.lerpDouble(a.x, b.x, t)!,
        ui.lerpDouble(a.y, b.y, t)!,
        ui.lerpDouble(a.zoom, b.zoom, t)!,
        {
          for (final id in {...a.rings.keys, ...b.rings.keys})
            id: ui.lerpDouble(a.rings[id] ?? 0, b.rings[id] ?? 0, t)!,
        },
      );
}

final _scene = ValueNotifier<String>('title'); // title, game, map, end
final _caption = ValueNotifier<_Caption?>(null);
final _touch = ValueNotifier<_Touch?>(null);
final _dissolve = ValueNotifier<(ui.Image, double)?>(null);
final _mapView = ValueNotifier<_MapView>(const _MapView(1300, 1265, 1));

class _TouchPainter extends CustomPainter {
  _TouchPainter(this.touch);
  final _Touch touch;

  @override
  void paint(Canvas canvas, Size size) {
    final s = touch.strength;
    final r = 22.0 + 4 * s;
    canvas.drawCircle(touch.at, r + 2, Paint()..color = Colors.black.withValues(alpha: 0.12 * s));
    canvas.drawCircle(touch.at, r, Paint()..color = Colors.white.withValues(alpha: 0.42 * s));
    canvas.drawCircle(
      touch.at,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.95 * s),
    );
  }

  @override
  bool shouldRepaint(_TouchPainter old) => old.touch != touch;
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.rings);
  final List<(Offset, double, double)> rings; // middle, radius, strength

  @override
  void paint(Canvas canvas, Size size) {
    for (final (at, radius, strength) in rings) {
      if (strength <= 0) continue;
      canvas.drawCircle(
        at,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
          ..color = _purple.withValues(alpha: 0.35 * strength),
      );
      canvas.drawCircle(
        at,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = _ink.withValues(alpha: 0.9 * strength),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => true;
}

TextStyle _label() =>
    GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: 3.4, color: _purple, height: 1.2);

/// The whole frame: the tablet with the game in it on the left, the words on the right;
/// or the map; with the opening and closing cards over them.
class _Stage extends StatelessWidget {
  const _Stage({required this.engine, required this.map, required this.facts, required this.faces});
  final EngineProvider engine;
  final Map<String, dynamic> map; // tools/illustration/game_map_points.json
  final Map<String, dynamic> facts; // tools/illustration/game_map.json
  final List<String> faces;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const ValueKey('capture'),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder<String>(
          valueListenable: _scene,
          builder: (context, scene, _) => Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: _paper)),
              _shown(scene == 'map', Positioned(left: 60, top: 22, width: 990, height: 990, child: _mapPanel())),
              _shown(
                scene == 'game',
                Positioned(left: 170, top: (_stage.height - _device.height - 2 * _bezel) / 2, child: _tablet()),
              ),
              _shown(scene == 'game' || scene == 'map', _words(scene == 'map' ? 1110 : 900)),
              _shown(scene == 'title', Positioned.fill(child: _titleCard())),
              _shown(scene == 'end', Positioned.fill(child: _endCard())),
              Positioned.fill(
                child: IgnorePointer(
                  child: ValueListenableBuilder<(ui.Image, double)?>(
                    valueListenable: _dissolve,
                    builder: (_, d, __) => d == null
                        ? const SizedBox.shrink()
                        : Opacity(opacity: d.$2, child: RawImage(image: d.$1, fit: BoxFit.fill)),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: ValueListenableBuilder<_Touch?>(
                    valueListenable: _touch,
                    builder: (_, t, __) =>
                        t == null ? const SizedBox.expand() : CustomPaint(painter: _TouchPainter(t)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A part of the frame that fades in and out with its scene. It stays in the tree while
  /// hidden: the game must go on living behind the cards.
  Widget _shown(bool visible, Widget positioned) {
    final p = positioned as Positioned;
    return Positioned(
      left: p.left,
      top: p.top,
      right: p.right,
      bottom: p.bottom,
      width: p.width,
      height: p.height,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 550),
          curve: Curves.easeInOut,
          child: p.child,
        ),
      ),
    );
  }

  Widget _tablet() {
    return Container(
      padding: const EdgeInsets.all(_bezel),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2426),
        borderRadius: BorderRadius.circular(46),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 44, offset: const Offset(0, 20)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(31),
        child: SizedBox.fromSize(
          size: _device,
          // The game, as lib/main.dart starts it: the same theme, the same wrapper, the same
          // screen. Only its content is dealt from a fixed seed, so the film can be made again.
          child: ChangeNotifierProvider<EngineProvider>.value(
            value: engine,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: _theme.copyWith(
                // a device shows the stars of the last card with its own emoji; so must the film
                textTheme: _theme.textTheme.apply(fontFamilyFallback: const [_emoji]),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(size: _device),
                child: child!,
              ),
              home: const ResponsiveWrapper(child: EngineScreen()),
            ),
          ),
        ),
      ),
    );
  }

  /// The narrator's line, and under it what the game itself is saying.
  Positioned _words(double left) {
    final width = _stage.width - left - 90;
    return Positioned(
      left: left,
      top: 0,
      width: width,
      height: _stage.height,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: _stage.height - 500,
            child: ValueListenableBuilder<_Caption?>(
              valueListenable: _caption,
              builder: (_, c, __) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 560),
                switchInCurve: const Interval(0.5, 1, curve: Curves.easeOut),
                switchOutCurve: const Interval(0.5, 1, curve: Curves.easeIn),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.bottomLeft,
                  children: [...previous, if (current != null) current],
                ),
                child: c == null
                    ? const SizedBox(key: ValueKey('no caption'), width: double.infinity)
                    : Column(
                        key: ValueKey(c.text),
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (c.label.isNotEmpty) Text(c.label.toUpperCase(), style: _label()),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: Text(
                              c.text,
                              style: GoogleFonts.quicksand(
                                  fontSize: 54, fontWeight: FontWeight.w700, height: 1.2, color: _ink),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 30,
            top: 552,
            child: ValueListenableBuilder<_Speech?>(
              valueListenable: _speech,
              builder: (_, s, __) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topLeft,
                  children: [...previous, if (current != null) current],
                ),
                child: s == null ? const SizedBox(key: ValueKey('silent'), width: double.infinity) : _says(s),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _says(_Speech s) {
    final what = switch (s.kind) {
      'name' => 'a name',
      'explanation' => 'why they belong',
      'feedback' => '',
      _ => s.kind.startsWith('clue') ? 'a clue' : '',
    };
    return Container(
      key: ValueKey(s.text),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 22, 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _purple.withValues(alpha: 0.22), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.volume_up_rounded, color: _purple, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  what.isEmpty ? 'THE GAME SAYS' : 'THE GAME SAYS  ·  ${what.toUpperCase()}',
                  style: GoogleFonts.inter(
                      fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 2.4, color: _soft),
                ),
                const SizedBox(height: 7),
                Text(
                  '\u201C${s.text}\u201D',
                  style: GoogleFonts.inter(
                      fontSize: s.text.length > 60 ? 26 : 32,
                      fontWeight: FontWeight.w500,
                      height: 1.36,
                      color: _ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapPanel() {
    final image = (map['image'] as List).cast<num>();
    final w = image[0].toDouble(), h = image[1].toDouble();
    final points = (map['points'] as Map).cast<String, dynamic>();
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: LayoutBuilder(
        builder: (context, box) => ValueListenableBuilder<_MapView>(
          valueListenable: _mapView,
          builder: (_, view, __) {
            final scale = box.maxWidth / w * view.zoom;
            double place(double middle, double length, double room) {
              final at = room / 2 - middle * scale;
              return length * scale <= room ? (room - length * scale) / 2 : at.clamp(room - length * scale, 0.0);
            }

            final left = place(view.x, w, box.maxWidth), top = place(view.y, h, box.maxHeight);
            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: w * scale,
                  height: h * scale,
                  child: Image(
                    image: _mapPicture,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _RingPainter([
                      for (final ring in view.rings.entries)
                        (
                          Offset(left + (points[ring.key] as List)[0] * scale, top + (points[ring.key] as List)[1] * scale),
                          ((points[ring.key] as List)[2] as num) * scale * 1.13,
                          ring.value,
                        ),
                    ]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _card(String face) => Container(
        width: 150,
        height: 150,
        margin: const EdgeInsets.symmetric(horizontal: 11),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 18, offset: const Offset(0, 8)),
          ],
        ),
        child: Image.asset(face, fit: BoxFit.contain),
      );

  Widget _titleCard() {
    return ColoredBox(
      color: _paper,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final face in faces) _card(face)]),
          const SizedBox(height: 54),
          Text('A SORTING GAME IN PICTURES', style: _label()),
          const SizedBox(height: 18),
          Text('How the game is played',
              style: GoogleFonts.quicksand(fontSize: 82, fontWeight: FontWeight.w700, color: _ink, height: 1.1)),
          const SizedBox(height: 20),
          Text('For a child who cannot read yet.',
              style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w500, color: _soft)),
        ],
      ),
    );
  }

  Widget _endCard() {
    final now = DateTime.now();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October',
      'November', 'December'
    ];
    return ColoredBox(
      color: _paper,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final line in const ['Touch to hear.', 'Choose four.', 'Dig deeper.'])
            Text(line,
                style: GoogleFonts.quicksand(fontSize: 78, fontWeight: FontWeight.w700, color: _ink, height: 1.22)),
          const SizedBox(height: 46),
          Text(
            'The game as it stands on ${now.day} ${months[now.month - 1]} ${now.year}:  '
            '${facts['things']} things, ${facts['boards']} boards a child can open.',
            style: GoogleFonts.inter(fontSize: 25, fontWeight: FontWeight.w500, color: _soft),
          ),
          const SizedBox(height: 12),
          Text(
            'Every screen, every tap and every word the game speaks in this film is the game\u2019s own.',
            style: GoogleFonts.inter(fontSize: 21, fontWeight: FontWeight.w500, color: _soft),
          ),
        ],
      ),
    );
  }
}

/// The map is a file of the project, not one of the game's own.
final _mapPicture = FileImage(File('docs/game_map.png'));

// ---------------------------------------------------------------------------
// The camera.

class _Film {
  _Film(this.tester, this.players, this.voice) {
    players.onStart = (asset, seconds) => _heard.add({
          'asset': asset,
          'seconds': seconds,
          'frame': frames,
          't': frames / _fps,
          'filmed': filming,
        });
  }

  final WidgetTester tester;
  final _FilmPlayers players;
  final Map<String, dynamic> voice; // the narrator's lines: id -> {label, text, seconds}

  /// Frames saved, and frames the game has lived through. They differ after a cut.
  int frames = 0;
  int lived = 0;
  bool filming = true;
  int _pointer = 20;
  int _voiceEnds = 0;

  final _heard = <Map<String, Object>>[];
  final _spoken = <Map<String, Object>>[];
  final _cuts = <Map<String, Object>>[];
  final _marks = <Map<String, Object>>[];

  void mark(String name) => _marks.add({'mark': name, 'frame': frames, 't': frames / _fps});

  void writeEvents() => File('$_out/frames/events.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
        'fps': _fps,
        'every': _every,
        'frames': frames,
        'size': [_width, (_width * _stage.height / _stage.width).round()],
        'seed': _seed,
        'voice': _spoken,
        'game': _heard,
        'cuts': _cuts,
        'marks': _marks,
      }));

  RenderRepaintBoundary get _boundary =>
      tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('capture')));

  /// Lets the game live one frame (its clock, its animations, its sounds) and, unless
  /// this stretch is being cut, saves the picture.
  Future<void> frame() async {
    await tester.pump(_frame);
    lived++;
    if (!filming) return;
    if (frames % _every == 0) {
      final path = '$_out/frames/f${(frames ~/ _every).toString().padLeft(5, '0')}.png';
      await tester.runAsync(() async {
        final image = await _boundary.toImage(pixelRatio: _pixelRatio);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await File(path).writeAsBytes(png!.buffer.asUint8List());
      });
    }
    frames++;
    if (frames % (_fps * 5) == 0) _log('filmed ${frames ~/ _fps} s');
  }

  Future<void> hold(double seconds) async {
    final n = (seconds * _fps).round();
    for (var i = 0; i < n; i++) {
      await frame();
    }
  }

  /// Goes on until the game has finished what it is saying.
  Future<void> quiet([double after = 0.25]) async {
    var idle = 0;
    while (idle < 3) {
      await frame();
      idle = players.playing ? 0 : idle + 1;
    }
    await hold(after);
  }

  /// Goes on until the game begins a clip of this [kind]: its explanation, say.
  Future<void> untilGameSays(String kind, {double atMost = 8}) async {
    for (var i = 0; i < atMost * _fps && players.saying != kind; i++) {
      await frame();
    }
  }

  /// Shows a line of the narrator's without speaking it: the game itself is speaking.
  void show(String id) {
    final line = voice[id] as Map<String, dynamic>;
    _caption.value = _Caption(line['label'] as String, line['text'] as String);
  }

  /// The narrator speaks a line, and it is shown. Never over the game's own voice.
  Future<void> say(String id, {bool shown = true}) async {
    await quiet(0.1);
    final line = voice[id] as Map<String, dynamic>;
    if (shown) {
      show(id);
      await hold(0.2);
    }
    _spoken.add({'id': id, 'frame': frames, 't': frames / _fps});
    _voiceEnds = frames + ((line['seconds'] as num) * _fps).ceil();
  }

  /// Goes on until the narrator has finished, and a little longer.
  Future<void> spoken([double after = 0.3]) async {
    while (frames < _voiceEnds) {
      await frame();
    }
    await hold(after);
  }

  Future<void> _fingerFade(Offset at, {required bool down}) async {
    const steps = 4;
    for (var i = 1; i <= steps; i++) {
      _touch.value = _Touch(at, down ? i / steps : 1 - i / steps);
      await frame();
    }
    if (!down) _touch.value = null;
  }

  /// A finger presses at [at] and lifts: long enough to be seen.
  Future<void> press(Offset at) async {
    final g = await tester.startGesture(at, pointer: _pointer++);
    await _fingerFade(at, down: true);
    await hold(0.1);
    await g.up();
    await _fingerFade(at, down: false);
  }

  /// Leaves out a stretch of play: the game lives through [during] unfilmed, and the
  /// picture dissolves from where it was to where it is. A clip still playing at the cut
  /// is faded there by film_make.py; a clip that starts inside the cut is not heard.
  Future<void> cut(Future<void> Function() during) async {
    late ui.Image before;
    await tester.runAsync(() async => before = await _boundary.toImage(pixelRatio: _pixelRatio));
    final from = lived;
    filming = false;
    await during();
    filming = true;
    _cuts.add({'frame': frames, 't': frames / _fps, 'left out': (lived - from) / _fps});
    const steps = 12;
    for (var i = 0; i < steps; i++) {
      _dissolve.value = (before, 1 - (i + 1) / (steps + 1));
      await frame();
    }
    _dissolve.value = null;
    await frame();
    before.dispose();
  }

  /// Moves the look at the map from where it is to [to], with the ease of a hand.
  Future<void> mapTo(_MapView to, double seconds) async {
    final from = _mapView.value;
    final n = (seconds * _fps).round();
    for (var i = 1; i <= n; i++) {
      _mapView.value = _MapView.lerp(from, to, Curves.easeInOutCubic.transform(i / n));
      await frame();
    }
  }
}

// ---------------------------------------------------------------------------

/// The four groups of the board, the ones in [first] first.
List<BoardGroup> _order(EngineProvider g, List<String> first) => [
      for (final value in first) ...g.board!.groups.where((x) => x.value == value),
      ...g.board!.groups.where((x) => !first.contains(x.value)),
    ];

String _deal(EngineProvider g) => [
      '    ${g.pathLabels.join(' > ')}: ${g.prompt}',
      for (final group in g.board!.groups) '      ${group.label}: ${group.items.map((e) => e.label).join(', ')}',
    ].join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _entities = ContentRepository.thingsFromJson(_read('Assets/data/things.json'));
    _registry = DimensionRegistry.fromJson(_read('Assets/data/dictionary.json'));
    _words = GroupWordsBook.fromJson(_read('Assets/data/groups.json'));
    _assets = Directory('Assets')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll('\\', '/'))
        .toSet();
  });

  if (_scout > 0) {
    test('the boards each seed would deal', () async {
      for (var seed = 1; seed <= _scout; seed++) {
        final g = EngineProvider(repo: _repo(seed), random: Random(seed));
        await g.init();
        final lines = <String>['seed $seed', _deal(g)];
        void solve(List<String> first) {
          for (final group in _order(g, first)) {
            group.items.forEach(g.toggle);
            g.submit();
          }
        }

        solve(const ['animal', 'plant']);
        final dig = g.suggestedDig;
        if (dig?.value == 'animal') {
          g.descendInto(dig!);
          lines.add(_deal(g));
          if (g.board!.groups.any((x) => x.value == 'mammal')) {
            solve(const ['mammal']);
            g.descendInto(g.suggestedDig!);
            lines.add(_deal(g));
            solve(const ['pet']);
            lines.add('    then: ${g.suggestedDig == null ? 'Next board' : 'Dig deeper: ${g.suggestedDig!.label}'}');
            g.nextBoard();
            lines.add(_deal(g));
          } else {
            lines.add('    (no mammals on the second board)');
          }
        }
        // ignore: avoid_print
        print(lines.join('\n'));
      }
    });
    return;
  }

  testWidgets('film: how the game is played', timeout: const Timeout(Duration(minutes: 120)), (tester) async {
    final players = _FilmPlayers();
    AudioplayersPlatformInterface.instance = players;
    GlobalAudioplayersPlatformInterface.instance = _FilmGlobalAudio();
    AudioCache.instance = _FilmCache();
    PathProviderPlatform.instance = _FilmPaths();
    HttpOverrides.global = null; // the game's font package fetches its two fonts, as the game does
    await tester.runAsync(_loadFonts);

    tester.view.physicalSize = _stage * _pixelRatio;
    tester.view.devicePixelRatio = _pixelRatio;
    addTearDown(tester.view.reset);

    final folder = Directory('$_out/frames');
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    folder.createSync(recursive: true);

    final facts = _read('tools/illustration/game_map.json');
    final map = _read('tools/illustration/game_map_points.json');
    final voice = (_read('$_out/voice/manifest.json')['lines'] as Map).cast<String, dynamic>();
    const faces = ['dog', 'mango_tree', 'sun', 'car'];

    imageCache.maximumSizeBytes = 600 << 20;
    await _preload(tester, [
      for (final e in _entities) AssetImage('Assets/pictures/${e.id}.webp'),
      _mapPicture,
    ]);
    _log('pictures loaded');

    final engine = EngineProvider(repo: _repo(_seed), random: Random(_seed));
    unawaited(engine.init());
    await tester.pump();

    final film = _Film(tester, players, voice);
    BoardGroup group(String value) => engine.board!.groups.singleWhere((g) => g.value == value);
    Offset at(Finder f) => tester.getCenter(f);

    /// Where a finger touches a picture: the middle of what can be seen of it. With a clue
    /// and an explanation both showing, the lowest row of a small screen is partly under them.
    Offset onTile(Entity e) {
      final tile = tester.getRect(find.byKey(ValueKey(e.id)));
      final seen = tile.intersect(tester.getRect(find.byType(SingleChildScrollView)));
      expect(seen.height, greaterThan(30), reason: '${e.label} should be on the screen to be touched');
      if (seen.height < tile.height - 1) film.mark('partly hidden: ${e.label}');
      return seen.center;
    }

    Future<void> touch(Entity e, {double after = 0.2}) async {
      await film.press(onTile(e));
      await film.quiet(after);
    }

    Future<void> submit() => film.press(at(find.text('Submit')));
    Future<void> solve(BoardGroup g) async {
      for (final e in g.items) {
        await film.press(onTile(e));
      }
      await submit();
      await film.quiet();
    }

    debugDisableShadows = false;
    try {
      await tester.pumpWidget(_Stage(
        engine: engine,
        map: map,
        facts: facts,
        faces: [for (final face in faces) 'Assets/pictures/$face.webp'],
      ));
      await tester.pump();
      expect(engine.board, isNotNull, reason: 'the game should have dealt its first board');
      _log('first board:\n${_deal(engine)}');

      // ------------------------------------------------------------ the title
      await film.hold(3.0);
      _scene.value = 'game';
      await film.hold(1.0);

      // ------------------------------------------------------------ the first board
      film.mark('board');
      await film.say('board');
      await film.spoken(0.5);

      // the animal a small child is surest of is touched first
      const sure = ['dog', 'cat', 'cow', 'sheep', 'elephant', 'hen', 'lion', 'goldfish', 'parrot', 'butterfly'];
      int rank(Entity e) => sure.contains(e.id) ? sure.indexOf(e.id) : sure.length;
      final animals = [...group('animal').items]..sort((a, b) => rank(a).compareTo(rank(b)));
      await film.say('touch');
      await film.spoken(0.15);
      await touch(animals[0], after: 0.4);

      await film.say('four');
      await film.spoken(0.2);
      for (final e in animals.skip(1)) {
        await touch(e, after: 0.05);
      }
      await film.say('submit');
      await film.spoken(0.15);
      await submit(); // the game says "right", then why these four belong together
      await film.untilGameSays('explanation');
      film.show('why'); // on screen while the game speaks; the narrator keeps quiet
      await film.quiet(0.9);
      expect(engine.solved.single.value, 'animal');

      // ------------------------------------------------------------ a wrong guess
      film.mark('wrong');
      _caption.value = null;
      final plants = group('plant').items;
      final nature = group('nature_not_alive').items;
      // the one that does not belong: a thing of nature a child might well take for a plant
      final stray = [
        for (final id in const ['field', 'soil', 'mud', 'rain', 'hill', 'river', 'pond'])
          ...nature.where((e) => e.id == id),
        nature.first,
      ].first;
      for (final e in [...plants.take(3), stray]) {
        await touch(e, after: 0.0);
      }
      await submit();
      await film.quiet(0.15);
      expect(engine.mistakes, 1);
      await film.say('wrong');
      await film.spoken(0.4);

      // ------------------------------------------------------------ a clue, and a clearer one
      film.mark('clue');
      await film.say('stuck');
      await film.spoken(0.1);
      await touch(plants[0], after: 0.3);
      final clue = find.byKey(const ValueKey('clue-button'));
      await film.press(at(clue));
      await film.quiet(0.3);
      await film.say('clearer');
      await film.spoken(0.1);
      await film.press(at(clue));
      await film.quiet(0.3);
      expect(engine.cluesUsed, 2);
      await film.say('clue_free');
      await film.spoken(0.4);
      _caption.value = null;
      for (final e in plants.skip(1)) {
        await touch(e, after: 0.0);
      }
      await submit();
      await film.untilGameSays('explanation'); // "right" is heard; the cut comes as the explanation begins
      expect(engine.solved.length, 2);

      // ------------------------------------------------------------ the board is done
      final rest = _order(engine, const []).where((g) => !engine.solved.contains(g)).toList();
      await film.cut(() async {
        await film.quiet();
        await solve(rest[0]);
        for (final e in rest[1].items) {
          await film.press(onTile(e));
        }
        await film.quiet(0.4);
      });
      film.mark('done');
      await film.say('until_done');
      await film.spoken(0.1);
      await submit();
      await film.untilGameSays('explanation');
      expect(engine.boardFinished, isTrue);
      await film.cut(() => film.quiet(0.3));

      // ------------------------------------------------------------ dig deeper
      film.mark('dig');
      final next = find.byKey(const ValueKey('next'));
      expect(find.text('Dig deeper: Animals'), findsOneWidget, reason: 'the first board should lead into Animals');
      await film.say('dig');
      await film.spoken(0.2);
      await film.press(at(next));
      await film.hold(1.0);
      expect(engine.pathLabels.last, 'Animals');
      _log('second board:\n${_deal(engine)}');
      await film.say('finer');
      await film.spoken(0.8);

      await film.cut(() async {
        for (final g in _order(engine, const ['mammal'])) {
          await solve(g);
        }
        await film.quiet(0.4);
      });
      expect(find.text('Dig deeper: Mammals'), findsOneWidget, reason: 'the second board should lead into Mammals');
      film.mark('deeper');
      await film.say('deeper');
      await film.hold(1.3);
      await film.press(at(next));
      await film.spoken(0.6);
      expect(engine.pathLabels.last, 'Mammals');
      _log('third board:\n${_deal(engine)}');

      // one group of the third board is found; the rest is left out
      _caption.value = null;
      final pets = group('pet');
      for (final e in pets.items) {
        await touch(e, after: 0.0);
      }
      await submit();
      await film.untilGameSays('explanation');
      await film.hold(0.5);
      await film.cut(() async {
        await film.quiet();
        for (final g in _order(engine, const []).where((g) => !engine.solved.contains(g)).toList()) {
          await solve(g);
        }
        await film.quiet(0.4);
      });
      await film.say('same_dog');
      await film.spoken(0.5);

      // ------------------------------------------------------------ nothing deeper yet: another board
      expect(find.text('Next board'), findsOneWidget, reason: 'nothing is deeper than the third board yet');
      film.mark('another');
      await film.say('another');
      await film.hold(2.4);
      await film.press(at(next));
      await film.spoken(1.0);
      _log('fourth board:\n${_deal(engine)}');
      await film.hold(0.2);

      // ------------------------------------------------------------ the whole game, on the map
      film.mark('map');
      final points = (map['points'] as Map).cast<String, dynamic>();
      final size = (map['image'] as List).cast<num>();
      double px(String id, int i) => ((points[id] as List)[i] as num).toDouble();
      final whole = _MapView(size[0] / 2, size[1] / 2, 1);
      const path = ['seed', 'animal', 'animal/mammal'];
      final middle = Offset(
        path.map((id) => px(id, 0)).reduce((a, b) => a + b) / path.length,
        path.map((id) => px(id, 1)).reduce((a, b) => a + b) / path.length,
      );
      _mapView.value = whole;
      _caption.value = null;
      _scene.value = 'map';
      await film.hold(1.0);
      await film.say('whole');
      await film.spoken(0.6);
      await film.say('path');
      await film.mapTo(_MapView(middle.dx, middle.dy, 1.85, const {'seed': 1}), 1.5);
      await film.mapTo(_MapView(middle.dx, middle.dy, 1.85, const {'seed': 1, 'animal': 1}), 0.9);
      await film.mapTo(_MapView(middle.dx, middle.dy, 1.85, const {'seed': 1, 'animal': 1, 'animal/mammal': 1}), 0.9);
      await film.spoken(0.8);
      await film.say('grey');
      await film.mapTo(whole, 1.8);
      await film.spoken(1.2);

      // ------------------------------------------------------------ the last card
      film.mark('end');
      _scene.value = 'end';
      await film.hold(0.9);
      await film.say('three', shown: false);
      await film.spoken(3.2);

      film.writeEvents();
      _log('filmed ${(film.frames / _fps).toStringAsFixed(1)} s in ${film.frames} frames; '
          '${((film.lived - film.frames) / _fps).toStringAsFixed(1)} s of play left out at the cuts');
      // let what the game left running come to rest, so the test ends clean
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    } finally {
      debugDisableShadows = true;
    }
  });
}
