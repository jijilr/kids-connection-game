import 'dart:convert';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import '../models/entity.dart';

/// What we can show and play for one thing. Any field may be null.
class EntityMedia {
  final String? art; // a tile drawn for this game and approved, e.g. Assets/pictures/lotus.webp
  final String? image; // an older bundled photo, e.g. Assets/lion_1.png
  final String? emoji; // fallback picture when there is neither
  final String? audio; // recorded name clip, e.g. Assets/audio/names/name_lion.mp3
  const EntityMedia({this.art, this.image, this.emoji, this.audio});

  bool get hasPicture => art != null || image != null || emoji != null;
}

/// Resolves photos, emoji and recorded voice clips for things. Uses the real asset
/// manifest, so it only ever points at files that actually ship with the app. Which
/// emoji a thing uses comes from `pictures.json`, not from code.
class MediaResolver {
  final Set<String> _assets;
  final Map<String, String> _emoji;

  /// Things whose old picture / clip was saved under a different name.
  final Map<String, String> _fileNames;

  const MediaResolver(
    this._assets, {
    Map<String, String> emoji = const {},
    Map<String, String> fileNames = const {},
  })  : _emoji = emoji,
        _fileNames = fileNames;

  const MediaResolver.empty()
      : _assets = const {},
        _emoji = const {},
        _fileNames = const {};

  /// [pictures] is the decoded `pictures.json`.
  factory MediaResolver.fromJson(Set<String> assets, Map<String, dynamic> pictures) =>
      MediaResolver(
        assets,
        emoji: Map<String, String>.from((pictures['emoji'] as Map?) ?? const {}),
        fileNames: Map<String, String>.from((pictures['file_names'] as Map?) ?? const {}),
      );

  static Future<MediaResolver> load() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final pictures = await rootBundle.loadString('Assets/data/pictures.json');
      return MediaResolver.fromJson(
          manifest.listAssets().toSet(), json.decode(pictures) as Map<String, dynamic>);
    } catch (_) {
      return const MediaResolver.empty();
    }
  }

  EntityMedia forEntity(Entity e) {
    final key = _fileNames[e.id] ?? e.id;
    final art = 'Assets/pictures/${e.id}.webp';
    final img = 'Assets/${key}_1.png';
    final aud = 'Assets/audio/names/name_$key.mp3';
    return EntityMedia(
      art: _assets.contains(art) ? art : null,
      image: _assets.contains(img) ? img : null,
      emoji: _emoji[e.id],
      audio: _assets.contains(aud) ? aud : null,
    );
  }

  bool hasPicture(Entity e) => forEntity(e).hasPicture;

  /// The ways a tile can be drawn, best first. A board is drawn in one of them
  /// throughout (see [BoardAssembler.styles]); [inStyle] takes the index.
  List<bool Function(Entity)> get styles => [
        (e) => forEntity(e).art != null,
        (e) => forEntity(e).image != null,
        (e) => forEntity(e).emoji != null,
      ];

  /// What to show for [e] on a board drawn in [style] — only that style's picture, or
  /// none at all when the board shows names only. The voice clip is kept either way.
  EntityMedia inStyle(Entity e, int? style) {
    final m = forEntity(e);
    return EntityMedia(
      art: style == 0 ? m.art : null,
      image: style == 1 ? m.image : null,
      emoji: style == 2 ? m.emoji : null,
      audio: m.audio,
    );
  }
}
