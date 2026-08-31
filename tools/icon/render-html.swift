
import AppKit
import WebKit

let arguments = CommandLine.arguments
func parseSize(_ text: String) -> (CGFloat, CGFloat)? {
    let parts = text.lowercased().split(separator: "x").compactMap { Double($0) }
    if parts.count == 1 { return (CGFloat(parts[0]), CGFloat(parts[0])) }
    if parts.count == 2 { return (CGFloat(parts[0]), CGFloat(parts[1])) }
    return nil
}

guard arguments.count >= 4, let (width, height) = parseSize(arguments[3]) else {
    FileHandle.standardError.write(Data("""
        usage: render-html <input.html> <output.png> <size|WxH> [fragment] [layout|WxH]

          size    the PNG's pixel dimensions
          layout  the size the page is authored at, if it differs from `size`

        A page laid out at 1024 must be *rendered* at 1024 and then scaled, not
        laid out at 64: otherwise its content sits off-canvas and the PNG comes
        back almost empty.
        """.utf8))
    exit(2)
}

let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let (layoutWidth, layoutHeight) = arguments.count > 5
    ? (parseSize(arguments[5]) ?? (width, height))
    : (width, height)

final class Renderer: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let output: URL
    let width: CGFloat
    let height: CGFloat

    let layoutWidth: CGFloat
    let layoutHeight: CGFloat

    init(output: URL, width: CGFloat, height: CGFloat,
         layoutWidth: CGFloat, layoutHeight: CGFloat) {
        self.output = output
        self.width = width
        self.height = height
        self.layoutWidth = layoutWidth
        self.layoutHeight = layoutHeight
        let configuration = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: layoutWidth, height: layoutHeight),
                            configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        super.init()
        webView.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.snapshot() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error.localizedDescription)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        fail(error.localizedDescription)
    }

    private func snapshot() {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = NSRect(x: 0, y: 0, width: layoutWidth, height: layoutHeight)
        configuration.snapshotWidth = NSNumber(value: Double(layoutWidth))
        configuration.afterScreenUpdates = true

        webView.takeSnapshot(with: configuration) { image, error in
            guard let image else { return self.fail(error?.localizedDescription ?? "no image") }

            let wide = Int(self.width), high = Int(self.height)
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: wide, pixelsHigh: high,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ) else { return self.fail("could not allocate bitmap") }
            rep.size = NSSize(width: wide, height: high)

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in: NSRect(x: 0, y: 0, width: wide, height: high),
                       from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()

            guard let png = rep.representation(using: .png, properties: [:]) else {
                return self.fail("could not encode PNG")
            }
            do { try png.write(to: self.output) } catch { return self.fail("\(error)") }
            exit(0)
        }
    }

    private func fail(_ message: String) {
        FileHandle.standardError.write(Data("render-html: \(message)\n".utf8))
        exit(1)
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)

let renderer = Renderer(output: output, width: width, height: height,
                        layoutWidth: layoutWidth, layoutHeight: layoutHeight)
let fragment = arguments.count > 4 ? "#" + arguments[4] : ""
let target = URL(string: input.absoluteString + fragment) ?? input
renderer.webView.load(URLRequest(url: target))

DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
    FileHandle.standardError.write(Data("render-html: timed out\n".utf8))
    exit(1)
}

application.run()
