/// The MCRI mark (house outline + isometric "M") as centre-line polylines in
/// a 1024 x 1024 design space, traced from lib/assets/logo.png.
///
/// One geometry drives three things so they always match the real logo:
///   - the animated splash (stroke-drawing),
///   - the Android notification icon (vector drawable),
///   - icon generation tooling.
class LogoGeometry {
  LogoGeometry._();

  static const double size = 1024;

  /// Stroke width of the silver house outline.
  static const double houseStroke = 30;

  /// Stroke width of the orange M.
  static const double mStroke = 58;

  /// Roof with chimney, eave tip to eave tip.
  static const roof = <(double, double)>[
    (212, 410),
    (512, 214),
    (640, 298),
    (640, 252),
    (690, 252),
    (690, 331),
    (812, 410),
  ];

  /// Left wall and the left half of the floor (the gap is the "door").
  static const leftWall = <(double, double)>[
    (270, 373),
    (270, 720),
    (445, 720),
  ];

  /// Right wall and the right half of the floor.
  static const rightWall = <(double, double)>[
    (755, 373),
    (755, 720),
    (582, 720),
  ];

  /// The M, drawn as one continuous stroke from the bottom bar.
  static const mBody = <(double, double)>[
    (530, 700),
    (350, 602),
    (350, 412),
    (512, 506),
    (675, 412),
    (675, 625),
  ];

  /// The M's top bar (the isometric "lid").
  static const mTop = <(double, double)>[(492, 318), (675, 412)];

  static const house = [roof, leftWall, rightWall];
  static const m = [mBody, mTop];
}
