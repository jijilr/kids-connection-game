import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/game_item.dart';
import 'dart:math';

class AssetService {
  List<GameItem>? _cachedItems;
  Map<String, GroupingDefinition>? _cachedGroupings;

  /// Load all items from JSON
  Future<List<GameItem>> loadItems() async {
    if (_cachedItems != null) return _cachedItems!;
    
    try {
      final String rawData = await rootBundle.loadString('Assets/items_classification.json');
      final Map<String, dynamic> jsonData = json.decode(rawData);
      
      final List<dynamic> itemsJson = jsonData['items'] as List<dynamic>;
      _cachedItems = itemsJson
          .map((item) => GameItem.fromJson(item as Map<String, dynamic>))
          .toList();
      
      if (jsonData.containsKey('groupings')) {
        _cachedGroupings = {};
        final Map<String, dynamic> groupingsJson = jsonData['groupings'] as Map<String, dynamic>;
        groupingsJson.forEach((key, value) {
          _cachedGroupings![key] = GroupingDefinition.fromJson(key, value as Map<String, dynamic>);
        });
      }
      
      return _cachedItems!;
    } catch (e) {
      print("Error loading JSON: $e");
      return [];
    }
  }

  Future<Map<String, GroupingDefinition>> getGroupings() async {
    if (_cachedGroupings == null) {
      await loadItems();
    }
    return _cachedGroupings ?? {};
  }

  // ============ GROUPING CONFLICT RULES ============
  // These groups conflict with each other (can't both appear in same game)
  static final List<Set<String>> _conflictGroups = [
    // Dinosaur-related conflicts
    {'category:dinosaur', 'extinct:true', 'reptile:true'},
    // Living things conflicts
    {'category:mammal', 'category:bird', 'category:fish', 'category:insect', 'category:plant'},
    // Non-living conflicts
    {'category:toy', 'category:transport', 'man_made:true', 'living:false'},
    // Ability conflicts (a swimmer might also fly, etc.)
    {'flies:true', 'swims:true'},
  ];

  /// Check if a new group would conflict with already selected groups
  bool _hasConflict(String newGroupKey, List<String> existingKeys) {
    for (var conflictSet in _conflictGroups) {
      if (conflictSet.contains(newGroupKey)) {
        // Check if any existing key is in the same conflict set
        for (var existing in existingKeys) {
          if (conflictSet.contains(existing) && existing != newGroupKey) {
            return true; // Conflict found!
          }
        }
      }
    }
    return false;
  }

  /// Generates a random game level with 4 groups of 4 items each.
  /// Uses ONLY main category-based groups for simplicity and clarity.
  Future<List<GameGroup>> generateLevel() async {
    final allItems = await loadItems();
    final random = Random();
    
    // SIMPLE APPROACH: Only use main categories (no overlap possible)
    // This guarantees no confusing overlaps
    List<String> availableCategories = [
      'dinosaur', 'mammal', 'bird', 'fish', 'insect', 'plant', 'toy', 'transport'
    ];
    
    // Check which categories have at least 4 items
    Map<String, List<GameItem>> categoryItems = {};
    for (var category in availableCategories) {
      List<GameItem> items = allItems.where((item) => 
          item.hasTag('category', category)).toList();
      if (items.length >= 4) {
        categoryItems[category] = items;
      }
    }
    
    if (categoryItems.length < 4) {
      throw Exception("Not enough categories with 4+ items.");
    }
    
    // Select 4 random categories
    List<String> selectedCategories = categoryItems.keys.toList();
    selectedCategories.shuffle(random);
    selectedCategories = selectedCategories.take(4).toList();
    
    // Build the groups
    List<GameGroup> levelGroups = [];
    List<String> colors = ['0xFFE74C3C', '0xFF3498DB', '0xFFF1C40F', '0xFF9B59B6'];
    
    for (int i = 0; i < selectedCategories.length; i++) {
      String category = selectedCategories[i];
      List<GameItem> items = categoryItems[category]!;
      items.shuffle(random);
      
      List<GameItem> selectedItems = items.take(4).map((i) => i.copy()).toList();
      
      levelGroups.add(GameGroup(
        groupingKey: 'category',
        groupingValue: category,
        displayName: _getDisplayName(category),
        items: selectedItems,
        colorHex: colors[i],
      ));
    }
    
    return levelGroups;
  }
  
  /// Get human-readable display name for a category
  String _getDisplayName(String category) {
    final Map<String, String> displayNames = {
      'dinosaur': 'Dinosaurs',
      'mammal': 'Mammals',
      'bird': 'Birds',
      'fish': 'Fish',
      'insect': 'Insects',
      'plant': 'Plants',
      'toy': 'Toys',
      'transport': 'Transport',
      'reptile': 'Reptiles',
    };
    
    return displayNames[category] ?? category;
  }
}

/// Internal class to represent a grouping strategy
class _GroupingStrategy {
  final String key;
  final dynamic value;
  final String displayName;
  final int count;
  
  _GroupingStrategy({
    required this.key,
    required this.value,
    required this.displayName,
    required this.count,
  });
}
