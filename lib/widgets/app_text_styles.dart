import 'package:flutter/material.dart';

/// Small shared text style scale for text roles that were duplicated
/// verbatim across screens. This intentionally does NOT try to collapse
/// every ad hoc font size in the app (page titles range 22–32px by design
/// per screen) — only the handful of styles that were byte-for-byte
/// identical copies meant to represent the same thing (e.g. a timestamp
/// caption) are covered here, to avoid quietly changing per-screen visual
/// hierarchy.
class AppTextStyles {
  AppTextStyles._();

  /// Small "Last updated: ..." / "Last: ..." meta caption under loading and
  /// list-footer states.
  static const TextStyle timestampCaption = TextStyle(
    fontSize: 9,
    color: Colors.black38,
    letterSpacing: 0.3,
  );

  /// Uppercase loading indicator label (e.g. "LOADING...").
  static const TextStyle loadingLabel = TextStyle(
    fontSize: 10,
    letterSpacing: 1.5,
    color: Colors.black38,
    fontWeight: FontWeight.w700,
  );
}
