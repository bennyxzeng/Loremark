import 'package:flutter/material.dart';

/// Lets the page down as the keyboard goes over the whole of the keyboard's
/// way, so it eases to a stop with it, as it does when the keyboard comes.
///
/// A Scaffold ends its body at the keyboard's top or at the [bar] under it,
/// whichever is higher. Going, the keyboard is quick at first and eases to a
/// stop out of sight behind the bar, so the page would follow it only to the
/// bar and stop there at full speed. While the keyboard goes, with no text
/// field focused, how high it reaches is mapped onto the page's whole way down
/// instead. While one is focused the page keeps to the keyboard's top, so
/// nothing being written is ever under the keyboard.
class EasedKeyboard extends StatefulWidget {
  const EasedKeyboard({super.key, required this.bar, required this.child});

  /// How tall the bar is that the keyboard goes behind.
  final double bar;

  final Widget child;

  /// How high the keyboard reaches for the page under [context]: eased as it
  /// goes under an [EasedKeyboard], or as it is otherwise.
  static double insetOf(BuildContext context) {
    final eased = context.dependOnInheritedWidgetOfExactType<_Inset>();
    if (eased != null) return eased.inset;
    final view = View.of(context);
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  @override
  State<EasedKeyboard> createState() => _EasedKeyboardState();
}

class _EasedKeyboardState extends State<EasedKeyboard> {
  /// How high the keyboard reached when it began to go, while it goes.
  double? _from;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_focusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    super.dispose();
  }

  void _focusChanged() => setState(() {});

  /// Whether a text field has focus, and so the keyboard is staying.
  static bool get _writing =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>() !=
      null;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    if (_writing || keyboard == 0) {
      _from = null;
    } else {
      _from ??= keyboard;
    }
    final from = _from;
    final bar = widget.bar;
    final inset = from == null || from <= bar
        ? keyboard
        : bar + (from - bar) * keyboard / from;
    return _Inset(
      inset: inset,
      child: MediaQuery(
        data: media.copyWith(
          viewInsets: media.viewInsets.copyWith(bottom: inset),
        ),
        child: widget.child,
      ),
    );
  }
}

class _Inset extends InheritedWidget {
  const _Inset({required this.inset, required super.child});

  final double inset;

  @override
  bool updateShouldNotify(_Inset oldWidget) => oldWidget.inset != inset;
}
