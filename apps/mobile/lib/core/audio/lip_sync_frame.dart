/// Real-time mouth shape parameters driven by TTS audio playback at ~60fps.
class LipSyncFrame {
  /// Normalized jaw/mouth openness in `[0.0, 1.0]`:
  /// - `0.00`: closed bilabial consonant (`M`, `B`, `P`)
  /// - `0.28`: neutral resting smile (matches static portrait)
  /// - `0.35 .. 1.00`: open vowel (`E`, `A`, `O`, `U`)
  final double mouthOpen;

  /// Horizontal lip shape in `[-1.0, 1.0]`:
  /// - `< 0`: rounded/pursed lips (`O`, `Ô`, `U`)
  /// - `0`: neutral width
  /// - `> 0`: spread/wide smile (`I`, `Ê`, `A`)
  final double mouthWide;

  /// Raw normalized vocal energy in `[0.0, 1.0]` for subtle head/aura rhythm.
  final double energy;

  /// True when actively driven by JS audio playback (`AnalyserNode` or stream).
  final bool active;

  const LipSyncFrame({
    this.mouthOpen = restOpen,
    this.mouthWide = 0.0,
    this.energy = 0.0,
    this.active = false,
  });

  static const double restOpen = 0.28;
  static const LipSyncFrame idle = LipSyncFrame();
}

