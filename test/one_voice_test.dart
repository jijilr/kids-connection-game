import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connections_game/main.dart' show HushOnPageChange;
import 'package:connections_game/providers/engine_provider.dart';
import 'package:connections_game/services/sound_service.dart';
import 'next_board_test.dart' show repo;

/// The game's one voice. The owner, 26 Nov 2026: "fix the sound overlap please... when a
/// set moves on nothing from that set must be playing... when a new audio starts playing
/// all the previous one must shut up and go away".
///
/// A stand-in for the audio plugin: it plays nothing, takes [clipLength] over every clip,
/// then says it is complete, and writes down what was started and what was heard to the end.
class _Players extends AudioplayersPlatformInterface {
  static const clipLength = Duration(milliseconds: 120);
  final _events = <String, StreamController<AudioEvent>>{};
  final _source = <String, String>{};
  final _ending = <String, Timer>{};
  final started = <String>[];
  final heardToTheEnd = <String>[];
  String? playing;

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
    started.add(asset);
    playing = asset;
    _ending[playerId]?.cancel();
    _ending[playerId] = Timer(clipLength, () {
      _ending.remove(playerId);
      heardToTheEnd.add(asset);
      playing = null;
      _channel(playerId).add(const AudioEvent(eventType: AudioEventType.complete));
    });
  }

  void _cut(String playerId) {
    _ending.remove(playerId)?.cancel();
    playing = null;
  }

  @override
  Future<void> stop(String playerId) async => _cut(playerId);
  @override
  Future<void> pause(String playerId) async => _cut(playerId);
  @override
  Future<void> release(String playerId) async => _cut(playerId);
  @override
  Future<void> dispose(String playerId) async => _cut(playerId);
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

Future<void> _wait(int ms) => Future.delayed(Duration(milliseconds: ms));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final players = _Players();
  late SoundService sound;

  setUpAll(() {
    AudioplayersPlatformInterface.instance = players;
    GlobalAudioplayersPlatformInterface.instance = _GlobalAudio();
    AudioCache.instance = _Cache();
    sound = SoundService();
  });

  setUp(() async {
    await sound.hush();
    await _wait(20);
    players.started.clear();
    players.heardToTheEnd.clear();
  });

  test('the newest wins: a new sound stops the one playing, and the old one never comes back',
      () async {
    await sound.playAsset('dog');
    await _wait(30);
    await sound.playAsset('hen');
    await _wait(30);
    await sound.playAsset('fish');
    await _wait(400);
    expect(players.started, ['dog', 'hen', 'fish']);
    expect(players.heardToTheEnd, ['fish'], reason: 'the dog and the hen were cut off, and stay cut off');
  });

  test('names tapped in a hurry: only the last is said, none waits its turn to be heard late',
      () async {
    for (final name in ['a', 'b', 'c', 'd']) {
      unawaited(sound.playAsset(name));
    }
    await _wait(500);
    expect(players.heardToTheEnd, ['d']);
    expect(players.playing, isNull);
  });

  test('the one chain: the explanation waits for the sound that says "right"', () async {
    await sound.playAsset('right');
    await sound.playAfter('why');
    await _wait(50);
    expect(players.playing, 'right');
    await _wait(400);
    expect(players.heardToTheEnd, ['right', 'why']);
  });

  test('a tap during the explanation stops it, and nothing that waited plays after', () async {
    await sound.playAsset('right');
    await sound.playAfter('why');
    await _wait(30);
    await sound.playAsset('dog');
    await _wait(400);
    expect(players.started, ['right', 'dog']);
    expect(players.heardToTheEnd, ['dog']);
  });

  test("the device's voice stops a clip too: one voice, never two", () async {
    await sound.playAsset('right');
    await sound.playAfter('why');
    await _wait(30);
    await sound.say('Find four that belong together.'); // no clip: the device's voice
    await _wait(400);
    expect(players.heardToTheEnd, isEmpty, reason: 'the clip and what waited behind it were stopped');
  });

  test('hush stops everything, even a sound that had not started yet', () async {
    unawaited(sound.playAsset('right'));
    unawaited(sound.playAfter('why'));
    unawaited(sound.hush()); // before the clip could start
    await _wait(400);
    expect(players.started, isEmpty);
    expect(players.playing, isNull);
  });

  test('leaving a set tells the game to hush, before the next set shows', () async {
    var hushes = 0;
    final g = EngineProvider(repo: repo(2), onLeaveSet: () => hushes++);
    await g.init();
    final first = hushes;
    g.nextBoard();
    await _wait(20);
    expect(hushes, greaterThan(first));
    final before = hushes;
    g.newBoard();
    expect(hushes, greaterThan(before));
  });

  testWidgets('opening or closing a page hushes; a dialog does not', (tester) async {
    var hushes = 0;
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      navigatorObservers: [HushOnPageChange(hush: () => hushes++)],
      home: const Text('game'),
    ));
    expect(hushes, 0, reason: 'the first page is not a change');
    key.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('web')));
    await tester.pumpAndSettle();
    expect(hushes, 1);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(hushes, 2);
    showDialog<void>(context: key.currentContext!, builder: (_) => const Text('a dialog'));
    await tester.pumpAndSettle();
    expect(hushes, 2);
  });
}
