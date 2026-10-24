part of 'settingsPanel.dart';


extension _SettingsMediaOptions on _SettingsPanelState {
  Future<void> _refreshSources() async {
    if (_sourcesLoading) return;
    final int request = ++_sourceRequestSerial;
    _updateState(() {
      _sourcesLoading = true;
      _sourceError = null;
    });
    try {
      final snapshot = await AppState.mediaBackend.fetchSources();
      if (!mounted || request != _sourceRequestSerial) return;
      _updateState(() {
        _sources = snapshot.sources;
        _sourcesLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _sourceRequestSerial) return;
      _updateState(() {
        _sourcesLoading = false;
        _sourceError = AppState.mediaBackend.usesExternalProcess
            ? '无法读取播放程序，请检查 MusicFetcher'
            : '无法读取系统媒体会话，请确认播放器已开启系统媒体控制';
      });
    }
  }

  Future<void> _selectSource(String id) async {
    try {
      await AppState.mediaBackend.selectSource(id);
      if (!mounted) return;
      _updateState(() {
        AppState.selectedSourceAppId = id;
        _sourceError = null;
      });
      AppState.clearSpectrum();
      unawaited(AppState.saveSettings());
      unawaited(_refreshSources());
    } catch (_) {
      if (!mounted) return;
      _updateState(
        () => _sourceError = AppState.mediaBackend.usesExternalProcess
            ? '切换失败；请检查 MusicFetcher 后重试'
            : '切换未完成，请确认播放器正在运行后重试',
      );
    }
  }

  Future<void> _choosePlaylistFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['m3u', 'm3u8', 'json'],
      );
      final path = result?.files.single.path;
      if (!mounted || path == null || path.isEmpty) return;
      _updateState(() {
        AppState.playlistFilePath = path;
        AppState.selectedQueueProviderId = 'localPlaylist';
        AppState.showNextUp = true;
      });
      AppState.refreshQueue(force: true);
      widget.onLayoutChanged();
    } catch (_) {}
  }

  Future<void> _editQqPlaylist() async {
    String input = AppState.qqPlaylistLink;
    String? error;
    bool resolving = false;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: const Text(SettingsLabels.qqPlaylist),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(SettingsDescriptions.qqPlaylistDialog),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: input,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: SettingsLabels.qqPlaylistLink,
                    hintText: 'https://y.qq.com/n/ryqq/playlist/…',
                    errorText: error,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    input = value;
                    if (error != null) updateDialog(() => error = null);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: resolving
                  ? null
                  : () async {
                      final trimmed = input.trim();
                      updateDialog(() {
                        resolving = true;
                        error = null;
                      });
                      try {
                        final id =
                            await (widget.resolveQqPlaylistLink?.call(
                                  trimmed,
                                ) ??
                                resolveQqPlaylistId(trimmed));
                        if (!context.mounted) return;
                        if (id == null) {
                          updateDialog(() {
                            resolving = false;
                            error = '没有找到歌单 ID，请粘贴 QQ 音乐歌单分享链接或数字 ID';
                          });
                          return;
                        }
                        Navigator.pop(context, id);
                      } catch (_) {
                        if (!context.mounted) return;
                        updateDialog(() {
                          resolving = false;
                          error = '打开分享链接失败，请检查网络后重试';
                        });
                      }
                    },
              child: Text(resolving ? '正在识别…' : '保存'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    _updateState(() {
      AppState.qqPlaylistLink = selected;
      AppState.selectedQueueProviderId = 'qqMusicPlaylist';
      AppState.showNextUp = true;
    });
    AppState.refreshQueue(force: true);
    widget.onLayoutChanged();
  }

  List<DropdownMenuEntry<String>> _sourceEntries() {
    final selected = AppState.selectedSourceAppId;
    return [
      const DropdownMenuEntry(value: '', label: SettingsLabels.sourceAutomatic),
      if (selected.isNotEmpty &&
          !_sources.any(
            (source) => source.id.toLowerCase() == selected.toLowerCase(),
          ))
        DropdownMenuEntry(value: selected, label: '未运行 · $selected'),
      for (final source in _sources)
        DropdownMenuEntry(
          value: source.id,
          label: source.isPlaying ? '${source.label} · 播放中' : source.label,
        ),
    ];
  }

  Widget _buildPlaylistFileRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(SettingsLabels.playlistFile, style: _settingTitleStyle()),
                Text(
                  AppState.playlistFilePath.isEmpty
                      ? SettingsDescriptions.playlistFileEmpty
                      : AppState.playlistFilePath,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _settingSubtitleStyle(),
                ),
              ],
            ),
          ),
          if (AppState.playlistFilePath.isNotEmpty)
            IconButton(
              tooltip: '重新读取播放列表',
              onPressed: () => AppState.refreshQueue(force: true),
              icon: const Icon(Icons.refresh_rounded),
            ),
          if (AppState.playlistFilePath.isNotEmpty)
            IconButton(
              tooltip: '移除播放列表',
              onPressed: () {
                _updateState(() {
                  AppState.playlistFilePath = '';
                  AppState.showNextUp = false;
                });
                AppState.refreshQueue(force: true);
                widget.onLayoutChanged();
              },
              icon: const Icon(Icons.close_rounded),
            ),
          FilledButton.tonal(
            onPressed: _choosePlaylistFile,
            child: const Text('选择'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistSourceSelector() => KeyedSubtree(
    key: const ValueKey('playlist_source_selector'),
    child: _buildDropdownRow<String>(
      SettingsLabels.playlistSource,
      null,
      _displayQueueProviderId,
      (value) {
        _updateState(() => AppState.selectedQueueProviderId = value);
        AppState.refreshQueue();
        widget.onVisualChanged();
      },
      const [
        DropdownMenuEntry(value: 'qqMusicPlaylist', label: 'QQ 音乐'),
        DropdownMenuEntry(value: 'neteasePlaylist', label: '网易云音乐'),
        DropdownMenuEntry(value: 'localPlaylist', label: '本地歌单'),
      ],
    ),
  );

  Widget _buildSelectedPlaylistRow() {
    final id = _displayQueueProviderId;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedSize(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 200),
      curve: AppState.layoutSwitchCurve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: IgnorePointer(
            ignoring: child.key != ValueKey(id),
            child: child,
          ),
        ),
        child: KeyedSubtree(
          key: ValueKey(id),
          child: switch (id) {
            'neteasePlaylist' => _buildNeteasePlaylistRow(),
            'localPlaylist' => _buildPlaylistFileRow(),
            _ => _buildQqPlaylistRow(),
          },
        ),
      ),
    );
  }

  Future<void> _editNeteasePlaylist() async {
    String input = AppState.neteasePlaylistLink;
    String? error;
    final id = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text(SettingsLabels.neteasePlaylist),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('仅支持公开歌单链接或数字 ID，不读取账号。预告按歌单顺序推算，不代表播放器实际队列。'),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: input,
                  autofocus: true,
                  onChanged: (value) => input = value,
                  decoration: InputDecoration(
                    labelText: SettingsLabels.qqPlaylistLink,
                    hintText: 'https://music.163.com/#/playlist?id=…',
                    errorText: error,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final id = parseNeteasePlaylistId(input);
                if (id == null) {
                  update(() => error = '请粘贴网易云公开歌单链接或数字 ID');
                  return;
                }
                Navigator.pop(context, id);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || id == null) return;
    _updateState(() {
      AppState.neteasePlaylistLink = id;
      AppState.selectedQueueProviderId = 'neteasePlaylist';
      AppState.showNextUp = true;
    });
    AppState.refreshQueue(force: true);
    widget.onLayoutChanged();
  }

  Widget _buildNeteasePlaylistRow() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                SettingsLabels.neteasePlaylist,
                key: const ValueKey('netease_playlist_title'),
                style: _settingTitleStyle(),
              ),
              Text(
                AppState.neteasePlaylistLink.isEmpty
                    ? SettingsDescriptions.neteasePlaylist
                    : '已连接歌单 ${AppState.neteasePlaylistLink}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _settingSubtitleStyle(),
              ),
            ],
          ),
        ),
        if (AppState.neteasePlaylistLink.isNotEmpty) ...[
          IconButton(
            tooltip: '重新读取网易云歌单',
            onPressed: () => AppState.refreshQueue(force: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '移除网易云歌单',
            onPressed: () {
              _updateState(() {
                AppState.neteasePlaylistLink = '';
              });
              AppState.refreshQueue(force: true);
              widget.onLayoutChanged();
            },
            icon: const Icon(Icons.close_rounded),
          ),
        ],
        FilledButton.tonal(
          key: const ValueKey('netease_playlist_connect'),
          onPressed: _editNeteasePlaylist,
          child: Text(AppState.neteasePlaylistLink.isEmpty ? '连接' : '修改'),
        ),
      ],
    ),
  );

  Widget _buildQqPlaylistRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  SettingsLabels.qqPlaylist,
                  key: const ValueKey('qq_playlist_title'),
                  style: _settingTitleStyle(),
                ),
                Text(
                  AppState.qqPlaylistLink.isEmpty
                      ? SettingsDescriptions.qqPlaylistEmpty
                      : SettingsDescriptions.qqPlaylistConnected(
                          parseQqPlaylistId(AppState.qqPlaylistLink) ?? '',
                        ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _settingSubtitleStyle(),
                ),
              ],
            ),
          ),
          if (AppState.qqPlaylistLink.isNotEmpty)
            IconButton(
              tooltip: '重新读取 QQ 音乐歌单',
              onPressed: () => AppState.refreshQueue(force: true),
              icon: const Icon(Icons.refresh_rounded),
            ),
          if (AppState.qqPlaylistLink.isNotEmpty)
            IconButton(
              tooltip: '移除 QQ 音乐歌单',
              onPressed: () {
                _updateState(() {
                  AppState.qqPlaylistLink = '';
                });
                AppState.refreshQueue(force: true);
                widget.onLayoutChanged();
              },
              icon: const Icon(Icons.close_rounded),
            ),
          FilledButton.tonal(
            key: const ValueKey('qq_playlist_connect'),
            onPressed: _editQqPlaylist,
            child: Text(AppState.qqPlaylistLink.isEmpty ? '连接' : '修改'),
          ),
        ],
      ),
    );
  }
}
