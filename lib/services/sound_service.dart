import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:math';
import 'dart:async';
import 'dart:collection';

/// Comprehensive sound service for the Connections game.
/// Handles all audio playback including feedback sounds, category announcements,
/// item name pronunciations, and educational content.
/// 
/// Features a queueing system to ensure no two audio files play simultaneously.
/// Includes web-specific handling for browser autoplay policies.
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal() {
    _initPlayer();
  }

  final AudioPlayer _player = AudioPlayer();
  final Random _random = Random();
  
  // Audio queue system
  final Queue<_AudioTask> _audioQueue = Queue<_AudioTask>();
  bool _isPlaying = false;
  Completer<void>? _currentPlayCompleter;
  
  // Web-specific: Track if user has interacted (required for autoplay)
  bool _userHasInteracted = false;

  void _initPlayer() {
    // Listen for when audio completes to play next in queue
    _player.onPlayerComplete.listen((_) {
      _onAudioComplete();
    });
    
    // Also handle errors
    _player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.stopped || state == PlayerState.completed) {
        // Already handled by onPlayerComplete
      }
    });
    
    // Set audio context for web - log mode for debugging
    if (kIsWeb) {
      _player.setReleaseMode(ReleaseMode.stop);
    }
  }
  
  /// Call this when user interacts with the app (tap, click, etc.)
  /// This unlocks audio playback on web browsers.
  void notifyUserInteraction() {
    if (!_userHasInteracted) {
      _userHasInteracted = true;
      // On web, try to "warm up" the audio context with a silent play
      if (kIsWeb) {
        _player.setVolume(0);
        _playAsset('Assets/audio/feedback/correct_01.mp3').then((_) {
          _player.stop();
          _player.setVolume(1.0);
        }).catchError((_) {
          _player.setVolume(1.0);
        });
      }
    }
  }

  void _onAudioComplete() {
    _isPlaying = false;
    _currentPlayCompleter?.complete();
    _currentPlayCompleter = null;
    _processQueue();
  }

  /// Add an audio task to the queue and start processing if not already playing
  Future<void> _enqueue(String assetPath, {bool priority = false}) async {
    final task = _AudioTask(assetPath);
    
    if (priority) {
      // Priority items go to front of queue (but after currently playing)
      final currentTasks = _audioQueue.toList();
      _audioQueue.clear();
      _audioQueue.add(task);
      _audioQueue.addAll(currentTasks);
    } else {
      _audioQueue.add(task);
    }
    
    _processQueue();
  }

  /// Process the next item in the queue
  void _processQueue() {
    if (_isPlaying || _audioQueue.isEmpty) return;
    
    _isPlaying = true;
    final task = _audioQueue.removeFirst();
    
    _currentPlayCompleter = Completer<void>();
    
    _playAsset(task.assetPath).catchError((e) {
      print('Error playing audio: ${task.assetPath} - $e');
      _onAudioComplete();
    });
  }
  
  /// Play an asset - audioplayers handles platform differences internally
  Future<void> _playAsset(String assetPath) async {
    // AssetSource works for all platforms including web
    // The audioplayers package handles the platform-specific asset loading
    return _player.play(AssetSource(assetPath));
  }

  /// Clear the queue and stop current audio
  Future<void> stopAll() async {
    _audioQueue.clear();
    await _player.stop();
    _isPlaying = false;
    _currentPlayCompleter?.complete();
    _currentPlayCompleter = null;
  }

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
    final index = _random.nextInt(3) + 1; // cat_xxx_01 to cat_xxx_03 (usually)
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

/// Internal class to represent an audio task in the queue
class _AudioTask {
  final String assetPath;
  
  _AudioTask(this.assetPath);
}
