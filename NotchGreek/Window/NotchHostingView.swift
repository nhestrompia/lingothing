import AppKit
import SwiftUI

final class NotchHostingView: NSHostingView<NotchContentView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
