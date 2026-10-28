import AppKit

/// An illustration of the desired settings, never a reading of system state.
final class SetupGuideView: NSView {
    private let rowCount: Int
    private let compact: Bool

    init(step: ClockSetupStep, compact: Bool = false) {
        rowCount = step.rows.count
        self.compact = compact
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let caption = NSTextField(wrappingLabelWithString: "Схема настройки • вид зависит от версии macOS")
        caption.font = .systemFont(ofSize: compact ? 11 : 12)
        caption.textColor = .secondaryLabelColor
        let breadcrumb = NSTextField(wrappingLabelWithString: step.path)
        breadcrumb.font = .systemFont(ofSize: compact ? 13 : 14, weight: .semibold)
        breadcrumb.textColor = .labelColor
        let stack = NSStackView(views: [caption, breadcrumb])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = compact ? 8 : 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for (index, row) in step.rows.enumerated() {
            stack.addArrangedSubview(SetupGuideRowView(row: row, number: index + 1, compact: compact))
        }
        for view in stack.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Схема настройки. \(step.path). " + step.rows.map {
            "\($0.label): \($0.value)\($0.highlighted ? ", нужное значение" : ", оставить без изменений")"
        }.joined(separator: ". "))
        setAccessibilityChildren([])
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: compact ? (rowCount > 1 ? 220 : 144) : (rowCount > 1 ? 244 : 190))
    }

    required init?(coder: NSCoder) { nil }
}

private final class SetupGuideRowView: NSView {
    private let highlighted: Bool
    private let value: NSTextField

    init(row: ClockSetupRow, number: Int, compact: Bool) {
        highlighted = row.highlighted
        value = NSTextField(wrappingLabelWithString: row.value)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let marker = NSTextField(labelWithString: row.highlighted ? String(number) : "•")
        marker.font = .systemFont(ofSize: 15, weight: .bold)
        marker.textColor = row.highlighted ? .controlAccentColor : .secondaryLabelColor
        marker.alignment = .center
        let label = NSTextField(wrappingLabelWithString: row.label)
        label.font = .systemFont(ofSize: compact ? 12 : 14)
        label.textColor = .labelColor
        value.font = .systemFont(ofSize: compact ? 12 : 14, weight: .semibold)
        value.textColor = .labelColor
        value.alignment = .center
        for view in [marker, label, value] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            view.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: compact ? 68 : 72),
            marker.leadingAnchor.constraint(equalTo: leadingAnchor, constant: compact ? 6 : 12),
            marker.widthAnchor.constraint(equalToConstant: compact ? 18 : 24),
            label.leadingAnchor.constraint(equalTo: marker.trailingAnchor, constant: compact ? 6 : 10),
            label.trailingAnchor.constraint(equalTo: value.leadingAnchor, constant: compact ? -20 : -26),
            value.trailingAnchor.constraint(equalTo: trailingAnchor, constant: compact ? -18 : -24),
            value.widthAnchor.constraint(equalToConstant: compact ? 114 : 184)
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12)
        NSColor.controlBackgroundColor.setFill()
        outline.fill()
        (highlighted ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        outline.lineWidth = highlighted ? 2 : 1
        outline.stroke()
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: value.frame.insetBy(dx: -10, dy: -8), xRadius: 7, yRadius: 7).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    required init?(coder: NSCoder) { nil }
}
