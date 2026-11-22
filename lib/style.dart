import 'package:flutter/material.dart';

/// White paper, a pencil line, and colour only where it means something.
class C {
  static const paper = Color(0xFFFFFFFF);
  static const ink = Color(0xFF000000);
  static const lead = Color(0xFF1D1D1F); // pencil graphite
  static const ran = Color(0xFFE62E23); // this lap so far, and stop
  static const you = Color(0xFF1A54F0);
  static const go = Color(0xFF0E9A3F);
  static const trace = Color(0x21000000); // where you actually ran
  static const rule = Color(0x33000000);
  static const line = Color(0x29000000);
  static const wash = Color(0x0D000000);
}

/// Red Hat Mono, a variable font: weight goes through the wght axis.
TextStyle mono(double size, {double weight = 400, Color color = C.ink, double? height, bool underline = false}) =>
    TextStyle(
      fontFamily: 'RedHatMono',
      fontSize: size,
      height: height,
      color: color,
      fontWeight: weight <= 300
          ? FontWeight.w300
          : weight >= 500
          ? FontWeight.w500
          : FontWeight.w400,
      fontVariations: [FontVariation('wght', weight)],
      fontFeatures: const [FontFeature.tabularFigures()],
      decoration: underline ? TextDecoration.underline : null,
    );

const card = BoxDecoration(
  border: Border.fromBorderSide(BorderSide(color: C.line)),
  borderRadius: BorderRadius.all(Radius.circular(16)),
);
