import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audioOutputs.dart';
import 'audioOutputVolume.dart';
import 'md3AnchoredSelect.dart';
import 'settingsDescriptions.dart';
import 'settingsLabels.dart';


class AudioOutputChip extends StatelessWidget {
  static const double height = 28;
  static const _soundSettings = _AudioOutputChoice.settings();

  final AudioOutputs audio;
  final double width;

  const AudioOutputChip({super.key, required this.audio, required this.width});

  static bool isAvailable(AudioOutputs audio) =>
      audio.available && audio.outputs.isNotEmpty;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: audio,
    builder: (context, _) {
      if (!isAvailable(audio)) return const SizedBox.shrink();

      final devices = audio.outputs;
      final index = devices.indexWhere(
        (device) => device.id == audio.defaultId,
      );
      final current = index < 0 ? null : devices[index];
      DropdownMenuEntry<_AudioOutputChoice> entry(AudioOutput output) =>
          DropdownMenuEntry(
            value: _AudioOutputChoice.device(output.id),
            label: output.name.isEmpty
                ? SettingsLabels.unknownAudioOutput
                : output.name,
            leadingIcon: Icon(_iconFor(output), size: 17),
          );

      return Md3AnchoredSelect<_AudioOutputChoice>.chip(
        key: const ValueKey('home_audio_output_picker'),
        width: width,
        height: height,
        icon: _iconFor(current),
        activeRow: current == null
            ? null
            : (context, scale) => AudioOutputVolume(
                audio: audio,
                output: current,
                scale: scale,
                label: current.name.isEmpty
                    ? SettingsLabels.unknownAudioOutput
                    : current.name,
              ),
        enabled: !audio.switching,
        semanticLabel: audio.switching
            ? SettingsDescriptions.audioOutputChanging
            : audio.selectFailed
            ? SettingsDescriptions.audioOutputSelectFailed
            : SettingsDescriptions.audioOutputDevice,
        value: _AudioOutputChoice.device(current?.id ?? ''),
        entries: [
          if (current != null)
            entry(current)
          else
            const DropdownMenuEntry(
              value: _AudioOutputChoice.device(''),
              label: SettingsLabels.currentAudioOutputUnknown,
              enabled: false,
            ),
          for (final device in devices)
            if (device.id != current?.id) entry(device),
          const DropdownMenuEntry(
            value: _soundSettings,
            label: SettingsLabels.openWindowsSoundSettings,
            leadingIcon: Icon(Icons.open_in_new_rounded, size: 17),
          ),
        ],
        onSelected: (choice) {
          if (choice == _soundSettings) {
            unawaited(audio.openWindowsSettings());
          } else {
            unawaited(audio.select(choice.id!));
          }
        },
      );
    },
  );

  static IconData _iconFor(AudioOutput? output) => output == null
      ? Icons.speaker_group_rounded
      : output.bluetoothGroup.isEmpty
      ? Icons.speaker_rounded
      : Icons.headphones_rounded;
}

class _AudioOutputChoice {
  final String? id;
  const _AudioOutputChoice.settings() : id = null;
  const _AudioOutputChoice.device(String this.id);

  @override
  bool operator ==(Object other) =>
      other is _AudioOutputChoice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
