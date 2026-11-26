import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'dart:math';
import 'dart:async';
import 'dart:collection';
import 'speaker.dart';

/// The game's one voice: every sound of the game, recorded clips and the device's voice
/// alike, goes through here. Its rules (the owner's words of 26 Nov 2026: "when a set moves
/// on nothing from that set must be playing... when a new audio starts playing all the
/// previous one must shut up and go away"):
///
///  - One sound at a time: a clip or the device's voice, never both at once.
///  - The newest wins: a sound that starts now stops whatever was playing or waiting.
///  - One chain only: a group's explanation waits for the sound that says "right".
///  - [hush] stops everything at once. The game calls it when the set changes, when a
///    page opens or closes, and when the game is put away (another tab, a locked phone).
///  - Nothing hushed comes back: a sound that was still loading when it was hushed never
///    starts.
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal() {
    _initPlayer();
  }

  final AudioPlayer _player = AudioPlayer();
  final Random _random = Random();

  final Queue<_AudioTask> _audioQueue = Queue<_AudioTask>();
  bool _isPlaying = false;
  _AudioTask? _current;
  Completer<void>? _currentPlayCompleter;

  /// Goes up at every [hush]: anything started under an older number is stale and is
  /// neither started nor allowed to start what was waiting behind it.
  int _generation = 0;

  /// Calls on the player run one after another, never interleaved, so a stop can never
  /// land in the middle of a start and let the old clip through.
  Future<void> _ops = Future.value();

  // Kept so it keeps listening.
  // ignore: unused_field
  AppLifecycleListener? _lifecycle;

  // Web-specific: Track if user has interacted (required for autoplay)
  bool _userHasInteracted = false;

  void _initPlayer() {
    // A clip has ended: what was waiting behind it may start.
    _player.onPlayerComplete.listen((_) {
      if (_current?.assetPath != null) _finished(_generation);
    });

    if (kIsWeb) {
      _player.setReleaseMode(ReleaseMode.stop);
    }

    // Put away, nothing keeps talking: on the web when the page is hidden (another tab,
    // a locked phone), elsewhere when the app is hidden or paused.
    if (kIsWeb) {
      whenPageHidden(hush);
    } else {
      try {
        _lifecycle = AppLifecycleListener(onHide: hush, onPause: hush);
      } catch (_) {
        // No app binding (a plain unit test): nothing to listen to.
      }
    }
  }

  /// Call this when user interacts with the app (tap, click, etc.)
  /// This unlocks audio playback on web browsers.
  void notifyUserInteraction() {
    if (!_userHasInteracted) {
      _userHasInteracted = true;
      // On web, try to "warm up" the audio context with a silent play
      if (kIsWeb) {
        _run(() async {
          try {
            await _player.setVolume(0);
            await _playAsset('Assets/audio/feedback/correct_01.mp3');
            await _player.stop();
          } finally {
            await _player.setVolume(1.0);
          }
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() op) {
    final next = _ops.then((_) => op()).catchError((Object e) {
      debugPrint('Sound: $e');
    });
    _ops = next;
    return next;
  }

  /// The sound of [generation] has ended (or could not be played): start what waits.
  void _finished(int generation) {
    if (generation != _generation || !_isPlaying) return;
    _isPlaying = false;
    _current = null;
    _currentPlayCompleter?.complete();
    _currentPlayCompleter = null;
    _processQueue();
  }

  void _processQueue() {
    if (_isPlaying || _audioQueue.isEmpty) return;
    _isPlaying = true;
    final task = _audioQueue.removeFirst();
    _current = task;
    _currentPlayCompleter = Completer<void>();
    final gen = _generation;
    final text = task.text;
    if (text != null) {
      speakText(text, onDone: () => _finished(gen));
      return;
    }
    _run(() async {
      if (gen != _generation) return; // hushed before it could start
      try {
        await _playAsset(task.assetPath!);
      } catch (e) {
        debugPrint('Error playing audio: ${task.assetPath} - $e');
        _finished(gen);
      }
    });
  }

  /// Play an asset with platform-specific handling
  /// On web: use UrlSource with direct path (audioplayers AssetSource adds extra 'assets/' prefix)
  /// On native: use AssetSource which works correctly
  Future<void> _playAsset(String assetPath) async {
    if (kIsWeb) {
      // On web, Flutter assets are served from /assets/ folder
      // AssetSource on web incorrectly adds another 'assets/' prefix
      // So we use UrlSource with the correct direct path
      final webPath = 'assets/$assetPath';
      return _player.play(UrlSource(webPath));
    } else {
      // On native platforms, AssetSource works correctly
      return _player.play(AssetSource(assetPath));
    }
  }

  /// The newest wins: stop everything, then start [task].
  Future<void> _sayNow(_AudioTask task) {
    hush();
    _audioQueue.add(task);
    _processQueue();
    return Future.value();
  }

  /// Start [task] once what is playing or waiting has ended.
  Future<void> _sayAfter(_AudioTask task) {
    _audioQueue.add(task);
    _processQueue();
    return Future.value();
  }

  /// A clip: at once ([priority], which stops everything else) or after what is playing.
  Future<void> _enqueue(String assetPath, {bool priority = false}) =>
      priority ? _sayNow(_AudioTask.clip(assetPath)) : _sayAfter(_AudioTask.clip(assetPath));

  /// Stop everything at once: the clip playing, everything waiting, the device's voice.
  Future<void> hush() {
    _generation++;
    _audioQueue.clear();
    _isPlaying = false;
    _current = null;
    _currentPlayCompleter?.complete();
    _currentPlayCompleter = null;
    stopSpeaking();
    return _run(() => _player.stop());
  }

  /// The same as [hush].
  Future<void> stopAll() => hush();

  /// Clear only queued items but let current audio finish
  void clearQueue() {
    _audioQueue.clear();
  }

  /// Wait for the current audio to complete (if any is playing)
  /// Returns immediately if no audio is playing
  Future<void> waitForCurrentAudio() async {
    if (_isPlaying && _currentPlayCompleter != null) {
      await _currentPlayCompleter!.future;
    }
  }

  /// Wait for all queued audio to complete
  Future<void> waitForAllAudio() async {
    while (_isPlaying || _audioQueue.isNotEmpty) {
      if (_currentPlayCompleter != null) {
        await _currentPlayCompleter!.future;
      }
      // Small delay to allow queue processing
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Say something now, stopping everything else: its recorded [clip] if it has one, the
  /// device's voice saying [text] if not.
  Future<void> say(String text, {String? clip}) =>
      _sayNow(clip != null ? _AudioTask.clip(clip) : _AudioTask.speech(text));

  /// Say something once what is playing now has ended: a group's explanation after the
  /// sound that says "right".
  Future<void> sayAfter(String text, {String? clip}) =>
      _sayAfter(clip != null ? _AudioTask.clip(clip) : _AudioTask.speech(text));

  /// Play one specific bundled clip right away (e.g. a recorded animal name), stopping
  /// everything else.
  Future<void> playAsset(String assetPath) => _enqueue(assetPath, priority: true);

  /// Play a clip once whatever is playing or waiting has finished: an explanation after
  /// the sound that says "right".
  Future<void> playAfter(String assetPath) => _enqueue(assetPath);

  // ============ FEEDBACK SOUNDS ============
  
  /// Play a random "correct" sound when a group is solved
  Future<void> playCorrect() async {
    final index = _random.nextInt(8) + 1; // correct_01 to correct_08
    final filename = 'correct_${index.toString().padLeft(2, '0')}.mp3';
    await _enqueue('Assets/audio/feedback/$filename', priority: true);
  }

  /// Play a random "wrong" sound when an incorrect guess is made
  Future<void> playWrong() async {
    final index = _random.nextInt(6) + 1; // wrong_01 to wrong_06
    final filename = 'wrong_${index.toString().padLeft(2, '0')}.mp3';
    await _enqueue('Assets/audio/feedback/$filename', priority: true);
  }

  /// Play a random "one away" sound (3 out of 4 correct)
  Future<void> playOneAway() async {
    final index = _random.nextInt(4) + 1; // oneaway_01 to oneaway_04
    final filename = 'oneaway_${index.toString().padLeft(2, '0')}.mp3';
    await _enqueue('Assets/audio/feedback/$filename', priority: true);
  }

  /// Play a random "victory" sound when all groups are solved
  Future<void> playVictory() async {
    // Victory is high priority - clear queue first
    clearQueue();
    final index = _random.nextInt(5) + 1; // victory_01 to victory_05
    final filename = 'victory_${index.toString().padLeft(2, '0')}.mp3';
    await _enqueue('Assets/audio/feedback/$filename', priority: true);
  }

  /// Play a random "game over" sound
  Future<void> playGameOver() async {
    // Game over is high priority - clear queue first
    clearQueue();
    final index = _random.nextInt(3) + 1; // gameover_01 to gameover_03
    final filename = 'gameover_${index.toString().padLeft(2, '0')}.mp3';
    await _enqueue('Assets/audio/feedback/$filename', priority: true);
  }

  /// Play a random "encourage" sound after mistakes
  Future<void> playEncourage() async {
    final index = _random.nextInt(4) + 1; // encourage_01 to encourage_04
    final filename = 'encourage_${index.toString().padLeft(2, '0')}.mp3';
    await _enqueue('Assets/audio/feedback/$filename');
  }

  /// Play a random "instruction" sound
  Future<void> playInstruction() async {
    final index = _random.nextInt(4) + 1; // instruct_01 to instruct_04
    final filename = 'instruct_${index.toString().padLeft(2, '0')}.mp3';
    await _enqueue('Assets/audio/feedback/$filename');
  }

  // ============ CATEGORY ANNOUNCEMENTS ============
  
  /// Play a category announcement when a group is solved
  /// [categoryKey] should be lowercase like 'bigcat', 'bird', 'prehistoric', etc.
  Future<void> playCategory(String categoryKey) async {
    final normalizedKey = _normalizeCategoryKey(categoryKey);
    // Use 1-2 range since some categories only have 2 audio files
    final index = _random.nextInt(2) + 1; // cat_xxx_01 to cat_xxx_02
    final filename = 'cat_${normalizedKey}_${index.toString().padLeft(2, '0')}.mp3';
    await _enqueue('Assets/audio/categories/$filename');
  }

  // ============ ITEM NAME PRONUNCIATIONS ============
  
  /// Play the pronunciation of an item's name
  /// [itemName] should match the item name (e.g., 'T-Rex', 'Airplane')
  Future<void> playItemName(String itemName) async {
    final normalizedName = _normalizeItemName(itemName);
    final filename = 'name_$normalizedName.mp3';
    // Item names are priority - user just tapped, provide immediate feedback
    await _enqueue('Assets/audio/names/$filename', priority: true);
  }

  // ============ EDUCATIONAL CONTENT ============
  
  /// Play educational content about an item
  /// [itemName] should match the item name
  Future<void> playEducational(String itemName) async {
    final normalizedName = _normalizeItemName(itemName);
    final index = _random.nextInt(3) + 1; // edu_xxx_01 to edu_xxx_03
    final filename = 'edu_${normalizedName}_${index.toString().padLeft(2, '0')}.mp3';
    await _enqueue('Assets/audio/educational/$filename');
  }

  /// Play educational content explaining why an item doesn't belong to a category
  /// [itemName] - the item name
  /// [wrongCategory] - the category it was incorrectly grouped with
  Future<void> playEducationalNot(String itemName, String wrongCategory) async {
    final normalizedName = _normalizeItemName(itemName);
    final normalizedCategory = _normalizeCategoryKey(wrongCategory);
    final filename = 'edu_${normalizedName}_not_$normalizedCategory.mp3';
    await _enqueue('Assets/audio/educational/$filename');
  }

  // ============ LIFELINE SOUNDS ============
  
  /// Play sound when Reveal One lifeline is used
  Future<void> playRevealOne() async {
    final index = _random.nextInt(3) + 1;
    final filename = 'lifeline_reveal_${index.toString().padLeft(2, '0')}.mp3';
    try {
      await _enqueue('Assets/audio/lifelines/$filename', priority: true);
    } catch (e) {
      // Fallback to correct sound if lifeline audio not available
      await playCorrect();
    }
  }

  /// Play sound when Category Hint lifeline is used
  Future<void> playCategoryHint() async {
    final index = _random.nextInt(3) + 1;
    final filename = 'lifeline_hint_${index.toString().padLeft(2, '0')}.mp3';
    try {
      await _enqueue('Assets/audio/lifelines/$filename', priority: true);
    } catch (e) {
      await playInstruction();
    }
  }

  /// Play sound when Freeze lifeline is used
  Future<void> playFreeze() async {
    final index = _random.nextInt(3) + 1;
    final filename = 'lifeline_freeze_${index.toString().padLeft(2, '0')}.mp3';
    try {
      await _enqueue('Assets/audio/lifelines/$filename', priority: true);
    } catch (e) {
      // Silent fallback for freeze
    }
  }

  /// Play sound when Auto-Solve lifeline is used (intro)
  Future<void> playAutoSolve() async {
    final index = _random.nextInt(3) + 1;
    final filename = 'lifeline_solve_${index.toString().padLeft(2, '0')}.mp3';
    try {
      await _enqueue('Assets/audio/lifelines/$filename', priority: true);
    } catch (e) {
      await playCorrect();
    }
  }

  /// Play "finding group" narration during auto-solve
  /// "Let's look for the dinosaurs...", "Can you see the pattern?"
  Future<void> playSolveFinding() async {
    final index = _random.nextInt(2) + 1; // 2 variants
    final filename = 'solve_finding_${index.toString().padLeft(2, '0')}.mp3';
    try {
      await _enqueue('Assets/audio/lifelines/$filename', priority: true);
    } catch (e) {
      // Silent fallback - finding narration is optional
    }
  }

  /// Play confirmation before submitting during auto-solve
  /// "Yes! These belong together!", "That's right, let's submit!"
  Future<void> playSolveConfirm() async {
    final index = _random.nextInt(2) + 1; // 2 variants
    final filename = 'solve_confirm_${index.toString().padLeft(2, '0')}.mp3';
    try {
      await _enqueue('Assets/audio/lifelines/$filename', priority: true);
    } catch (e) {
      // Silent fallback
    }
  }

  // ============ HELPER METHODS ============
  
  /// Normalize item names for file lookup
  String _normalizeItemName(String name) {
    // Handle special cases
    String normalized = name.toLowerCase()
        .replaceAll('-', '')  // T-Rex -> trex
        .replaceAll(' ', '_') // Teddy Bear -> teddy_bear
        .trim();
    return normalized;
  }

  /// Normalize category keys for file lookup
  String _normalizeCategoryKey(String category) {
    // Map display names and categories to audio file keys
    final Map<String, String> categoryMap = {
      // New tag-based categories
      'living': 'living',
      'non-living': 'nonliving',
      'extinct': 'extinct',
      'still alive today': 'stillalive',
      'flies': 'flies',
      'cannot fly': 'nofly',
      'swims': 'swims',
      'cannot swim': 'noswim',
      'meat eaters': 'meateaters',
      'plant eaters': 'planteaters',
      'eats both': 'omnivore',
      'lives on land': 'landanimals',
      'lives in water': 'wateranimals',
      'large': 'large',
      'small': 'small',
      'furry': 'furry',
      'not furry': 'notfurry',
      'made by humans': 'manmade',
      'natural': 'natural',
      'dinosaurs': 'dinosaurs',
      'mammals': 'mammals',
      'birds': 'birds',
      'fish': 'fish_new',
      'insects': 'insects',
      'plants': 'plants',
      'toys': 'toys',
      'transport': 'transport_new',
      'predators': 'predators',
      // Old categories (backward compatibility)
      'big cat': 'bigcat',
      'land animal': 'land',
      'marsupial': 'mammal',
      'bird of prey': 'bird',
      'flightless': 'flightless',
      'tropical': 'bird',
      'bug': 'insect',
      'flying bug': 'flying',
      'pet/freshwater': 'fish',
      'saltwater/freshwater': 'fish',
      'saltwater': 'fish',
      'predator': 'fish',
      'flower': 'flower',
      'tree': 'plant',
      'herb': 'plant',
      'plaything': 'toy',
      'game': 'toy',
      'plush': 'toy',
      'electronic': 'toy',
      'air/land': 'transport',
      'land': 'transport',
      'rail': 'transport',
      'carnivore': 'carnivore',
      'herbivore': 'herbivore',
      'marine reptile': 'marine',
      'flying reptile': 'flying',
      'bird-like': 'bird',
      'snake': 'snake',
      'mammal': 'mammal',
      'bird': 'bird',
      'insect': 'insect',
      'plant': 'plant',
      'toy': 'toy',
      'prehistoric': 'prehistoric',
    };

    final key = category.toLowerCase().trim();
    return categoryMap[key] ?? key.replaceAll(' ', '').replaceAll('-', '');
  }

  /// Dispose of audio players
  void dispose() {
    _audioQueue.clear();
    _player.dispose();
  }
}


/// One thing to be heard: a recorded clip, or words for the device's voice.
class _AudioTask {
  final String? assetPath;
  final String? text;

  _AudioTask.clip(String this.assetPath) : text = null;
  _AudioTask.speech(String this.text) : assetPath = null;
}
