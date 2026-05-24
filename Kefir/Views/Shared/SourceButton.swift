import SwiftUI
import SwiftKEF

struct SourceButton: View {
    @ObservedObject var appState: AppState
    let source: KEFSource
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: sourceIcon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text(appState.source.displayName(for: source))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .glassCard(cornerRadius: 10, tint: isSelected ? .accentColor : nil)
        }
        .buttonStyle(PlainButtonStyle())
        .focusable(false)
    }
    
    private var sourceIcon: String {
        appState.source.symbolName(for: source)
    }
}

#Preview {
    let appState = AppState()
    return HStack(spacing: 10) {
        SourceButton(appState: appState, source: .wifi, isSelected: true, action: {})
        SourceButton(appState: appState, source: .bluetooth, isSelected: false, action: {})
        SourceButton(appState: appState, source: .tv, isSelected: false, action: {})
    }
    .padding()
}