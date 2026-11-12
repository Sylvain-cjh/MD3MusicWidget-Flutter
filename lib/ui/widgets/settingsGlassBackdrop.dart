import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/widgetDiagnostics.dart';
import 'backdropCaptureBoundary.dart';



class SettingsGlassBackdrop extends StatefulWidget {
  const SettingsGlassBackdrop({
    super.key,
    required this.sourceKey,
    required this.ready,
    required this.backgroundRevision,
    required this.child,
  });

  final GlobalKey? sourceKey;
  final bool ready;
  final Listenable backgroundRevision;
  final Widget child;

  static SettingsGlassSample? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GlassSampleScope>()?.sample;

  @override
  State<SettingsGlassBackdrop> createState() => _SettingsGlassBackdropState();
}

class _SettingsGlassBackdropState extends State<SettingsGlassBackdrop> {
  static const _layoutDelay = Duration(milliseconds: 125);
  static const _artworkDelay = Duration(milliseconds: 1050);
  SettingsGlassSample? _sample;
  Size? _size;
  Timer? _timer;
  int _serial = 0;
  int? _queued;
  double _dpr = 1;
  bool _highContrast = false;
  bool _busy = false;

  bool get _enabled => widget.sourceKey != null && !_highContrast;
  bool get _ready => _enabled && widget.ready;

  @override
  void initState() {
    super.initState();
    widget.backgroundRevision.addListener(_artworkChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final contrast = MediaQuery.highContrastOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (contrast == _highContrast && dpr == _dpr) return;
    _highContrast = contrast;
    _dpr = dpr;
    if (!_enabled) _clear();
    _schedule(_layoutDelay);
  }

  @override
  void didUpdateWidget(covariant SettingsGlassBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backgroundRevision != widget.backgroundRevision) {
      oldWidget.backgroundRevision.removeListener(_artworkChanged);
      widget.backgroundRevision.addListener(_artworkChanged);
    }
    if (oldWidget.sourceKey != widget.sourceKey) _clear();
    if (oldWidget.sourceKey != widget.sourceKey ||
        oldWidget.ready != widget.ready ||
        oldWidget.backgroundRevision != widget.backgroundRevision) {
      _schedule(_layoutDelay);
    }
  }

  void _artworkChanged() =>
      _schedule(_sample == null ? _layoutDelay : _artworkDelay);

  void _schedule(Duration delay) {
    _timer?.cancel();
    _queued = null;
    final serial = ++_serial;
    if (_ready) _timer = Timer(delay, () => unawaited(_capture(serial)));
  }

  bool _current(int serial) => mounted && _ready && serial == _serial;

  Future<void> _capture(int serial, {bool retry = true}) async {
    if (!_current(serial)) return;
    if (_busy) {
      _queued = serial;
      return;
    }
    _busy = true;
    ui.Image? pending;
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_current(serial)) return;
      final source = widget.sourceKey?.currentContext?.findRenderObject();
      final viewport = context.findRenderObject();
      if (source is! RenderBackdropCaptureBoundary ||
          !source.attached ||
          !source.hasSize ||
          viewport is! RenderBox ||
          !viewport.attached ||
          !viewport.hasSize) {
        return;
      }
      final area = MatrixUtils.transformRect(
        viewport.getTransformTo(source),
        Offset.zero & viewport.size,
      );
      if (!area.isFinite || area.isEmpty) return;
      final crop = area.inflate(24).intersect(Offset.zero & source.size);
      if (crop.isEmpty) return;
      final ratio = math.min(
        _dpr,
        math.min(448 / crop.width, 512 / crop.height),
      );
      WidgetDiagnostics.count('settingsSwitchGlassCaptures');
      final image = await source.capture(crop, pixelRatio: ratio);
      pending = image;
      if (!_current(serial)) return;
      final old = _sample;
      setState(() => _sample = SettingsGlassSample._(source, crop, image));
      pending = null;
      _retire(old);
    } catch (_) {
      
      if (retry && _current(serial)) {
        _timer = Timer(
          _layoutDelay,
          () => unawaited(_capture(serial, retry: false)),
        );
      }
    } finally {
      pending?.dispose();
      _busy = false;
      final queued = _queued;
      _queued = null;
      if (queued != null && _current(queued)) unawaited(_capture(queued));
    }
  }

  void _retire(SettingsGlassSample? sample) {
    if (sample == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => sample.image.dispose());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _clear() {
    final old = _sample;
    _sample = null;
    _retire(old);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _serial++;
    widget.backgroundRevision.removeListener(_artworkChanged);
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (_size != constraints.biggest) {
        _size = constraints.biggest;
        _schedule(_layoutDelay);
      }
      return _GlassSampleScope(sample: _sample, child: widget.child);
    },
  );
}

class _GlassSampleScope extends InheritedWidget {
  const _GlassSampleScope({required this.sample, required super.child});

  final SettingsGlassSample? sample;

  @override
  bool updateShouldNotify(_GlassSampleScope oldWidget) =>
      oldWidget.sample != sample;
}

class SettingsGlassSample {
  const SettingsGlassSample._(this._source, this._crop, this.image);

  final RenderBox _source;
  final Rect _crop;
  final ui.Image image;

  Rect? uvFor(RenderObject? target, Size size) {
    if (target is! RenderBox || !target.attached || !_source.attached) {
      return null;
    }
    final rect = MatrixUtils.transformRect(
      target.getTransformTo(_source),
      Offset.zero & size,
    );
    if (!rect.isFinite || rect.isEmpty || !_crop.overlaps(rect)) return null;
    return Rect.fromLTWH(
      (rect.left - _crop.left) / _crop.width,
      (rect.top - _crop.top) / _crop.height,
      rect.width / _crop.width,
      rect.height / _crop.height,
    );
  }
}
