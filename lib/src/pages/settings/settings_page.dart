import 'package:flutter/material.dart';
import 'package:flame_audio/flame_audio.dart';

/// ---------------------------------------------------------------------
/// Shared audio-settings state, defined here (outside the State class)
/// so any other page — most importantly MyFlameGame in
/// main_game_page.dart — can read/react to it directly, the same
/// pattern already used for gemsNotifier / coinsNotifier /
/// equippedSkinNotifier in skins_page.dart.
///
/// - musicEnabledNotifier: whether background music should be
///   playing at all. Toggling this pauses/resumes FlameAudio.bgm
///   immediately, from wherever the toggle is flipped.
/// - musicVolumeNotifier: 0.0–1.0 volume for the background music.
///   Dragging the slider updates FlameAudio.bgm's volume live.
/// - sfxEnabledNotifier: whether one-shot sound effects (shoot,
///   button clicks) should play. main_game_page.dart's playSfx()
///   helper should check this before calling FlameAudio.play().
///
/// NOTE: like the other shared notifiers in this project, this is
/// plain in-memory state — it resets to defaults on app restart.
/// Wire up shared_preferences here if you want the player's audio
/// settings to persist between sessions.
/// ---------------------------------------------------------------------
final ValueNotifier<bool> musicEnabledNotifier = ValueNotifier<bool>(true);
final ValueNotifier<double> musicVolumeNotifier = ValueNotifier<double>(0.5);
final ValueNotifier<bool> sfxEnabledNotifier = ValueNotifier<bool>(true);

/// Call this instead of toggling musicEnabledNotifier directly — it
/// keeps FlameAudio.bgm in sync (pause/resume) at the same time as
/// the notifier, so every listener (this page, the game) agrees on
/// both the flag AND the actual playback state.
void setMusicEnabled(bool enabled) {
  musicEnabledNotifier.value = enabled;
  if (enabled) {
    FlameAudio.bgm.resume();
  } else {
    FlameAudio.bgm.pause();
  }
}

/// Call this instead of setting musicVolumeNotifier directly — keeps
/// FlameAudio.bgm's actual volume in sync with the slider in real
/// time as the player drags it.
void setMusicVolume(double volume) {
  musicVolumeNotifier.value = volume;
  FlameAudio.bgm.audioPlayer.setVolume(volume);
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Text(
                    'Settings',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionLabel('Audio'),
                  const SizedBox(height: 10),

                  // ---- Music on/off + volume slider, in one card ----
                  ValueListenableBuilder<bool>(
                    valueListenable: musicEnabledNotifier,
                    builder: (context, musicEnabled, _) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.deepOrange.shade900, width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  musicEnabled
                                      ? Icons.music_note_rounded
                                      : Icons.music_off_rounded,
                                  color: Colors.orangeAccent,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Music',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Switch(
                                  value: musicEnabled,
                                  activeColor: Colors.orangeAccent,
                                  onChanged: (value) {
                                    setMusicEnabled(value);
                                  },
                                ),
                              ],
                            ),

                            // Volume slider — disabled (dimmed, no
                            // interaction) whenever music is off, since
                            // adjusting volume for silent music is
                            // confusing.
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: musicEnabled ? 1.0 : 0.35,
                              child: IgnorePointer(
                                ignoring: !musicEnabled,
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.volume_down_rounded,
                                      color: Colors.white54,
                                      size: 18,
                                    ),
                                    Expanded(
                                      child:
                                          ValueListenableBuilder<double>(
                                        valueListenable:
                                            musicVolumeNotifier,
                                        builder: (context, volume, __) {
                                          return SliderTheme(
                                            data: SliderTheme.of(context)
                                                .copyWith(
                                              activeTrackColor:
                                                  Colors.orangeAccent,
                                              inactiveTrackColor: Colors
                                                  .white
                                                  .withOpacity(0.15),
                                              thumbColor:
                                                  Colors.orangeAccent,
                                              overlayColor: Colors
                                                  .orangeAccent
                                                  .withOpacity(0.2),
                                            ),
                                            child: Slider(
                                              value: volume,
                                              min: 0.0,
                                              max: 1.0,
                                              onChanged: (value) {
                                                setMusicVolume(value);
                                              },
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const Icon(
                                      Icons.volume_up_rounded,
                                      color: Colors.white54,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  // ---- Sound effects on/off ----
                  ValueListenableBuilder<bool>(
                    valueListenable: sfxEnabledNotifier,
                    builder: (context, sfxEnabled, _) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.deepOrange.shade900, width: 1),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              sfxEnabled
                                  ? Icons.graphic_eq_rounded
                                  : Icons.volume_off_rounded,
                              color: Colors.orangeAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Sound Effects',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Switch(
                              value: sfxEnabled,
                              activeColor: Colors.orangeAccent,
                              onChanged: (value) {
                                sfxEnabledNotifier.value = value;
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const Expanded(child: SizedBox()),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: Colors.grey.shade500,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.0,
      ),
    );
  }
}