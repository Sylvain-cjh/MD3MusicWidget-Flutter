part of 'trackControls.dart';


extension _TrackPlaybackFeedback on _ContinuousTrackControlsState {
  bool get _displayPlaying => _pendingPlaying ?? AppState.isPlaying;

  void _clearPlaybackIntent() {
    _playbackIntentTimer?.cancel();
    if (mounted && _pendingPlaying != null) {
      _updatePlaybackFeedback(() => _pendingPlaying = null);
    }
  }

  void _handlePlaybackFeedback() {
    _handleTimelineAvailability();
    if (_pendingPlaying != null &&
        ((_playbackIntentAccepted && _pendingPlaying == AppState.isPlaying) ||
            _pendingPlaybackContext !=
                AppState.currentPlatformTrack?.contextIdentity)) {
      _clearPlaybackIntent();
    }
  }

  void _togglePlaying() {
    final serial = ++_playbackIntentSerial;
    final target = !_displayPlaying;
    _playbackIntentAccepted = false;
    _pendingPlaybackContext = AppState.currentPlatformTrack?.contextIdentity;
    _updatePlaybackFeedback(() => _pendingPlaying = target);
    _playbackIntentTimer?.cancel();
    _playbackIntentTimer = Timer(const Duration(seconds: 3), () {
      if (serial == _playbackIntentSerial) _clearPlaybackIntent();
    });
    unawaited(
      AppState.sendCommand(MediaCommand.togglePlayPause).then((accepted) {
        if (!mounted || serial != _playbackIntentSerial) return;
        _playbackIntentAccepted = accepted;
        if (!accepted || AppState.isPlaying == target) _clearPlaybackIntent();
      }),
    );
  }
}
