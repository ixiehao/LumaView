import SwiftUI

/// The application uses the MIT-licensed Tabler Icons Outline set for every functional
/// control. Keeping the asset mapping here guarantees a single 24 pt / 2 pt outline
/// language across the toolbar, canvas, and contextual actions.
enum LumaIconKind: Equatable {
    case previous, next, zoomOut, zoomIn, fit, rotateLeft, rotateRight, more, information
    case folder, image, imagePlus, reveal, print

    var tablerAssetName: String {
        switch self {
        case .previous: return "TablerChevronLeft"
        case .next: return "TablerChevronRight"
        case .zoomOut: return "TablerZoomOut"
        case .zoomIn: return "TablerZoomIn"
        case .fit: return "TablerMaximize"
        case .rotateLeft: return "TablerRotateCounterclockwise"
        case .rotateRight: return "TablerRotateClockwise"
        case .more: return "TablerDots"
        case .information: return "TablerInfoCircle"
        case .folder: return "TablerFolder"
        case .image: return "TablerPhoto"
        case .imagePlus: return "TablerPhotoPlus"
        case .reveal: return "TablerFolderOpen"
        case .print: return "TablerPrinter"
        }
    }
}

struct LumaIcon: View {
    let kind: LumaIconKind
    var size: CGFloat = 16
    var color: Color = .primary

    var body: some View {
        Image(kind.tablerAssetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct LumaIconButton: View {
    let kind: LumaIconKind
    let label: String
    var isProminent = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            LumaIcon(kind: kind, size: 17, color: foregroundColor)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.34)
        .accessibilityLabel(label)
        .onHover { isHovering = isEnabled && $0 }
    }

    private var foregroundColor: Color {
        if isProminent || isHovering { return .accentColor }
        return .primary
    }
}
