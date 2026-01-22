import SwiftUI

struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ToolbarButtonLabel(configuration: configuration)
    }
}

private struct ToolbarButtonLabel: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false
    
    var body: some View {
        configuration.label
            .foregroundColor(configuration.isPressed ? .secondary : .primary)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct ActionButtonStyle: ButtonStyle {
    var isProminent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        ActionButtonLabel(configuration: configuration, isProminent: isProminent)
    }
}

private struct ActionButtonLabel: View {
    let configuration: ButtonStyle.Configuration
    let isProminent: Bool
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? (isProminent ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.15)) : (isProminent ? Color.accentColor : Color.secondary.opacity(0.1)))
            )
            .foregroundColor(isProminent ? .white : .primary)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

struct StatusPill: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.15))
            )
            .fixedSize()
    }
}

extension View {
    func toolbarButtonStyle() -> some View {
        self.buttonStyle(ToolbarButtonStyle())
    }
    
    func actionButtonStyle(isProminent: Bool = false) -> some View {
        self.buttonStyle(ActionButtonStyle(isProminent: isProminent))
    }
}
