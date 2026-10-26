import SwiftUI

/// Target buttons grouped by kind, followed by install hints for missing tools.
struct ConverterTargetGrid: View {
    let model: ConverterSelectionModel
    let columnCount: Int
    let onPick: (ConversionTarget) -> Void

    private static let rowHeight: CGFloat = 38
    private static let sectionHeaderHeight: CGFloat = 22
    private static let hintHeight: CGFloat = 20

    /// Approximate rendered height, so a floating panel can be sized before layout.
    static func estimatedHeight(for model: ConverterSelectionModel, columnCount: Int) -> CGFloat {
        let sections = model.sections.reduce(CGFloat(0)) { total, section in
            let rows = (section.targets.count + columnCount - 1) / columnCount
            return total + sectionHeaderHeight + CGFloat(rows) * rowHeight
        }
        return sections + CGFloat(model.missingToolHints.count) * hintHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text(section.group.title))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columnCount), spacing: 6) {
                        ForEach(section.targets) { target in
                            Button { onPick(target) } label: {
                                Text(L10n.text(target.title))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(BrandSecondaryButtonStyle())
                        }
                    }
                }
            }
            ForEach(model.missingToolHints, id: \.self) { hint in
                Label(L10n.text(hint), systemImage: "arrow.down.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(height: Self.hintHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
