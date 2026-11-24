import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import '../models/entity.dart';
import '../models/dimension.dart';
import '../models/game_settings.dart';
import '../models/group_words.dart';
import 'board_assembler.dart';
import 'live_link.dart';
import 'media.dart';

/// Loads the things and the dictionary from bundled JSON, plus the start settings and
/// which photos / emoji / voice clips exist, and hands back a ready assembler. All of
/// it is made ahead of time; nothing is generated while a child plays.
class ContentRepository {
  late List<Entity> entities;
  late DimensionRegistry registry;
  late GameSettings settings;
  late BoardAssembler assembler;
  MediaResolver media = const MediaResolver.empty();

  /// The clues and the explanation of each group. Empty until they are written.
  GroupWordsBook words = const GroupWordsBook.empty();
  bool _loaded = false;
  Random? _random;

  ContentRepository();

  /// For tests: use in-memory data instead of the asset bundle.
  ContentRepository.fromData(
    List<Entity> ents,
    DimensionRegistry reg,
    GameSettings settings, {
    Random? random,
    MediaResolver media = const MediaResolver.empty(),
    GroupWordsBook words = const GroupWordsBook.empty(),
  }) {
    _set(ents, reg, settings, media, random);
    this.words = words;
  }

  /// The things in a decoded `things.json`, in file order.
  static List<Entity> thingsFromJson(Map<String, dynamic> json) =>
      (json['things'] as Map<String, dynamic>)
          .entries
          .map((e) => Entity.fromJson(e.key, e.value as Map<String, dynamic>))
          .toList();

  void _set(List<Entity> ents, DimensionRegistry reg, GameSettings s, MediaResolver m,
      Random? random) {
    _random = random ?? _random;
    entities = ents;
    registry = reg;
    settings = s;
    media = m;
    assembler = BoardAssembler(ents, reg,
        random: _random, styles: m.styles, heldBack: s.holdBack);
    _loaded = true;
  }

  Future<void> load() async {
    if (_loaded) return;
    Future<Map<String, dynamic>> read(String file) async =>
        json.decode(await rootBundle.loadString('Assets/data/$file')) as Map<String, dynamic>;
    final things = thingsFromJson(await read('things.json'));
    final reg = DimensionRegistry.fromJson(await read('dictionary.json'));
    final s = GameSettings.fromJson(await read('settings.json'));
    _set(things, reg, s, await MediaResolver.load(), null);
    try {
      words = GroupWordsBook.fromJson(await read('groups.json'));
    } catch (_) {
      // no words yet: the game plays without clues and explanations
    }
  }

  /// Take the data as it stands now on the owner's PC, through the helper: the same
  /// files, read fresh, with whatever sets were made while he played (the owner's design
  /// of 24 Nov 2026: one game, dynamic data). False, and nothing changed, if any of it
  /// could not be read: the game then goes on with what it has.
  Future<bool> loadLive(LiveLink link, LiveState state) async {
    try {
      Future<Map<String, dynamic>?> read(String file) async {
        final text = await link.read('Assets/data/$file');
        return text == null ? null : json.decode(text) as Map<String, dynamic>;
      }

      final things = await read('things.json');
      final dictionary = await read('dictionary.json');
      final start = await read('settings.json');
      final pictures = await read('pictures.json');
      if (things == null || dictionary == null || start == null || pictures == null) return false;
      final book = await read('groups.json');
      _set(thingsFromJson(things), DimensionRegistry.fromJson(dictionary), GameSettings.fromJson(start),
          MediaResolver.fromJson(state.files, pictures), null);
      if (book != null) words = GroupWordsBook.fromJson(book);
      return true;
    } catch (_) {
      return false;
    }
  }
}
