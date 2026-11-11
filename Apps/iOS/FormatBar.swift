import EditorKit
import UIKit

/// The bar above the keyboard while writing a note: links, styles and lists in a glass capsule,
/// scrolling sideways, in the order they're reached for. (Hiding the keyboard is at the note's
/// top right.) While a `[[link` or `#tag` is being typed, what it could be takes the tools'
/// place.
final class FormatBar: UIView {
    private weak var textView: PhoneTextView?
    private let scroller = UIScrollView()
    private let choices = UIScrollView()
    private let choiceStack = UIStackView()
    private let glass = UIVisualEffectView(effect: UIGlassEffect())
    private static let height: CGFloat = 44
    /// Off in the title, which has no styles.
    /// What goes in a link for a note title picked (its name, and its title as the label).
    var linkText: ((String) -> String)?

    var showsTools = true {
        didSet { glass.isHidden = !showsTools }
    }

    init(textView: PhoneTextView) {
        self.textView = textView
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.height + 8))
        autoresizingMask = .flexibleWidth
        // Its height is fixed, as the keyboard's own rows are.
        maximumContentSizeCategory = .extraExtraExtraLarge

        let tools = UIStackView(arrangedSubviews: [
            button("Link to a note", title: "[[") { $0.format { $0.wikiLink() } },
            button("Bold", symbol: "bold") { $0.format { $0.toggleBold() } },
            button("Italic", symbol: "italic") { $0.format { $0.toggleItalic() } },
            headingButton(),
            button("Quote", symbol: "text.quote") { $0.format { $0.toggleBlockQuote() } },
            button("Checklist", symbol: "checklist") { $0.format { $0.toggleChecklist() } },
            button("Bulleted list", symbol: "list.bullet") { $0.format { $0.toggleBulletList() } },
            button("Numbered list", symbol: "list.number") { $0.format { $0.toggleNumberedList() } },
            button("Outdent", symbol: "decrease.indent") { $0.format { $0.outdent() } },
            button("Indent", symbol: "increase.indent") { $0.format { $0.indent() } },
        ])
        tools.spacing = 2
        tools.isLayoutMarginsRelativeArrangement = true
        tools.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)
        tools.translatesAutoresizingMaskIntoConstraints = false

        // At the screen's bottom, with a hardware keyboard, the home bar's inset would lift the tools.
        tools.insetsLayoutMarginsFromSafeArea = false
        scroller.showsHorizontalScrollIndicator = false
        scroller.translatesAutoresizingMaskIntoConstraints = false
        scroller.addSubview(tools)

        choiceStack.spacing = 4
        choiceStack.alignment = .center
        choiceStack.isLayoutMarginsRelativeArrangement = true
        choiceStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)
        choiceStack.translatesAutoresizingMaskIntoConstraints = false
        choiceStack.insetsLayoutMarginsFromSafeArea = false
        choices.showsHorizontalScrollIndicator = false
        choices.translatesAutoresizingMaskIntoConstraints = false
        choices.isHidden = true
        choices.addSubview(choiceStack)

        glass.cornerConfiguration = .capsule()
        glass.clipsToBounds = true
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView.addSubview(scroller)
        glass.contentView.addSubview(choices)

        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            glass.centerYAnchor.constraint(equalTo: centerYAnchor),
            glass.heightAnchor.constraint(equalToConstant: Self.height),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            scroller.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor),
            scroller.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor),
            scroller.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
            scroller.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
            tools.leadingAnchor.constraint(equalTo: scroller.leadingAnchor),
            tools.trailingAnchor.constraint(equalTo: scroller.trailingAnchor),
            tools.topAnchor.constraint(equalTo: scroller.topAnchor),
            tools.bottomAnchor.constraint(equalTo: scroller.bottomAnchor),
            tools.heightAnchor.constraint(equalTo: scroller.heightAnchor),
            choices.leadingAnchor.constraint(equalTo: scroller.leadingAnchor),
            choices.trailingAnchor.constraint(equalTo: scroller.trailingAnchor),
            choices.topAnchor.constraint(equalTo: scroller.topAnchor),
            choices.bottomAnchor.constraint(equalTo: scroller.bottomAnchor),
            choiceStack.leadingAnchor.constraint(equalTo: choices.leadingAnchor),
            choiceStack.trailingAnchor.constraint(equalTo: choices.trailingAnchor),
            choiceStack.topAnchor.constraint(equalTo: choices.topAnchor),
            choiceStack.bottomAnchor.constraint(equalTo: choices.bottomAnchor),
            choiceStack.heightAnchor.constraint(equalTo: choices.heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    /// Between and around its pieces, taps reach the note behind.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }

    /// Offers `choices` for a completion, or goes back to the tools if there are none.
    func show(_ completion: MarkdownEditing.Completion?, choices titles: [String]) {
        choiceStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        choices.isHidden = titles.isEmpty
        scroller.isHidden = !titles.isEmpty
        choices.contentOffset = .zero
        guard let completion else { return }
        for title in titles {
            var configuration = UIButton.Configuration.gray()
            configuration.title = title
            configuration.cornerStyle = .capsule
            configuration.baseForegroundColor = .label
            configuration.titleLineBreakMode = .byTruncatingTail
            let choice = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                let choice = completion.kind == .note ? self.linkText?(title) ?? title : title
                self.textView?.format { $0.complete(completion, with: choice) }
            })
            choice.widthAnchor.constraint(lessThanOrEqualToConstant: 240).isActive = true
            choiceStack.addArrangedSubview(choice)
        }
    }

    private func button(_ name: String, symbol: String? = nil, title: String? = nil, action: @escaping (PhoneTextView) -> Void) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = symbol.flatMap { UIImage(systemName: $0) }
        configuration.title = title
        configuration.baseForegroundColor = .label
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            if let textView = self?.textView { action(textView) }
        })
        button.accessibilityLabel = name
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return button
    }

    /// The heading levels, from a menu: three is as many as a phone needs.
    private func headingButton() -> UIButton {
        let button = button("Heading", symbol: "textformat.size") { _ in }
        let levels = [("Heading 1", 1), ("Heading 2", 2), ("Heading 3", 3), ("Body text", 0)].map { name, level in
            UIAction(title: name) { [weak self] _ in self?.textView?.format { $0.setHeading(level) } }
        }
        button.menu = UIMenu(children: levels)
        button.showsMenuAsPrimaryAction = true
        return button
    }
}
