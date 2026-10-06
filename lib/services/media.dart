import 'dart:convert';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import '../models/entity.dart';

/// What we can show and play for one thing. Any field may be null.
class EntityMedia {
  final String? image; // bundled photo, e.g. Assets/lion_1.png
  final String? emoji; // fallback picture when there is no photo
  final String? audio; // recorded name clip, e.g. Assets/audio/names/name_lion.mp3
  const EntityMedia({this.image, this.emoji, this.audio});

  bool get hasPicture => image != null || emoji != null;
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
    final img = 'Assets/${key}_1.png';
    final aud = 'Assets/audio/names/name_$key.mp3';
    return EntityMedia(
      image: _assets.contains(img) ? img : null,
      emoji: _emoji[e.id],
      audio: _assets.contains(aud) ? aud : null,
    );
  }

  bool hasPicture(Entity e) => forEntity(e).hasPicture;
}
