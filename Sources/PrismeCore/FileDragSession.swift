/// Separates a new drag gesture from clicks and the drag pasteboard's retained contents.
/// File URLs may only be read after movement and a change of pasteboard ownership
/// since this press. Modifier keys deliberately do not affect this state.
public struct FileDragSession {
    private var initialPasteboardChangeCount: Int?
    private var hasDragged = false

    public init() {}

    public mutating func mouseDown(pasteboardChangeCount: Int) {
        initialPasteboardChangeCount = pasteboardChangeCount
        hasDragged = false
    }

    public mutating func mouseDragged() {
        guard initialPasteboardChangeCount != nil else { return }
        hasDragged = true
    }

    public func allowsPasteboardRead(changeCount: Int) -> Bool {
        guard let initialPasteboardChangeCount, hasDragged else { return false }
        return changeCount != initialPasteboardChangeCount
    }

    public mutating func mouseUp() {
        initialPasteboardChangeCount = nil
        hasDragged = false
    }
}
