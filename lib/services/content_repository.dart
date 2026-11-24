import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import '../models/entity.dart';
import '../models/dimension.dart';
import '../models/game_settings.dart';
import '../models/group_words.dart';
import '../models/places_map.dart';
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

  /// The map of every place: what there is, what is asked where, what lies in what. The
  /// game reads it and works out nothing about places for itself.
  PlacesMap places = PlacesMap.empty();

  // Things stored by place (the map of places, step 5). A phone cannot load every thing
  // there is. So the game starts with the things of the first place only, and takes up
  // the small file of another place when it goes there. However large the game grows, what
  // a device holds is what it has visited. In a test, with all the things given at once,
  // none of this is used.
  final Set<String> _placesLoaded = {};
  final Map<String, Entity> _held = {};
  LiveLink? _link;
  bool _byPlace = false;

  /// The things are being taken up place by place, not all at once.
  bool get byPlace => _byPlace;

  /// Whether the things a set at [place] needs are here. Always true where the things
  /// were given whole.
  bool has(String place) =>
      !_byPlace || _placesLoaded.contains(place) || places[place]?.thingsFile == null;

  /// How many places' things have been taken up so far.
  int get placesLoaded => _placesLoaded.length;

  Future<String?> _readData(String file) async {
    final link = _link;
    if (link != null) return link.read('Assets/data/$file');
    try {
      return await rootBundle.loadString('Assets/data/$file');
    } catch (_) {
      return null;
    }
  }

  /// The things in a place's file, or null if it cannot be read or was written at another
  /// moment than the map.
  Future<Map<String, Entity>?> _thingsOf(String place) async {
    final file = places[place]?.thingsFile;
    if (file == null) return const {};
    final text = await _readData(file);
    if (text == null) return null;
    final data = json.decode(text) as Map<String, dynamic>;
    if ('${data['stamp']}' != places.stamp) return null;
    return {
      for (final e in (data['things'] as Map<String, dynamic>).entries)
        e.key: Entity.fromJson(e.key, e.value as Map<String, dynamic>)
    };
  }

  /// Take up the things of [place], if they are not here yet. False if they could not be
  /// read; the game then stays where it is.
  Future<bool> ensure(String place) async {
    if (has(place)) return true;
    try {
      final more = await _thingsOf(place);
      if (more == null) return false;
      _held.addAll(more);
      _placesLoaded.add(place);
      _set(_held.values.toList(), registry, settings, media, null);
      return true;
    } catch (_) {
      return false;
    }
  }
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
    PlacesMap? places,
  }) {
    _set(ents, reg, settings, media, random);
    this.words = words;
    if (places != null) this.places = places;
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
    final reg = DimensionRegistry.fromJson(await read('dictionary.json'));
    final s = GameSettings.fromJson(await read('settings.json'));
    try {
      places = PlacesMap.fromJson(await read('places.json'));
    } catch (_) {
      // no map: the game can play its first set, and nothing beyond it
    }
    final pictures = await MediaResolver.load();
    final first = places.byPlace ? await _thingsOf('seed') : null;
    if (first != null) {
      // the things of the first place only; the rest come as he goes
      _held
        ..clear()
        ..addAll(first);
      _placesLoaded
        ..clear()
        ..add('seed');
      _byPlace = true;
      _set(_held.values.toList(), reg, s, pictures, null);
    } else {
      // no files by place, or the first could not be read: every thing at once, as before
      _byPlace = false;
      _set(thingsFromJson(await read('things.json')), reg, s, pictures, null);
    }
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

      final dictionary = await read('dictionary.json');
      final start = await read('settings.json');
      final pictures = await read('pictures.json');
      final map = await read('places.json');
      if (dictionary == null || start == null || pictures == null || map == null) return false;
      // The map and the things are written a moment apart. A map built for another number
      // of things was read in between: nothing is taken up, and the next look tries again.
      final fresh = PlacesMap.fromJson(map);
      final book = await read('groups.json');
      if (fresh.byPlace) {
        // Things by place: the places he has been to are read again, each from its own file,
        // and every file must carry the map's own mark, or nothing is taken up.
        final before = (places: places, link: _link);
        places = fresh;
        _link = link;
        final again = <String, Entity>{};
        final been = {'seed', ..._placesLoaded}.where((id) => fresh[id]?.thingsFile != null).toList();
        for (final id in been) {
          final its = await _thingsOf(id);
          if (its == null) {
            places = before.places;
            _link = before.link;
            return false;
          }
          again.addAll(its);
        }
        _held
          ..clear()
          ..addAll(again);
        _placesLoaded
          ..clear()
          ..addAll(been);
        _byPlace = true;
        _set(_held.values.toList(), DimensionRegistry.fromJson(dictionary), GameSettings.fromJson(start),
            MediaResolver.fromJson(state.files, pictures), null);
      } else {
        // no files by place: every thing at once, as before
        final things = await read('things.json');
        if (things == null) return false;
        final list = thingsFromJson(things);
        if (fresh.things != list.length) return false;
        _byPlace = false;
        _link = link;
        _set(list, DimensionRegistry.fromJson(dictionary), GameSettings.fromJson(start),
            MediaResolver.fromJson(state.files, pictures), null);
        places = fresh;
      }
      if (book != null) words = GroupWordsBook.fromJson(book);
      return true;
    } catch (_) {
      return false;
    }
  }
}
