import SwiftUI
import SwiftKEF

struct PopoverView: View {
    @ObservedObject var appState: AppState
    let appDelegate: AppDelegate
    @State private var showingAddSpeaker = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            if let speaker = appState.currentSpeaker {
                if appState.isConnected {
                    if appState.powerStatus == .powerOn {
                        ConnectedView(appState: appState, speaker: speaker)
                    } else {
                        StandbyView(appState: appState, speaker: speaker)
                    }
                } else {
                    DisconnectedView(appState: appState, speaker: speaker)
                }
            } else {
                EmptyStateView(showingAddSpeaker: $showingAddSpeaker)
            }
            
            BottomBar(
                appState: appState,
                appDelegate: appDelegate,
                showingAddSpeaker: $showingAddSpeaker
            )
        }
        .frame(width: 400)
        .background(rootBackground)
        .sheet(isPresented: $showingAddSpeaker) {
            AddSpeakerView(appState: appState)
        }
    }

    /// Clear on macOS 26 so the Liquid Glass cards refract the popover's
    /// native backdrop; opaque window background on earlier systems.
    @ViewBuilder
    private var rootBackground: some View {
        if #available(macOS 26.0, *) {
            Color.clear
        } else {
            Color(NSColor.windowBackgroundColor)
        }
    }
}
