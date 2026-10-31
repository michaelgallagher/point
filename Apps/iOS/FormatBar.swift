import EditorKit
import UIKit

/// The bar above the keyboard while writing a note: links, tags, lists and styles, scrolling
/// sideways, in the order they're reached for; and at its right, always in reach, hiding the
/// keyboard. While a `[[link` or `#tag` is being typed, what it could be takes the tools' place.
final class FormatBar: UIInputView {
    private weak var textView: PhoneTextView?
    private let scroller = UIScrollView()
    private let choices = UIScrollView()
    private let choiceStack = UIStackView()

    init(textView: PhoneTextView) {
        self.textView = textView
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 48), inputViewStyle: .keyboard)
        allowsSelfSizing = false
        autoresizingMask = .flexibleWidth
        // Its height is fixed, as the keyboard's own rows are.
        maximumContentSizeCategory = .extraExtraExtraLarge

        let tools = UIStackView(arrangedSubviews: [
            button("Link to a Note", title: "[[") { $0.format { $0.wikiLink() } },
            button("Tag", symbol: "number") { $0.format { $0.inserting("#") } },
            button("Checklist", symbol: "checklist") { $0.format { $0.toggleChecklist() } },
            button("Bulleted List", symbol: "list.bullet") { $0.format { $0.toggleBulletList() } },
            button("Outdent", symbol: "decrease.indent") { $0.format { $0.outdent() } },
            button("Indent", symbol: "increase.indent") { $0.format { $0.indent() } },
            headingButton(),
            button("Bold", symbol: "bold") { $0.format { $0.toggleBold() } },
            button("Italic", symbol: "italic") { $0.format { $0.toggleItalic() } },
            button("Highlight", symbol: "highlighter") { $0.format { $0.toggleHighlight() } },
            button("Strikethrough", symbol: "strikethrough") { $0.format { $0.toggleStrikethrough() } },
            button("Quote", symbol: "text.quote") { $0.format { $0.toggleBlockQuote() } },
            button("Code", symbol: "chevron.left.forwardslash.chevron.right") { $0.format { $0.toggleCode() } },
        ])
        tools.spacing = 2
        tools.translatesAutoresizingMaskIntoConstraints = false

        scroller.showsHorizontalScrollIndicator = false
        scroller.translatesAutoresizingMaskIntoConstraints = false
        scroller.addSubview(tools)

        choiceStack.spacing = 4
        choiceStack.alignment = .center
        choiceStack.translatesAutoresizingMaskIntoConstraints = false
        choices.showsHorizontalScrollIndicator = false
        choices.translatesAutoresizingMaskIntoConstraints = false
        choices.isHidden = true
        choices.addSubview(choiceStack)

        let hide = button("Hide Keyboard", symbol: "keyboard.chevron.compact.down") { $0.resignFirstResponder() }
        hide.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scroller)
        addSubview(choices)
        addSubview(hide)
        NSLayoutConstraint.activate([
            scroller.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scroller.topAnchor.constraint(equalTo: topAnchor),
            scroller.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroller.trailingAnchor.constraint(equalTo: hide.leadingAnchor, constant: -4),
            hide.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            hide.centerYAnchor.constraint(equalTo: centerYAnchor),
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
                self?.textView?.format { $0.complete(completion, with: title) }
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
        let levels = [("Heading 1", 1), ("Heading 2", 2), ("Heading 3", 3), ("Body Text", 0)].map { name, level in
            UIAction(title: name) { [weak self] _ in self?.textView?.format { $0.setHeading(level) } }
        }
        button.menu = UIMenu(children: levels)
        button.showsMenuAsPrimaryAction = true
        return button
    }
}
