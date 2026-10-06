import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import '../models/entity.dart';
import '../models/dimension.dart';
import '../models/game_settings.dart';
import 'board_assembler.dart';
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
  bool _loaded = false;

  ContentRepository();

  /// For tests: use in-memory data instead of the asset bundle.
  ContentRepository.fromData(
    List<Entity> ents,
    DimensionRegistry reg,
    GameSettings settings, {
    Random? random,
    MediaResolver media = const MediaResolver.empty(),
  }) {
    _set(ents, reg, settings, media, random);
  }

  /// The things in a decoded `things.json`, in file order.
  static List<Entity> thingsFromJson(Map<String, dynamic> json) =>
      (json['things'] as Map<String, dynamic>)
          .entries
          .map((e) => Entity.fromJson(e.key, e.value as Map<String, dynamic>))
          .toList();

  void _set(List<Entity> ents, DimensionRegistry reg, GameSettings s, MediaResolver m,
      Random? random) {
    entities = ents;
    registry = reg;
    settings = s;
    media = m;
    // Favour things that have a picture so a board never gives a group away by
    // mixing picture tiles with bare-text tiles.
    assembler = BoardAssembler(ents, reg, random: random, preferred: m.hasPicture);
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
  }
}
