// The Instagram film: the game's own screen, played for real, for the phone in the Blender scene.
//
// Made like the owner's Glym promos (vocabulary_swipe_app, tool/deck_engine/blender/promo4_*.py):
// the app's own film plays on a phone lying on a desk, and a camera follows the story. This
// file makes the app's own film. The game on it is the game itself: its own screen, theme,
// things, pictures, clues and explanations, played through Flutter's gesture system by taps a
// finger would make, and saved frame by frame at 30 a second, on a phone held upright (405 by
// 720 of the game's units). Nothing of the game is redrawn. The film draws only a soft dot
// where the finger touches.
//
// It writes, in tools/insta/out/screen/: the frames (f00000.png ...), and events.json: where
// each moment of the story begins (the marks the camera follows), on which frame the narrator
// starts each line, and on which frame the game itself played which clip.
//
//   python tools/insta/insta_voice.py
//   flutter test tools/insta/insta_game_test.dart
//   python tools/insta/insta_make.py
//
//   --dart-define=SEED=7     film this deal; otherwise the first deal from 1 that tells the story
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
// ignore: depend_on_referenced_packages
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:connections_game/main.dart';
import 'package:connections_game/models/dimension.dart';
import 'package:connections_game/models/entity.dart';
import 'package:connections_game/models/game_settings.dart';
import 'package:connections_game/models/group_words.dart';
import 'package:connections_game/models/places_map.dart';
import 'package:connections_game/providers/engine_provider.dart';
import 'package:connections_game/screens/engine_screen.dart';
import 'package:connections_game/services/board_assembler.dart';
import 'package:connections_game/services/content_repository.dart';
import 'package:connections_game/services/media.dart';
import 'package:connections_game/services/progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

const _askedSeed = int.fromEnvironment('SEED');
const _out = 'tools/insta/out';
const _fps = 30;
const _frame = Duration(microseconds: 1000000 ~/ _fps);

/// A phone held upright, in the game's own units; saved at 810 by 1440 pixels.
const _screen = Size(405, 720);
const _ratio = 2.0;
const _emoji = 'Segoe UI Emoji';

final _clock = Stopwatch()..start();
// ignore: avoid_print
void _log(String m) => print('[${(_clock.elapsedMilliseconds / 1000).toStringAsFixed(1)}s] $m');

Map<String, dynamic> _read(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

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
      places: PlacesMap.fromJson(_read('Assets/data/places.json')),
    );

// ---------------------------------------------------------------------------
// Stand-ins for two plugins a test has no device for (as in tools/film/film_game_test.dart).

/// The audio plugin. It plays nothing; it takes as long over a clip as the clip is, and then
/// reports it complete, so the game's own queue of sounds runs as on a device. Each clip it is
/// asked for is written down with the frame it started on.
class _Players extends AudioplayersPlatformInterface {
  final _events = <String, StreamController<AudioEvent>>{};
  final _source = <String, String>{};
  final _ending = <String, Timer>{};
  final Map<String, dynamic> clips = _read('$_out/game_audio.json');
  void Function(String asset, double seconds)? onStart;
  bool get playing => _ending.isNotEmpty;
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
    saying = clip['kind'] as String;
    _ending[playerId]?.cancel();
    _ending[playerId] = Timer(Duration(milliseconds: (seconds * 1000).round()), () {
      _ending.remove(playerId);
      saying = null;
      _channel(playerId).add(const AudioEvent(eventType: AudioEventType.complete));
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

class _GlobalAudio implements GlobalAudioplayersPlatformInterface {
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

class _Cache extends AudioCache {
  _Cache() : super(prefix: '');
  @override
  Future<Uri> load(String fileName) async => Uri.parse(Uri.encodeFull(fileName));
}

class _Paths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => Directory('$_out/fonts').absolute.path;
  @override
  Future<String?> getApplicationDocumentsPath() async => Directory('$_out/fonts').absolute.path;
  @override
  Future<String?> getApplicationCachePath() async => Directory('$_out/fonts').absolute.path;
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

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
  }
  _log('fonts loaded');
}

Future<void> _preload(WidgetTester tester, Iterable<ImageProvider> images) async {
  await tester.runAsync(() async {
    for (final provider in images) {
      final done = Completer<void>();
      provider.resolve(ImageConfiguration(bundle: rootBundle, devicePixelRatio: _ratio)).addListener(
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
// What the film draws: a soft dot where the finger is, and a dissolve where play is left out.

class _Touch {
  const _Touch(this.at, this.strength);
  final Offset at;
  final double strength;
}

final _touch = ValueNotifier<_Touch?>(null);
final _dissolve = ValueNotifier<(ui.Image, double)?>(null);

class _TouchPainter extends CustomPainter {
  _TouchPainter(this.touch);
  final _Touch touch;

  @override
  void paint(Canvas canvas, Size size) {
    final s = touch.strength;
    final r = 17.0 + 3 * s;
    canvas.drawCircle(touch.at, r + 2, Paint()..color = Colors.black.withValues(alpha: 0.14 * s));
    canvas.drawCircle(touch.at, r, Paint()..color = Colors.white.withValues(alpha: 0.45 * s));
    canvas.drawCircle(
      touch.at,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white.withValues(alpha: 0.95 * s),
    );
  }

  @override
  bool shouldRepaint(_TouchPainter old) => old.touch != touch;
}

/// The phone's screen: the game as lib/main.dart starts it, the dot of the finger over it.
class _Phone extends StatelessWidget {
  const _Phone({required this.engine});
  final EngineProvider engine;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const ValueKey('capture'),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            Positioned.fill(
              child: ChangeNotifierProvider<EngineProvider>.value(
                value: engine,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: _theme.copyWith(textTheme: _theme.textTheme.apply(fontFamilyFallback: const [_emoji])),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(size: _screen),
                    child: child!,
                  ),
                  home: const ResponsiveWrapper(child: EngineScreen()),
                ),
              ),
            ),
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
                  builder: (_, t, __) => t == null ? const SizedBox.expand() : CustomPaint(painter: _TouchPainter(t)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Film {
  _Film(this.tester, this.players, this.voice) {
    players.onStart = (asset, seconds) =>
        _heard.add({'asset': asset, 'seconds': seconds, 'frame': frames, 't': frames / _fps, 'filmed': filming && speed == 1});
  }

  final WidgetTester tester;
  final _Players players;
  final Map<String, dynamic> voice;
  int frames = 0;
  int lived = 0;
  bool filming = true;

  /// One frame kept in this many: 1 at the game's own pace; more in the second half, which runs
  /// fast forward (the owner, 26 Nov 2026: "the second one is a bit more fast forwarded"). The
  /// game's own clips are not heard while it does.
  int speed = 1;
  int _pointer = 20;
  int _voiceEnds = 0;
  final _heard = <Map<String, Object>>[];
  final _spoken = <Map<String, Object>>[];
  final _cuts = <Map<String, Object>>[];
  final _marks = <Map<String, Object>>[];
  final _boxes = <String, List<double>>{};
  final _presses = <Map<String, Object>>[];
  List<Map<String, Object?>> tiles = [];
  List<Map<String, Object?>> web = [];

  void mark(String name) => _marks.add({'mark': name, 'frame': frames, 't': frames / _fps});

  /// Where a part of the screen is, in the screen's own pixels, for the camera to close in on.
  void box(String name, Rect r) => _boxes[name] = [r.left * _ratio, r.top * _ratio, r.right * _ratio, r.bottom * _ratio];

  void writeEvents(int seed) => File('$_out/screen/events.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
        'fps': _fps,
        'frames': frames,
        'size': [(_screen.width * _ratio).round(), (_screen.height * _ratio).round()],
        'seed': seed,
        'voice': _spoken,
        'game': _heard,
        'cuts': _cuts,
        'marks': _marks,
        'boxes': _boxes,
        'presses': _presses,
        'tiles': tiles,
        'web': web,
      }));

  RenderRepaintBoundary get _boundary =>
      tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('capture')));

  Future<void> frame() async {
    await tester.pump(_frame);
    lived++;
    if (!filming || lived % speed != 0) return;
    final path = '$_out/screen/f${frames.toString().padLeft(5, '0')}.png';
    await tester.runAsync(() async {
      final image = await _boundary.toImage(pixelRatio: _ratio);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await File(path).writeAsBytes(png!.buffer.asUint8List());
    });
    frames++;
    if (frames % (_fps * 5) == 0) _log('filmed ${frames ~/ _fps} s');
  }

  Future<void> hold(double seconds) async {
    for (var i = 0; i < (seconds * _fps).round(); i++) {
      await frame();
    }
  }

  Future<void> quiet([double after = 0.25]) async {
    var idle = 0;
    while (idle < 3) {
      await frame();
      idle = players.playing ? 0 : idle + 1;
    }
    await hold(after);
  }

  Future<void> untilGameSays(String kind, {double atMost = 8}) async {
    for (var i = 0; i < atMost * _fps && players.saying != kind; i++) {
      await frame();
    }
  }

  /// The narrator begins a line: never over the game's own voice (in the fast half that voice is not heard).
  Future<void> say(String id) async {
    final line = voice[id] as Map<String, dynamic>;
    _spoken.add({'id': id, 'frame': frames, 't': frames / _fps});
    _voiceEnds = frames + ((line['seconds'] as num) * _fps).ceil();
  }

  Future<void> spoken([double after = 0.3]) async {
    while (frames < _voiceEnds) {
      await frame();
    }
    await hold(after);
  }

  Future<void> _fingerFade(Offset at, {required bool down}) async {
    const steps = 3;
    for (var i = 1; i <= steps; i++) {
      _touch.value = _Touch(at, down ? i / steps : 1 - i / steps);
      await frame();
    }
    if (!down) _touch.value = null;
  }

  Future<void> press(Offset at, [String kind = 'tile']) async {
    if (speed == 1 && filming) _presses.add({'t': frames / _fps, 'kind': kind});
    final g = await tester.startGesture(at, pointer: _pointer++);
    await _fingerFade(at, down: true);
    await hold(0.07);
    await g.up();
    await _fingerFade(at, down: false);
  }

  /// A press as a quick child makes it, for the fast-forward half: the game still sees a real tap.
  Future<void> tap(Offset at) async {
    final g = await tester.startGesture(at, pointer: _pointer++);
    _touch.value = _Touch(at, 1);
    await frame();
    await frame();
    await g.up();
    _touch.value = null;
    await frame();
  }

  /// Lives [n] frames, whatever is kept of them.
  Future<void> live(int n) async {
    for (var i = 0; i < n; i++) {
      await frame();
    }
  }

  /// Leaves out a stretch of play: the game lives through [during] unfilmed, and the picture
  /// dissolves from where it was to where it is.
  Future<void> cut(Future<void> Function() during) async {
    late ui.Image before;
    await tester.runAsync(() async => before = await _boundary.toImage(pixelRatio: _ratio));
    final from = lived;
    filming = false;
    await during();
    filming = true;
    _cuts.add({'frame': frames, 't': frames / _fps, 'left out': (lived - from) / _fps});
    const steps = 10;
    for (var i = 0; i < steps; i++) {
      _dissolve.value = (before, 1 - (i + 1) / (steps + 1));
      await frame();
    }
    _dissolve.value = null;
    await frame();
    before.dispose();
  }
}

// ---------------------------------------------------------------------------
// The story, played without a screen first, to find a deal that tells it.

const _sure = ['dog', 'cat', 'cow', 'elephant', 'lion', 'hen', 'parrot', 'sheep', 'goldfish', 'butterfly', 'horse'];
const _strays = ['field', 'soil', 'mud', 'rain', 'hill', 'river', 'pond', 'sand', 'rock'];

List<Entity> _animals(EngineProvider g) {
  int rank(Entity e) => _sure.contains(e.id) ? _sure.indexOf(e.id) : _sure.length;
  return [...g.board!.groups.singleWhere((x) => x.value == 'animal').items]..sort((a, b) => rank(a).compareTo(rank(b)));
}

Entity? _stray(EngineProvider g) {
  final nature = g.board!.groups.where((x) => x.value == 'nature_not_alive');
  if (nature.isEmpty) return null;
  for (final id in _strays) {
    for (final e in nature.single.items) {
      if (e.id == id) return e;
    }
  }
  return null;
}

/// Plays the story headless: does this deal tell it?
Future<bool> _tellsTheStory(int seed) async {
  final g = EngineProvider(repo: _repo(seed), random: Random(seed), progressStore: MemoryProgressStore());
  await g.init();
  final values = g.board!.groups.map((x) => x.value).toSet();
  if (!values.containsAll(const ['animal', 'plant', 'nature_not_alive'])) return false;
  final animals = _animals(g);
  final stray = _stray(g);
  if (!_sure.contains(animals.first.id) || stray == null) return false;
  animals.forEach(g.toggle);
  g.submit();
  final plants = g.board!.groups.singleWhere((x) => x.value == 'plant').items;
  [...plants.take(3), stray].forEach(g.toggle);
  if (g.submit() != SubmitResult.oneAway) return false;
  g.toggle(plants.first);
  final clue = g.nextClue();
  if (clue == null) return false;
  plants.skip(1).forEach(g.toggle);
  g.submit();
  for (final rest in g.board!.groups.where((x) => !g.solved.contains(x)).toList()) {
    rest.items.forEach(g.toggle);
    g.submit();
  }
  return g.boardFinished && g.nextStep?.id == 'animal';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _entities = ContentRepository.thingsFromJson(_read('Assets/data/things.json'));
    _registry = DimensionRegistry.fromJson(_read('Assets/data/dictionary.json'));
    _words = GroupWordsBook.fromJson(_read('Assets/data/groups.json'));
    _assets = Directory('Assets').listSync(recursive: true).whereType<File>().map((f) => f.path.replaceAll('\\', '/')).toSet();
  });

  testWidgets('insta film: the game on a phone', timeout: const Timeout(Duration(minutes: 60)), (tester) async {
    final players = _Players();
    AudioplayersPlatformInterface.instance = players;
    GlobalAudioplayersPlatformInterface.instance = _GlobalAudio();
    AudioCache.instance = _Cache();
    PathProviderPlatform.instance = _Paths();
    HttpOverrides.global = null; // the game's font package fetches its two fonts, as the game does
    await tester.runAsync(_loadFonts);

    var seed = _askedSeed;
    if (seed == 0) {
      await tester.runAsync(() async {
        for (var s = 1; s <= 80 && seed == 0; s++) {
          if (await _tellsTheStory(s)) seed = s;
        }
      });
      expect(seed, isNot(0), reason: 'no deal from 1 to 80 tells the story');
    }
    _log('the deal: seed $seed');

    tester.view.physicalSize = _screen * _ratio;
    tester.view.devicePixelRatio = _ratio;
    addTearDown(tester.view.reset);

    final folder = Directory('$_out/screen');
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    folder.createSync(recursive: true);
    final voice = (_read('$_out/voice/manifest.json')['lines'] as Map).cast<String, dynamic>();

    imageCache.maximumSizeBytes = 600 << 20;
    await _preload(tester, [for (final e in _entities) AssetImage('Assets/pictures/${e.id}.webp')]);
    _log('pictures loaded');

    // The game as a family meets it on a phone: Automate on, and the explanation kept small (the owner's
    // choice of 24 Nov 2026 for a phone: in full it "takes away too much vertical space"). It is still spoken.
    final engine = EngineProvider(
        repo: _repo(seed), random: Random(seed), progressStore: MemoryProgressStore()..saveFlag('words_small', true));
    unawaited(engine.init());
    await tester.pump();
    final film = _Film(tester, players, voice);
    BoardGroup group(String value) => engine.board!.groups.singleWhere((g) => g.value == value);
    Offset at(Finder f) => tester.getCenter(f);
    Offset onTile(Entity e) {
      final tile = tester.getRect(find.byKey(ValueKey(e.id)));
      final seen = tile.intersect(tester.getRect(find.byType(SingleChildScrollView).first));
      expect(seen.height, greaterThan(24), reason: '${e.label} should be on the screen to be touched');
      return seen.center;
    }

    Future<void> touch(Entity e, {double after = 0.0}) async {
      await film.press(onTile(e));
      await film.quiet(after);
    }

    Future<void> submit() => film.press(at(find.text('Submit')));

    debugDisableShadows = false;
    try {
      await tester.pumpWidget(_Phone(engine: engine));
      await tester.pump();
      expect(engine.board, isNotNull);
      expect(engine.automate, isTrue, reason: 'the game as a family meets it');
      expect(engine.wordsSmall, isTrue);
      film.box('board', tester.getRect(find.byType(SingleChildScrollView).first));
      film.box('top', Rect.fromLTWH(0, 0, _screen.width, 200));

      // The game's own voice is left out of the reel (the owner, 26 Nov 2026: "supress the voice from the
      // app and you tell what is that you are clicking"). The narrator says what is touched, and the pace is
      // hers: the finger touches each picture as its name is said.
      final names = <String, Entity>{for (final e in engine.board!.tiles) e.id: e};
      film.tiles = [
        for (final e in engine.board!.tiles)
          {
            'id': e.id,
            'label': e.label,
            'rect': [
              for (final v in [
                tester.getRect(find.byKey(ValueKey(e.id))).left,
                tester.getRect(find.byKey(ValueKey(e.id))).top,
                tester.getRect(find.byKey(ValueKey(e.id))).right,
                tester.getRect(find.byKey(ValueKey(e.id))).bottom,
              ])
                v * _ratio
            ],
          }
      ];

      /// The narrator says [line], and the finger touches [things] as each cue word of it is said.
      Future<void> touchAsSaid(String line, List<Entity> things) async {
        final cues = ((voice[line] as Map<String, dynamic>)['cue_times'] as List).cast<num>();
        expect(cues, hasLength(things.length));
        final from = film.frames;
        await film.say(line);
        for (var i = 0; i < things.length; i++) {
          final due = from + (cues[i] * _fps).round() - 2; // the finger lands just as the word begins
          while (film.frames < due) {
            await film.frame();
          }
          await film.press(onTile(things[i]));
        }
        await film.spoken(0.15);
      }

      // ------------------------------------------------ the hook: sixteen pictures
      film.mark('hook');
      await film.say('hook');
      await film.spoken(0.25);

      // ------------------------------------------------ four animals, each named as it is touched; right
      film.mark('touch');
      final animals = [for (final id in const ['dog', 'hen', 'catla_fish', 'stegosaurus']) names[id]!];
      expect(animals.every((e) => group('animal').items.contains(e)), isTrue,
          reason: 'the narrator names these four (insta.voice.json): the deal must be seed 4');
      await touchAsSaid('animals', animals);
      film.mark('right');
      await film.press(at(find.text('Submit')), 'submit');
      await film.hold(0.15);
      expect(engine.solved.single.value, 'animal');
      await film.say('right');
      await film.spoken(0.35);

      // ------------------------------------------------ a wrong guess: one away
      film.mark('wrong');
      final plants = [for (final id in const ['coconut_tree', 'grass', 'rose', 'soil']) names[id]!];
      await touchAsSaid('plants', plants);
      film.mark('oneaway');
      await film.press(at(find.text('Submit')), 'wrong');
      await film.hold(0.15);
      expect(engine.mistakes, 1);
      await film.say('oneaway');
      await film.spoken(0.3);

      // ------------------------------------------------ a clue
      film.mark('clue');
      await film.say('clue');
      await film.hold(1.2);
      film.box('clue', tester.getRect(find.byKey(const ValueKey('clue-button'))).inflate(30));
      await film.press(at(find.byKey(const ValueKey('clue-button'))), 'button');
      expect(engine.cluesUsed, 1);
      await film.spoken(1.1);
      await film.cut(() async {
        for (final rest in engine.board!.groups.where((x) => !engine.solved.contains(x)).toList()) {
          for (final e in rest.items) {
            await film.press(onTile(e));
          }
          await submit();
          await film.hold(0.3);
        }
        await film.hold(0.5);
      });
      expect(engine.boardFinished, isTrue);
      film.mark('done');
      await film.hold(0.5);

      // ------------------------------------------------ the second half: set after set, fast forward
      // The owner, 26 Nov 2026: "the second one is a bit more fast forwarded... such that when you show the
      // diagram... it looks more rich". The game plays on as a quick child plays it, every group found at
      // once, and one frame in five is kept. Where the game opens his web by itself (after four sets in a
      // sitting), its own button leads on. The sets are the ones Automate chooses.
      film.mark('fast');
      film.speed = 5;
      await film.say('fast');
      var sets = 0;
      Future<void> onward() async {
        final next = find.byKey(const ValueKey('next'));
        await film.tap(at(next));
        await film.live(14);
        final web = find.byKey(const ValueKey('web-next'));
        if (web.evaluate().isNotEmpty) {
          await film.live(40);
          await film.tap(at(web));
          await film.live(12);
        }
      }

      while (sets < 10) {
        await onward();
        if (engine.board == null || engine.boardFinished) break;
        for (final g in [...engine.board!.groups]) {
          for (final e in g.items) {
            await film.tap(onTile(e));
          }
          await film.tap(at(find.text('Submit')));
          await film.live(6);
        }
        expect(engine.boardFinished, isTrue);
        sets++;
        _log('fast: set $sets, ${engine.pathLabels.join(' > ')}');
        await film.live(12);
      }
      await film.spoken(0.0);
      await film.live(10);
      film.speed = 1;
      film.mark('slow');
      await film.hold(0.3);

      // ------------------------------------------------ the web of what he has found, now rich
      film.mark('web');
      await film.press(at(find.byKey(const ValueKey('web-mini'))), 'button');
      await film.say('web');
      await film.hold(0.4);
      if (find.byKey(const ValueKey('web-grew')).evaluate().isNotEmpty) {
        film.box('grew', tester.getRect(find.byKey(const ValueKey('web-grew'))).inflate(16));
      }
      await film.spoken(1.8);
      _log('the web: ${engine.web.length} knots, ${engine.progress.lines.length} lines');
      // his web, as the game holds it, for the 3D web of the reel's close
      film.web = [
        for (final n in engine.web)
          {
            'id': n.id,
            'label': n.label,
            'parent': n.parent,
            'found': n.found,
            'picture': n.picture?.art,
            'also': n.also,
            'end': n.end,
          }
      ];

      // ------------------------------------------------ the close
      film.mark('close');
      await film.say('close');
      await film.spoken(1.6);
      film.mark('end');

      film.writeEvents(seed);
      _log('filmed ${(film.frames / _fps).toStringAsFixed(1)} s in ${film.frames} frames');
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    } finally {
      debugDisableShadows = true;
    }
  });
}
