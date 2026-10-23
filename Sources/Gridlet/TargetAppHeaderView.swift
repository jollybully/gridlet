import AppKit

struct TargetAppHeaderMetadata {
    var title: String
    var symbolName: String?
    var image: NSImage?

    init(title: String, symbolName: String? = nil, image: NSImage? = nil) {
        self.title = title
        self.symbolName = symbolName
        self.image = image
    }

}

@MainActor
enum TargetAppHeaderPresets {
    static var safari: TargetAppHeaderMetadata {
        TargetAppHeaderMetadata(title: "Safari", symbolName: "safari")
    }
    static var visualStudioCode: TargetAppHeaderMetadata {
        TargetAppHeaderMetadata(
            title: "Visual Studio Code",
            symbolName: "chevron.left.forwardslash.chevron.right"
        )
    }
    static var noWindow: TargetAppHeaderMetadata {
        TargetAppHeaderMetadata(title: "No window", symbolName: "app.dashed")
    }
}

/// Icon + title row centered as one unit in the panel header.
final class TargetAppHeaderView: NSView {
    static let iconSize: CGFloat = 22
    static let iconTitleGap: CGFloat = 6

    let iconContainer = NSView()
    let iconView = NSImageView()
    let titleGapView = NSView()
    let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleGapView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyDown
        iconView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        titleGapView.setContentHuggingPriority(.required, for: .horizontal)
        titleGapView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        iconContainer.addSubview(iconView)
        addSubview(iconContainer)
        addSubview(titleGapView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconContainer.heightAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor),
            iconView.topAnchor.constraint(equalTo: iconContainer.topAnchor),
            iconView.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor),
            titleGapView.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor),
            titleGapView.widthAnchor.constraint(equalToConstant: Self.iconTitleGap),
            titleGapView.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            titleGapView.heightAnchor.constraint(equalToConstant: 1),
            titleLabel.leadingAnchor.constraint(equalTo: titleGapView.trailingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            topAnchor.constraint(equalTo: iconContainer.topAnchor),
            bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func apply(_ metadata: TargetAppHeaderMetadata) {
        titleLabel.stringValue = metadata.title
        if let image = metadata.image {
            iconView.image = image
        } else if let symbolName = metadata.symbolName {
            iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        } else {
            iconView.image = nil
        }
    }
}

struct PanelHeaderAlignmentSnapshot: Codable, Equatable {
    struct RectCodable: Codable, Equatable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ rect: NSRect) {
            x = Double(rect.origin.x)
            y = Double(rect.origin.y)
            width = Double(rect.width)
            height = Double(rect.height)
        }

        var midX: Double { x + width / 2 }
    }

    let scenario: String
    let panelSize: RectCodable
    let panelMidX: Double
    let group: RectCodable
    let icon: RectCodable
    let title: RectCodable
    let close: RectCodable
    let settings: RectCodable
    let centerDelta: Double
    let iconTitleGap: Double
    let headerCenterY: Double
}

enum HeaderAlignmentDiagnostics {
    @MainActor
    static func allSnapshots(controller: GridPanelController) -> [PanelHeaderAlignmentSnapshot] {
        let scenarios: [(String, TargetAppHeaderMetadata)] = [
            ("safari_short", TargetAppHeaderPresets.safari),
            ("visual_studio_code_medium", TargetAppHeaderPresets.visualStudioCode),
            (
                "very_long_app_name",
                TargetAppHeaderMetadata(
                    title: String(repeating: "Integration Studio ", count: 8),
                    symbolName: "app"
                )
            ),
            ("no_window", TargetAppHeaderPresets.noWindow),
        ]
        return scenarios.map { name, metadata in
            controller.prepareHeaderAlignmentProbe(metadata: metadata)
            return controller.headerAlignmentSnapshot(scenario: name)
        }
    }

    @MainActor
    static func jsonString(controller: GridPanelController) -> String {
        let snaps = allSnapshots(controller: controller)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snaps),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }
}
