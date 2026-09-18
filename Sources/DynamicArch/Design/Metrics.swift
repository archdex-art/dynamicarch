import CoreGraphics

/// One dimensional system for the whole island.
///
/// Sizes come from the golden ratio and spacing from the Fibonacci sequence
/// that approximates it, so every gap, inset and panel relates to the others
/// by the same proportion instead of being picked by eye. Everything is
/// rounded to whole points - the island is centred by halving its width, and
/// fractional sizes put its edges on half-pixels.
enum Metrics {
    static let phi: CGFloat = 1.618_033_988_75

    // Spacing scale: 5, 8, 13, 21, 34, 55.
    static let tight: CGFloat = 5
    static let small: CGFloat = 8
    static let medium: CGFloat = 13
    static let large: CGFloat = 21
    static let xlarge: CGFloat = 34
    static let xxlarge: CGFloat = 55

    /// Panel width, and the heights derived from it.
    static let panelWidth: CGFloat = 618
    /// width / phi^2 - the resting proportion for content panels.
    static var panelHeight: CGFloat { (panelWidth / (phi * phi)).rounded() }
    /// One step taller, for the scrolling lists.
    static var listPanelHeight: CGFloat { (panelHeight * 1.272).rounded() }

    /// Square art and rings: the Fibonacci step that fits panelHeight with
    /// `large` padding on both sides.
    static let artwork: CGFloat = 89
    static let ring: CGFloat = 89
    /// Side column, one Fibonacci step below the artwork plus a gap.
    static let sideColumn: CGFloat = 110
    /// Tile height: the artwork step scaled by phi, which fills the panel's
    /// content band without leaving it looking empty.
    static var tile: CGFloat { (artwork * phi).rounded() }
    /// Text column beside a ring or artwork: the panel's major section, so the
    /// pair together occupies panelWidth / phi.
    static var textColumn: CGFloat { ((panelWidth / phi) - ring - large).rounded() }

    /// Horizontal inset inside the panel, and the inset compact content needs
    /// to clear the inverted top corners.
    static let panelInset: CGFloat = large
    static let compactInset: CGFloat = medium + tight
}
