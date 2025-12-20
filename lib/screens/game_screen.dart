import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';
import '../providers/game_provider.dart';
import '../widgets/item_card.dart';
import '../widgets/solved_group_card.dart';
import '../services/sound_service.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({Key? key}) : super(key: key);

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final SoundService _soundService = SoundService();
  bool _hasPlayedGameOverSound = false;
  bool _isSolvingAll = false; // Flag for animated solve

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<GameProvider>(context, listen: false).startNewGame();
    });
  }

  @override
  void dispose() {
    _soundService.dispose();
    super.dispose();
  }

  void _onItemTap(GameProvider game, item) {
    _soundService.playItemName(item.name);
    game.toggleSelection(item);
  }



  /// Animate solving all remaining groups one by one - HUMAN PACE
  Future<void> _animatedSolveAll(GameProvider game) async {
    if (_isSolvingAll) return;
    
    int groupsToSolve = game.useAutoSolveAll();
    if (groupsToSolve == 0) return;
    
    setState(() => _isSolvingAll = true);
    
    // Play initial "Let me help you" audio
    _soundService.playAutoSolve();
    
    // Wait for the intro sound
    await Future.delayed(const Duration(milliseconds: 3000));
    
    // Solve each group with human-like pacing
    for (int i = 0; i < groupsToSolve; i++) {
      if (!mounted || game.isGameOver) break;
      
      // Get the next group to solve
      final groupToSolve = game.getNextUnsolvedGroup();
      if (groupToSolve == null) break;
      
      // Play "finding" narration at the start of each group
      // "Let's look for the dinosaurs...", "Can you see the pattern?"
      _soundService.playSolveFinding();
      await Future.delayed(const Duration(milliseconds: 2000));
      
      // SELECT ITEMS ONE BY ONE (like a human)
      for (int j = 0; j < groupToSolve.items.length; j++) {
        if (!mounted) break;
        
        final item = groupToSolve.items[j];
        
        // Find and select this item in current items
        final currentItem = game.currentItems.firstWhere(
          (i) => i.id == item.id,
          orElse: () => item,
        );
        
        // Play item name and select it
        _soundService.playItemName(item.name);
        game.toggleSelection(currentItem);
        
        // Wait between selections (human thinking time)
        await Future.delayed(const Duration(milliseconds: 1200));
      }
      
      // Play confirmation before submitting
      // "Yes! These belong together!", "That's right, let's submit!"
      _soundService.playSolveConfirm();
      await Future.delayed(const Duration(milliseconds: 2000));
      
      // Now solve this group
      final solvedGroup = game.solveNextGroup();
      if (solvedGroup != null) {
        // Just announce the category (no "Great job!" since computer solved it)
        await Future.delayed(const Duration(milliseconds: 500));
        _soundService.playCategory(solvedGroup.displayName);
        
        // Wait before moving to next group
        await Future.delayed(const Duration(milliseconds: 2500));
      }
    }
    
    // Victory!
    if (game.isVictory) {
      await Future.delayed(const Duration(milliseconds: 1200));
      _soundService.playVictory();
    }
    
    if (mounted) {
      setState(() => _isSolvingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
            ),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎮', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Text(
              'CONNECTIONS',
              style: GoogleFonts.quicksand(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 22,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 8),
            const Text('🧩', style: TextStyle(fontSize: 24)),
          ],
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              onPressed: () {
                _hasPlayedGameOverSound = false;
                _soundService.stopAll();
                Provider.of<GameProvider>(context, listen: false).startNewGame();
              },
            ),
          ),
        ],
      ),
      body: Consumer<GameProvider>(
        builder: (context, game, child) {
          if (game.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (game.isGameOver && !game.isVictory && !_hasPlayedGameOverSound) {
            _hasPlayedGameOverSound = true;
            Future.microtask(() => _soundService.playGameOver());
          }

          if (game.isVictory) {
            return _buildVictoryScreen(game);
          }

          if (game.isGameOver && !game.isVictory) {
            return _buildGameOverScreen(game);
          }

          return Column(
            children: [
              _buildScoreBar(game),
              const Divider(height: 1),
              
              // Hint banner
              if (game.activeHint != null)
                _buildHintBanner(game),
              
              // Freeze indicator
              if (game.freezeActive)
                _buildFreezeIndicator(),
              
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final screenWidth = constraints.maxWidth;
                    
                    // Dynamic grid columns based on width
                    int columns = 4;
                    if (screenWidth < 280) columns = 3;
                    
                    // Simple responsive spacing
                    final spacing = (screenWidth * 0.02).clamp(6.0, 10.0);
                    final padding = (screenWidth * 0.03).clamp(8.0, 16.0);

                    return SingleChildScrollView(
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      child: Column(
                        children: [
                          SizedBox(height: spacing),
                          // Solved Groups
                          ...game.solvedGroups.map((group) => SolvedGroupCard(
                            group: group,
                            onTap: () {
                              if (group.items.isNotEmpty) {
                                _soundService.playEducational(group.items.first.name);
                              }
                            },
                          )),
                          
                          if (game.solvedGroups.isNotEmpty) SizedBox(height: spacing),

                          // Clean Grid with SQUARE cards (1:1 aspect ratio)
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: game.currentItems.length,
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              crossAxisSpacing: spacing,
                              mainAxisSpacing: spacing,
                              childAspectRatio: 1.0, // Square cards - always elegant
                            ),
                            itemBuilder: (context, index) {
                              final item = game.currentItems[index];
                              final isRevealed = game.revealedItemIds.contains(item.id);
                              return ItemCard(
                                item: item,
                                isRevealed: isRevealed,
                                onTap: _isSolvingAll ? () {} : () => _onItemTap(game, item),
                              );
                            },
                          ),
                          SizedBox(height: spacing),
                        ],
                      ),
                    );
                  },
                ),
              ),
              
              // Lifelines
              _buildLifelineBar(game),
              
              // Controls
              _buildControls(game),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHintBanner(GameProvider game) {
    return FadeIn(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: Colors.amber.shade100,
        child: Row(
          children: [
            const Icon(Icons.lightbulb, color: Colors.amber, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                game.activeHint!,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade900,
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: Colors.amber.shade700, size: 18),
              onPressed: () => game.clearHint(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFreezeIndicator() {
    return FadeIn(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.blue.shade100,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.ac_unit, color: Colors.blue, size: 18),
            const SizedBox(width: 8),
            Text(
              'FREEZE ACTIVE - Next mistake won\'t count!',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade900,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreBar(GameProvider game) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SCORE',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                  letterSpacing: 1,
                ),
              ),
              Text(
                '${game.currentScore}',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          if (game.streak > 0)
            FadeIn(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B6B), Color(0xFFFFE66D)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_fire_department, color: Colors.white, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      '${game.streak}x',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'HIGH SCORE',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                  letterSpacing: 1,
                ),
              ),
              Text(
                '${game.highScore}',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.amber.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLifelineBar(GameProvider game) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildLifelineButton(
            icon: Icons.lightbulb_outline,
            label: 'Reveal',
            count: game.revealOneRemaining,
            color: Colors.amber,
            onPressed: game.revealOneRemaining > 0 ? () {
              if (game.useRevealOne()) {
                _soundService.playRevealOne();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Look for the glowing items! ⭐", textAlign: TextAlign.center),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Colors.amber,
                  )
                );
              }
            } : null,
          ),
          _buildLifelineButton(
            icon: Icons.help_outline,
            label: 'Hint',
            count: game.categoryHintRemaining,
            color: Colors.purple,
            onPressed: game.categoryHintRemaining > 0 ? () {
              if (game.useCategoryHint()) {
                _soundService.playCategoryHint();
              }
            } : null,
          ),
          _buildLifelineButton(
            icon: Icons.ac_unit,
            label: 'Freeze',
            count: game.freezeRemaining,
            color: Colors.blue,
            isActive: game.freezeActive,
            onPressed: game.freezeRemaining > 0 && !game.freezeActive ? () {
              if (game.useFreeze()) {
                _soundService.playFreeze();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Freeze activated! ❄️", textAlign: TextAlign.center),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Colors.blue,
                  )
                );
              }
            } : null,
          ),
          _buildLifelineButton(
            icon: Icons.auto_fix_high,
            label: _isSolvingAll ? '...' : 'Solve All',
            count: game.autoSolveRemaining,
            color: Colors.green,
            isActive: _isSolvingAll,
            onPressed: (game.autoSolveRemaining > 0 && !_isSolvingAll) 
                ? () => _animatedSolveAll(game) 
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildLifelineButton({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    required VoidCallback? onPressed,
    bool isActive = false,
  }) {
    final bool isDisabled = onPressed == null;
    
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive 
              ? color.withOpacity(0.2) 
              : isDisabled 
                  ? Colors.grey.shade200 
                  : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: isActive 
              ? Border.all(color: color, width: 2)
              : Border.all(color: isDisabled ? Colors.grey.shade300 : color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                Icon(
                  icon,
                  color: isDisabled ? Colors.grey : color,
                  size: 24,
                ),
                if (count > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDisabled ? Colors.grey : color,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isDisabled ? Colors.grey : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(GameProvider game) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Mistakes remaining:", style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
              const SizedBox(width: 10),
              Row(
                children: List.generate(game.maxMistakes, (index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: CircleAvatar(
                      radius: 6,
                      backgroundColor: index < (game.maxMistakes - game.mistakes)
                          ? Colors.black87
                          : Colors.grey.shade300,
                    ),
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: game.selectedItems.isEmpty ? null : () => game.deselectAll(),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  foregroundColor: Colors.black,
                ),
                child: const Text("Deselect all"),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => game.shuffleItems(),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  foregroundColor: Colors.black,
                ),
                child: const Text("Shuffle"),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: game.selectedItems.length != 4
                    ? null
                    : () async {
                        bool oneAway = game.isOneAway();
                        int solvedBefore = game.solvedGroups.length;
                        await game.submitSelection();
                        int solvedAfter = game.solvedGroups.length;
                        
                        if (game.isVictory) {
                          _soundService.playVictory();
                        } else if (solvedAfter > solvedBefore) {
                          _soundService.playCorrect();
                          final solvedGroup = game.solvedGroups.last;
                          _soundService.playCategory(solvedGroup.displayName);
                        } else if (oneAway) {
                          _soundService.playOneAway();
                           ScaffoldMessenger.of(context).showSnackBar(
                             const SnackBar(
                               content: Text("One away...", textAlign: TextAlign.center),
                               duration: Duration(seconds: 1),
                               behavior: SnackBarBehavior.floating,
                               width: 200,
                               backgroundColor: Colors.black87,
                             )
                           );
                        } else {
                          _soundService.playWrong();
                          if (game.mistakes > 0 && game.mistakes < game.maxMistakes) {
                            _soundService.playEncourage();
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Not quite!", textAlign: TextAlign.center),
                              duration: Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                              width: 200,
                              backgroundColor: Colors.black87,
                            )
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                ),
                child: const Text("Submit"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVictoryScreen(GameProvider game) {
    bool isNewHighScore = game.currentScore >= game.highScore && game.currentScore > 0;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeInDown(
              child: Text(
                game.getGameRating(),
                style: GoogleFonts.inter(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.amber.shade700,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FadeInUp(
              delay: const Duration(milliseconds: 200),
              child: Text(
                "YOU WON!",
                style: GoogleFonts.inter(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 24),
            FadeInUp(
              delay: const Duration(milliseconds: 400),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(
                      'FINAL SCORE',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${game.currentScore}',
                      style: GoogleFonts.inter(
                        fontSize: 56,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                    if (isNewHighScore)
                      Pulse(
                        infinite: true,
                        child: Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '🏆 NEW HIGH SCORE!',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FadeInUp(
              delay: const Duration(milliseconds: 600),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStatCard('Games Won', '${game.totalGamesWon}'),
                  const SizedBox(width: 16),
                  _buildStatCard('Mistakes', '${game.mistakes}'),
                ],
              ),
            ),
            const SizedBox(height: 32),
            FadeInUp(
              delay: const Duration(milliseconds: 800),
              child: ElevatedButton.icon(
                onPressed: () {
                  _hasPlayedGameOverSound = false;
                  _soundService.stopAll();
                  game.startNewGame();
                },
                icon: const Icon(Icons.replay),
                label: const Text("Play Again"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameOverScreen(GameProvider game) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeInDown(
              child: const Text(
                "😢",
                style: TextStyle(fontSize: 64),
              ),
            ),
            const SizedBox(height: 16),
            FadeInUp(
              delay: const Duration(milliseconds: 200),
              child: Text(
                "GAME OVER",
                style: GoogleFonts.inter(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 24),
            FadeInUp(
              delay: const Duration(milliseconds: 400),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(
                      'YOUR SCORE',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${game.currentScore}',
                      style: GoogleFonts.inter(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Groups Found: ${game.solvedGroups.length}/4',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FadeInUp(
              delay: const Duration(milliseconds: 600),
              child: Text(
                'High Score: ${game.highScore}',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade700,
                ),
              ),
            ),
            const SizedBox(height: 32),
            FadeInUp(
              delay: const Duration(milliseconds: 800),
              child: ElevatedButton.icon(
                onPressed: () {
                  _hasPlayedGameOverSound = false;
                  _soundService.stopAll();
                  game.startNewGame();
                },
                icon: const Icon(Icons.replay),
                label: const Text("Try Again"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}
