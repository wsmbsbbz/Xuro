import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:get_it/get_it.dart';
import 'package:xuro/common/constants/strings.dart';
import 'package:xuro/core/theme/theme_controller.dart';
import 'package:xuro/core/platform/wakelock_controller.dart';
import 'package:xuro/core/platform/lyric_overlay_manager.dart';
import 'package:xuro/core/settings/app_settings_service.dart';
import 'package:xuro/screens/settings/cache_manager_screen.dart';
import 'package:xuro/screens/settings/audio_format_order_dialog.dart';
import 'package:xuro/screens/settings/widgets/settings_group.dart';
import 'package:xuro/screens/settings/widgets/settings_tile.dart';
import 'package:xuro/screens/settings/widgets/settings_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final bgColor = SettingsTheme.pageBackground(context);

    return Scaffold(
      appBar: AppBar(title: const Text(Strings.settings)),
      backgroundColor: bgColor,
      body: SettingsTheme.noSplashTheme(
        context: context,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            _appearanceSection(),
            const SizedBox(height: 24),
            _colorVariantSection(),
            const SizedBox(height: 24),
            _networkSection(),
            const SizedBox(height: 24),
            _contentSection(context),
            const SizedBox(height: 24),
            _playbackSection(),
            const SizedBox(height: 24),
            _narrationSection(),
            const SizedBox(height: 24),
            _lyricOverlaySection(),
            const SizedBox(height: 24),
            _storageSection(context),
          ],
        ),
      ),
    );
  }

  Widget _appearanceSection() {
    return Consumer<ThemeController>(
      builder: (context, tc, _) => SettingsGroup(
        header: Strings.appearance,
        footer: Strings.themeAutoDesc,
        children: [
          SettingsTile.selection(
            title: Strings.followSystem,
            leading: Icons.palette_outlined,
            selected: tc.themeMode == ThemeMode.system,
            onTap: () => tc.setThemeMode(ThemeMode.system),
          ),
          SettingsTile.selection(
            title: Strings.lightMode,
            leading: Icons.palette_outlined,
            selected: tc.themeMode == ThemeMode.light,
            onTap: () => tc.setThemeMode(ThemeMode.light),
          ),
          SettingsTile.selection(
            title: Strings.darkMode,
            leading: Icons.palette_outlined,
            selected: tc.themeMode == ThemeMode.dark,
            onTap: () => tc.setThemeMode(ThemeMode.dark),
          ),
        ],
      ),
    );
  }

  Widget _colorVariantSection() {
    return Builder(
      builder: (context) {
        final settings = GetIt.I<AppSettingsService>();
        return ListenableBuilder(
          listenable: settings,
          builder: (context, _) => SettingsGroup(
            header: Strings.colorVariantTitle,
            footer: Strings.colorVariantDesc,
            children: [
              SettingsTile.selection(
                title: Strings.colorVariantBlue,
                leading: Icons.circle,
                selected: settings.colorVariant == ColorVariant.blue,
                onTap: () => settings.setColorVariant(ColorVariant.blue),
              ),
              SettingsTile.selection(
                title: Strings.colorVariantMono,
                leading: Icons.circle,
                selected: settings.colorVariant == ColorVariant.mono,
                onTap: () => settings.setColorVariant(ColorVariant.mono),
              ),
              SettingsTile.selection(
                title: Strings.colorVariantGreen,
                leading: Icons.circle,
                selected: settings.colorVariant == ColorVariant.green,
                onTap: () => settings.setColorVariant(ColorVariant.green),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _networkSection() {
    return Builder(
      builder: (context) {
        final settings = GetIt.I<AppSettingsService>();
        return ListenableBuilder(
          listenable: settings,
          builder: (context, _) => SettingsGroup(
            header: Strings.network,
            children: AppSettingsService.serverOptions.entries.map((entry) {
              return SettingsTile.selection(
                title: entry.value,
                subtitle: entry.key,
                leading: Icons.lan_outlined,
                selected: settings.serverUrl == entry.key,
                onTap: () => settings.setServerUrl(entry.key),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _contentSection(BuildContext context) {
    return Builder(
      builder: (context) {
        final settings = GetIt.I<AppSettingsService>();
        return ListenableBuilder(
          listenable: settings,
          builder: (context, _) => SettingsGroup(
            header: Strings.content,
            children: [
              SettingsTile.toggle(
                title: Strings.smartPath,
                subtitle: Strings.smartPathDesc,
                leading: Icons.folder_open_outlined,
                value: settings.smartPathEnabled,
                onChanged: (v) => settings.setSmartPathEnabled(v),
              ),
              SettingsTile.navigation(
                title: Strings.audioFormatPreference,
                leading: Icons.audio_file_outlined,
                value: settings.audioFormatOrder.join(' > '),
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => AudioFormatOrderDialog(settings: settings),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _playbackSection() {
    return Builder(
      builder: (context) {
        final controller = GetIt.I<WakeLockController>();
        return ListenableBuilder(
          listenable: controller,
          builder: (context, _) => SettingsGroup(
            header: Strings.playback,
            footer: Strings.screenKeepAwakeDesc,
            children: [
              SettingsTile.toggle(
                title: Strings.screenKeepAwake,
                leading: Icons.wb_sunny_outlined,
                value: controller.enabled,
                onChanged: (_) => controller.toggle(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _narrationSection() {
    return Builder(
      builder: (context) {
        final settings = GetIt.I<AppSettingsService>();
        return ListenableBuilder(
          listenable: settings,
          builder: (context, _) => SettingsGroup(
            header: Strings.narration,
            footer: Strings.narrationConcurrencyDesc,
            children: [
              SettingsTile.toggle(
                title: Strings.narrationEnabled,
                subtitle: Strings.narrationEnabledDesc,
                leading: Icons.record_voice_over_outlined,
                value: settings.narrationEnabled,
                onChanged: (v) => settings.setNarrationEnabled(v),
              ),
              SettingsTile.navigation(
                title: Strings.narrationVolume,
                leading: Icons.volume_down_outlined,
                value: '${(settings.narrationVolume * 100).round()}%',
                onTap: () {
                  const values = [0.04, 0.08, 0.12, 0.18, 0.24];
                  final current = settings.narrationVolume;
                  final index = values.indexWhere((v) => v > current + 0.001);
                  settings.setNarrationVolume(
                    index == -1 ? values.first : values[index],
                  );
                },
              ),
              SettingsTile.navigation(
                title: Strings.narrationVoice,
                leading: Icons.language_outlined,
                value: settings.narrationVoice,
                onTap: () {
                  const voices = ['zh-CN', 'zh-TW', 'zh-HK'];
                  final index = voices.indexOf(settings.narrationVoice);
                  settings.setNarrationVoice(
                    voices[(index + 1) % voices.length],
                  );
                },
              ),
              SettingsTile.navigation(
                title: Strings.narrationConcurrency,
                leading: Icons.speed_outlined,
                value: '${settings.narrationConcurrency}',
                onTap: () => settings.setNarrationConcurrency(
                  settings.narrationConcurrency == 1 ? 2 : 1,
                ),
              ),
              SettingsTile.navigation(
                title: Strings.narrationBackendUrl,
                subtitle: Strings.narrationBackendUrlDesc,
                leading: Icons.cloud_outlined,
                value: settings.narrationBackendUrl.isEmpty
                    ? '未设置'
                    : settings.narrationBackendUrl,
                onTap: () => _editStringSetting(
                  context: context,
                  title: Strings.narrationBackendUrl,
                  initialValue: settings.narrationBackendUrl,
                  onSubmitted: settings.setNarrationBackendUrl,
                ),
              ),
              SettingsTile.navigation(
                title: Strings.narrationBackendToken,
                subtitle: Strings.narrationBackendTokenDesc,
                leading: Icons.key_outlined,
                value: settings.narrationBackendToken.isEmpty ? '未设置' : '已设置',
                onTap: () => _editStringSetting(
                  context: context,
                  title: Strings.narrationBackendToken,
                  initialValue: settings.narrationBackendToken,
                  onSubmitted: settings.setNarrationBackendToken,
                  obscureText: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editStringSetting({
    required BuildContext context,
    required String title,
    required String initialValue,
    required ValueChanged<String> onSubmitted,
    bool obscureText = false,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: obscureText,
          decoration: const InputDecoration(hintText: '留空则清除'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(Strings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text(Strings.confirm),
          ),
        ],
      ),
    );
    if (value != null) onSubmitted(value);
  }

  Widget _lyricOverlaySection() {
    return Builder(
      builder: (context) {
        final settings = GetIt.I<AppSettingsService>();
        final manager = GetIt.I<LyricOverlayManager>();
        return ListenableBuilder(
          listenable: settings,
          builder: (context, _) => SettingsGroup(
            header: Strings.lyricOverlaySection,
            footer: Strings.lyricOverlayUnlockDesc,
            children: [
              SettingsTile.toggle(
                title: Strings.lyricOverlayUnlockTitle,
                leading: Icons.lyrics_outlined,
                value: settings.lyricOverlayUnlocked,
                onChanged: (v) => manager.setUnlockedPreference(v),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _storageSection(BuildContext context) {
    return SettingsGroup(
      header: Strings.storage,
      children: [
        SettingsTile.navigation(
          title: Strings.cacheManager,
          leading: Icons.storage_outlined,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CacheManagerScreen()),
          ),
        ),
      ],
    );
  }
}
