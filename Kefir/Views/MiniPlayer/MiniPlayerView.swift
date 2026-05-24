import SwiftUI
import SwiftKEF

struct MiniPlayerView: View {
    @ObservedObject var appState: AppState
    @State private var isDraggingVolume = false
    @State private var isHovering = false
    let onClose: () -> Void
    
    private var shouldShowProgress: Bool {
        appState.isConnected && 
        appState.powerStatus == .powerOn && 
        (appState.currentSource == .wifi || appState.currentSource == .bluetooth) && 
        appState.trackDuration > 0
    }
    
    var body: some View {
        ZStack {
            // Background with visual effect
            MiniPlayerBackground()
            
            // Content
            if appState.isConnected && appState.powerStatus == .powerOn {
                VStack(spacing: 0) {
                    ZStack {
                        // Default view - Track info
                        HStack(spacing: 12) {
                            // Album art or app icon
                            ZStack {
                            if let coverURL = appState.currentTrack?.coverURL {
                                AlbumArtView(coverURL: coverURL)
                                    .frame(width: 50, height: 50)
                            } else {
                                Image(nsImage: NSApp.applicationIconImage!)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 50, height: 50)
                                    .cornerRadius(8)
                            }
                        }
                        
                        // Track info
                        VStack(alignment: .leading, spacing: 4) {
                            if let track = appState.currentTrack, let title = track.title {
                                Text(title)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                if let artist = track.artist {
                                    Text(artist)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            } else {
                                Text(appState.currentSpeaker?.name ?? "KEF Speaker")
                                    .font(.system(size: 13, weight: .medium))
                                Text(appState.source.displayName(for: appState.currentSource))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .opacity(isHovering ? 0 : 1)
                        
                        // Hover view - Controls
                        if isHovering {
                        HStack(spacing: 20) {
                            // Playback controls
                            if appState.currentSource == .wifi || appState.currentSource == .bluetooth {
                                HStack(spacing: 16) {
                                    Button(action: {
                                        Task { await appState.previousTrack() }
                                    }) {
                                        Image(systemName: "backward.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.primary)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .focusable(false)
                                    
                                    Button(action: {
                                        Task { await appState.togglePlayPause() }
                                    }) {
                                        Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                                            .font(.system(size: 18))
                                            .foregroundColor(.primary)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .focusable(false)
                                    
                                    Button(action: {
                                        Task { await appState.nextTrack() }
                                    }) {
                                        Image(systemName: "forward.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.primary)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .focusable(false)
                                }
                                
                                Divider()
                                    .frame(height: 30)
                            }
                            
                            // Volume controls
                            MiniVolumeControl(
                                volume: Binding(
                                    get: { appState.currentVolume },
                                    set: { newValue in
                                        Task { await appState.setVolume(newValue) }
                                    }
                                ),
                                isMuted: Binding(
                                    get: { appState.isMuted },
                                    set: { _ in }
                                ),
                                isDragging: $isDraggingVolume,
                                onVolumeChange: { newVolume in
                                    Task { await appState.setVolume(newVolume) }
                                },
                                onMuteToggle: {
                                    Task { await appState.toggleMute() }
                                }
                            )
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    
                    // Progress indicator - visible in both modes
                    if (appState.currentSource == .wifi || appState.currentSource == .bluetooth) && appState.trackDuration > 0 {
                        MiniProgressBar(
                            position: appState.trackPosition,
                            duration: appState.trackDuration,
                            isPlaying: appState.isPlaying
                        )
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                }
            } else {
                // Disconnected or standby state
                HStack {
                    Image(systemName: "hifispeaker.slash")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading) {
                        Text(appState.currentSpeaker?.name ?? "No Speaker")
                            .font(.system(size: 13, weight: .medium))
                        Text(appState.isConnected ? "Standby" : "Disconnected")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if appState.isConnected {
                        Button(action: {
                            Task { await appState.togglePower() }
                        }) {
                            Image(systemName: "power")
                                .font(.system(size: 14))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .focusable(false)
                    }
                }
                .padding(12)
            }
            
            // Close button (visible on hover)
            if isHovering {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .focusable(false)
                    }
                    Spacer()
                }
                .padding(6)
                .transition(.opacity)
            }
        }
        .frame(width: CGFloat(Constants.UI.miniPlayerWidth), 
               height: CGFloat(shouldShowProgress ? Constants.UI.miniPlayerHeightWithProgress : Constants.UI.miniPlayerHeight))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

// Mini volume control for the floating player
struct MiniVolumeControl: View {
    @Binding var volume: Int
    @Binding var isMuted: Bool
    @Binding var isDragging: Bool
    let onVolumeChange: (Int) -> Void
    let onMuteToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            // Mute button
            Button(action: onMuteToggle) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14))
                    .foregroundColor(isMuted ? .accentColor : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .focusable(false)
            
            // Volume up/down buttons
            Button(action: {
                let newVolume = max(0, volume - 5)
                onVolumeChange(newVolume)
            }) {
                Image(systemName: "minus.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .focusable(false)
            
            Text("\(volume)%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40)
            
            Button(action: {
                let newVolume = min(100, volume + 5)
                onVolumeChange(newVolume)
            }) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .focusable(false)
        }
    }
}

// Visual effect background
// Mini progress bar for the floating player
struct MiniProgressBar: View {
    let position: Int64
    let duration: Int
    let isPlaying: Bool
    
    @State private var displayPosition: Int64 = 0
    @State private var lastUpdateTime = Date()
    @State private var timer: Timer?
    
    private var progress: Double {
        guard duration > 0 else { return 0 }
        return Double(displayPosition) / Double(duration)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color(NSColor.separatorColor).opacity(0.2))
                    .frame(height: 3)
                
                // Progress fill
                Capsule()
                    .fill(Color.accentColor.opacity(0.8))
                    .frame(width: geometry.size.width * CGFloat(progress), height: 3)
                    .animation(.linear(duration: 0.1), value: progress)
            }
        }
        .frame(height: 3)
        .onAppear {
            displayPosition = position
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: position) { oldValue, newValue in
            // Update display position when we get a new position from the speaker
            displayPosition = newValue
            lastUpdateTime = Date()
        }
        .onChange(of: isPlaying) { oldValue, newValue in
            // Reset timer when play state changes
            if newValue {
                lastUpdateTime = Date()
                startTimer()
            }
        }
    }
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // Only update if playing and not at the end
            if isPlaying && displayPosition < Int64(duration) {
                // Calculate elapsed time since last update
                let elapsed = Date().timeIntervalSince(lastUpdateTime)
                // Add elapsed time in milliseconds
                displayPosition = min(displayPosition + Int64(elapsed * 1000), Int64(duration))
                lastUpdateTime = Date()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

/// Floating mini-player backdrop. Liquid Glass on macOS 26; the prior
/// `NSVisualEffectView` HUD material on earlier systems.
struct MiniPlayerBackground: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
        } else {
            VisualEffectBackground()
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

#Preview {
    MiniPlayerView(appState: {
        let state = AppState()
        state.isConnected = true
        state.powerStatus = .powerOn
        state.currentVolume = 50
        state.currentSource = .wifi
        state.isPlaying = true
        state.currentTrack = SongInfo(
            title: "Bohemian Rhapsody",
            artist: "Queen",
            album: "A Night at the Opera"
        )
        state.trackPosition = 90000 // 1:30
        state.trackDuration = 355000 // 5:55
        return state
    }(), onClose: {})
    .frame(width: 280, height: 82)
}