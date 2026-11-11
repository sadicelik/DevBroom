import AppKit

/// The menu bar broom. A template image (follows the menu bar's colour) normally; orange when space is low.
enum BroomIcon {
    static func image(warning: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let color: NSColor = warning ? .systemOrange : .black
            color.setStroke()
            color.setFill()
            // Handle: from top right down to the bristle band.
            let handle = NSBezierPath()
            handle.move(to: NSPoint(x: 16.0, y: 1.2))
            handle.line(to: NSPoint(x: 10.6, y: 7.2))
            handle.lineWidth = 1.8
            handle.lineCapStyle = .round
            handle.stroke()
            // Band and bristles, tilted with the handle.
            let t = NSAffineTransform()
            t.translateX(by: 9.6, yBy: 8.6)
            t.rotate(byDegrees: 42)
            let head = NSBezierPath()
            head.appendRoundedRect(NSRect(x: -3.2, y: -1.6, width: 6.4, height: 2.2), xRadius: 0.8, yRadius: 0.8)
            head.move(to: NSPoint(x: -3.0, y: 1.0))
            head.line(to: NSPoint(x: 3.0, y: 1.0))
            head.line(to: NSPoint(x: 4.2, y: 6.6))
            head.line(to: NSPoint(x: -4.2, y: 6.6))
            head.close()
            head.transform(using: t as AffineTransform)
            head.fill()
            // Bristle gaps.
            NSColor.clear.setStroke()
            let gaps = NSBezierPath()
            for x in [-1.6, 0.0, 1.6] {
                gaps.move(to: NSPoint(x: x, y: 3.2))
                gaps.line(to: NSPoint(x: x * 1.3, y: 6.8))
            }
            gaps.transform(using: t as AffineTransform)
            gaps.lineWidth = 0.7
            NSGraphicsContext.current?.compositingOperation = .clear
            gaps.stroke()
            return true
        }
        img.isTemplate = !warning
        img.accessibilityDescription = warning ? "DevBroom, disk space low" : "DevBroom"
        return img
    }
}
