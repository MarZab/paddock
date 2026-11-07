import SwiftUI

/// One card of a project's Info (backlog doc UI, Project Info): its title with a symbol, its actions
/// at the top right (icon buttons with tooltips), and its content in a gray box. Every part of Info
/// is one, so the page reads as a set of like cards that wrap with the window's width.
struct InfoCard<Title: View, Content: View, Actions: View>: View {
    let title: Title
    let content: Content
    let actions: Actions

    /// A title of the card's own (the Status card's state).
    init(@ViewBuilder title: () -> Title, @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions) {
        self.title = title()
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                title
                    .font(.headline)
                    .labelStyle(.titleAndIcon)
                Spacer(minLength: 8)
                actions
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            content
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

extension InfoCard where Title == Label<Text, Image> {
    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions) {
        self.init(title: { Label(title, systemImage: systemImage) }, content: content, actions: actions)
    }
}

extension InfoCard where Title == Label<Text, Image>, Actions == EmptyView {
    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(title, systemImage: systemImage, content: content) { EmptyView() }
    }
}

enum CardMetrics {
    /// The gap between a card's lines (`CardFacts`, and lines next to them: the Status card's meters).
    static let lineSpacing: CGFloat = 6
}

/// Label and value lines in a card: the labels in a column of their own, secondary.
struct CardFacts<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: CardMetrics.lineSpacing) {
            content
        }
        .lineLimit(1)
    }
}

/// One line of `CardFacts`.
struct CardFact<Value: View>: View {
    let title: String
    @ViewBuilder let value: Value
    @Environment(\.cardLabelWidth) private var labelWidth

    init(_ title: String, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    var body: some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)
            value
        }
    }
}

extension EnvironmentValues {
    /// One width for a card's labels, so lines of different kinds in it start their values at the
    /// same edge (the Status card's meters and facts); nil leaves each grid its own.
    @Entry var cardLabelWidth: CGFloat?
}

/// Info's two columns (PAD-131): the narrow cards (one third, left) and the notices and wide cards
/// (two thirds, right), each column its cards at their own height. Subviews in order: wide, narrow. Narrower than `stackBelow`, they
/// stack: the narrow column (agent and status on top), then the wide one.
struct InfoColumns: Layout {
    var spacing: CGFloat = 12
    var stackBelow: CGFloat = 720

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 900
        return CGSize(width: width, height: frames(width: width, subviews: subviews).map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    /// The wide column's frame and the narrow one's, in the subviews' order (wide, narrow).
    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let height = { (subview: LayoutSubview, width: CGFloat) in
            subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        guard subviews.count == 2 else {
            return subviews.map { CGRect(x: 0, y: 0, width: width, height: height($0, width)) }
        }
        guard width >= stackBelow else {
            let narrow = height(subviews[1], width)
            return [CGRect(x: 0, y: narrow + spacing, width: width, height: height(subviews[0], width)),
                    CGRect(x: 0, y: 0, width: width, height: narrow)]
        }
        let wide = ((width - spacing) * 2 / 3).rounded()
        let narrow = width - spacing - wide
        return [CGRect(x: narrow + spacing, y: 0, width: wide, height: height(subviews[0], wide)),
                CGRect(x: 0, y: 0, width: narrow, height: height(subviews[1], narrow))]
    }
}
