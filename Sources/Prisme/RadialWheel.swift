import AppKit
import SwiftUI
import PrismeCore
import Darwin

struct WheelItem {
    let id: String
    let title: String
    let shortTitle: String
    let symbol: String
    let action: ConversionAction?
}

@MainActor
final class GlobalDragController {
    private let model: AppModel
    private var timer: Timer?
    private var panel: NSPanel?
    private var wheel: RadialDropView?
    private var wasDragging = false
    private var previousFlags: NSEvent.ModifierFlags = []
    private var dismissedDuringDrag = false

    init(model: AppModel) { self.model = model }

    func start() {
        model.dismissQuickPalette = { [weak self] in self?.dismiss() }
        model.presentQuickPalette = { [weak self] urls in self?.show(urls: urls, mode: .convert, at: NSEvent.mouseLocation) }
        // The system drag pasteboard and modifier state avoid an accessibility event tap.
        let timer = Timer(timeInterval: 0.055, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        let dragging = NSEvent.pressedMouseButtons & 1 != 0
        let flags = NSEvent.modifierFlags.intersection([.shift, .command, .control, .option])
        defer { wasDragging = dragging; previousFlags = flags }
        guard model.globalDragEnabled, !model.isWorking else { if panel?.isVisible == true { dismiss() }; return }
        if dragging && !wasDragging { dismissedDuringDrag = false }
        if !dragging && wasDragging {
            // Drag destinations process the drop before the next run-loop cycle.
            if panel?.isVisible == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.dismiss() }
            }
            return
        }
        guard dragging, !dismissedDuringDrag, flags != previousFlags || !wasDragging || panel?.isVisible != true else { return }
        let mode: PaletteMode?
        if flags.contains(DragKey.flag(model.conversionTrigger)) { mode = .convert }
        else if flags.contains(DragKey.flag(model.toolsTrigger)) { mode = .tools }
        else if flags.contains(DragKey.flag(model.actionsTrigger)) { mode = .actions }
        else { mode = nil }
        guard let mode else { return }
        let pasteboard = NSPasteboard(name: .drag)
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL] ?? []).map { $0 as URL }
        guard !urls.isEmpty else { return }
        show(urls: urls, mode: mode, at: NSEvent.mouseLocation)
    }

    func show(urls: [URL], mode: PaletteMode, at point: NSPoint) {
        guard !model.isWorking else { return }
        model.quickFiles = urls
        model.quickMode = mode
        let items: [WheelItem]
        if mode == .actions {
            items = [
                WheelItem(id: "reveal", title: "Afficher dans le Finder", shortTitle: "Finder", symbol: "folder", action: nil),
                WheelItem(id: "copy", title: "Copier les fichiers", shortTitle: "Copier", symbol: "doc.on.doc", action: nil),
                WheelItem(id: "path", title: "Copier le chemin", shortTitle: "Chemin", symbol: "link", action: nil),
                WheelItem(id: "airdrop", title: "Envoyer avec AirDrop", shortTitle: "AirDrop", symbol: "airplayaudio", action: nil),
                WheelItem(id: "terminal", title: "Ouvrir le dossier dans Terminal", shortTitle: "Terminal", symbol: "terminal", action: nil)
            ]
        } else {
            items = model.quickActions.map { action in
                let short = (ConversionEngine.isTool(action) ? nil : action.outputExtension?.uppercased()) ?? action.title
                    .replacingOccurrences(of: " les images", with: "")
                    .replacingOccurrences(of: " le PDF", with: "")
                    .replacingOccurrences(of: "Créer une archive ", with: "")
                return WheelItem(id: action.id, title: action.title, shortTitle: short, symbol: action.symbol, action: action)
            }
        }
        if panel == nil {
            let panel = WheelPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 340), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = .popUpMenu
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.title = "Roue Prisme"
            let wheel = RadialDropView(frame: NSRect(x: 0, y: 0, width: 340, height: 340))
            wheel.onSelect = { [weak self] item, droppedURLs in
                guard let self else { return }
                let inputs = droppedURLs.isEmpty ? self.model.quickFiles : droppedURLs
                if let action = item.action { self.model.run(action, on: inputs) }
                else { self.model.fileAction(item.id, urls: inputs) }
                self.dismiss()
            }
            wheel.onDismiss = { [weak self] in self?.dismiss() }
            panel.contentView = wheel
            self.wheel = wheel
            self.panel = panel
        }
        wheel?.configure(items: items, files: urls, mode: mode, glass: model.wheelAppearance == "glass")
        let newlyVisible = panel?.isVisible != true
        if newlyVisible {
            let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let origin = NSPoint(x: max(visible.minX + 8, min(point.x - 170, visible.maxX - 348)),
                                 y: max(visible.minY + 8, min(point.y - 170, visible.maxY - 348)))
            panel?.setFrameOrigin(origin)
            panel?.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        }
        panel?.orderFrontRegardless()
        if newlyVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.13
                panel?.animator().alphaValue = 1
            }
        }
        if NSEvent.pressedMouseButtons & 1 == 0 {
            panel?.makeKey()
            panel?.makeFirstResponder(wheel)
        }
    }

    func dismiss() {
        panel?.orderOut(nil)
        dismissedDuringDrag = true
    }
}

private final class WheelPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum DragKey {
    static let all = ["shift", "command", "control", "option"]
    static func label(_ value: String) -> String {
        switch value { case "command": return "⌘ Commande"; case "control": return "⌃ Contrôle"; case "option": return "⌥ Option"; default: return "⇧ Maj" }
    }
    static func flag(_ value: String) -> NSEvent.ModifierFlags {
        switch value { case "command": return .command; case "control": return .control; case "option": return .option; default: return .shift }
    }
}

@MainActor
final class RadialDropView: NSView {
    var onSelect: ((WheelItem, [URL]) -> Void)?
    var onDismiss: (() -> Void)?
    private var items: [WheelItem] = []
    private var files: [URL] = []
    private var mode: PaletteMode = .convert
    private var selected: Int?
    private var glass = true
    private var tracking: NSTrackingArea?
    private let centerPoint = NSPoint(x: 230, y: 230)
    private let outerRadius: CGFloat = 199
    private let innerRadius: CGFloat = 88
    private var page = 0
    private let pageSize = 10
    private let geometry = RadialGeometry()

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Roue Prisme : déposez un fichier sur un segment")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(items: [WheelItem], files: [URL], mode: PaletteMode, glass: Bool) {
        self.items = items
        self.files = files
        self.mode = mode
        self.glass = glass
        page = 0
        selected = nil
        setAccessibilityValue(items.map(\.title).joined(separator: ", "))
        needsDisplay = true
    }

    private var visibleItems: [WheelItem] { Array(items.dropFirst(page * pageSize).prefix(pageSize)) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    private func sectorPath(_ index: Int, count: Int) -> NSBezierPath {
        let step = 360.0 / Double(count)
        let start = 90.0 - Double(index) * step + step / 2 - 1.2
        let end = start - step + 2.4
        let corner: CGFloat = 9
        let outerInset = Double(corner / outerRadius) * 180 / .pi
        let innerInset = Double(corner / innerRadius) * 180 / .pi
        func point(_ radius: CGFloat, _ angle: Double) -> NSPoint {
            let radians = angle * .pi / 180
            return NSPoint(x: centerPoint.x + radius * CGFloat(Darwin.cos(radians)),
                           y: centerPoint.y + radius * CGFloat(Darwin.sin(radians)))
        }
        let path = NSBezierPath()
        func roundedCorner(to destination: NSPoint, via control: NSPoint) {
            let previous = path.currentPoint
            path.curve(to: destination,
                       controlPoint1: NSPoint(x: previous.x + (control.x - previous.x) * 2 / 3, y: previous.y + (control.y - previous.y) * 2 / 3),
                       controlPoint2: NSPoint(x: destination.x + (control.x - destination.x) * 2 / 3, y: destination.y + (control.y - destination.y) * 2 / 3))
        }
        path.move(to: point(outerRadius, start - outerInset))
        path.appendArc(withCenter: centerPoint, radius: outerRadius, startAngle: CGFloat(start - outerInset), endAngle: CGFloat(end + outerInset), clockwise: true)
        roundedCorner(to: point(outerRadius - corner, end), via: point(outerRadius, end))
        path.line(to: point(innerRadius + corner, end))
        roundedCorner(to: point(innerRadius, end + innerInset), via: point(innerRadius, end))
        path.appendArc(withCenter: centerPoint, radius: innerRadius, startAngle: CGFloat(end + innerInset), endAngle: CGFloat(start - innerInset), clockwise: false)
        roundedCorner(to: point(innerRadius + corner, start), via: point(innerRadius, start))
        path.line(to: point(outerRadius - corner, start))
        roundedCorner(to: point(outerRadius, start - outerInset), via: point(outerRadius, start))
        path.close()
        return path
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let scale = NSAffineTransform()
        scale.scale(by: bounds.width / 460)
        scale.concat()
        let visible = visibleItems
        let accent = NSColor(red: 0.64, green: 0.93, blue: 0.80, alpha: 1)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = .black.withAlphaComponent(0.30)
        shadow.shadowBlurRadius = 20
        shadow.set()
        NSColor(red: 0.055, green: 0.075, blue: 0.085, alpha: glass ? 0.90 : 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 29, y: 29, width: 402, height: 402)).fill()
        NSGraphicsContext.restoreGraphicsState()
        for (index, item) in visible.enumerated() {
            let path = sectorPath(index, count: visible.count)
            let highlighted = selected == index
            (highlighted ? accent.withAlphaComponent(0.95) : NSColor.white.withAlphaComponent(0.045)).setFill()
            path.fill()
            (highlighted ? accent : NSColor.white.withAlphaComponent(0.11)).setStroke()
            path.lineWidth = 0.7
            path.stroke()
            let location = geometry.labelCenter(for: index, count: visible.count)
            let foreground = highlighted ? NSColor(red: 0.04, green: 0.13, blue: 0.12, alpha: 1) : accent
            let configuration = NSImage.SymbolConfiguration(pointSize: 20, weight: .light)
            if let icon = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)?.withSymbolConfiguration(configuration) {
                icon.isTemplate = true
                let tinted = NSImage(size: NSSize(width: 24, height: 24))
                tinted.lockFocus()
                foreground.setFill()
                NSRect(x: 0, y: 0, width: 24, height: 24).fill()
                icon.draw(in: NSRect(x: 2, y: 2, width: 20, height: 20), from: .zero, operation: .destinationIn, fraction: 1)
                tinted.unlockFocus()
                tinted.draw(in: NSRect(x: location.x - 12, y: location.y + 1, width: 24, height: 24))
            }
            drawText(item.shortTitle, center: NSPoint(x: location.x, y: location.y - 15), width: visible.count > 8 ? 92 : 116,
                     font: .systemFont(ofSize: item.shortTitle.count > 16 ? 11 : 13, weight: .medium), color: foreground)
        }
        NSColor(red: 0.07, green: 0.10, blue: 0.115, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 147, y: 147, width: 166, height: 166)).fill()
        NSColor.white.withAlphaComponent(0.10).setStroke()
        NSBezierPath(ovalIn: NSRect(x: 147, y: 147, width: 166, height: 166)).stroke()
        drawText("PRISME", center: NSPoint(x: 230, y: 265), width: 128, font: .monospacedSystemFont(ofSize: 9, weight: .semibold), color: accent.withAlphaComponent(0.6))
        let mainTitle = selected.flatMap { visible.indices.contains($0) ? visible[$0].title : nil } ?? (items.isEmpty ? "Aucune option" : mode.rawValue)
        drawText(mainTitle, center: NSPoint(x: 230, y: 233), width: 140, font: .systemFont(ofSize: 14, weight: .medium), color: .white)
        let caption = selected == nil ? (files.count == 1 ? files[0].lastPathComponent : "\(files.count) fichiers") : "Relâchez pour appliquer"
        drawText(caption, center: NSPoint(x: 230, y: 203), width: 132, font: .systemFont(ofSize: 10), color: .white.withAlphaComponent(0.5))
        if items.count > pageSize {
            drawText("‹  \(page + 1) / \(Int(ceil(Double(items.count) / Double(pageSize))))  ›", center: NSPoint(x: 230, y: 175), width: 95, font: .systemFont(ofSize: 10), color: accent)
        }
        drawText("⇧ Formats    ⌘ Outils    ⌃ Actions", center: NSPoint(x: 230, y: 9), width: 360, font: .systemFont(ofSize: 10, weight: .medium), color: .white.withAlphaComponent(0.72))
    }

    private func drawText(_ text: String, center: NSPoint, width: CGFloat, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
        let height = string.boundingRect(with: NSSize(width: width, height: 38), options: [.usesLineFragmentOrigin]).height
        string.draw(in: NSRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: min(height, 38)))
    }

    private func updateSelection(_ point: NSPoint) {
        let normalized = NSPoint(x: point.x * 460 / bounds.width, y: point.y * 460 / bounds.height)
        let next = geometry.segmentIndex(at: normalized, count: visibleItems.count)
        if selected != next { selected = next; needsDisplay = true }
    }

    override func mouseMoved(with event: NSEvent) { updateSelection(convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { selected = nil; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if hypot(point.x * 460 / bounds.width - 230, point.y * 460 / bounds.height - 230) < innerRadius {
            if items.count > pageSize { page = (page + 1) % Int(ceil(Double(items.count) / Double(pageSize))); selected = nil; needsDisplay = true }
            return
        }
        updateSelection(point)
        if let selected, visibleItems.indices.contains(selected) { onSelect?(visibleItems[selected], files) }
        else { onDismiss?() }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDismiss?(); return }
        if event.keyCode == 36, let selected, visibleItems.indices.contains(selected) { onSelect?(visibleItems[selected], files); return }
        guard !visibleItems.isEmpty else { return }
        if event.keyCode == 123 || event.keyCode == 126 { selected = ((selected ?? 0) - 1 + visibleItems.count) % visibleItems.count }
        if event.keyCode == 124 || event.keyCode == 125 { selected = ((selected ?? -1) + 1) % visibleItems.count }
        needsDisplay = true
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateSelection(convert(sender.draggingLocation, from: nil))
        return selected == nil ? [] : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { selected = nil; needsDisplay = true }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { selected != nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        updateSelection(convert(sender.draggingLocation, from: nil))
        guard let selected, visibleItems.indices.contains(selected) else { return false }
        let urls = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL] ?? []).map { $0 as URL }
        guard !urls.isEmpty else { return false }
        let item = visibleItems[selected]
        DispatchQueue.main.async { [weak self] in self?.onSelect?(item, urls) }
        return true
    }
}
