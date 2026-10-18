import AppKit
import SwiftUI

struct SmartProfileIcon: View {
    let path: String?
    let size: CGFloat

    var body: some View {
        if let path, FileManager.default.fileExists(atPath: path) {
            Image(nsImage: AppIconCache.shared.icon(forFile: path))
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            BrandIconTile(iconName: "app", color: XmacTheme.blue, size: size)
        }
    }
}
