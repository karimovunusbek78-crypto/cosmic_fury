// spells_detector.dart
import 'dart:async';
import 'package:cosmic_fury/src/pages/skins/skins_page.dart';
import 'package:flutter/material.dart';
import 'package:cosmic_fury/src/pages/spells/spells_page.dart';
// ^ adjust this path to wherever spells_page.dart actually lives —
//   this pulls in kAllSpells, equippedSpellIdsNotifier,
//   ownedSpellCountsNotifier, SpellData, SpellTier, and
//   AnimatedTapButton, so this widget never drifts from what the
//   shop/loadout pages show.

/// Cooldown per tier (seconds) — how long a spell stays greyed out
/// after casting, so it can't be spammed every frame.
const Map<SpellTier, double> kSpellCooldownSeconds = {
  SpellTier.basic: 6,
  SpellTier.advanced: 10,
  SpellTier.elite: 15,
};

/// In-battle spell HUD.
///
/// Collapsed = the first equipped spell's icon + owned count, sitting
/// right next to a separate forward-arrow tap target:
///  - Tapping the spell icon/count DIRECTLY CASTS that spell (quick
///    cast — no need to open anything first).
///  - Tapping the forward arrow expands the full spell list.
///
/// Expanded = every equipped spell in a list; tapping a spell row
/// casts it WITHOUT closing the list — the list only closes when the
/// back arrow at the top is tapped.
///
/// This widget only tracks charges/cooldowns for display — the
/// actual gameplay effect lives in [onCast], supplied by the level
/// page.
class SpellsDetector extends StatefulWidget {
  final void Function(SpellData spell) onCast;

  const SpellsDetector({Key? key, required this.onCast}) : super(key: key);

  @override
  State<SpellsDetector> createState() => _SpellsDetectorState();
}

class _SpellsDetectorState extends State<SpellsDetector> {
  bool _expanded = false;
  final Map<String, Timer> _cooldownTimers = {};
  final Map<String, ValueNotifier<double>> _cooldownFractions = {};

  @override
  void dispose() {
    for (final t in _cooldownTimers.values) {
      t.cancel();
    }
    for (final n in _cooldownFractions.values) {
      n.dispose();
    }
    super.dispose();
  }

  bool _isOnCooldown(String spellId) =>
      (_cooldownFractions[spellId]?.value ?? 0) > 0;

  void _startCooldown(SpellData spell) {
    final totalSeconds = kSpellCooldownSeconds[spell.tier] ?? 6;
    final fraction = _cooldownFractions.putIfAbsent(
      spell.id,
      () => ValueNotifier<double>(0),
    );
    fraction.value = 1.0;

    _cooldownTimers[spell.id]?.cancel();

    const tickMs = 100;
    var elapsedMs = 0;
    _cooldownTimers[spell.id] = Timer.periodic(
      const Duration(milliseconds: tickMs),
      (timer) {
        elapsedMs += tickMs;
        final remaining =
            (1 - (elapsedMs / (totalSeconds * 1000))).clamp(0.0, 1.0);
        fraction.value = remaining;
        if (remaining <= 0) {
          timer.cancel();
        }
      },
    );
  }

  void _tryCast(SpellData spell, int ownedCount) {
    if (ownedCount <= 0) return;
    if (_isOnCooldown(spell.id)) return;

    ownedSpellCountsNotifier.value = {
      ...ownedSpellCountsNotifier.value,
      spell.id: ownedCount - 1,
    };

    _startCooldown(spell);
    widget.onCast(spell);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: equippedSpellIdsNotifier,
      builder: (context, equippedIds, _) {
        final equippedSpells =
            kAllSpells.where((s) => equippedIds.contains(s.id)).toList();

        if (equippedSpells.isEmpty) {
          return const SizedBox.shrink();
        }

        return Align(
          alignment: Alignment.centerLeft,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topLeft,
            child: _expanded
                ? _buildExpandedList(equippedSpells)
                : _buildCollapsedPill(equippedSpells),
          ),
        );
      },
    );
  }

  /// Collapsed pill: two independent tap targets side by side.
  ///  - Left (icon + count): quick-casts the first equipped spell
  ///    directly, same as tapping it in the expanded list would.
  ///  - Right (forward arrow): expands the full list. Nothing else
  ///    in the pill opens the list.
  Widget _buildCollapsedPill(List<SpellData> equippedSpells) {
    final first = equippedSpells.first;

    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: ownedSpellCountsNotifier,
      builder: (context, owned, _) {
        final count = owned[first.id] ?? 0;
        final fraction = _cooldownFractions.putIfAbsent(
          first.id,
          () => ValueNotifier<double>(0),
        );

        return ValueListenableBuilder<double>(
          valueListenable: fraction,
          builder: (context, cooldownFraction, _) {
            final onCooldown = cooldownFraction > 0;
            final usable = count > 0 && !onCooldown;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: first.accentColor.withOpacity(0.7)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // QUICK-CAST — tapping the spell itself casts it,
                  // no need to open the list at all.
                  AnimatedTapButton(
                    onTap: () => _tryCast(first, count),
                    child: Opacity(
                      opacity: usable ? 1.0 : 0.45,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (onCooldown)
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      value: 1 - cooldownFraction,
                                      strokeWidth: 2,
                                      color: first.accentColor,
                                      backgroundColor: Colors.white24,
                                    ),
                                    Icon(
                                      first.icon,
                                      color: first.accentColor,
                                      size: 12,
                                    ),
                                  ],
                                ),
                              )
                            else
                              Icon(
                                first.icon,
                                color: first.accentColor,
                                size: 20,
                              ),
                            const SizedBox(width: 6),
                            Text(
                              'x$count',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // OPEN LIST — the only thing that expands the full
                  // spell list. Separate tap target from the quick
                  // cast above so the two never fight each other.
                  AnimatedTapButton(
                    onTap: () => setState(() => _expanded = true),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildExpandedList(List<SpellData> equippedSpells) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'SPELLS',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              // The ONLY way to close the expanded list — tapping a
              // spell row below casts it but deliberately leaves the
              // list open.
              GestureDetector(
                onTap: () => setState(() => _expanded = false),
                child: const Icon(Icons.chevron_left_rounded,
                    color: Colors.white70, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...equippedSpells.map(_buildSpellRow),
        ],
      ),
    );
  }

  Widget _buildSpellRow(SpellData spell) {
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: ownedSpellCountsNotifier,
      builder: (context, owned, _) {
        final count = owned[spell.id] ?? 0;
        final fraction = _cooldownFractions.putIfAbsent(
          spell.id,
          () => ValueNotifier<double>(0),
        );

        return ValueListenableBuilder<double>(
          valueListenable: fraction,
          builder: (context, cooldownFraction, _) {
            final onCooldown = cooldownFraction > 0;
            final usable = count > 0 && !onCooldown;

            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: AnimatedTapButton(
                // Casting here never closes the list — only the
                // chevron_left in _buildExpandedList does that.
                onTap: () => _tryCast(spell, count),
                child: Opacity(
                  opacity: usable ? 1.0 : 0.45,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withOpacity(0.05),
                      border: Border.all(
                        color: spell.accentColor.withOpacity(0.6),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(spell.icon, color: spell.accentColor, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            spell.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (onCooldown)
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              value: 1 - cooldownFraction,
                              strokeWidth: 2,
                              color: spell.accentColor,
                              backgroundColor: Colors.white24,
                            ),
                          )
                        else
                          Text(
                            'x$count',
                            style: TextStyle(
                              color: count > 0
                                  ? Colors.white
                                  : Colors.grey.shade600,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}