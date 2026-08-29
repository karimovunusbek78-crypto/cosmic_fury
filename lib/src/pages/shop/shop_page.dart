import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // <-- light haptic on taps
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/particles.dart';
import 'package:flame_audio/flame_audio.dart'; // <-- click SFX, matches other pages

// Pulls in gemsNotifier / coinsNotifier / ownedSkinAssetsNotifier /
// kSkins / SkinData, the ResponsiveSize (context.wp/hp/sp) extension,
// AnimatedCounterText, and AnimatedTapButton — all shared with the
// Skins/Upgrade pages so this screen looks and behaves consistently
// with them. Adjust the path to wherever skins_page.dart actually
// lives in your project.
import 'package:cosmic_fury/src/pages/skins/skins_page.dart';

// Pulls in superPowerFor / SuperPowerData / isSuperPowerOwned /
// ownedSuperPowerAssetsNotifier — the package cards below show the
// ship's REAL super power (icon, name, description) right next to the
// flying ship, and the bundle unlocks that ability directly by adding
// straight into this set (bypassing the usual coin cost), the same way
// _grantPackage adds straight into ownedSkinAssetsNotifier instead of
// going through purchaseSkin()'s gem check. Adjust the path to
// wherever ship_super_powers.dart actually lives in your project.
import 'package:cosmic_fury/src/pages/main/level_pages/ship_super_powers.dart';

// Pulls in kAllSpells / SpellData / SpellTier / SpellTierX and
// ownedSpellCountsNotifier — the same spell-ownership map the Spells
// shop and Battle Loadout pages read/write. Everything this page
// grants (package bonus spells, and the Spells tab's bundles) writes
// straight into that notifier, so spells bought here show up in the
// loadout immediately. Adjust the path to wherever spells_page.dart
// actually lives in your project.
import 'package:cosmic_fury/src/pages/spells/spells_page.dart';

/// Set to false to drop the animated starfield/ember layer behind the
/// page. Each package card already runs its own little Flame game for
/// the flying ship, so on older devices you may prefer to spend the
/// frame budget on those instead of the background.
const bool kShopAmbientBackground = true;

/// ------------------------------------------------------------
/// PALETTE — one place for the page's shared colors so the whole
/// screen stays consistent instead of having magic hex values
/// sprinkled through every widget.
/// ------------------------------------------------------------
const Color _kInk = Color(0xFF0B0300); // deepest background
const Color _kCard = Color(0xFF190802); // card base
const Color _kEmber = Color(0xFFFF5F3D); // primary brand orange
const Color _kGold = Color(0xFFFFC371); // highlight / price
const Color _kGemBlue = Color(0xFF6FCBFF);
const Color _kCoinGold = Color(0xFFFFC96B);
const Color _kSpellMint = Color(0xFF64F0C8);

const String _kGemAsset = 'assets/images/budget.png';
const String _kCoinAsset = 'assets/images/coin.png';

/// Groups an int with commas — 200000 -> "200,000". Avoids pulling in
/// `intl` just for this.
String _fmt(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// ------------------------------------------------------------
/// CATEGORIES — the four top-level tabs pinned under the wallet.
/// Each one owns an accent color used by its tab pill, its section
/// header and the page's background tint, so switching tabs reads as
/// switching the whole screen's "mode" rather than just swapping a
/// block of content.
/// ------------------------------------------------------------
enum _ShopCategory { packages, money, spells, cases }

class _CategoryMeta {
  final _ShopCategory category;
  final String label;
  final IconData icon;
  final Color color;

  const _CategoryMeta({
    required this.category,
    required this.label,
    required this.icon,
    required this.color,
  });
}

const List<_CategoryMeta> _kCategories = [
  _CategoryMeta(
    category: _ShopCategory.packages,
    label: 'Packs',
    icon: Icons.rocket_launch_rounded,
    color: Color(0xFFFF8A3D),
  ),
  _CategoryMeta(
    category: _ShopCategory.money,
    label: 'Money',
    icon: Icons.diamond_rounded,
    color: _kGemBlue,
  ),
  _CategoryMeta(
    category: _ShopCategory.spells,
    label: 'Spells',
    icon: Icons.auto_awesome_rounded,
    color: _kSpellMint,
  ),
  _CategoryMeta(
    category: _ShopCategory.cases,
    label: 'Cases',
    icon: Icons.inventory_2_rounded,
    color: Color(0xFFB68CFF),
  ),
];

/// ------------------------------------------------------------
/// MONEY — plain gem/coin top-ups. Coins deliberately mirror the gem
/// tiers 100x over (10 gems <-> 1,000 coins, 100 <-> 10,000, etc.) so
/// both currency rows read as the same pricing ladder.
///
/// `tagLabel` is purely cosmetic merchandising — it just paints a
/// ribbon on the tile. Null means no ribbon.
/// ------------------------------------------------------------
class _CurrencyTier {
  final int amount;
  final String priceLabel;
  final String? tagLabel;
  final bool special;

  const _CurrencyTier({
    required this.amount,
    required this.priceLabel,
    this.tagLabel,
    this.special = false,
  });
}

const List<_CurrencyTier> _kGemTiers = [
  _CurrencyTier(amount: 10, priceLabel: '\$0.20'),
  _CurrencyTier(amount: 100, priceLabel: '\$0.99'),
  _CurrencyTier(amount: 1000, priceLabel: '\$7.00', tagLabel: 'POPULAR'),
  _CurrencyTier(
    amount: 10000,
    priceLabel: '\$50.00',
    tagLabel: 'BEST VALUE',
    special: true,
  ),
];

const List<_CurrencyTier> _kCoinTiers = [
  _CurrencyTier(amount: 1000, priceLabel: '\$0.20'),
  _CurrencyTier(amount: 10000, priceLabel: '\$0.99'),
  _CurrencyTier(amount: 100000, priceLabel: '\$7.00', tagLabel: 'POPULAR'),
  _CurrencyTier(
    amount: 1000000,
    priceLabel: '\$50.00',
    tagLabel: 'BEST VALUE',
    special: true,
  ),
];

/// ------------------------------------------------------------
/// PACKAGES — the two headline bundles. `shipIndex` points into
/// kSkins (see skins_page.dart) — the bundle unlocks that ship AND
/// its super power ability, in addition to the flat gem/coin grant
/// and `bonusSpellCount` random spells.
///
/// There's no artwork field any more: the card renders the ACTUAL
/// ship from kSkins[shipIndex] live with Flame (flying, with its own
/// colored engine trail), and pins that ship's real super power icon
/// beside it — so the card always shows exactly what you're buying,
/// and never drifts out of sync with the roster.
/// ------------------------------------------------------------
class _ShopPackage {
  final String label;
  final String tagLabel;
  final String description;
  final int gems;
  final int coins;
  final int shipIndex;
  final int bonusSpellCount;
  final String priceLabel;
  final Color accentColor;

  const _ShopPackage({
    required this.label,
    required this.tagLabel,
    required this.description,
    required this.gems,
    required this.coins,
    required this.shipIndex,
    required this.bonusSpellCount,
    required this.priceLabel,
    required this.accentColor,
  });
}

const List<_ShopPackage> _kPackages = [
  _ShopPackage(
    label: 'Starter Pack',
    tagLabel: 'STARTER',
    description: 'Everything you need to get off the launch pad.',
    gems: 200,
    coins: 10000,
    shipIndex: 1, // Interceptor
    bonusSpellCount: 10,
    priceLabel: '\$4.99',
    accentColor: _kGemBlue,
  ),
  _ShopPackage(
    label: 'Elite Pack',
    tagLabel: 'BEST VALUE',
    description: 'The full loadout — ship, ability, spells and a war chest.',
    gems: 3000,
    coins: 200000,
    shipIndex: 3, // Frostbyte
    bonusSpellCount: 50,
    priceLabel: '\$16.99',
    accentColor: _kGold,
  ),
];

/// ------------------------------------------------------------
/// SPELL BUNDLES — buy a whole tier at once instead of tapping the
/// same spell five times on the Spells page.
///
/// Two shapes, distinguished by whether `tier` is null:
///
///   * tier != null  -> a TIER bundle: `copiesPerSpell` copies of
///                      EVERY spell in that tier. With 5 spells per
///                      tier and copiesPerSpell = 5, that's "5 of
///                      each of the 5 spells" = 25 spells in one buy.
///   * tier == null  -> a RANDOM crate: `randomCount` spells rolled
///                      from the whole book, weighted toward the
///                      lower tiers (see _rollRandomSpells).
///
/// Prices are COMPUTED from the real gem costs in kAllSpells (see
/// _bundleGemCost) minus `discountPercent`, so if you ever retune a
/// spell's gemCost the bundles stay priced sensibly on their own.
/// ------------------------------------------------------------
class _SpellBundle {
  final String label;
  final String description;
  final SpellTier? tier;
  final int copiesPerSpell;
  final int randomCount;
  final int discountPercent;
  final IconData icon;
  final Color accentColor;

  const _SpellBundle({
    required this.label,
    required this.description,
    required this.tier,
    this.copiesPerSpell = 0,
    this.randomCount = 0,
    required this.discountPercent,
    required this.icon,
    required this.accentColor,
  });
}

const List<_SpellBundle> _kSpellBundles = [
  _SpellBundle(
    label: 'Basic Spell Bundle',
    description: '5 copies of every Basic spell.',
    tier: SpellTier.basic,
    copiesPerSpell: 5,
    discountPercent: 25,
    icon: Icons.auto_awesome_rounded,
    accentColor: Color(0xFF7CFFB2),
  ),
  _SpellBundle(
    label: 'Advanced Spell Bundle',
    description: '5 copies of every Advanced spell.',
    tier: SpellTier.advanced,
    copiesPerSpell: 5,
    discountPercent: 25,
    icon: Icons.auto_fix_high_rounded,
    accentColor: Color(0xFFB68CFF),
  ),
  _SpellBundle(
    label: 'Elite Spell Bundle',
    description: '5 copies of every Elite spell.',
    tier: SpellTier.elite,
    copiesPerSpell: 5,
    discountPercent: 25,
    icon: Icons.workspace_premium_rounded,
    accentColor: _kGold,
  ),
  _SpellBundle(
    label: 'Mystery Spell Crate',
    description: '25 spells rolled at random from the whole book.',
    tier: null,
    randomCount: 25,
    discountPercent: 35,
    icon: Icons.casino_rounded,
    accentColor: Color(0xFFFF7CE0),
  ),
];

/// All spells belonging to [tier], in list order.
List<SpellData> _spellsOfTier(SpellTier tier) =>
    kAllSpells.where((s) => s.tier == tier).toList();

/// How many individual spell copies a bundle hands over.
int _bundleSpellCount(_SpellBundle bundle) => bundle.tier == null
    ? bundle.randomCount
    : _spellsOfTier(bundle.tier!).length * bundle.copiesPerSpell;

/// Gem price of a bundle, derived from the real per-spell costs in
/// kAllSpells so it can never drift away from them.
int _bundleGemCost(_SpellBundle bundle) {
  if (bundle.tier == null) {
    // Random crate — priced off the average spell in the book.
    final total = kAllSpells.fold<int>(0, (sum, s) => sum + s.gemCost);
    final avg = total / kAllSpells.length;
    final full = avg * bundle.randomCount;
    return (full * (100 - bundle.discountPercent) / 100).round();
  }
  final tierSpells = _spellsOfTier(bundle.tier!);
  final full = tierSpells.fold<int>(0, (sum, s) => sum + s.gemCost) *
      bundle.copiesPerSpell;
  return (full * (100 - bundle.discountPercent) / 100).round();
}

/// What a bundle would have cost bought spell-by-spell on the Spells
/// page — shown struck through next to the discounted price.
int _bundleFullGemCost(_SpellBundle bundle) {
  if (bundle.tier == null) {
    final total = kAllSpells.fold<int>(0, (sum, s) => sum + s.gemCost);
    return ((total / kAllSpells.length) * bundle.randomCount).round();
  }
  return _spellsOfTier(bundle.tier!).fold<int>(0, (sum, s) => sum + s.gemCost) *
      bundle.copiesPerSpell;
}

final Random _shopRng = Random();

/// Rolls [count] spells at random, weighted so a random grant leans
/// toward the cheaper end of the book instead of showering the player
/// with Elite spells. Weights are per-tier picks in a bag: Basic 5,
/// Advanced 3, Elite 2 — so roughly 50% / 30% / 20%.
List<SpellData> _rollRandomSpells(int count) {
  const weights = <SpellTier, int>{
    SpellTier.basic: 5,
    SpellTier.advanced: 3,
    SpellTier.elite: 2,
  };

  final bag = <SpellData>[];
  for (final spell in kAllSpells) {
    final w = weights[spell.tier] ?? 1;
    for (var i = 0; i < w; i++) {
      bag.add(spell);
    }
  }

  return List<SpellData>.generate(
    count,
    (_) => bag[_shopRng.nextInt(bag.length)],
  );
}

/// Adds [spells] (duplicates included) into the shared ownership map
/// in one write, so listeners rebuild once rather than 50 times.
void _addSpellsToInventory(Iterable<SpellData> spells) {
  final updated = Map<String, int>.from(ownedSpellCountsNotifier.value);
  for (final spell in spells) {
    updated[spell.id] = (updated[spell.id] ?? 0) + 1;
  }
  ownedSpellCountsNotifier.value = updated;
}

/// ------------------------------------------------------------
/// CASES — locked for now. Tapping any of these just says so; no
/// currency is spent and nothing is granted.
/// ------------------------------------------------------------
class _ShopCase {
  final String label;
  final String rarity;
  final Color accentColor;

  const _ShopCase({
    required this.label,
    required this.rarity,
    required this.accentColor,
  });
}

const List<_ShopCase> _kCases = [
  _ShopCase(label: 'Common', rarity: 'Case', accentColor: Color(0xFF9BE7FF)),
  _ShopCase(label: 'Rare', rarity: 'Case', accentColor: Color(0xFFB68CFF)),
  _ShopCase(label: 'Legendary', rarity: 'Case', accentColor: _kGold),
];

class ShopPage extends StatefulWidget {
  const ShopPage({Key? key}) : super(key: key);

  @override
  _ShopPageState createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage>
    with SingleTickerProviderStateMixin {
  _ShopCategory _selected = _ShopCategory.packages;

  /// Drives the diagonal light sweep that runs across the package
  /// cards and the "best value" tiles. One controller for the whole
  /// page so every highlight pulses in sync.
  late final AnimationController _shine;

  @override
  void initState() {
    super.initState();
    // Preload the shared click SFX the same way every other page
    // does, so the very first tap on this page fires instantly.
    FlameAudio.audioCache.load('click.mp3');

    _shine = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  /// Click SFX + a light haptic, the standard feedback for every
  /// tappable thing on this page.
  void _tap() {
    FlameAudio.play('click.mp3', volume: 0.6);
    HapticFeedback.lightImpact();
  }

  void _selectCategory(_ShopCategory category) {
    if (category == _selected) return;
    _tap();
    setState(() => _selected = category);
  }

  void _showSnack(String message, {required IconData icon, Color? color}) {
    final accent = color ?? _kGold;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1B0803),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withOpacity(0.6), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(icon, color: accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }

  /// Grants a flat gem/coin top-up. Real IAP receipt validation would
  /// go here before this line — this only mutates the shared
  /// notifiers, same "testing pile" approach the rest of the app uses.
  void _grantCurrency(bool isGems, _CurrencyTier tier) {
    if (isGems) {
      gemsNotifier.value += tier.amount;
    } else {
      coinsNotifier.value += tier.amount;
    }
    _showSnack(
      '+${_fmt(tier.amount)} ${isGems ? 'gems' : 'coins'} added!',
      icon: isGems ? Icons.diamond_rounded : Icons.monetization_on_rounded,
      color: isGems ? _kGemBlue : _kCoinGold,
    );
  }

  /// Grants a package's gems/coins, unlocks its ship, unlocks that
  /// ship's super power ability, and rolls its bonus random spells
  /// straight into the shared spell inventory — all bypassing the
  /// normal gem/coin costs those purchases would otherwise take,
  /// since the bundle price already covers them.
  void _grantPackage(_ShopPackage package) {
    gemsNotifier.value += package.gems;
    coinsNotifier.value += package.coins;

    final ship = kSkins[package.shipIndex];
    ownedSkinAssetsNotifier.value = {
      ...ownedSkinAssetsNotifier.value,
      ship.asset,
    };
    ownedSuperPowerAssetsNotifier.value = {
      ...ownedSuperPowerAssetsNotifier.value,
      ship.asset,
    };

    if (package.bonusSpellCount > 0) {
      _addSpellsToInventory(_rollRandomSpells(package.bonusSpellCount));
    }

    final spellsLine = package.bonusSpellCount > 0
        ? ' + ${package.bonusSpellCount} random spells'
        : '';
    _showSnack(
      '${package.label} unlocked — ${ship.name} & its ability$spellsLine.',
      icon: Icons.check_circle_rounded,
      color: package.accentColor,
    );
  }

  /// Spends gems on a spell bundle and drops every copy into the
  /// shared inventory. Unlike the packages above this one is a REAL
  /// purchase — it checks the balance first and refuses if short.
  void _buySpellBundle(_SpellBundle bundle) {
    final cost = _bundleGemCost(bundle);
    if (gemsNotifier.value < cost) {
      _showSnack(
        'Not enough gems — ${bundle.label} costs ${_fmt(cost)}.',
        icon: Icons.error_outline_rounded,
        color: _kEmber,
      );
      return;
    }

    gemsNotifier.value -= cost;

    if (bundle.tier == null) {
      _addSpellsToInventory(_rollRandomSpells(bundle.randomCount));
    } else {
      final granted = <SpellData>[];
      for (final spell in _spellsOfTier(bundle.tier!)) {
        for (var i = 0; i < bundle.copiesPerSpell; i++) {
          granted.add(spell);
        }
      }
      _addSpellsToInventory(granted);
    }

    _showSnack(
      '${bundle.label} bought — ${_bundleSpellCount(bundle)} spells added.',
      icon: Icons.auto_awesome_rounded,
      color: bundle.accentColor,
    );
  }

  void _showCaseComingSoon(_ShopCase caseItem) {
    _showSnack(
      '${caseItem.label} ${caseItem.rarity} — coming soon!',
      icon: Icons.lock_rounded,
      color: caseItem.accentColor,
    );
  }

  // ==================================================================
  // BUILD
  // ==================================================================
  @override
  Widget build(BuildContext context) {
    final activeMeta = _kCategories.firstWhere((m) => m.category == _selected);

    return Scaffold(
      backgroundColor: _kInk,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 1 — base gradient, faintly tinted by the active
          // category so the mood of the page follows the tab.
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(const Color(0xFF3A1607), activeMeta.color, 0.16)!,
                  const Color(0xFF160600),
                  _kInk,
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),

          // Layer 2 — a soft glow bloom behind the header, again in
          // the active category's color.
          Positioned(
            top: -context.hp(12),
            left: -context.wp(20),
            right: -context.wp(20),
            height: context.hp(38),
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      activeMeta.color.withOpacity(0.22),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Layer 3 — Flame: drifting starfield + rising embers. Pure
          // decoration, never intercepts input, transparent-backed so
          // the gradient above shows through.
          if (kShopAmbientBackground)
            const Positioned.fill(
              child: IgnorePointer(child: _SpaceBackground()),
            ),

          // Layer 4 — the actual UI.
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                SizedBox(height: context.hp(1.4)),
                _buildWalletRow(),
                SizedBox(height: context.hp(1.8)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.wp(5)),
                  child: _buildCategoryTabsBar(),
                ),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Header — back button + "SHOP" title with a subtitle.
  // ------------------------------------------------------------------
  Widget _buildHeader() {
    return Padding(
      padding:
          EdgeInsets.fromLTRB(context.wp(4), context.hp(1.6), context.wp(5), 0),
      child: Row(
        children: [
          AnimatedTapButton(
            onTap: () {
              _tap();
              Navigator.of(context).pop();
            },
            child: Container(
              width: context.sp(40),
              height: context.sp(40),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.5),
                border: Border.all(color: _kEmber.withOpacity(0.7), width: 1.2),
                boxShadow: [
                  BoxShadow(color: _kEmber.withOpacity(0.25), blurRadius: 12),
                ],
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  color: _kGold, size: context.sp(16)),
            ),
          ),
          SizedBox(width: context.wp(3.5)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  colors: [Colors.white, _kGold],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ).createShader(rect),
                child: Text(
                  'SHOP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: context.sp(22),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                    height: 1.0,
                  ),
                ),
              ),
              SizedBox(height: context.hp(0.2)),
              Text(
                'Gear up, commander',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.42),
                  fontSize: context.sp(10),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // WALLET — current balances. Tapping either chip jumps straight to
  // the Money tab, which is what players expect from the little "+"
  // next to a balance in every other mobile game.
  // ------------------------------------------------------------------
  Widget _buildWalletRow() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.wp(5)),
      child: Row(
        children: [
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: gemsNotifier,
              builder: (context, gems, _) => _buildWalletCard(
                iconAsset: _kGemAsset,
                fallbackIcon: Icons.diamond_rounded,
                value: gems,
                accentColor: _kGemBlue,
              ),
            ),
          ),
          SizedBox(width: context.wp(3)),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: coinsNotifier,
              builder: (context, coins, _) => _buildWalletCard(
                iconAsset: _kCoinAsset,
                fallbackIcon: Icons.monetization_on_rounded,
                value: coins,
                accentColor: _kCoinGold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletCard({
    required String iconAsset,
    required IconData fallbackIcon,
    required int value,
    required Color accentColor,
  }) {
    return AnimatedTapButton(
      onTap: () => _selectCategory(_ShopCategory.money),
      child: Container(
        padding: EdgeInsets.fromLTRB(context.wp(2.5), context.hp(0.9),
            context.wp(1.5), context.hp(0.9)),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Color.lerp(_kCard, accentColor, 0.14)!,
              Colors.black.withOpacity(0.75),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: accentColor.withOpacity(0.5), width: 1.1),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.18),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            _assetOrIcon(iconAsset,
                size: context.sp(24),
                fallbackIcon: fallbackIcon,
                fallbackColor: accentColor),
            SizedBox(width: context.wp(2)),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AnimatedCounterText(
                  value: value,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: context.sp(16),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            SizedBox(width: context.wp(1)),
            Container(
              width: context.sp(20),
              height: context.sp(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentColor.withOpacity(0.22),
                border:
                    Border.all(color: accentColor.withOpacity(0.7), width: 1),
              ),
              child: Icon(Icons.add_rounded,
                  color: accentColor, size: context.sp(13)),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // CATEGORY TABS — pinned strip of four segments with a single
  // indicator pill that SLIDES between them as you tap. Tapping a tab
  // swaps the section below (via the AnimatedSwitcher in _buildBody);
  // nothing scrolls.
  // ------------------------------------------------------------------
  Widget _buildCategoryTabsBar() {
    final selectedIndex =
        _kCategories.indexWhere((m) => m.category == _selected);

    return Container(
      height: context.sp(58),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / _kCategories.length;
          final activeColor = _kCategories[selectedIndex].color;

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                left: segmentWidth * selectedIndex,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    gradient: LinearGradient(
                      colors: [
                        activeColor,
                        Color.lerp(activeColor, Colors.black, 0.35)!,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: activeColor.withOpacity(0.45),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: _kCategories.map((meta) {
                  final active = meta.category == _selected;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _selectCategory(meta.category),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedScale(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutBack,
                            scale: active ? 1.0 : 0.9,
                            child: Icon(
                              meta.icon,
                              color: active
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.35),
                              size: context.sp(17),
                            ),
                          ),
                          SizedBox(height: context.hp(0.3)),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 260),
                            style: TextStyle(
                              color: active
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.35),
                              fontSize: context.sp(9.5),
                              fontWeight:
                                  active ? FontWeight.w900 : FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                            child: Text(meta.label.toUpperCase()),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------------
  // BODY — cross-fades between the sections, with a soft fade at the
  // bottom so scrolled content dissolves instead of getting chopped
  // off at the screen edge.
  // ------------------------------------------------------------------
  Widget _buildBody() {
    return Stack(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.05),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey(_selected),
            child: ScrollConfiguration(
              behavior: const _NoGlowBehavior(),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(context.wp(5), context.hp(2.2),
                    context.wp(5), context.hp(4)),
                child: _buildSectionForCategory(_selected),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: context.hp(5),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, _kInk],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionForCategory(_ShopCategory category) {
    switch (category) {
      case _ShopCategory.packages:
        return _buildPackagesSection();
      case _ShopCategory.money:
        return _buildMoneySection();
      case _ShopCategory.spells:
        return _buildSpellsSection();
      case _ShopCategory.cases:
        return _buildCasesSection();
    }
  }

  Widget _buildSectionHeader(String title, String subtitle, Color color) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.hp(1.8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3.5,
                height: context.sp(15),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(color: color.withOpacity(0.7), blurRadius: 8),
                  ],
                ),
              ),
              SizedBox(width: context.wp(2.2)),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: context.sp(14),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          SizedBox(height: context.hp(0.5)),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: context.sp(10.5),
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  // ==================================================================
  // PACKAGES
  // ==================================================================
  Widget _buildPackagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Packages',
          'Bundles — currency, a ship, its super power and spells in one buy.',
          const Color(0xFFFF8A3D),
        ),
        ..._kPackages.map(_buildPackageCard),
      ],
    );
  }

  /// Vertical hero card: the LIVE ship flying across the top with its
  /// super power pinned beside it, then name + blurb, then the perk
  /// breakdown, then a full-width buy button carrying the price.
  Widget _buildPackageCard(_ShopPackage package) {
    final ship = kSkins[package.shipIndex];
    final power = superPowerFor(ship);
    final accent = package.accentColor;

    return Padding(
      padding: EdgeInsets.only(bottom: context.hp(2.2)),
      child: AnimatedTapButton(
        onTap: () {
          _tap();
          _grantPackage(package);
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accent.withOpacity(0.65), width: 1.4),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.28),
                blurRadius: 26,
                spreadRadius: -4,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22.6),
            child: Stack(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color.lerp(_kCard, accent, 0.20)!,
                        const Color(0xFF150501),
                        const Color(0xFF0C0300),
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildPackageStage(package, ship, power),
                      Padding(
                        padding: EdgeInsets.fromLTRB(context.wp(4.5), 0,
                            context.wp(4.5), context.wp(4)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              package.label,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: context.sp(18),
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.3,
                              ),
                            ),
                            SizedBox(height: context.hp(0.35)),
                            Text(
                              package.description,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.45),
                                fontSize: context.sp(10.5),
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                              ),
                            ),
                            SizedBox(height: context.hp(1.6)),
                            Row(
                              children: [
                                Expanded(
                                  child: _perkStat(
                                    iconAsset: _kGemAsset,
                                    fallbackIcon: Icons.diamond_rounded,
                                    value: _fmt(package.gems),
                                    label: 'GEMS',
                                    color: _kGemBlue,
                                  ),
                                ),
                                SizedBox(width: context.wp(2.5)),
                                Expanded(
                                  child: _perkStat(
                                    iconAsset: _kCoinAsset,
                                    fallbackIcon:
                                        Icons.monetization_on_rounded,
                                    value: _fmt(package.coins),
                                    label: 'COINS',
                                    color: _kCoinGold,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: context.hp(1.2)),
                            _perkLine(
                              Icons.rocket_launch_rounded,
                              '${ship.name} ship, unlocked',
                              accent,
                            ),
                            SizedBox(height: context.hp(0.7)),
                            _perkLine(
                              power.icon,
                              '${power.name} super power, unlocked',
                              power.color,
                            ),
                            if (package.bonusSpellCount > 0) ...[
                              SizedBox(height: context.hp(0.7)),
                              _perkLine(
                                Icons.auto_awesome_rounded,
                                '${package.bonusSpellCount} random spells',
                                _kSpellMint,
                              ),
                            ],
                            SizedBox(height: context.hp(2)),
                            _buyButton(package.priceLabel),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _shineOverlay(),
                Positioned(
                  top: context.hp(1.4),
                  right: context.wp(3.5),
                  child: _tagChip(package.tagLabel, accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The card's "stage": the ACTUAL ship from kSkins rendered live by
  /// Flame, cruising slowly across the card with its own colored
  /// engine trail — the same ship, flame color, spread and engine
  /// offset the Skins page shows — with the ship's REAL super power
  /// pinned to the right so you can see the ability you're buying
  /// without leaving the shop. Tapping the ability badge opens its
  /// details instead of buying.
  Widget _buildPackageStage(
      _ShopPackage package, SkinData ship, SuperPowerData power) {
    return SizedBox(
      height: context.hp(19),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Glow pool the ship flies over.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.15, 0),
                radius: 0.9,
                colors: [
                  package.accentColor.withOpacity(0.33),
                  package.accentColor.withOpacity(0.07),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),

          // The live ship. Keyed by asset so each card keeps its own
          // sprite + particle instance.
          Positioned.fill(
            right: context.wp(22), // leave room for the ability badge
            child: IgnorePointer(
              child: GameWidget(
                key: ValueKey('pkg-ship-${ship.asset}'),
                game: ShipFlyPreviewGame(
                  shipAsset: ship.asset,
                  flameAccent: ship.flameAccent,
                  engineOffsetYFraction: ship.engineOffsetYFraction,
                  flameSpread: ship.flameSpread,
                  flameParticleRadius: ship.flameParticleRadius,
                  flameLength: ship.flameLength,
                ),
              ),
            ),
          ),

          // Ability badge, pinned beside the ship.
          Positioned(
            right: context.wp(3),
            top: 0,
            bottom: context.hp(1),
            child: Center(child: _abilityBadge(ship, power)),
          ),

          // Ship name plate, bottom-left.
          Positioned(
            left: context.wp(4.5),
            bottom: context.hp(0.8),
            child: _shipNamePlate(ship),
          ),

          // Scrim so the stage melts into the card body.
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: context.hp(4.5),
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        const Color(0xFF150501).withOpacity(0.9),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shipNamePlate(SkinData ship) {
    final color = ship.nameColor ?? _kGold;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.wp(2.5), vertical: context.hp(0.4)),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.black.withOpacity(0.45),
        border: Border.all(color: color.withOpacity(0.45), width: 1),
      ),
      child: Text(
        ship.name.toUpperCase(),
        style: TextStyle(
          color: color == Colors.black ? Colors.white : color,
          fontSize: context.sp(9),
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  /// The super power badge that sits next to the flying ship. It's a
  /// nested tap target, so tapping it opens the power's details
  /// rather than firing the card's buy action.
  Widget _abilityBadge(SkinData ship, SuperPowerData power) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _tap();
        _showAbilitySheet(ship, power);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'ABILITY',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: context.sp(7.5),
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          SizedBox(height: context.hp(0.5)),
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: context.sp(62),
                height: context.sp(62),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [power.color.withOpacity(0.35), Colors.transparent],
                  ),
                ),
              ),
              Container(
                width: context.sp(48),
                height: context.sp(48),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.65),
                  border:
                      Border.all(color: power.color.withOpacity(0.9), width: 1.8),
                  boxShadow: [
                    BoxShadow(
                      color: power.color.withOpacity(0.4),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: Icon(power.icon,
                    color: power.color, size: context.sp(24)),
              ),
            ],
          ),
          SizedBox(height: context.hp(0.5)),
          SizedBox(
            width: context.wp(20),
            child: Text(
              power.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: power.color,
                fontSize: context.sp(8.5),
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
          SizedBox(height: context.hp(0.3)),
          Icon(Icons.info_outline_rounded,
              color: Colors.white.withOpacity(0.35), size: context.sp(11)),
        ],
      ),
    );
  }

  /// Read-only detail sheet for a package's super power — same
  /// numbers the Skins page shows, no buy button here since the
  /// package grants it outright.
  void _showAbilitySheet(SkinData ship, SuperPowerData power) {
    final durationLabel = power.activeDuration == null
        ? 'Rest of the level'
        : '${power.activeDuration!.inSeconds}s';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: BoxDecoration(
          color: const Color(0xFF160600),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(color: power.color.withOpacity(0.55), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade700,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: power.color.withOpacity(0.15),
                    border: Border.all(color: power.color.withOpacity(0.75)),
                  ),
                  child: Icon(power.icon, color: power.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        power.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${ship.name.toUpperCase()} · SUPER POWER',
                        style: TextStyle(
                          color: power.color,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              power.description,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.timer_outlined,
                    color: Colors.white38, size: 14),
                const SizedBox(width: 6),
                Text(durationLabel,
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 16),
                const Icon(Icons.replay, color: Colors.white38, size: 14),
                const SizedBox(width: 6),
                Text('${power.usesPerLevel}x per level',
                    style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: _kSpellMint.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kSpellMint.withOpacity(0.55)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.card_giftcard_rounded,
                      color: _kSpellMint, size: 17),
                  SizedBox(width: 8),
                  Text(
                    'INCLUDED IN THIS PACK',
                    style: TextStyle(
                      color: _kSpellMint,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _perkStat({
    required String iconAsset,
    required IconData fallbackIcon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.wp(2.5), vertical: context.hp(1.0)),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.04),
        border: Border.all(color: color.withOpacity(0.28), width: 1),
      ),
      child: Row(
        children: [
          _assetOrIcon(iconAsset,
              size: context.sp(22),
              fallbackIcon: fallbackIcon,
              fallbackColor: color),
          SizedBox(width: context.wp(2)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: context.sp(14),
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: color.withOpacity(0.85),
                    fontSize: context.sp(8.5),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _perkLine(IconData icon, String text, Color color) {
    return Row(
      children: [
        Container(
          width: context.sp(22),
          height: context.sp(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            color: color.withOpacity(0.16),
            border: Border.all(color: color.withOpacity(0.4), width: 1),
          ),
          child: Icon(icon, color: color, size: context.sp(12)),
        ),
        SizedBox(width: context.wp(2.2)),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: context.sp(11.5),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buyButton(String priceLabel) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: context.hp(1.4)),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: const LinearGradient(
          colors: [_kGold, _kEmber],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _kEmber.withOpacity(0.45),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_bag_rounded,
              color: Colors.white, size: context.sp(15)),
          SizedBox(width: context.wp(2)),
          Text(
            'GET FOR $priceLabel',
            style: TextStyle(
              color: Colors.white,
              fontSize: context.sp(13),
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  // ==================================================================
  // MONEY
  // ==================================================================
  Widget _buildMoneySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Money',
          'Straight gem and coin top-ups. Bigger tiers, better rate.',
          _kGemBlue,
        ),
        _buildSubLabel('GEMS', _kGemBlue),
        SizedBox(height: context.hp(1.2)),
        _buildCurrencyGrid(_kGemTiers, _kGemAsset, Icons.diamond_rounded,
            isGems: true, accent: _kGemBlue),
        SizedBox(height: context.hp(2.4)),
        _buildSubLabel('COINS', _kCoinGold),
        SizedBox(height: context.hp(1.2)),
        _buildCurrencyGrid(
            _kCoinTiers, _kCoinAsset, Icons.monetization_on_rounded,
            isGems: false, accent: _kCoinGold),
      ],
    );
  }

  Widget _buildSubLabel(String label, Color color) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: context.sp(11),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        SizedBox(width: context.wp(2.5)),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withOpacity(0.35), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrencyGrid(
    List<_CurrencyTier> tiers,
    String iconAsset,
    IconData fallbackIcon, {
    required bool isGems,
    required Color accent,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiers.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: context.wp(3),
        mainAxisSpacing: context.wp(3.5),
        childAspectRatio: 0.92,
      ),
      itemBuilder: (context, i) => _buildCurrencyTile(
          tiers[i], iconAsset, fallbackIcon,
          isGems: isGems, accent: accent),
    );
  }

  Widget _buildCurrencyTile(
    _CurrencyTier tier,
    String iconAsset,
    IconData fallbackIcon, {
    required bool isGems,
    required Color accent,
  }) {
    final borderColor = tier.special
        ? Colors.amberAccent.withOpacity(0.9)
        : accent.withOpacity(0.45);

    return AnimatedTapButton(
      onTap: () {
        _tap();
        _grantCurrency(isGems, tier);
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: borderColor, width: tier.special ? 1.6 : 1.1),
          boxShadow: [
            BoxShadow(
              color: (tier.special ? Colors.amberAccent : accent)
                  .withOpacity(tier.special ? 0.3 : 0.14),
              blurRadius: tier.special ? 20 : 12,
              spreadRadius: -3,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16.5),
          child: Stack(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(_kCard, accent, tier.special ? 0.22 : 0.12)!,
                      const Color(0xFF0E0400),
                    ],
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(context.wp(2.5), context.hp(2.0),
                      context.wp(2.5), context.hp(1.2)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: context.sp(50),
                            height: context.sp(50),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  accent.withOpacity(0.35),
                                  Colors.transparent
                                ],
                              ),
                            ),
                          ),
                          _assetOrIcon(iconAsset,
                              size: context.sp(34),
                              fallbackIcon: fallbackIcon,
                              fallbackColor: accent),
                        ],
                      ),
                      SizedBox(height: context.hp(0.6)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _fmt(tier.amount),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: context.sp(16),
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      SizedBox(height: context.hp(0.8)),
                      Container(
                        width: double.infinity,
                        padding:
                            EdgeInsets.symmetric(vertical: context.hp(0.85)),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          gradient: tier.special
                              ? const LinearGradient(
                                  colors: [_kGold, _kEmber],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: tier.special
                              ? null
                              : Colors.white.withOpacity(0.07),
                          border: tier.special
                              ? null
                              : Border.all(
                                  color: Colors.white.withOpacity(0.16),
                                  width: 1),
                        ),
                        child: Center(
                          child: Text(
                            tier.priceLabel,
                            style: TextStyle(
                              color: tier.special
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.9),
                              fontSize: context.sp(12),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (tier.special) _shineOverlay(),
              if (tier.tagLabel != null)
                Positioned(
                  top: context.hp(0.9),
                  right: context.wp(2),
                  child: _tagChip(
                    tier.tagLabel!,
                    tier.special ? Colors.amberAccent : accent,
                    small: true,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================================================================
  // SPELLS — bundles that drop straight into the shared spell
  // inventory (ownedSpellCountsNotifier), so anything bought here is
  // instantly available on the Battle Loadout page.
  // ==================================================================
  Widget _buildSpellsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Spells',
          'Whole tiers in one buy, cheaper than picking them off one at a time.',
          _kSpellMint,
        ),
        _buildSpellBookSummary(),
        SizedBox(height: context.hp(2.0)),
        ..._kSpellBundles.map(_buildSpellBundleCard),
        SizedBox(height: context.hp(1.4)),
        _buildFootnote(
          Icons.info_outline_rounded,
          'You can own any spell straight away, but the higher tiers only '
          'become equippable once a stronger ship is flying. Check the '
          'Battle Loadout page to bring them into a fight.',
          _kSpellMint,
        ),
      ],
    );
  }

  /// Live readout of what's already in the spell book, so the player
  /// can see a bundle land the moment they buy it.
  Widget _buildSpellBookSummary() {
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: ownedSpellCountsNotifier,
      builder: (context, owned, _) {
        final total = owned.values.fold<int>(0, (a, b) => a + b);
        final distinct = owned.values.where((v) => v > 0).length;

        return Container(
          padding: EdgeInsets.symmetric(
              horizontal: context.wp(4), vertical: context.hp(1.4)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                Color.lerp(_kCard, _kSpellMint, 0.16)!,
                const Color(0xFF0E0400),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: _kSpellMint.withOpacity(0.35), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: context.sp(38),
                height: context.sp(38),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kSpellMint.withOpacity(0.14),
                  border: Border.all(color: _kSpellMint.withOpacity(0.5)),
                ),
                child: Icon(Icons.menu_book_rounded,
                    color: _kSpellMint, size: context.sp(19)),
              ),
              SizedBox(width: context.wp(3)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR SPELL BOOK',
                      style: TextStyle(
                        color: _kSpellMint,
                        fontSize: context.sp(9),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                    SizedBox(height: context.hp(0.3)),
                    Text(
                      total == 0
                          ? 'Empty — grab a bundle below.'
                          : '$distinct of ${kAllSpells.length} spells known',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: context.sp(10.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AnimatedCounterText(
                    value: total,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: context.sp(20),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'COPIES',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.35),
                      fontSize: context.sp(8),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSpellBundleCard(_SpellBundle bundle) {
    final cost = _bundleGemCost(bundle);
    final fullCost = _bundleFullGemCost(bundle);
    final count = _bundleSpellCount(bundle);
    final accent = bundle.accentColor;
    final contents =
        bundle.tier == null ? kAllSpells : _spellsOfTier(bundle.tier!);

    return Padding(
      padding: EdgeInsets.only(bottom: context.hp(1.6)),
      child: ValueListenableBuilder<int>(
        valueListenable: gemsNotifier,
        builder: (context, gems, _) {
          final canAfford = gems >= cost;

          return AnimatedTapButton(
            onTap: () {
              _tap();
              _buySpellBundle(bundle);
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: accent.withOpacity(0.55), width: 1.3),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.2),
                    blurRadius: 18,
                    spreadRadius: -4,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18.7),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(_kCard, accent, 0.18)!,
                        const Color(0xFF0D0300),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(context.wp(4)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: context.sp(44),
                              height: context.sp(44),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withOpacity(0.6),
                                border: Border.all(
                                    color: accent.withOpacity(0.85),
                                    width: 1.4),
                                boxShadow: [
                                  BoxShadow(
                                      color: accent.withOpacity(0.35),
                                      blurRadius: 12),
                                ],
                              ),
                              child: Icon(bundle.icon,
                                  color: accent, size: context.sp(21)),
                            ),
                            SizedBox(width: context.wp(3)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    bundle.label,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: context.sp(14.5),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  SizedBox(height: context.hp(0.25)),
                                  Text(
                                    bundle.description,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: context.sp(10.5),
                                      fontWeight: FontWeight.w500,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: context.wp(2)),
                            _tagChip('$count SPELLS', accent, small: true),
                          ],
                        ),
                        SizedBox(height: context.hp(1.4)),

                        // What's inside — the real spell icons.
                        _buildBundleContents(bundle, contents, accent),

                        SizedBox(height: context.hp(1.4)),

                        // Price row.
                        Row(
                          children: [
                            if (cost < fullCost) ...[
                              Text(
                                _fmt(fullCost),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.3),
                                  fontSize: context.sp(11),
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                              SizedBox(width: context.wp(2)),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  color: _kSpellMint.withOpacity(0.16),
                                ),
                                child: Text(
                                  '-${bundle.discountPercent}%',
                                  style: TextStyle(
                                    color: _kSpellMint,
                                    fontSize: context.sp(9),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                            const Spacer(),
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: context.wp(4),
                                  vertical: context.hp(1.0)),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(13),
                                gradient: canAfford
                                    ? const LinearGradient(
                                        colors: [_kGold, _kEmber],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : null,
                                color: canAfford
                                    ? null
                                    : Colors.white.withOpacity(0.06),
                                border: canAfford
                                    ? null
                                    : Border.all(
                                        color: Colors.white.withOpacity(0.15)),
                                boxShadow: canAfford
                                    ? [
                                        BoxShadow(
                                          color: _kEmber.withOpacity(0.4),
                                          blurRadius: 14,
                                          offset: const Offset(0, 5),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _assetOrIcon(_kGemAsset,
                                      size: context.sp(16),
                                      fallbackIcon: Icons.diamond_rounded,
                                      fallbackColor: canAfford
                                          ? Colors.white
                                          : Colors.white54),
                                  SizedBox(width: context.wp(1.8)),
                                  Text(
                                    _fmt(cost),
                                    style: TextStyle(
                                      color: canAfford
                                          ? Colors.white
                                          : Colors.white.withOpacity(0.45),
                                      fontSize: context.sp(13),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Row of the actual spell icons a bundle contains, so it's obvious
  /// what's inside without opening anything. Random crates show a
  /// sample of the book with a "?" cap instead.
  Widget _buildBundleContents(
      _SpellBundle bundle, List<SpellData> contents, Color accent) {
    final isRandom = bundle.tier == null;
    final shown = isRandom ? contents.take(5).toList() : contents;

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.wp(2.5), vertical: context.hp(1.0)),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: Colors.black.withOpacity(0.35),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          ...shown.map(
            (spell) => Padding(
              padding: EdgeInsets.only(right: context.wp(2)),
              child: Container(
                width: context.sp(28),
                height: context.sp(28),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: spell.accentColor.withOpacity(0.14),
                  border: Border.all(
                      color: spell.accentColor.withOpacity(0.45), width: 1),
                ),
                child: Icon(spell.icon,
                    color: spell.accentColor, size: context.sp(15)),
              ),
            ),
          ),
          if (isRandom)
            Container(
              width: context.sp(28),
              height: context.sp(28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                color: Colors.white.withOpacity(0.06),
                border: Border.all(color: Colors.white.withOpacity(0.18)),
              ),
              child: Icon(Icons.question_mark_rounded,
                  color: Colors.white54, size: context.sp(14)),
            ),
          const Spacer(),
          Text(
            isRandom
                ? 'random roll'
                : '×${bundle.copiesPerSpell} each',
            style: TextStyle(
              color: accent.withOpacity(0.9),
              fontSize: context.sp(9.5),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  // ==================================================================
  // CASES
  // ==================================================================
  Widget _buildCasesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Cases',
          'Roll for ships, abilities and spells. Landing in a future update.',
          const Color(0xFFB68CFF),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _kCases.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: context.wp(3),
            mainAxisSpacing: context.wp(3),
            childAspectRatio: 0.72,
          ),
          itemBuilder: (context, i) => _buildCaseCard(_kCases[i]),
        ),
        SizedBox(height: context.hp(2.4)),
        _buildFootnote(
          Icons.hourglass_top_rounded,
          'Cases are still in the hangar. When they land, each one rolls a '
          'random reward from its rarity pool — the rarer the case, the '
          'better the odds.',
          const Color(0xFFB68CFF),
        ),
      ],
    );
  }

  Widget _buildFootnote(IconData icon, String text, Color color) {
    return Container(
      padding: EdgeInsets.all(context.wp(4)),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.035),
        border: Border.all(color: color.withOpacity(0.22), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: context.sp(18)),
          SizedBox(width: context.wp(3)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: context.sp(10.5),
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaseCard(_ShopCase caseItem) {
    final accent = caseItem.accentColor;

    return AnimatedTapButton(
      onTap: () {
        _tap();
        _showCaseComingSoon(caseItem);
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withOpacity(0.4), width: 1.1),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.14),
              blurRadius: 14,
              spreadRadius: -3,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16.9),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(const Color(0xFF13060F), accent, 0.16)!,
                  const Color(0xFF0B0300),
                ],
              ),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: context.wp(1.5), vertical: context.hp(1.6)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: context.sp(52),
                        height: context.sp(52),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              accent.withOpacity(0.28),
                              Colors.transparent
                            ],
                          ),
                        ),
                      ),
                      Icon(Icons.inventory_2_rounded,
                          color: accent.withOpacity(0.55),
                          size: context.sp(34)),
                      Container(
                        width: context.sp(20),
                        height: context.sp(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withOpacity(0.75),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.25), width: 1),
                        ),
                        child: Icon(Icons.lock_rounded,
                            color: Colors.white70, size: context.sp(11)),
                      ),
                    ],
                  ),
                  SizedBox(height: context.hp(1.0)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      caseItem.label.toUpperCase(),
                      style: TextStyle(
                        color: accent,
                        fontSize: context.sp(10),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  Text(
                    caseItem.rarity,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: context.sp(9),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: context.hp(0.9)),
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: context.wp(2), vertical: context.hp(0.35)),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white.withOpacity(0.07),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'SOON',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: context.sp(8),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================================================================
  // SHARED BITS
  // ==================================================================

  /// Diagonal light sweep, driven by the page-wide `_shine` controller.
  /// Drop it into a ClipRRect'd Stack and it rakes across the card.
  Widget _shineOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _shine,
          builder: (context, _) {
            // Sweep left -> right over the first half of the cycle,
            // then rest, so it reads as a glint rather than a strobe.
            final raw = (_shine.value * 2).clamp(0.0, 1.0);
            final x = -1.6 + raw * 3.2;
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(x, -1),
                  end: Alignment(x + 0.55, 1),
                  colors: [
                    Colors.white.withOpacity(0.0),
                    Colors.white.withOpacity(0.09),
                    Colors.white.withOpacity(0.0),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _tagChip(String label, Color color, {bool small = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 7 : 9,
        vertical: small ? 2.5 : 3.5,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [color, Color.lerp(color, Colors.black, 0.3)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 10)],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.black.withOpacity(0.85),
          fontSize: context.sp(small ? 8 : 8.5),
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Renders an asset image, falling back to an icon if the file
  /// isn't in the bundle — keeps the layout intact instead of showing
  /// Flutter's red error box.
  Widget _assetOrIcon(
    String asset, {
    required double size,
    required IconData fallbackIcon,
    required Color fallbackColor,
  }) {
    return Image.asset(
      asset,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stack) =>
          Icon(fallbackIcon, size: size, color: fallbackColor),
    );
  }
}

/// Kills the Android overscroll glow — the bouncing physics plus a
/// blue-ish glow on a dark game screen looks off.
class _NoGlowBehavior extends ScrollBehavior {
  const _NoGlowBehavior();

  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}

/// ====================================================================
/// SHIP FLY PREVIEW — the little Flame game each package card runs to
/// show the ACTUAL ship it unlocks, cruising rather than just sitting
/// there.
///
/// It's modelled on SkinPreviewGame in skins_page.dart, with two
/// differences that matter for a card-sized stage:
///
///   * the ship SIZES ITSELF to the box it's given instead of the
///     Skins page's fixed 240px, and the engine-flame numbers
///     (spread / particle radius / speed) are scaled by the same
///     factor — otherwise a trail tuned for a 240px ship swamps a
///     110px one;
///   * it actually FLIES: a slow lazy figure-eight across the stage
///     with a bank into each turn, instead of a vertical bob in place.
///
/// Transparent background, and the widget is wrapped in IgnorePointer
/// on the card so it never eats the card's buy tap.
/// ====================================================================
class ShipFlyPreviewGame extends FlameGame {
  ShipFlyPreviewGame({
    required this.shipAsset,
    required this.flameAccent,
    required this.engineOffsetYFraction,
    required this.flameSpread,
    required this.flameParticleRadius,
    required this.flameLength,
  });

  final String shipAsset;
  final Color flameAccent;
  final double engineOffsetYFraction;
  final double flameSpread;
  final double flameParticleRadius;
  final double flameLength;

  /// The Skins page tunes flameSpread / flameParticleRadius against a
  /// 240px ship, so everything here is scaled relative to that.
  static const double _referenceShipSize = 240;

  _FlyingShip? _ship;

  @override
  Color backgroundColor() => const Color(0x00000000); // transparent

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final sprite = await loadSprite(shipAsset);

    // Conservative sizing: leaves room for the flight path AND the
    // bank rotation without the sprite clipping the card edges.
    final shipSize = min(size.x * 0.44, size.y * 0.62);
    final scale = shipSize / _referenceShipSize;

    final ship = _FlyingShip(sprite: sprite, shipSize: shipSize)
      ..stage = size.clone();
    _ship = ship;
    add(ship);

    add(_FlyingEngineFlame(
      ship: ship,
      accentColor: flameAccent,
      engineOffsetYFraction: engineOffsetYFraction,
      spread: flameSpread * scale,
      particleRadius: flameParticleRadius * scale,
      length: flameLength,
      speedScale: scale,
    ));
  }

  @override
  void onGameResize(Vector2 newSize) {
    super.onGameResize(newSize);
    _ship?.stage = newSize.clone();
  }
}

/// The ship sprite itself. Traces a slow figure-eight (horizontal at
/// one rate, vertical at double it) and banks into each turn, so it
/// reads as a ship on patrol rather than a static picture.
class _FlyingShip extends SpriteComponent {
  _FlyingShip({required Sprite sprite, required double shipSize})
      : super(
          sprite: sprite,
          size: Vector2.all(shipSize),
          anchor: Anchor.center,
        );

  Vector2 stage = Vector2.zero();
  double _t = 0;

  static const double _sweepSpeed = 0.62; // radians/sec, horizontal
  static const double _maxBank = 0.17; // radians (~10 degrees)

  @override
  void update(double dt) {
    super.update(dt);
    if (stage.x <= 0 || stage.y <= 0) return;

    _t += dt;

    final ampX = stage.x * 0.15;
    final ampY = stage.y * 0.07;

    position.setValues(
      stage.x / 2 + sin(_t * _sweepSpeed) * ampX,
      stage.y / 2 + sin(_t * _sweepSpeed * 2) * ampY,
    );

    // Bank proportional to horizontal velocity — cos() is the
    // derivative of the sin() above, so this leans into the turn and
    // levels out at the ends of each sweep.
    angle = cos(_t * _sweepSpeed) * _maxBank;
  }
}

/// Engine-flame particle stream for the card preview — same look as
/// PreviewEngineFlame on the Skins page, but tracking [_FlyingShip]
/// and rotating its nozzle offset with the ship's bank so the trail
/// stays glued to the tail through the turns.
class _FlyingEngineFlame extends Component {
  _FlyingEngineFlame({
    required this.ship,
    required this.accentColor,
    required this.engineOffsetYFraction,
    required this.spread,
    required this.particleRadius,
    required this.length,
    required this.speedScale,
  });

  final _FlyingShip ship;
  final Color accentColor;
  final double engineOffsetYFraction;
  final double spread;
  final double particleRadius;
  final double length;
  final double speedScale;

  final List<_FlameBit> _bits = [];
  final Random _rng = Random();
  double _spawnTimer = 0;

  static const double _spawnInterval = 0.022;

  /// Rotates [v] by [angle] radians. Done by hand rather than with
  /// Flame's Vector2 extension so this file doesn't depend on which
  /// Flame version ships that helper.
  static Vector2 _rotated(Vector2 v, double angle) {
    final c = cos(angle);
    final s = sin(angle);
    return Vector2(v.x * c - v.y * s, v.x * s + v.y * c);
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Nozzle position, rotated with the ship so the flame follows the
    // bank instead of hanging straight down.
    final offset = _rotated(
      Vector2(0, ship.size.y * engineOffsetYFraction),
      ship.angle,
    );
    final enginePos = ship.position + offset;

    _spawnTimer += dt;
    if (_spawnTimer >= _spawnInterval) {
      _spawnTimer = 0;
      final life = (0.24 + _rng.nextDouble() * 0.14) * length;
      final velocity = _rotated(
        Vector2(
          (_rng.nextDouble() - 0.5) * (spread * 0.6),
          (_rng.nextDouble() * 90 + 90) * length * speedScale,
        ),
        ship.angle,
      );

      _bits.add(_FlameBit(
        position: enginePos + Vector2((_rng.nextDouble() - 0.5) * spread, 0),
        velocity: velocity,
        life: life,
        radius: _rng.nextDouble() * (particleRadius * 0.6) + particleRadius,
      ));
    }

    for (final bit in _bits) {
      bit.position += bit.velocity * dt;
      bit.age += dt;
    }
    _bits.removeWhere((bit) => bit.age >= bit.life);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final paint = Paint();
    for (final bit in _bits) {
      final t = (bit.age / bit.life).clamp(0.0, 1.0);
      final color =
          Color.lerp(Colors.white, accentColor, t) ?? accentColor;
      paint.color = color.withOpacity((1 - t) * 0.85);
      canvas.drawCircle(
        bit.position.toOffset(),
        bit.radius * (1 - t * 0.7),
        paint,
      );
    }
  }
}

class _FlameBit {
  _FlameBit({
    required this.position,
    required this.velocity,
    required this.life,
    required this.radius,
  });

  Vector2 position;
  final Vector2 velocity;
  final double life;
  final double radius;
  double age = 0;
}

/// ====================================================================
/// SPACE BACKGROUND — a small Flame game rendered behind the whole
/// page. Two cheap layers: a parallax starfield of ~60 twinkling dots
/// drawn in one pass with a single Paint, and warm embers spawned as
/// Flame particles that rise and fade.
///
/// Transparent background so the page's gradient shows through, and
/// wrapped in IgnorePointer above so it never steals a tap. Flip
/// [kShopAmbientBackground] to false to drop this layer entirely.
/// ====================================================================
class _SpaceBackground extends StatelessWidget {
  const _SpaceBackground({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GameWidget(game: _SpaceGame());
  }
}

class _SpaceGame extends FlameGame {
  final Random _rnd = Random();
  double _spawnTimer = 0;

  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(_StarField(count: 60)..priority = -10);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (size.x <= 0 || size.y <= 0) return;

    _spawnTimer += dt;
    const spawnEvery = 0.26;
    if (_spawnTimer >= spawnEvery) {
      _spawnTimer -= spawnEvery;
      _spawnEmber();
    }
  }

  void _spawnEmber() {
    final startX = _rnd.nextDouble() * size.x;
    final drift = (_rnd.nextDouble() - 0.5) * 46;
    final radius = 0.9 + _rnd.nextDouble() * 1.9;
    final lifespan = 3.4 + _rnd.nextDouble() * 2.8;

    add(
      ParticleSystemComponent(
        position: Vector2(startX, size.y + 10),
        particle: MovingParticle(
          from: Vector2.zero(),
          to: Vector2(drift, -(size.y + 70)),
          curve: Curves.easeOut,
          child: ComputedParticle(
            lifespan: lifespan,
            renderer: (canvas, particle) {
              final t = particle.progress;
              // Fade in fast, fade out over the tail.
              final alpha =
                  (t < 0.12 ? t / 0.12 : (1 - t) / 0.88).clamp(0.0, 1.0);
              final color =
                  Color.lerp(const Color(0xFFFFE29A), _kEmber, t)!
                      .withOpacity(alpha * 0.5);
              canvas.drawCircle(Offset.zero, radius, Paint()..color = color);
            },
          ),
        ),
      ),
    );
  }
}

class _Star {
  const _Star({
    required this.fx,
    required this.fy,
    required this.radius,
    required this.phase,
    required this.twinkleSpeed,
    required this.drift,
  });

  final double fx; // 0..1 across the screen
  final double fy; // 0..1 down the screen
  final double radius;
  final double phase;
  final double twinkleSpeed;
  final double drift; // px/sec upward
}

class _StarField extends Component {
  _StarField({required this.count});

  final int count;
  final Random _rnd = Random();
  final List<_Star> _stars = [];
  final Paint _paint = Paint();

  Vector2 _area = Vector2.zero();
  double _elapsed = 0;

  @override
  Future<void> onLoad() async {
    for (var i = 0; i < count; i++) {
      _stars.add(
        _Star(
          fx: _rnd.nextDouble(),
          fy: _rnd.nextDouble(),
          radius: 0.5 + _rnd.nextDouble() * 1.3,
          phase: _rnd.nextDouble() * pi * 2,
          twinkleSpeed: 0.5 + _rnd.nextDouble() * 1.4,
          drift: 2 + _rnd.nextDouble() * 7,
        ),
      );
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _area = size;
  }

  @override
  void update(double dt) {
    _elapsed += dt;
  }

  @override
  void render(Canvas canvas) {
    if (_area.x <= 0 || _area.y <= 0) return;

    for (final star in _stars) {
      final twinkle = 0.3 +
          0.7 * (0.5 + 0.5 * sin(_elapsed * star.twinkleSpeed + star.phase));
      // Dart's % on doubles always returns a non-negative result for a
      // positive divisor, so this wraps cleanly as stars drift off-screen.
      final y = (star.fy * _area.y - _elapsed * star.drift) % _area.y;
      _paint.color = Colors.white.withOpacity(0.42 * twinkle);
      canvas.drawCircle(Offset(star.fx * _area.x, y), star.radius, _paint);
    }
  }
}