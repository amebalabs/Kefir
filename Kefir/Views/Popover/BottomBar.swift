import SwiftUI
import SwiftKEF

struct BottomBar: View {
    @ObservedObject var appState: AppState
    let appDelegate: AppDelegate
    @Binding var showingAddSpeaker: Bool
    @State private var showingPowerOffConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Speaker info and source selection
            if let speaker = appState.currentSpeaker, appState.isConnected && appState.powerStatus == .powerOn {
                // Main bottom bar
                HStack {
                    Button(action: {
                        showingPowerOffConfirmation = true
                    }) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable(false)
                    .help("Turn off speaker")
                    .confirmationDialog(
                        "Turn off speaker?",
                        isPresented: $showingPowerOffConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Turn Off", role: .destructive) {
                            Task { await appState.togglePower() }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will put \(speaker.name) into standby mode.")
                    }
                    
                    // Speaker selector
                    Menu {
                        ForEach(appState.speakers) { speaker in
                            Button(action: {
                                Task { await appState.selectSpeaker(speaker) }
                            }) {
                                HStack {
                                    Text(speaker.name)
                                    if speaker.isDefault {
                                        Text("(default)")
                                            .font(.caption)
                                    }
                                    if speaker.id == appState.currentSpeaker?.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button("Add Speaker...") {
                            showingAddSpeaker = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "hifispeaker.2.fill")
                                    .font(.system(size: 14))
                                Text(speaker.name)
                                    .font(.system(size: 13))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                    .focusable(false)
                    
                    Menu {
                        ForEach(SourceManager.availableSources, id: \.self) { source in
                            Button(action: {
                                Task { await appState.setSource(source) }
                            }) {
                                HStack {
                                    Image(systemName: appState.source.symbolName(for: source))
                                    Text(appState.source.displayName(for: source))
                                    if source == appState.currentSource {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: appState.source.symbolName(for: appState.currentSource))
                                .font(.system(size: 12))
                            Text(appState.source.displayName(for: appState.currentSource))
                                .font(.system(size: 12))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(.secondary)
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                    .focusable(false)
                    Spacer()
                    
                    // Mini player button
                    Button(action: {
                        appDelegate.toggleMiniPlayer()
                    }) {
                        Image(systemName: "pip.enter")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable(false)
                    .help("Show Mini Player")
                    
                    // Settings button
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable(false)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassCard(cornerRadius: 0)
            } else {
                // Simplified bottom bar when not connected or in standby
                HStack {
                    // Show different indicator based on connection status
                    if appState.isConnected {
                        Button(action: {
                            Task { await appState.togglePower() }
                        }) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .focusable(false)
                        .help("Turn on speaker")
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                    }
                    Menu {
                        ForEach(appState.speakers) { speaker in
                            Button(action: {
                                Task { await appState.selectSpeaker(speaker) }
                            }) {
                                HStack {
                                    Text(speaker.name)
                                    if speaker.isDefault {
                                        Text("(default)")
                                            .font(.caption)
                                    }
                                    if speaker.id == appState.currentSpeaker?.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button("Add Speaker...") {
                            showingAddSpeaker = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "hifispeaker.2.fill")
                                    .font(.system(size: 14))
                                Text("Speakers")
                                    .font(.system(size: 13))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                    .focusable(false)
                    
                    Spacer()
                    
                    // Mini player button
                    Button(action: {
                        appDelegate.toggleMiniPlayer()
                    }) {
                        Image(systemName: "pip.enter")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable(false)
                    .help("Show Mini Player")
                    
                    // Settings button
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable(false)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassCard(cornerRadius: 0)
            }
        }
    }
}
