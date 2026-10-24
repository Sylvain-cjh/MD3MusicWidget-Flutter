import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


class EditableSliderValue extends StatefulWidget {
  final String title, label;
  final double value, min, max;
  final double inputScale;
  final int fractionDigits;
  final String prefix, suffix;
  final TextStyle? style;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  const EditableSliderValue({
    super.key,
    required this.title,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
    this.inputScale = 1,
    this.fractionDigits = 0,
    this.prefix = '',
    this.suffix = '',
    this.style,
  }) : assert(inputScale > 0),
       assert(fractionDigits >= 0 && fractionDigits <= 6),
       assert(min <= max);

  @override
  State<EditableSliderValue> createState() => _EditableSliderValueState();
}

class _EditableSliderValueState extends State<EditableSliderValue> {
  final _controller = TextEditingController();
  final _displayFocus = FocusNode();
  final _inputFocus = FocusNode();
  bool _editing = false, _focused = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _inputFocus.addListener(_onFocusChanged);
  }

  String _number(double value) =>
      (value * widget.inputScale).toStringAsFixed(widget.fractionDigits);

  void _begin() {
    if (_editing) return;
    _controller.text = _number(widget.value);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    setState(() {
      _editing = true;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _inputFocus.requestFocus();
    });
  }

  double? _parse() {
    var text = _controller.text.trim().replaceAll('−', '-');
    if (widget.prefix.isNotEmpty && text.startsWith(widget.prefix)) {
      text = text.substring(widget.prefix.length).trim();
    }
    if (widget.suffix.isNotEmpty && text.endsWith(widget.suffix)) {
      text = text.substring(0, text.length - widget.suffix.length).trim();
    }
    final parsed = double.tryParse(text);
    if (parsed == null || !parsed.isFinite) return null;
    final original = parsed / widget.inputScale;
    if (original < widget.min - 1e-9 || original > widget.max + 1e-9) {
      return null;
    }
    final rounded = double.tryParse(
      parsed.toStringAsFixed(widget.fractionDigits),
    );
    if (rounded == null) return null;
    final value = rounded / widget.inputScale;
    if (!value.isFinite ||
        value < widget.min - 1e-9 ||
        value > widget.max + 1e-9) {
      return null;
    }
    return value.clamp(widget.min, widget.max);
  }

  void _close({bool restoreFocus = false}) {
    setState(() {
      _editing = false;
      _error = null;
    });
    _inputFocus.unfocus();
    if (restoreFocus) _displayFocus.requestFocus();
  }

  void _commit({bool focusLost = false}) {
    if (!_editing) return;
    final value = _parse();
    if (value == null) {
      if (focusLost) {
        _close();
      } else {
        setState(
          () => _error =
              '请输入 ${_number(widget.min)}–${_number(widget.max)}${widget.suffix} 之间的数值',
        );
      }
      return;
    }
    _close(restoreFocus: !focusLost);
    if ((value - widget.value).abs() > 1e-9) {
      widget.onChanged(value);
      widget.onChangeEnd();
    }
  }

  void _onFocusChanged() {
    if (!_inputFocus.hasFocus && _editing) _commit(focusLost: true);
  }

  @override
  void dispose() {
    _inputFocus.removeListener(_onFocusChanged);
    _inputFocus.dispose();
    _displayFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hint =
        '双击输入；范围 ${_number(widget.min)}–${_number(widget.max)}${widget.suffix}';
    return SizedBox(
      width: 112,
      height: 48,
      child: _editing
          ? Center(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      _close(restoreFocus: true),
                },
                child: Tooltip(
                  message: _error ?? hint,
                  child: Semantics(
                    liveRegion: _error != null,
                    label: _error == null
                        ? widget.title
                        : '${widget.title}，$_error',
                    child: TextField(
                      controller: _controller,
                      focusNode: _inputFocus,
                      style: widget.style,
                      textAlign: TextAlign.end,
                      maxLength: 24,
                      keyboardType: TextInputType.numberWithOptions(
                        signed: widget.min < 0,
                        decimal: widget.fractionDigits > 0,
                      ),
                      textInputAction: TextInputAction.done,
                      
                      
                      onEditingComplete: () {},
                      onSubmitted: (_) => _commit(),
                      onTapOutside: (_) => _inputFocus.unfocus(),
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest,
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        prefixText: widget.prefix.isEmpty
                            ? null
                            : widget.prefix,
                        suffixText: widget.suffix.isEmpty
                            ? null
                            : ' ${widget.suffix}',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: scheme.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _error == null
                                ? scheme.primary
                                : scheme.error,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : Focus(
              focusNode: _displayFocus,
              onFocusChange: (focused) => setState(() => _focused = focused),
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    (event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.f2 ||
                        event.logicalKey == LogicalKeyboardKey.space)) {
                  _begin();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Semantics(
                excludeSemantics: true,
                button: true,
                label: widget.title,
                value: widget.label,
                hint: hint,
                onTap: _begin,
                child: Tooltip(
                  message: hint,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.text,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: _begin,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: _focused
                              ? scheme.primary.withValues(alpha: .10)
                              : null,
                        ),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            widget.label,
                            style: widget.style,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
