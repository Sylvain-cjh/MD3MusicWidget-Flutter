import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/releaseCheck.dart';
import 'settingsDescriptions.dart';
import 'settingsLabels.dart';
import 'settingsLicensesPage.dart';
import 'smoothRoundedClip.dart';

class SettingsAboutPage extends StatefulWidget {
  const SettingsAboutPage({super.key, this.fetchLatestTag});

  final Future<String?> Function()? fetchLatestTag;

  @override
  State<SettingsAboutPage> createState() => _SettingsAboutPageState();
}

class _SettingsAboutPageState extends State<SettingsAboutPage> {
  static const _appInfo = MethodChannel('md3_music_widget/app_info');
  late final Future<String?> _version = _readVersion();
  bool _linkFailed = false;
  bool _checking = false;
  bool _hasUpdate = false;
  String? _updateMessage;

  Future<void> _checkUpdate(String current) async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _hasUpdate = false;
      _updateMessage = null;
    });
    var available = false;
    String message;
    try {
      final tag =
          await (widget.fetchLatestTag ?? ReleaseCheck.fetchLatestTag)();
      if (tag == null) {
        message = SettingsLabels.aboutNoPublicRelease;
      } else {
        available = ReleaseCheck.isNewer(tag, current);
        message = available
            ? SettingsLabels.aboutUpdateAvailable(tag)
            : SettingsLabels.aboutUpToDate;
      }
    } catch (_) {
      message = SettingsLabels.aboutUpdateFailed;
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _hasUpdate = available;
      _updateMessage = message;
    });
  }

  Future<String?> _readVersion() async {
    try {
      final version = await _appInfo.invokeMethod<String>('version');
      return version == null || version.isEmpty ? null : version;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _openLink(String method) async {
    var opened = false;
    try {
      opened = await _appInfo.invokeMethod<bool>(method) ?? false;
    } on PlatformException {
      
    } on MissingPluginException {
      
    }
    if (mounted && _linkFailed == opened) {
      setState(() => _linkFailed = !opened);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return FutureBuilder<String?>(
      future: _version,
      builder: (context, snapshot) {
        final version = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: scheme.surfaceContainerLow.withValues(alpha: 0.94),
              shape: SmoothSurfaceCorners.shape(
                SmoothSurfaceCorners.settingsCard,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SmoothRoundedClip(
                          borderRadius: SmoothSurfaceCorners.small,
                          composite: false,
                          child: Image.asset(
                            theme.brightness == Brightness.dark
                                ? 'images/tray_icon_dark.png'
                                : 'images/tray_icon.png',
                            width: 48,
                            height: 48,
                            cacheWidth: 128,
                            gaplessPlayback: true,
                            excludeFromSemantics: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                SettingsLabels.appName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                version != null
                                    ? SettingsLabels.aboutVersion(version)
                                    : snapshot.connectionState ==
                                          ConnectionState.waiting
                                    ? SettingsLabels.aboutVersionLoading
                                    : SettingsLabels.aboutVersionUnavailable,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      SettingsDescriptions.aboutApp,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      icon: _checking
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.system_update_alt_rounded,
                              size: 18,
                            ),
                      onPressed: version == null || _checking
                          ? null
                          : () => unawaited(_checkUpdate(version)),
                      label: Text(
                        _checking
                            ? SettingsLabels.aboutCheckingUpdate
                            : SettingsLabels.aboutCheckUpdate,
                      ),
                    ),
                    if (_updateMessage case final message?)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            message,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _hasUpdate
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    if (_hasUpdate)
                      TextButton(
                        onPressed: () => _openLink('openReleases'),
                        child: const Text(SettingsLabels.aboutViewUpdate),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Material(
              color: scheme.surfaceContainerLow.withValues(alpha: 0.94),
              shape: SmoothSurfaceCorners.shape(
                SmoothSurfaceCorners.settingsCard,
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  children: [
                    _action(
                      Icons.code_rounded,
                      SettingsLabels.aboutSource,
                      Icons.open_in_new_rounded,
                      () => _openLink('openProject'),
                    ),
                    _action(
                      Icons.new_releases_outlined,
                      SettingsLabels.aboutReleases,
                      Icons.open_in_new_rounded,
                      () => _openLink('openReleases'),
                    ),
                    _action(
                      Icons.article_outlined,
                      SettingsLabels.aboutLicenses,
                      Icons.chevron_right_rounded,
                      () => showSettingsLicenses(context),
                    ),
                    if (_linkFailed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                        child: Text(
                          SettingsDescriptions.aboutLinkFailed,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _action(
    IconData icon,
    String label,
    IconData trailing,
    VoidCallback onTap,
  ) => ListTile(
    minTileHeight: 44,
    dense: true,
    leading: Icon(icon, size: 20),
    trailing: Icon(trailing, size: 17),
    title: Text(label),
    shape: SmoothSurfaceCorners.shape(SmoothSurfaceCorners.small),
    onTap: onTap,
  );
}
