/// Represents a game item with flexible tag-based classification
class GameItem {
  final String id;
  final String name;
  final String filename;
  final Map<String, dynamic> tags;
  bool isSelected;
  bool isSolved;

  GameItem({
    required this.id,
    required this.name,
    required this.filename,
    required this.tags,
    this.isSelected = false,
    this.isSolved = false,
  });

  String get imagePath => 'Assets/$filename';

  /// Check if this item has a specific tag with a specific value
  bool hasTag(String tagName, dynamic value) {
    return tags.containsKey(tagName) && tags[tagName] == value;
  }

  /// Check if this item has a tag (for boolean tags)
  bool hasTagTrue(String tagName) {
    return tags.containsKey(tagName) && tags[tagName] == true;
  }

  /// Get a tag value
  dynamic getTag(String tagName) {
    return tags[tagName];
  }

  /// Create from JSON
  factory GameItem.fromJson(Map<String, dynamic> json) {
    return GameItem(
      id: json['id'] as String,
      name: json['name'] as String,
      filename: json['filename'] as String,
      tags: Map<String, dynamic>.from(json['tags'] as Map),
    );
  }

  @override
  String toString() {
    return 'GameItem(id: $id, name: $name)';
  }

  /// Create a copy of this item for game state
  GameItem copy() {
    return GameItem(
      id: id,
      name: name,
      filename: filename,
      tags: Map<String, dynamic>.from(tags),
      isSelected: false,
      isSolved: false,
    );
  }
}

/// Represents a group of items that share a common trait
class GameGroup {
  final String groupingKey;      // The tag used for grouping (e.g., "extinct", "flies")
  final dynamic groupingValue;   // The value of that tag (e.g., true, "carnivore")
  final String displayName;      // Human-readable name for this group
  final List<GameItem> items;
  final String colorHex;

  GameGroup({
    required this.groupingKey,
    required this.groupingValue,
    required this.displayName,
    required this.items,
    required this.colorHex,
  });
}

/// Defines a possible grouping strategy
class GroupingDefinition {
  final String key;
  final String displayName;
  final String description;
  final bool isBooleanGroup;
  final String? trueLabel;
  final String? falseLabel;
  final Map<String, String>? valueLabels;

  GroupingDefinition({
    required this.key,
    required this.displayName,
    this.description = '',
    this.isBooleanGroup = true,
    this.trueLabel,
    this.falseLabel,
    this.valueLabels,
  });

  factory GroupingDefinition.fromJson(String key, Map<String, dynamic> json) {
    bool isBoolean = json.containsKey('true_label');
    return GroupingDefinition(
      key: key,
      displayName: json['display_name'] as String,
      description: json['description'] as String? ?? '',
      isBooleanGroup: isBoolean,
      trueLabel: json['true_label'] as String?,
      falseLabel: json['false_label'] as String?,
      valueLabels: json['values'] != null 
          ? Map<String, String>.from(json['values'] as Map)
          : null,
    );
  }
}
