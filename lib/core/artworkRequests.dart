import 'dart:async';
import 'dart:typed_data';



final class ArtworkRequests {
  final _pending = <String, ArtworkRequest>{};

  Future<bool> run(
    String version,
    Future<bool> Function(ArtworkRequest) prepare, {
    Uint8List? bytes,
    bool allowLegacyFetch = false,
  }) {
    final pending = _pending[version];
    if (pending != null) {
      pending._offer(bytes, allowLegacyFetch);
      return pending._completion.future;
    }
    final request = ArtworkRequest._().._offer(bytes, allowLegacyFetch);
    _pending[version] = request;
    unawaited(_run(version, request, prepare));
    return request._completion.future;
  }

  Future<void> _run(
    String version,
    ArtworkRequest request,
    Future<bool> Function(ArtworkRequest) prepare,
  ) async {
    try {
      request._completion.complete(await prepare(request));
    } catch (error, stack) {
      request._completion.completeError(error, stack);
    } finally {
      committed(version, request);
    }
  }

  
  
  
  void committed(String version, ArtworkRequest request) {
    if (identical(_pending[version], request)) _pending.remove(version);
  }
}

final class ArtworkRequest {
  ArtworkRequest._();

  final _completion = Completer<bool>();
  Uint8List? _bytes;
  bool _allowLegacyFetch = false;

  Uint8List? get bytes => _bytes;
  bool get allowLegacyFetch => _allowLegacyFetch;

  void _offer(Uint8List? bytes, bool allowLegacyFetch) {
    if (bytes != null && bytes.isNotEmpty) _bytes ??= bytes;
    _allowLegacyFetch |= allowLegacyFetch;
  }
}
