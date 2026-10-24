import 'dart:typed_data';

import 'mediaProvider.dart';
import 'musicSourceService.dart';


abstract interface class MediaCaptureBackend
    implements MediaProvider, MusicSourceClient {
  bool get usesExternalProcess;
  bool get supportsLegacyPolling;

  
  Future<bool> dispatchCommand(MediaCommand command);

  @override
  Future<void> close();
}


abstract interface class LegacyMediaReader {
  Future<Uint8List> readLegacyResponse(
    Uri resource, {
    required Duration timeout,
  });
  Future<int?> waitUntilReady({Duration maxWait});
}
