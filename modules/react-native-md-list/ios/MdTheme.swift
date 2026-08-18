import UIKit

/// Colors, fonts and metrics for one (colorScheme, fontSize) combination.
/// Immutable: everything derived from it can be built on a background queue.
final class MdTheme {

    let dark: Bool
    let baseSize: CGFloat

    let textPrimary: UIColor
    let textSecondary: UIColor
    let link: UIColor
    let divider: UIColor
    let inlineCodeBg: UIColor
    let inlineCodeFg: UIColor
    let codeBg: UIColor
    let codeHeaderBg: UIColor
    let codeFg: UIColor
    let codeHeaderFg: UIColor
    let quoteBar: UIColor
    let quoteFg: UIColor
    let bubbleBg: UIColor
    let tableBorder: UIColor
    let tableHeaderBg: UIColor
    let background: UIColor

    let synKeyword = UIColor(red: 0.78, green: 0.47, blue: 0.87, alpha: 1)
    let synString = UIColor(red: 0.60, green: 0.76, blue: 0.47, alpha: 1)
    let synNumber = UIColor(red: 0.82, green: 0.60, blue: 0.40, alpha: 1)
    let synComment = UIColor(red: 0.50, green: 0.52, blue: 0.56, alpha: 1)
    let synType = UIColor(red: 0.90, green: 0.75, blue: 0.48, alpha: 1)
    let synFunc = UIColor(red: 0.38, green: 0.69, blue: 0.94, alpha: 1)

    let body: UIFont
    let mono: UIFont
    let codeFont: UIFont
    let codeHeaderFont: UIFont
    let tableCellFont: UIFont
    let tableHeadFont: UIFont
    let headings: [UIFont]

    let key: String

    init(dark: Bool, baseSize: CGFloat) {
        self.dark = dark
        self.baseSize = baseSize

        textPrimary = dark ? UIColor(white: 0.925, alpha: 1) : UIColor(white: 0.05, alpha: 1)
        textSecondary = dark ? UIColor(white: 0.61, alpha: 1) : UIColor(red: 0.43, green: 0.43, blue: 0.50, alpha: 1)
        link = dark ? UIColor(red: 0.48, green: 0.72, blue: 1.0, alpha: 1) : UIColor(red: 0.10, green: 0.45, blue: 0.91, alpha: 1)
        divider = dark ? UIColor(white: 0.18, alpha: 1) : UIColor(white: 0.90, alpha: 1)
        inlineCodeBg = dark ? UIColor(white: 0.17, alpha: 1) : UIColor(white: 0.945, alpha: 1)
        inlineCodeFg = dark ? UIColor(red: 0.94, green: 0.64, blue: 0.64, alpha: 1) : UIColor(red: 0.78, green: 0.15, blue: 0.31, alpha: 1)
        codeBg = dark ? UIColor(red: 0.06, green: 0.07, blue: 0.08, alpha: 1) : UIColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 1)
        codeHeaderBg = dark ? UIColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1) : UIColor(red: 0.15, green: 0.17, blue: 0.21, alpha: 1)
        codeFg = UIColor(red: 0.90, green: 0.93, blue: 0.95, alpha: 1)
        codeHeaderFg = UIColor(white: 0.73, alpha: 1)
        quoteBar = dark ? UIColor(white: 0.29, alpha: 1) : UIColor(white: 0.83, alpha: 1)
        quoteFg = dark ? UIColor(white: 0.75, alpha: 1) : UIColor(white: 0.36, alpha: 1)
        bubbleBg = dark ? UIColor(white: 0.19, alpha: 1) : UIColor(white: 0.94, alpha: 1)
        tableBorder = dark ? UIColor(white: 0.23, alpha: 1) : UIColor(white: 0.87, alpha: 1)
        tableHeaderBg = dark ? UIColor(white: 0.14, alpha: 1) : UIColor(white: 0.97, alpha: 1)
        background = dark ? UIColor(white: 0.13, alpha: 1) : .white

        body = UIFont.systemFont(ofSize: baseSize)
        mono = UIFont.monospacedSystemFont(ofSize: baseSize * 0.92, weight: .regular)
        codeFont = UIFont.monospacedSystemFont(ofSize: baseSize * 0.84, weight: .regular)
        codeHeaderFont = UIFont.systemFont(ofSize: baseSize * 0.72, weight: .medium)
        tableCellFont = UIFont.systemFont(ofSize: baseSize * 0.9)
        tableHeadFont = UIFont.systemFont(ofSize: baseSize * 0.9, weight: .semibold)

        let scales: [CGFloat] = [1.62, 1.38, 1.2, 1.08, 1.0, 0.94]
        headings = scales.map { UIFont.systemFont(ofSize: baseSize * $0, weight: .bold) }

        key = "\(dark ? "d" : "l")-\(baseSize)"
    }

    func headingFont(_ level: Int) -> UIFont {
        headings[min(max(level - 1, 0), 5)]
    }
}
