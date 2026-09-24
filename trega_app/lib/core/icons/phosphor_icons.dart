// Phosphor icons, vendored for Trega.
//
// `phosphor_flutter` 2.0.x cannot compile on current Flutter stable: it
// declares `class PhosphorIconData extends IconData`, but `IconData` is now a
// final class and can no longer be extended. This file keeps the exact same
// Phosphor glyphs (same codepoints, same OFL-licensed font files, now bundled
// under assets/fonts/) as plain `const IconData` values, so no call site in
// the app had to change. Only the icons actually used by the app are listed.

import 'package:flutter/widgets.dart';

/// Outline (Regular) Phosphor glyphs.
class PhosphorIconsRegular {
  const PhosphorIconsRegular._();

  static const IconData bell = IconData(
    0xe9af,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData bellSlash = IconData(
    0xe9b5,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData camera = IconData(
    0xe9e9,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData cameraPlus = IconData(
    0xe9ea,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData caretRight = IconData(
    0xea00,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData chartBar = IconData(
    0xea17,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData check = IconData(
    0xea30,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData checkCircle = IconData(
    0xea31,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData cloudSlash = IconData(
    0xea50,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData deviceMobile = IconData(
    0xea93,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData dotsThree = IconData(
    0xeaaf,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData envelope = IconData(
    0xeac5,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData fingerprint = IconData(
    0xeb09,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData flag = IconData(
    0xeb13,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData gameController = IconData(
    0xeb3d,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData gavel = IconData(
    0xeb42,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData gear = IconData(
    0xeb43,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData handshake = IconData(
    0xeb7b,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData headset = IconData(
    0xeb88,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData heart = IconData(
    0xeb89,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData house = IconData(
    0xeb9c,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData image = IconData(
    0xeba2,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData images = IconData(
    0xeba3,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData info = IconData(
    0xeba7,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData laptop = IconData(
    0xebb6,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData lightning = IconData(
    0xebbd,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData lock = IconData(
    0xebd1,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData magnifyingGlass = IconData(
    0xebdd,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData mapPin = IconData(
    0xebe0,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData musicNote = IconData(
    0xec07,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData package = IconData(
    0xec3c,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData play = IconData(
    0xec7e,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData plus = IconData(
    0xec86,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData plusCircle = IconData(
    0xec87,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData prohibit = IconData(
    0xec94,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData question = IconData(
    0xec9f,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData sealCheck = IconData(
    0xecc4,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData shareNetwork = IconData(
    0xecd1,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData shieldCheck = IconData(
    0xecd3,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData signIn = IconData(
    0xece9,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData signOut = IconData(
    0xecea,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData squaresFour = IconData(
    0xed20,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData star = IconData(
    0xed28,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData trash = IconData(
    0xed8a,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData tray = IconData(
    0xed8c,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData trendUp = IconData(
    0xed92,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData truck = IconData(
    0xed95,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData user = IconData(
    0xeda0,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData wallet = IconData(
    0xedbd,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData warning = IconData(
    0xedbf,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData warningCircle = IconData(
    0xedc0,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData watch = IconData(
    0xedc3,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData x = IconData(
    0xeddb,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
  static const IconData xCircle = IconData(
    0xeddc,
    fontFamily: 'PhosphorRegular',
    matchTextDirection: true,
  );
}

/// Filled Phosphor glyphs.
class PhosphorIconsFill {
  const PhosphorIconsFill._();

  static const IconData heart = IconData(
    0xeb8b,
    fontFamily: 'PhosphorFill',
    matchTextDirection: true,
  );
}
