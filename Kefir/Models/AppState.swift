import Foundation
import SwiftKEF
import KeyboardShortcuts
import AppKit
import Combine

/// Main application state that coordinates between specialized managers
@MainActor
class AppState: ObservableObject {
    // MARK: - Published Properties
    @Published var speakers: [SpeakerProfile] = []
    @Published var currentSpeaker: SpeakerProfile?
    @Published var isConnected = false
    @Published var powerStatus: KEFSpeakerStatus = .standby
    
    // MARK: - Managers
    let connection: SpeakerConnectionManager
    let volume: VolumeManager
    let playback: PlaybackStateManager
    let source: SourceManager
    let error: ErrorManager
    let config: ConfigurationManager
    
    // MARK: - Published Properties for real-time updates
    @Published var currentVolume: Int = 0
    @Published var isMuted: Bool = false
    @Published var currentSource: KEFSource = .wifi
    @Published var isPlaying: Bool = false
    @Published var currentTrack: SongInfo? = nil
    @Published var trackPosition: Int64 = 0
    @Published var trackDuration: Int = 0
    
    // MARK: - Private Properties
    private var pollingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        self.connection = SpeakerConnectionManager()
        self.volume = VolumeManager()
        self.playback = PlaybackStateManager()
        self.source = SourceManager()
        self.error = ErrorManager()
        self.config = ConfigurationManager()
        
        // Subscribe to manager property changes for real-time updates
        volume.$currentVolume
            .sink { [weak self] newValue in
                self?.currentVolume = newValue
            }
            .store(in: &cancellables)
            
        volume.$isMuted
            .sink { [weak self] newValue in
                self?.isMuted = newValue
            }
            .store(in: &cancellables)
        
        playback.$isPlaying
            .sink { [weak self] newValue in
                self?.isPlaying = newValue
            }
            .store(in: &cancellables)
            
        playback.$currentTrack
            .sink { [weak self] newValue in
                self?.currentTrack = newValue
            }
            .store(in: &cancellables)
            
        playback.$trackPosition
            .sink { [weak self] newValue in
                self?.trackPosition = newValue
            }
            .store(in: &cancellables)
            
        playback.$trackDuration
            .sink { [weak self] newValue in
                self?.trackDuration = newValue
            }
            .store(in: &cancellables)
        
        source.$currentSource
            .sink { [weak self] newValue in
                self?.currentSource = newValue
            }
            .store(in: &cancellables)
        
        Task {
            await loadConfiguration()
            await setupKeyboardShortcuts()
        }
    }
    
    deinit {
        pollingTask?.cancel()
    }
    
    // MARK: - Configuration
    
    func loadConfiguration() async {
        speakers = await config.getSpeakers()
        if let defaultSpeaker = await config.getDefaultSpeaker() {
            await selectSpeaker(defaultSpeaker)
        }
    }
    
    // MARK: - Speaker Selection
    
    func selectSpeaker(_ profile: SpeakerProfile) async {
        currentSpeaker = profile
        
        // Stop current polling
        pollingTask?.cancel()
        
        do {
            // Connect to new speaker
            try await connection.connect(to: profile)
            isConnected = connection.isConnected
            powerStatus = connection.powerStatus
            
            // Update initial status if connected
            if isConnected {
                await updateStatus()
                // Start polling after initial status update completes
                Task {
                    startPolling()
                }
            }
        } catch {
            self.error.showConnectionError(error)
            isConnected = false
        }
    }
    
    // MARK: - Status Updates
    
    func updateStatus() async {
        guard isConnected else { return }
        
        do {
            powerStatus = try await connection.getStatus()
            
            if powerStatus == .powerOn {
                try await volume.updateFromSpeaker(using: connection)
                try await source.updateFromSpeaker(using: connection)
                
                let playing = try await connection.isPlaying()
                playback.isPlaying = playing
                isPlaying = playing
                
                if playing {
                    await playback.updateTrackInfo(from: connection)
                    // Update our local properties from playback manager
                    currentTrack = playback.currentTrack
                    trackPosition = playback.trackPosition
                    trackDuration = playback.trackDuration
                } else {
                    playback.reset()
                    // Also reset our local properties
                    currentTrack = nil
                    trackPosition = 0
                    trackDuration = 0
                }
            }
        } catch {
            // Connection lost
            isConnected = false
            
            // Try to reconnect after delay
            if !Task.isCancelled {
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(Constants.Timing.connectionRetryDelay * 1_000_000_000))
                    if currentSpeaker != nil && !isConnected {
                        await updateStatus()
                    }
                }
            }
        }
    }
    
    // MARK: - Polling
    
    private func startPolling() {
        pollingTask?.cancel()
        
        pollingTask = Task {
            guard let eventStream = await connection.startPolling(
                pollInterval: Constants.Timing.defaultPollingInterval,
                pollSongStatus: true
            ) else { return }
            
            do {
                for try await event in eventStream {
                    if Task.isCancelled { break }
                    
                    // Update connection status
                    if let status = event.speakerStatus {
                        powerStatus = status
                        isConnected = true
                    }
                    
                    // Update managers with event data
                    if powerStatus == .powerOn {
                        await MainActor.run {
                            volume.updateFromEvent(event)
                            source.updateFromEvent(event)
                            playback.updateFromEvent(event)
                        }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    isConnected = false
                }
            }
        }
    }
    
    // MARK: - Control Methods
    
    func setVolume(_ volume: Int) async {
        // Optimistic UI update so the slider thumb stays where the user dragged
        // it instead of snapping back during the HTTP round-trip.
        let clamped = max(Constants.Volume.min, min(Constants.Volume.max, volume))
        let previous = self.currentVolume
        self.currentVolume = clamped
        self.volume.currentVolume = clamped

        do {
            try await self.volume.setVolume(clamped, using: self.connection)
        } catch {
            self.currentVolume = previous
            self.volume.currentVolume = previous
            self.error.showOperationError(error, operation: "Set Volume")
        }
    }

    func adjustVolume(by amount: Int) async {
        await setVolume(self.currentVolume + amount)
    }
    
    func toggleMute() async {
        await error.performOperation(operation: "Toggle Mute") {
            try await self.volume.toggleMute(using: self.connection)
        }
    }
    
    func setSource(_ source: KEFSource) async {
        await error.performOperation(operation: "Set Source") {
            try await self.source.setSource(source, using: self.connection)
        }
    }
    
    func togglePower() async {
        await error.performOperation(operation: "Toggle Power") {
            if powerStatus == .powerOn {
                try await connection.shutdown()
                powerStatus = .standby
            } else {
                try await connection.powerOn()
                powerStatus = .powerOn
                // Re-start polling after power on
                Task { startPolling() }
            }
        }
    }
    
    func togglePlayPause() async {
        await error.performOperation(operation: "Toggle Playback") {
            try await connection.togglePlayPause()
            isPlaying.toggle()
        }
    }
    
    func nextTrack() async {
        await error.performOperation(operation: "Next Track") {
            try await connection.nextTrack()
        }
    }
    
    func previousTrack() async {
        await error.performOperation(operation: "Previous Track") {
            try await connection.previousTrack()
        }
    }
    
    func seekToPosition(_ position: Int64) async {
        // Note: KEF speakers don't support seeking through their API
    }
    
    // MARK: - Speaker Profile Management
    
    func addSpeaker(name: String, host: String) async throws {
        // Validate input
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.showError(
                ValidationError.invalidInput("Speaker name cannot be empty"),
                title: "Invalid Name"
            )
            throw ValidationError.invalidInput("Speaker name cannot be empty")
        }
        
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.showError(
                ValidationError.invalidInput("Host address cannot be empty"),
                title: "Invalid Host"
            )
            throw ValidationError.invalidInput("Host address cannot be empty")
        }
        
        // Validate host format (basic check)
        let hostPattern = #"^(?:\d{1,3}\.){3}\d{1,3}$|^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"#
        guard host.range(of: hostPattern, options: .regularExpression) != nil else {
            error.showError(
                ValidationError.invalidInput("Invalid host address format"),
                title: "Invalid Host"
            )
            throw ValidationError.invalidInput("Invalid host address format")
        }
        
        _ = try await config.addSpeaker(name: name, host: host, setAsDefault: speakers.isEmpty)
        await loadConfiguration()
    }
    
    func removeSpeaker(_ profile: SpeakerProfile) async throws {
        // If removing current speaker, disconnect first
        if currentSpeaker?.id == profile.id {
            await connection.disconnect()
            currentSpeaker = nil
            isConnected = false
        }
        
        try await config.removeSpeaker(id: profile.id)
        await loadConfiguration()
    }
    
    func setDefaultSpeaker(_ profile: SpeakerProfile) async throws {
        try await config.setDefaultSpeaker(id: profile.id)
        await loadConfiguration()
    }
    
    // MARK: - Cleanup
    
    func cleanup() async {
        pollingTask?.cancel()
        await connection.disconnect()
    }
    
    // MARK: - Keyboard Shortcuts
    
    private func setupKeyboardShortcuts() async {
        KeyboardShortcuts.onKeyUp(for: .volumeUp) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                await self.error.performOperation(operation: "Volume Up") {
                    try await self.volume.increaseVolume(using: self.connection)
                }
            }
        }
        
        KeyboardShortcuts.onKeyUp(for: .volumeDown) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                await self.error.performOperation(operation: "Volume Down") {
                    try await self.volume.decreaseVolume(using: self.connection)
                }
            }
        }
        
        KeyboardShortcuts.onKeyUp(for: .toggleMute) { [weak self] in
            Task { @MainActor in
                await self?.toggleMute()
            }
        }
        
        KeyboardShortcuts.onKeyUp(for: .playPause) { [weak self] in
            Task { @MainActor in
                await self?.togglePlayPause()
            }
        }
        
        KeyboardShortcuts.onKeyUp(for: .nextTrack) { [weak self] in
            Task { @MainActor in
                await self?.nextTrack()
            }
        }
        
        KeyboardShortcuts.onKeyUp(for: .previousTrack) { [weak self] in
            Task { @MainActor in
                await self?.previousTrack()
            }
        }
    }
}

// MARK: - Validation Errors

enum ValidationError: LocalizedError {
    case invalidInput(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return message
        }
    }
}