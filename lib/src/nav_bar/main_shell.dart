import 'package:flutter/material.dart';
import 'package:cosmic_fury/src/pages/main/main_game_page.dart'; // adjust path
import 'package:cosmic_fury/src/pages/skins/skins_page.dart'; // adjust path
import 'package:cosmic_fury/src/pages/spells/spells_page.dart'; // adjust path
import 'package:cosmic_fury/src/pages/settings/settings_page.dart'; // adjust path
import 'nav_bar.dart'; // adjust path

/// Hosts every tab's page + the NavBar in ONE persistent widget tree.
///
/// Why this matters: if you instead push a new route per tab
/// (Navigator.pushReplacement), Flutter tears down the old page —
/// including the NavBar's State object — and builds a brand new one.
/// A freshly-built NavBar has no "previous frame" to animate from, so
/// AnimatedPositioned / AnimationControllers just snap instead of
/// transitioning. Keeping NavBar alive here, and only swapping which
/// page is visible via setState, is what makes the animations real.
class MainShell extends StatefulWidget {
  const MainShell({Key? key}) : super(key: key);

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  // IndexedStack keeps every page's widget/state alive too (so e.g.
  // scroll position / game state on other tabs isn't lost when you
  // switch away and back).
  final List<Widget> _pages = const [
    MainGamePage(),
    SkinsPage(),
    SpellsPage(),
    SettingsPage(),
  ];

  void _onTabSelected(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Without this, Scaffold defaults to a white surface. That white
      // shows through the gaps around NavBar's rounded corners — that's
      // the pink/white halo around the pill.
      backgroundColor: Colors.black,
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      // Scaffold wraps bottomNavigationBar in a Material with the theme's
      // canvas color (white) by default. Force it transparent so only
      // NavBar's own black background shows.
      bottomNavigationBar: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: NavBar(
              selectedIndex: _selectedIndex,
              onTabSelected: _onTabSelected,
            ), // closes NavBar
          ), // closes Padding
        ), // closes SafeArea
      ), // closes Material
    ); // closes Scaffold
  }
}