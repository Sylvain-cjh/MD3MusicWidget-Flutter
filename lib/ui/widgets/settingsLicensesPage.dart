import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/appState.dart';
import 'settingsLabels.dart';
import 'smoothRoundedClip.dart';

void showSettingsLicenses(BuildContext context) {
  final theme = Theme.of(context);
  final radius = SmoothSurfaceCorners.windowRadius * AppState.componentScale;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Theme(
        data: theme,
        child: _LicensesPage(radius: radius),
      ),
    ),
  );
}

class _LicensesPage extends StatefulWidget {
  const _LicensesPage({required this.radius});
  final double radius;

  @override
  State<_LicensesPage> createState() => _LicensesPageState();
}

class _LicensesPageState extends State<_LicensesPage> {
  late final _packages = _load();
  String _filter = '';
  String? _package;

  static Future<Map<String, List<LicenseEntry>>> _load() async {
    final groups = <String, List<LicenseEntry>>{};
    await for (final entry in LicenseRegistry.licenses) {
      for (final package in entry.packages.toSet()) {
        (groups[package] ??= []).add(entry);
      }
    }
    return {
      for (final package
          in groups.keys.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())))
        package: groups[package]!,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final package = _package;
    void back() {
      if (package != null) {
        setState(() => _package = null);
      } else {
        Navigator.of(context).pop();
      }
    }

    return PopScope(
      canPop: package == null,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && package != null) setState(() => _package = null);
      },
      child: SmoothRoundedClip(
        borderRadius: BorderRadius.circular(widget.radius),
        composite: false,
        child: Scaffold(
          backgroundColor: scheme.surface,
          body: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: back,
                      tooltip: '返回',
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        package ?? SettingsLabels.aboutLicenses,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Offstage(
                  offstage: package != null,
                  child: ExcludeFocus(
                    excluding: package != null,
                    child: TextField(
                      onChanged: (value) =>
                          setState(() => _filter = value.trim().toLowerCase()),
                      decoration: InputDecoration(
                        hintText: '搜索组件',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: scheme.surfaceContainerHigh,
                        isDense: true,
                        border: const OutlineInputBorder(
                          borderRadius: SmoothSurfaceCorners.control,
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                if (package == null) const SizedBox(height: 12),
                Expanded(
                  child: Material(
                    color: scheme.surfaceContainerLow,
                    shape: SmoothSurfaceCorners.shape(
                      SmoothSurfaceCorners.settingsViewport,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: FutureBuilder<Map<String, List<LicenseEntry>>>(
                      future: _packages,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Center(child: Text('暂时无法读取许可'));
                        }
                        final data = snapshot.data;
                        if (data == null) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (package != null) {
                          final entries = data[package]!;
                          return ListView.builder(
                            key: ValueKey(package),
                            padding: const EdgeInsets.all(16),
                            itemCount: entries.length,
                            itemBuilder: (context, index) => Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: SelectableText(
                                entries[index].paragraphs
                                    .map((p) => p.text)
                                    .join('\n\n'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  height: 1.48,
                                ),
                              ),
                            ),
                          );
                        }
                        final names = data.keys
                            .where(
                              (name) => name.toLowerCase().contains(_filter),
                            )
                            .toList(growable: false);
                        if (names.isEmpty) {
                          return const Center(child: Text('没有匹配的组件'));
                        }
                        return ListView.builder(
                          key: const PageStorageKey(
                            'settings_license_packages',
                          ),
                          padding: const EdgeInsets.all(8),
                          itemCount: names.length,
                          itemBuilder: (context, index) {
                            final name = names[index];
                            return ListTile(
                              dense: true,
                              shape: SmoothSurfaceCorners.shape(
                                SmoothSurfaceCorners.settingsCard,
                              ),
                              title: Text(name),
                              subtitle: Text('${data[name]!.length} 份许可'),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () {
                                FocusScope.of(context).unfocus();
                                setState(() => _package = name);
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
