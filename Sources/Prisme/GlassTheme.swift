import AppKit
import SwiftUI

enum PrismTheme {
    static let accent = Color(red: 0.08, green: 0.46, blue: 1)
    static let accentColor = NSColor(red: 0.08, green: 0.46, blue: 1, alpha: 1)
    static let ice = Color(red: 0.55, green: 0.78, blue: 1)
}

extension View {
    func prismGlass(radius: CGFloat = 20, selected: Bool = false, interactive: Bool = false) -> some View {
        modifier(PrismGlassSurface(radius: radius, selected: selected, interactive: interactive))
    }
}

private struct PrismGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let radius: CGFloat
    let selected: Bool
    let interactive: Bool

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(selected ? PrismTheme.accent.opacity(0.6) : .primary.opacity(0.12)))
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular.tint(selected ? PrismTheme.accent.opacity(0.18) : nil).interactive(interactive), in: shape)
                .overlay(shape.strokeBorder(selected ? PrismTheme.accent.opacity(0.38) : .clear))
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .background(selected ? PrismTheme.accent.opacity(0.15) : .clear, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.3)))
        }
    }
}

struct PrismGlassGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 12) { content }
        } else { content }
    }
}

struct WindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct WindowChrome: NSViewRepresentable {
    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
        }
    }
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context: Context) {}
}

struct PrismBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
            else { WindowBackdrop() }
            GeometryReader { geometry in
                Ellipse().fill(PrismTheme.accent.opacity(scheme == .dark ? 0.16 : 0.09))
                    .frame(width: geometry.size.width * 0.8, height: 350).blur(radius: 90)
                    .offset(x: -150, y: -180)
                Ellipse().fill(Color.indigo.opacity(scheme == .dark ? 0.13 : 0.065))
                    .frame(width: 520, height: 420).blur(radius: 100)
                    .offset(x: geometry.size.width - 340, y: geometry.size.height - 270)
            }.allowsHitTesting(false)
        }.ignoresSafeArea()
    }
}

struct PrismMark: View {
    var size: CGFloat = 42
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [PrismTheme.ice.opacity(0.7), PrismTheme.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "triangle.lefthalf.filled")
                .font(.system(size: size * 0.48, weight: .medium)).foregroundStyle(.white)
        }.frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: size * 0.28).strokeBorder(.white.opacity(0.55), lineWidth: 0.7))
            .shadow(color: PrismTheme.accent.opacity(0.22), radius: 10, y: 4)
    }
}

struct GlassIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                .frame(width: 38, height: 38).contentShape(Circle())
        }.buttonStyle(.plain).prismGlass(radius: 19, interactive: true)
            .help(label).accessibilityLabel(label)
    }
}

struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 14, weight: .medium))
            .frame(minWidth: 30, minHeight: 28).prismGlass(radius: 8)
    }
}
