import 'package:flutter/material.dart';
import 'package:cosmic_fury/src/pages/skins/skins_page.dart';
// ^ pulls in gemsNotifier, equippedSkinNotifier, kSkins, and
//   AnimatedTapButton — this page reads the REAL equipped ship to
//   decide which spell tiers are unlocked, and spends from the same
//   gem balance shown everywhere else in the game.

/// ------------------------------------------------------------
/// SPELL DATA
/// ------------------------------------------------------------
enum SpellTier { basic, advanced, elite }

extension SpellTierX on SpellTier {
  int get rank => index + 1; // 1, 2, 3
  String get label {
    switch (this) {
      case SpellTier.basic:
        return 'Basic';
      case SpellTier.advanced:
        return 'Advanced';
      case SpellTier.elite:
        return 'Elite';
    }
  }
}

class SpellData {
  final String id;
  final String name;

  /// Short blurb shown on the card itself — kept to ~2 lines.
  final String description;

  /// Full mechanical writeup shown in the info sheet when the player
  /// taps the (i) icon on a card — every number here should match
  /// exactly what level_page.dart's _castSpell handlers actually do.
  final String fullDescription;

  final IconData icon;
  final int gemCost; // cost per copy purchased
  final SpellTier tier;
  final Color accentColor;

  const SpellData({
    required this.id,
    required this.name,
    required this.description,
    required this.fullDescription,
    required this.icon,
    required this.gemCost,
    required this.tier,
    required this.accentColor,
  });
}

const List<SpellData> kAllSpells = [
  // ---------------- Tier 1 — Basic ----------------
  // NOTE: descriptions below match exactly what each spell actually
  // does in level_page.dart's _castSpell handlers — see that file
  // for the implementation each of these is describing.
  SpellData(
    id: 'spark_shot',
    name: 'Spark Shot',
    description:
        'Fires at a blistering rate for 5 seconds, completely free — no energy is spent the whole time.',
    fullDescription:
        'For 5 seconds your guns fire at a blistering 0.10s cadence and '
        'cost zero energy — not discounted, actually free. Energy is '
        'never read or spent at all during the window. Once it ends, '
        'your fire rate and energy spending return to normal exactly '
        'where they left off.',
    icon: Icons.flash_on,
    gemCost: 40,
    tier: SpellTier.basic,
    accentColor: Color(0xFFFFC371),
  ),
  SpellData(
    id: 'shield_burst',
    name: 'Shield Burst',
    description:
        'Throws up a barrier that blocks the next 13 hits, lasting up to 10 seconds.',
    fullDescription:
        'Instantly raises a barrier that blocks the next 13 hits '
        'outright — no damage gets through at all, whether it\'s an '
        'enemy bullet stopping right on the visible shield ring or an '
        'enemy ramming you. The shield lasts up to 10 seconds, but '
        'drops early the moment all 13 charges are used up.',
    icon: Icons.shield,
    gemCost: 60,
    tier: SpellTier.basic,
    accentColor: Color(0xFF6FCBFF),
  ),
  SpellData(
    id: 'nano_repair',
    name: 'Nano Repair',
    description:
        'Nanobots patch the hull instantly, restoring 60% of your max health.',
    fullDescription:
        'Nanobots swarm the hull and repair it instantly, restoring '
        '60% of your ship\'s maximum health in one burst. It\'s a flat '
        'percentage, so it scales with whichever ship you have '
        'equipped — a tankier ship gets more HP back per cast.',
    icon: Icons.healing,
    gemCost: 55,
    tier: SpellTier.basic,
    accentColor: Color(0xFF7CFFB2),
  ),
  SpellData(
    id: 'ice_nova',
    name: 'Ice Nova',
    description:
        'Freezes up to 7 of the nearest enemies in place for 4 seconds.',
    fullDescription:
        'Sends out a freezing pulse that locks up to 7 of the nearest '
        'enemies in place for 4 seconds. Frozen enemies can\'t move or '
        'fire, but they can still be damaged and killed normally — '
        'it\'s a great window to focus a target down safely.',
    icon: Icons.ac_unit,
    gemCost: 50,
    tier: SpellTier.basic,
    accentColor: Color(0xFF9BE7FF),
  ),
  SpellData(
    id: 'scrap_magnet',
    name: 'Scrap Magnet',
    description:
        'Rips 100 health and 15 energy off nearby enemies over 10 seconds and pulls it straight into your ship.',
    fullDescription:
        'Rips a flat 100 health and 15 energy off nearby enemies over '
        '10 seconds, streaming it straight into your ship in small '
        'ticks. The health stream is real damage, not just a visual — '
        'each pull actually hurts the enemy it comes from, so a weak '
        'enemy can be finished off by it. You still get the full heal '
        'even if no enemy is around to pull from.',
    icon: Icons.attractions,
    gemCost: 35,
    tier: SpellTier.basic,
    accentColor: Color(0xFFE0C066),
  ),

  // ---------------- Tier 2 — Advanced ----------------
  // NOTE: same rule applies here — every number matches level_page's
  // _castHomingMissiles / _castEmpPulse / _castOvercharge /
  // _castChainLightning / _castTimeWarp exactly.
  SpellData(
    id: 'homing_missiles',
    name: 'Homing Missiles',
    description:
        'Launches 4 heat-seeking missiles at up to 4 nearby enemies, dealing 350 damage each — they never miss.',
    fullDescription:
        'Fires 4 missiles at once, each locking onto a different '
        'nearby enemy (closest first). Every missile tracks its '
        'target\'s exact position as it flies, so it can\'t miss unless '
        'that enemy dies to something else first — in which case the '
        'missile just fizzles out quietly. Each missile that connects '
        'deals 350 damage.',
    icon: Icons.rocket_launch,
    gemCost: 90,
    tier: SpellTier.advanced,
    accentColor: Color(0xFFFF8A5C),
  ),
  SpellData(
    id: 'emp_pulse',
    name: 'EMP Pulse',
    description:
        'Knocks out every enemy\'s weapons on screen for 10 seconds — they can\'t fire, but can still move and ram.',
    fullDescription:
        'Sends out an EMP burst that disables firing on every enemy '
        'currently on screen for 10 seconds. Affected enemies keep '
        'moving, dodging, and ramming normally — only their guns go '
        'offline. Enemies that spawn after the pulse goes off aren\'t '
        'affected.',
    icon: Icons.bolt,
    gemCost: 85,
    tier: SpellTier.advanced,
    accentColor: Color(0xFFB68CFF),
  ),
  SpellData(
    id: 'overcharge',
    name: 'Overcharge',
    description: 'Adds a flat +70 damage to every bullet you fire for 10 seconds.',
    fullDescription:
        'Supercharges your weapons, adding a flat +70 damage on top of '
        'every bullet you fire for the next 10 seconds. It stacks with '
        'your ship\'s base damage, and the bonus is applied the instant '
        'a bullet lands — so changing fire rate or ships mid-window '
        'doesn\'t weaken it.',
    icon: Icons.local_fire_department,
    gemCost: 100,
    tier: SpellTier.advanced,
    accentColor: Color(0xFFFF5F5F),
  ),
  SpellData(
    id: 'chain_lightning',
    name: 'Chain Lightning',
    description:
        '4 bolts of 150 damage, chaining across enemies on screen — loops back onto the same targets if there aren\'t 4 to hit.',
    fullDescription:
        'Unleashes 4 bolts of lightning at 150 damage each, chaining '
        'outward starting from your ship. With 4 or more enemies on '
        'screen it hits four different targets once each. With fewer '
        'enemies the extra bolts loop back: 3 enemies means one of '
        'them takes 2 bolts, 2 enemies means both take 2 bolts each, '
        'and a single enemy on screen eats all 4 bolts for 600 total '
        'damage.',
    icon: Icons.electric_bolt,
    gemCost: 95,
    tier: SpellTier.advanced,
    accentColor: Color(0xFF6FE3FF),
  ),
  SpellData(
    id: 'time_warp',
    name: 'Time Warp',
    description:
        'Slows every enemy\'s movement and bullets to a third speed for 7 seconds.',
    fullDescription:
        'Warps time around every enemy currently on screen, slowing '
        'both their movement and their bullet speed to 1/3 normal for '
        '7 seconds. Their fire rate — how often they shoot — is '
        'untouched, it\'s only how fast they move and how fast what '
        'they fire actually travels. Enemies that spawn after the cast '
        'aren\'t affected.',
    icon: Icons.hourglass_bottom,
    gemCost: 110,
    tier: SpellTier.advanced,
    accentColor: Color(0xFFC9A6FF),
  ),

  // ---------------- Tier 3 — Elite ----------------
  // NOTE: same rule applies here too — every number matches
  // level_page's _castBlackHole / _castOverdriveCore / _castSolarFlare
  // / _castGravityWell / _castSingularityBomb exactly.
  SpellData(
    id: 'black_hole',
    name: 'Black Hole',
    description:
        'Opens a singularity at screen center that drags in up to 5 enemies — weak ones vanish, tough ones take 400 damage and break free.',
    fullDescription:
        'Conjures a collapsing singularity at the center of the screen '
        'that reaches out and drags in the nearest enemies until 5 '
        'have been pulled to the center or 10 seconds pass — '
        'whichever comes first. Any enemy with under 400 health that '
        'reaches the center is crushed instantly. Anything with 400 '
        'health or more instead takes a flat 400 damage and gets '
        'flung back out, free to act normally again. The hole closes '
        'the instant it has processed 5 enemies, even if that happens '
        'well before the 10 seconds are up.',
    icon: Icons.blur_circular,
    gemCost: 180,
    tier: SpellTier.elite,
    accentColor: Color(0xFF8B7CFF),
  ),
  SpellData(
    id: 'phoenix_rebirth',
    name: 'Overdrive Core',
    description:
        'Permanently boosts your ship by +300 max health and +50 bullet damage for the rest of the level. Can only be triggered once per level.',
    fullDescription:
        'Overclocks your ship\'s core for the remainder of the level, '
        'permanently adding +300 to your maximum health (healing you '
        'for the same amount immediately) and +50 flat damage to '
        'every bullet you fire from now on. The boost never wears '
        'off, but the core can only be ignited once per level — '
        'casting it again afterward does nothing and hands back the '
        'copy you tried to spend.',
    icon: Icons.offline_bolt,
    gemCost: 220,
    tier: SpellTier.elite,
    accentColor: Color(0xFFFFB25C),
  ),
  SpellData(
    id: 'solar_flare',
    name: 'Solar Flare',
    description:
        'Unleashes a blinding flare across the whole screen, hitting every enemy currently on screen for 500 damage.',
    fullDescription:
        'Channels a blinding solar flare that sweeps across the '
        'entire screen in an instant, dealing a flat 500 damage to '
        'every enemy on screen the moment it\'s cast. Enemies that '
        'spawn after the flash aren\'t touched — only what\'s on '
        'screen right when you cast it.',
    icon: Icons.wb_sunny,
    gemCost: 200,
    tier: SpellTier.elite,
    accentColor: Color(0xFFFFD65C),
  ),
  SpellData(
    id: 'gravity_well',
    name: 'Gravity Well',
    description:
        'Traps every enemy on screen in a crushing gravity field for 6 seconds, tearing them apart with damage over time.',
    fullDescription:
        'Opens a gravity well that locks every enemy currently on '
        'screen in place for 6 seconds — they can\'t move or fire '
        'while trapped — and ticks 30 damage into each of them every '
        'half-second, for up to 360 total damage per enemy if the '
        'well runs its full course. Enemies that die mid-well are '
        'simply removed from it; the well itself closes automatically '
        'once the 6 seconds are up.',
    icon: Icons.brightness_2,
    gemCost: 190,
    tier: SpellTier.elite,
    accentColor: Color(0xFF7C8CFF),
  ),
  SpellData(
    id: 'singularity_bomb',
    name: 'Singularity Bomb',
    description:
        'Launches a bomb to the center of the screen for a 1000-damage blast, then sprays 10 fragments outward for 150 damage each.',
    fullDescription:
        'Lobs a heavy bomb toward the center of the screen. On '
        'arrival it detonates for 1000 damage to any enemy caught in '
        'the blast radius, then immediately sprays 10 fragments '
        'outward in a full circle, each one dealing 150 damage to the '
        'first enemy it touches before burning out.',
    icon: Icons.whatshot,
    gemCost: 260,
    tier: SpellTier.elite,
    accentColor: Color(0xFFFF4D4D),
  ),
];

/// How many spells can be brought into a fight at once. Purchase
/// quantity itself is uncapped — the player can buy as many copies of
/// a spell as they want, this only limits the battle loadout.
const int kMaxEquippedSpells = 3;

/// ------------------------------------------------------------
/// PER-SHIP UNLOCK TABLE
///
/// Each entry is [basicUnlocked, advancedUnlocked, eliteUnlocked] —
/// how many of that tier's 5 spells are available (in list order)
/// once that ship (by its index in kSkins) is the one equipped:
///
///   Ship 1 (Falcon)        -> Tier 1 only
///   Ship 2 (Interceptor)   -> Tier 1 full, Tier 2 half (3/5)
///   Ship 3 (Nebula)        -> Tier 1 full, Tier 2 full
///   Ship 4 (Frostbyte)     -> Tier 1+2 full, Tier 3 half (3/5)
///   Ship 5 (Shadow Reaper) -> everything
///
/// If kSkins ever grows past 5 entries, any extra ship falls back to
/// the last row (everything unlocked) via the clamp in
/// [unlockedCountForTier].
/// ------------------------------------------------------------
const List<List<int>> kTierUnlockCounts = [
  [5, 0, 0], // Falcon Mk.I
  [5, 3, 0], // Interceptor
  [5, 5, 0], // Nebula
  [5, 5, 3], // Frostbyte
  [5, 5, 5], // Shadow Reaper
];

/// ------------------------------------------------------------
/// SHARED STATE — defined at top level (same pattern as gemsNotifier
/// / ownedSkinAssetsNotifier in skins_page.dart) so the shop page and
/// the separate battle-loadout page both read/write the exact same
/// data instead of each keeping their own out-of-sync copy.
/// ------------------------------------------------------------

/// spellId -> how many copies the player owns. Uncapped.
final ValueNotifier<Map<String, int>> ownedSpellCountsNotifier =
    ValueNotifier<Map<String, int>>({});

/// The (up to kMaxEquippedSpells) spells picked for the next fight.
final ValueNotifier<Set<String>> equippedSpellIdsNotifier =
    ValueNotifier<Set<String>>({});

int ownedCountOf(SpellData spell) =>
    ownedSpellCountsNotifier.value[spell.id] ?? 0;

/// Position of [spell] within its own tier's 5-spell list (0-4) —
/// checked against kTierUnlockCounts to see if it's unlocked yet.
int spellTierPosition(SpellData spell) {
  final tierSpells = kAllSpells.where((s) => s.tier == spell.tier).toList();
  return tierSpells.indexOf(spell);
}

int shipIndexOf(SkinData ship) {
  final idx = kSkins.indexOf(ship);
  return idx == -1 ? 0 : idx;
}

int unlockedCountForTier(int shipIndex, SpellTier tier) {
  final row =
      kTierUnlockCounts[shipIndex.clamp(0, kTierUnlockCounts.length - 1)];
  return row[tier.index];
}

bool isSpellLocked(SpellData spell, int shipIndex) {
  final unlocked = unlockedCountForTier(shipIndex, spell.tier);
  return spellTierPosition(spell) >= unlocked;
}

/// Buys one more copy of [spell]. No ownership cap — the player can
/// keep buying as long as they have the gems. Returns true if the
/// purchase went through, false if there weren't enough gems.
bool buySpell(SpellData spell) {
  if (gemsNotifier.value < spell.gemCost) return false;
  gemsNotifier.value -= spell.gemCost;
  ownedSpellCountsNotifier.value = {
    ...ownedSpellCountsNotifier.value,
    spell.id: ownedCountOf(spell) + 1,
  };
  return true;
}

/// Toggles [spell] in/out of the battle loadout. Returns null on
/// success, or a short error message to show the player on failure
/// (locked, not owned, or loadout already full).
String? toggleEquipSpell(SpellData spell, int shipIndex) {
  if (isSpellLocked(spell, shipIndex)) {
    return '${spell.name} needs a stronger ship to unlock.';
  }
  if (ownedCountOf(spell) <= 0) {
    return 'Buy ${spell.name} from the shop first.';
  }
  final current = {...equippedSpellIdsNotifier.value};
  if (current.contains(spell.id)) {
    current.remove(spell.id);
    equippedSpellIdsNotifier.value = current;
    return null;
  }
  if (current.length >= kMaxEquippedSpells) {
    return 'You can only equip $kMaxEquippedSpells spells at a time.';
  }
  current.add(spell.id);
  equippedSpellIdsNotifier.value = current;
  return null;
}

/// Small reusable gem icon — the same budget.png asset used for the
/// gem stat card everywhere else in the game, instead of a generic
/// diamond glyph.
Widget _gemIcon(double size) => Image.asset(
      'assets/images/budget.png',
      width: size,
      height: size,
    );

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF2A0F05),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
}

/// ------------------------------------------------------------------
/// SPELL INFO SHEET — full mechanical writeup for a spell, opened by
/// tapping the (i) icon on any spell card (shop or loadout, locked or
/// unlocked). Shows the icon, name, tier badge, gem cost, and the
/// spell's full description — a separate tap target from the card's
/// own buy/equip behavior, so viewing info never spends gems or
/// changes the loadout.
/// ------------------------------------------------------------------
void _showSpellInfo(BuildContext context, SpellData spell) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          margin: const EdgeInsets.all(14),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A).withOpacity(0.98),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: spell.accentColor.withOpacity(0.55)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black,
                      border: Border.all(
                        color: spell.accentColor.withOpacity(0.85),
                        width: 1.4,
                      ),
                    ),
                    child: Icon(spell.icon, color: spell.accentColor, size: 23),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          spell.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.black,
                                border: Border.all(
                                  color: spell.accentColor.withOpacity(0.5),
                                ),
                              ),
                              child: Text(
                                'Tier ${spell.tier.rank} · ${spell.tier.label}',
                                style: TextStyle(
                                  color: spell.accentColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _gemIcon(12),
                            const SizedBox(width: 4),
                            Text(
                              '${spell.gemCost}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.grey.shade500,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                spell.fullDescription,
                style: TextStyle(
                  color: Colors.grey.shade300,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Small (i) tap target used on both the shop and loadout cards —
/// deliberately a separate GestureDetector from the card's own
/// AnimatedTapButton, so tapping it opens the info sheet without
/// triggering a buy or an equip toggle.
Widget _infoButton(BuildContext context, SpellData spell) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => _showSpellInfo(context, spell),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Icon(
        Icons.info_outline_rounded,
        size: 16,
        color: Colors.grey.shade500,
      ),
    ),
  );
}

/// ------------------------------------------------------------------
/// SHOP — browse & buy. No back arrow (this page lives as a bottom-nav
/// / main-flow destination, same as SkinsPage). Equipping for battle
/// happens on the separate SpellLoadoutPage, reached via the pill in
/// the header.
/// ------------------------------------------------------------------
class SpellsPage extends StatelessWidget {
  const SpellsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ValueListenableBuilder<SkinData>(
          valueListenable: equippedSkinNotifier,
          builder: (context, ship, _) {
            final shipIndex = shipIndexOf(ship);
            return Column(
              children: [
                _buildHeader(context, ship),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      ..._buildTierSection(SpellTier.basic, shipIndex),
                      ..._buildTierSection(SpellTier.advanced, shipIndex),
                      ..._buildTierSection(SpellTier.elite, shipIndex),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Header: title, gem balance, ship line, and a "Battle Loadout"
  // pill that opens the separate selection page. No back arrow — this
  // page is a main destination, not a pushed sub-page.
  // ------------------------------------------------------------------
  Widget _buildHeader(BuildContext context, SkinData ship) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Spells',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              ValueListenableBuilder<int>(
                valueListenable: gemsNotifier,
                builder: (context, gems, _) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.deepOrange.shade900),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _gemIcon(16),
                      const SizedBox(width: 6),
                      Text(
                        '$gems',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Flying ${ship.name} — buy spells for your arsenal',
                  style: const TextStyle(color: Colors.grey, fontSize: 12.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              AnimatedTapButton(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SpellLoadoutPage(),
                    ),
                  );
                },
                child: ValueListenableBuilder<Set<String>>(
                  valueListenable: equippedSpellIdsNotifier,
                  builder: (context, equipped, _) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFC371), Color(0xFFFF5F3D)],
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome,
                            color: Colors.white, size: 13),
                        const SizedBox(width: 5),
                        Text(
                          'Loadout ${equipped.length}/$kMaxEquippedSpells',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // One tier section: heading (with an "N/5 unlocked" badge when
  // partially open, or a lock icon when fully closed) + its 5 cards.
  // ------------------------------------------------------------------
  List<Widget> _buildTierSection(SpellTier tier, int shipIndex) {
    final spells = kAllSpells.where((s) => s.tier == tier).toList();
    final unlockedCount = unlockedCountForTier(shipIndex, tier);
    final fullyLocked = unlockedCount == 0;
    final partiallyUnlocked =
        unlockedCount > 0 && unlockedCount < spells.length;

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Row(
          children: [
            Text(
              'Tier ${tier.rank} · ${tier.label}',
              style: TextStyle(
                color:
                    fullyLocked ? Colors.grey.shade600 : Colors.orangeAccent,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
            if (fullyLocked) ...[
              const SizedBox(width: 6),
              Icon(Icons.lock, size: 13, color: Colors.grey.shade600),
            ],
            if (partiallyUnlocked) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.black,
                  border: Border.all(
                      color: Colors.orangeAccent.withOpacity(0.5)),
                ),
                child: Text(
                  '$unlockedCount/${spells.length} unlocked',
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      ...spells.map((s) => _buildSpellCard(s, shipIndex)),
    ];
  }

  // ------------------------------------------------------------------
  // A single spell card — buy-only. Tapping the card body (while
  // unlocked) buys one more copy every time, no cap. The small (i)
  // icon next to the name is a separate tap target that opens the
  // full info sheet instead — it works even while locked, so the
  // player can still read what a spell does before unlocking it.
  // ------------------------------------------------------------------
  Widget _buildSpellCard(SpellData spell, int shipIndex) {
    final locked = isSpellLocked(spell, shipIndex);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Builder(
        builder: (context) => AnimatedTapButton(
          onTap: () {
            if (locked) {
              _showSnack(context, '${spell.name} needs a stronger ship to unlock.');
              return;
            }
            final bought = buySpell(spell);
            if (!bought) {
              _showSnack(context, 'Not enough gems for ${spell.name}.');
            }
          },
          child: Opacity(
            opacity: locked ? 0.55 : 1.0,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF141414), Color(0xFF0A0A0A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: Colors.deepOrange.shade900.withOpacity(0.7),
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Icon medallion
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black,
                      border: Border.all(
                        color: locked
                            ? Colors.grey.shade700
                            : spell.accentColor.withOpacity(0.8),
                        width: 1.4,
                      ),
                    ),
                    child: Icon(
                      locked ? Icons.lock : spell.icon,
                      color: locked ? Colors.grey.shade600 : spell.accentColor,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Name (+ info icon) + description
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                spell.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            _infoButton(context, spell),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          locked
                              ? 'Requires a stronger ship to unlock.'
                              : spell.description,
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 11.5,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Trailing: owned count + buy pill.
                  if (!locked)
                    ValueListenableBuilder<Map<String, int>>(
                      valueListenable: ownedSpellCountsNotifier,
                      builder: (context, owned, _) {
                        final count = owned[spell.id] ?? 0;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'x$count',
                              style: TextStyle(
                                color: count > 0
                                    ? Colors.white
                                    : Colors.grey.shade600,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(11),
                                color: Colors.black,
                                border: Border.all(
                                  color: const Color(0xFF9BE7FF)
                                      .withOpacity(0.6),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _gemIcon(12),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${spell.gemCost}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    )
                  else
                    const SizedBox(width: 44),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------------
/// BATTLE LOADOUT — a separate page, reached from the shop's header
/// pill. Only shows spells the player actually owns; tapping an
/// unlocked, owned spell toggles it in/out of the 3-spell loadout.
/// This page keeps its own back arrow since it's a pushed sub-page,
/// not a main destination.
/// ------------------------------------------------------------------
class SpellLoadoutPage extends StatelessWidget {
  const SpellLoadoutPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ValueListenableBuilder<SkinData>(
          valueListenable: equippedSkinNotifier,
          builder: (context, ship, _) {
            final shipIndex = shipIndexOf(ship);
            return ValueListenableBuilder<Map<String, int>>(
              valueListenable: ownedSpellCountsNotifier,
              builder: (context, owned, _) {
                final ownedSpells = kAllSpells
                    .where((s) => (owned[s.id] ?? 0) > 0)
                    .toList();

                return Column(
                  children: [
                    _buildHeader(context, ship),
                    Expanded(
                      child: ownedSpells.isEmpty
                          ? _buildEmptyState()
                          : ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              children: ownedSpells
                                  .map((s) => _buildLoadoutCard(
                                      context, s, shipIndex, owned[s.id]!))
                                  .toList(),
                            ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, SkinData ship) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.orangeAccent, size: 18),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const Text(
                'Battle Loadout',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Flying ${ship.name} — choose $kMaxEquippedSpells spells',
                  style: const TextStyle(color: Colors.grey, fontSize: 12.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<Set<String>>(
                valueListenable: equippedSpellIdsNotifier,
                builder: (context, equipped, _) => Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFC371), Color(0xFFFF5F3D)],
                    ),
                  ),
                  child: Text(
                    '${equipped.length}/$kMaxEquippedSpells selected',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined,
                color: Colors.grey.shade700, size: 40),
            const SizedBox(height: 12),
            Text(
              "You haven't bought any spells yet.\nHead to the Spells shop first.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // A single loadout card — tapping the card body toggles it in/out
  // of the battle loadout. The small (i) icon next to the name is a
  // separate tap target that opens the full info sheet instead of
  // toggling equip state.
  // ------------------------------------------------------------------
  Widget _buildLoadoutCard(
      BuildContext context, SpellData spell, int shipIndex, int count) {
    final locked = isSpellLocked(spell, shipIndex);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedTapButton(
        onTap: () {
          final error = toggleEquipSpell(spell, shipIndex);
          if (error != null) _showSnack(context, error);
        },
        child: Opacity(
          opacity: locked ? 0.55 : 1.0,
          child: ValueListenableBuilder<Set<String>>(
            valueListenable: equippedSpellIdsNotifier,
            builder: (context, equippedIds, _) {
              final equipped = equippedIds.contains(spell.id);
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: equipped
                        ? [const Color(0xFF3D1707), const Color(0xFF160600)]
                        : [const Color(0xFF141414), const Color(0xFF0A0A0A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: equipped
                        ? Colors.orangeAccent
                        : Colors.deepOrange.shade900.withOpacity(0.7),
                    width: equipped ? 1.6 : 1,
                  ),
                  boxShadow: equipped
                      ? [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black,
                        border: Border.all(
                          color: locked
                              ? Colors.grey.shade700
                              : spell.accentColor.withOpacity(0.8),
                          width: 1.4,
                        ),
                      ),
                      child: Icon(
                        locked ? Icons.lock : spell.icon,
                        color:
                            locked ? Colors.grey.shade600 : spell.accentColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  spell.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              _infoButton(context, spell),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            locked
                                ? 'Requires a stronger ship to unlock.'
                                : 'Owned x$count',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            equipped ? Colors.orangeAccent : Colors.transparent,
                        border: Border.all(
                          color: equipped
                              ? Colors.orangeAccent
                              : Colors.grey.shade600,
                          width: 1.5,
                        ),
                      ),
                      child: equipped
                          ? const Icon(Icons.check,
                              color: Colors.black, size: 16)
                          : null,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}