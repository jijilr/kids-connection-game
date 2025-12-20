import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_item.dart';
import '../services/asset_service.dart';

class GameProvider extends ChangeNotifier {
  final AssetService _assetService = AssetService();

  List<GameItem> _currentItems = [];
  final List<GameItem> _selectedItems = [];
  final List<GameGroup> _solvedGroups = [];
  List<GameGroup> _targetGroups = []; // The solution
  
  int _mistakes = 0;
  final int _maxMistakes = 4;
  bool _isLoading = false;
  bool _isGameOver = false;
  bool _isVictory = false;

  // ============ SCORING SYSTEM ============
  int _currentScore = 0;
  int _highScore = 0;
  int _streak = 0; // Consecutive correct guesses
  int _totalGamesPlayed = 0;
  int _totalGamesWon = 0;
  
  // Score values
  static const int _baseGroupScore = 100;
  static const int _streakBonus = 50;
  static const int _perfectGameBonus = 500;
  static const int _mistakePenalty = 25;
  static const int _lifelinePenalty = 50; // Points lost when using lifeline

  // ============ LIFELINES ============
  int _revealOneRemaining = 1;
  int _categoryHintRemaining = 2;
  int _freezeRemaining = 1;
  int _autoSolveRemaining = 1;
  
  bool _freezeActive = false;
  Set<String> _revealedItemIds = {};
  String? _activeHint;

  List<GameItem> get currentItems => _currentItems;
  List<GameItem> get selectedItems => _selectedItems;
  List<GameGroup> get solvedGroups => _solvedGroups;
  int get mistakes => _mistakes;
  int get maxMistakes => _maxMistakes;
  bool get isLoading => _isLoading;
  bool get isGameOver => _isGameOver;
  bool get isVictory => _isVictory;
  
  // Score getters
  int get currentScore => _currentScore;
  int get highScore => _highScore;
  int get streak => _streak;
  int get totalGamesPlayed => _totalGamesPlayed;
  int get totalGamesWon => _totalGamesWon;
  
  // Lifeline getters
  int get revealOneRemaining => _revealOneRemaining;
  int get categoryHintRemaining => _categoryHintRemaining;
  int get freezeRemaining => _freezeRemaining;
  int get autoSolveRemaining => _autoSolveRemaining;
  bool get freezeActive => _freezeActive;
  Set<String> get revealedItemIds => _revealedItemIds;
  String? get activeHint => _activeHint;

  GameProvider() {
    _loadHighScore();
  }

  Future<void> _loadHighScore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _highScore = prefs.getInt('highScore') ?? 0;
      _totalGamesPlayed = prefs.getInt('totalGamesPlayed') ?? 0;
      _totalGamesWon = prefs.getInt('totalGamesWon') ?? 0;
      notifyListeners();
    } catch (e) {
      print("Error loading high score: $e");
    }
  }

  Future<void> _saveStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('highScore', _highScore);
      await prefs.setInt('totalGamesPlayed', _totalGamesPlayed);
      await prefs.setInt('totalGamesWon', _totalGamesWon);
    } catch (e) {
      print("Error saving stats: $e");
    }
  }

  Future<void> startNewGame() async {
    _isLoading = true;
    _isGameOver = false;
    _isVictory = false;
    _mistakes = 0;
    _currentScore = 0;
    _streak = 0;
    _solvedGroups.clear();
    _selectedItems.clear();
    
    // Reset lifelines
    _revealOneRemaining = 1;
    _categoryHintRemaining = 2;
    _freezeRemaining = 1;
    _autoSolveRemaining = 1;
    _freezeActive = false;
    _revealedItemIds.clear();
    _activeHint = null;
    
    notifyListeners();

    try {
      _targetGroups = await _assetService.generateLevel();
      
      // DEBUG: Print the 4 target groups
      print("=== NEW GAME GENERATED ===");
      for (int i = 0; i < _targetGroups.length; i++) {
        final g = _targetGroups[i];
        print("Group ${i+1}: ${g.displayName}");
        print("  Items: ${g.items.map((item) => item.name).join(', ')}");
      }
      print("==========================");
      
      // Flatten groups to get all items (use copy to get fresh instances)
      _currentItems = [];
      for (var group in _targetGroups) {
        for (var item in group.items) {
          _currentItems.add(item.copy());
        }
      }
      
      _currentItems.shuffle();
    } catch (e) {
      print("Error starting game: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void toggleSelection(GameItem item) {
    if (_isGameOver || _solvedGroups.any((g) => g.items.any((i) => i.id == item.id))) return;

    if (_selectedItems.any((i) => i.id == item.id)) {
      _selectedItems.removeWhere((i) => i.id == item.id);
      item.isSelected = false;
    } else {
      if (_selectedItems.length < 4) {
        _selectedItems.add(item);
        item.isSelected = true;
      }
    }
    notifyListeners();
  }

  void deselectAll() {
    for (var item in _selectedItems) {
      item.isSelected = false;
    }
    _selectedItems.clear();
    notifyListeners();
  }

  void shuffleItems() {
    List<GameItem> unsolved = _currentItems.where((item) => !item.isSolved).toList();
    unsolved.shuffle();
    _currentItems = unsolved;
    notifyListeners();
  }

  Future<void> submitSelection() async {
    if (_selectedItems.length != 4) return;

    bool isCorrect = false;
    GameGroup? matchedGroup;

    for (var group in _targetGroups) {
      List<String> groupIds = group.items.map((i) => i.id).toList();
      List<String> selectedIds = _selectedItems.map((i) => i.id).toList();
      
      if (selectedIds.every((id) => groupIds.contains(id))) {
        isCorrect = true;
        matchedGroup = group;
        break;
      }
    }

    if (isCorrect) {
      _streak++;
      
      int groupScore = _baseGroupScore;
      groupScore += _streakBonus * (_streak - 1);
      _currentScore += groupScore;
      
      for (var item in _selectedItems) {
        item.isSolved = true;
        item.isSelected = false;
      }
      
      _solvedGroups.add(matchedGroup!);
      _currentItems.removeWhere((item) => item.isSolved);
      _selectedItems.clear();
      _activeHint = null; // Clear hint after solving
      
      if (_solvedGroups.length == 4) {
        _isVictory = true;
        _isGameOver = true;
        
        if (_mistakes == 0) {
          _currentScore += _perfectGameBonus;
        }
        
        _totalGamesPlayed++;
        _totalGamesWon++;
        
        if (_currentScore > _highScore) {
          _highScore = _currentScore;
        }
        
        _saveStats();
      }
    } else {
      // Check if freeze is active
      if (_freezeActive) {
        _freezeActive = false; // Use up the freeze
      } else {
        _mistakes++;
      }
      
      _streak = 0;
      _currentScore = (_currentScore - _mistakePenalty).clamp(0, 999999);
      
      if (_mistakes >= _maxMistakes) {
        _isGameOver = true;
        _totalGamesPlayed++;
        _saveStats();
      }
    }
    notifyListeners();
  }
  
  // ============ LIFELINES ============
  
  /// Reveal One: Highlights one correct item from each unsolved group
  bool useRevealOne() {
    if (_revealOneRemaining <= 0 || _isGameOver) return false;
    
    _revealOneRemaining--;
    _currentScore = (_currentScore - _lifelinePenalty).clamp(0, 999999);
    
    // Get unsolved groups
    List<GameGroup> unsolvedGroups = _targetGroups.where((group) {
      return !_solvedGroups.any((solved) => 
          solved.groupingKey == group.groupingKey && 
          solved.groupingValue == group.groupingValue);
    }).toList();
    
    // Reveal one item from each unsolved group
    for (var group in unsolvedGroups) {
      // Find an item from this group that's still in currentItems
      for (var groupItem in group.items) {
        if (_currentItems.any((i) => i.id == groupItem.id)) {
          _revealedItemIds.add(groupItem.id);
          break; // Only reveal one per group
        }
      }
    }
    
    notifyListeners();
    return true;
  }
  
  /// Category Hint: Shows the category name for a random unsolved group
  bool useCategoryHint() {
    if (_categoryHintRemaining <= 0 || _isGameOver) return false;
    
    _categoryHintRemaining--;
    _currentScore = (_currentScore - _lifelinePenalty).clamp(0, 999999);
    
    // Get unsolved groups
    List<GameGroup> unsolvedGroups = _targetGroups.where((group) {
      return !_solvedGroups.any((solved) => 
          solved.groupingKey == group.groupingKey && 
          solved.groupingValue == group.groupingValue);
    }).toList();
    
    if (unsolvedGroups.isNotEmpty) {
      unsolvedGroups.shuffle();
      _activeHint = "Look for: ${unsolvedGroups.first.displayName}";
    }
    
    notifyListeners();
    return true;
  }
  
  /// Freeze: Next wrong answer doesn't count
  bool useFreeze() {
    if (_freezeRemaining <= 0 || _isGameOver || _freezeActive) return false;
    
    _freezeRemaining--;
    _freezeActive = true;
    // No score penalty for freeze - it's defensive
    
    notifyListeners();
    return true;
  }
  
  /// Auto-Solve: Triggers solving ALL remaining groups (animated from UI)
  /// Returns the number of unsolved groups to solve
  int useAutoSolveAll() {
    if (_autoSolveRemaining <= 0 || _isGameOver) return 0;
    
    _autoSolveRemaining--;
    _currentScore = (_currentScore - _lifelinePenalty * 3).clamp(0, 999999); // Triple penalty for solving all
    
    // Get count of unsolved groups
    int unsolvedCount = _targetGroups.where((group) {
      return !_solvedGroups.any((solved) => 
          solved.groupingKey == group.groupingKey && 
          solved.groupingValue == group.groupingValue);
    }).length;
    
    notifyListeners();
    return unsolvedCount;
  }
  
  /// Get the next unsolved group (for preview/animation) without solving it
  GameGroup? getNextUnsolvedGroup() {
    List<GameGroup> unsolvedGroups = _targetGroups.where((group) {
      return !_solvedGroups.any((solved) => 
          solved.groupingKey == group.groupingKey && 
          solved.groupingValue == group.groupingValue);
    }).toList();
    
    if (unsolvedGroups.isEmpty) return null;
    return unsolvedGroups.first;
  }
  
  /// Solve exactly one unsolved group (called by UI animation)
  /// Returns the solved group or null if none left
  GameGroup? solveNextGroup() {
    // Get unsolved groups
    List<GameGroup> unsolvedGroups = _targetGroups.where((group) {
      return !_solvedGroups.any((solved) => 
          solved.groupingKey == group.groupingKey && 
          solved.groupingValue == group.groupingValue);
    }).toList();
    
    if (unsolvedGroups.isEmpty) return null;
    
    // Solve the first unsolved group
    GameGroup groupToSolve = unsolvedGroups.first;
    
    // Mark all items from this group as solved
    for (var groupItem in groupToSolve.items) {
      for (var currentItem in _currentItems) {
        if (currentItem.id == groupItem.id) {
          currentItem.isSolved = true;
          currentItem.isSelected = false;
        }
      }
    }
    
    // Deselect all
    for (var item in _selectedItems) {
      item.isSelected = false;
    }
    _selectedItems.clear();
    
    // Add to solved and remove from current
    _solvedGroups.add(groupToSolve);
    _currentItems.removeWhere((item) => item.isSolved);
    
    // Check for victory
    if (_solvedGroups.length == 4) {
      _isVictory = true;
      _isGameOver = true;
      _totalGamesPlayed++;
      _totalGamesWon++;
      if (_currentScore > _highScore) {
        _highScore = _currentScore;
      }
      _saveStats();
    }
    
    notifyListeners();
    return groupToSolve;
  }
  
  /// Clear the active hint
  void clearHint() {
    _activeHint = null;
    notifyListeners();
  }
  
  // Helper to check "One Away"
  bool isOneAway() {
    if (_selectedItems.length != 4) return false;
    
    for (var group in _targetGroups) {
      List<String> groupIds = group.items.map((i) => i.id).toList();
      List<String> selectedIds = _selectedItems.map((i) => i.id).toList();
      
      int matchCount = 0;
      for (var id in selectedIds) {
        if (groupIds.contains(id)) matchCount++;
      }
      
      if (matchCount == 3) return true;
    }
    return false;
  }
  
  String getGameRating() {
    if (!_isVictory) return '';
    
    if (_mistakes == 0) {
      return '⭐⭐⭐ PERFECT!';
    } else if (_mistakes == 1) {
      return '⭐⭐ GREAT!';
    } else if (_mistakes <= 2) {
      return '⭐ GOOD!';
    } else {
      return 'COMPLETED!';
    }
  }
}
