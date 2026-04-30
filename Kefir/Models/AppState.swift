import Foundation
import SwiftKEF
import KeyboardShortcuts
import AppKit
import Combine
import os

private let log = Logger(subsystem: "co.ameba.Kefir", category: "AppState")

/// Main application state that coordinates between specialized managers
@MainActor
class AppState: ObservableObject {
    // MARK: - Published Properties
    @Published var speakers: [SpeakerProfile] = []
    @Published var currentSpeaker: SpeakerProfile?
    @Published var isConnected = false
    @Published var powerStatus: KEFSpeakerStatus = .standby
    /// True while a power-on request is in flight. KEF speakers can take
    /// 15–30s to physically wake from standby, so we surface this in the UI.
    @Published var isPoweringOn = false
    
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
    private var reconnectTask: Task<Void, Never>?
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
        reconnectTask?.cancel()
    }
    
    // MARK: - Configuration
    
    func loadConfiguration() async {
        speakers = await config.getSpeakers()
        if let defaultSpeaker = await config.getDefaultSpeaker() {
            await selectSpeaker(defaultSpeaker)
        }
    }
    
    // MARK: - Speaker Selection
    
    /// - Parameter silent: When true, swallow errors and don't surface a dialog.
    ///   Used by the background reconnect loop so transient blips don't spam alerts.
    func selectSpeaker(_ profile: SpeakerProfile, silent: Bool = false) async {
        log.info("selectSpeaker name=\(profile.name, privacy: .public) host=\(profile.host, privacy: .public) silent=\(silent)")
        currentSpeaker = profile

        // Stop current polling and any pending reconnect
        pollingTask?.cancel()
        reconnectTask?.cancel()

        do {
            try await connection.connect(to: profile)
            isConnected = connection.isConnected
            powerStatus = connection.powerStatus
            log.info("Connected. powerStatus=\(self.powerStatus.rawValue, privacy: .public)")

            if isConnected {
                await updateStatus()
                Task { startPolling() }
            }
        } catch {
            log.error("connect() failed: \(error.localizedDescription, privacy: .public)")
            isConnected = false
            if !silent {
                self.error.showConnectionError(error)
            }
            scheduleReconnect()
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
            log.warning("updateStatus failed: \(error.localizedDescription, privacy: .public). Verifying connection…")
            await handleTransientFailure()
        }
    }

    // MARK: - Connection Health

    /// Probes the speaker with a single getStatus() to decide whether a polling
    /// or status-update error reflects a real connection loss or just a
    /// transient blip. Restarts polling on success, drops to disconnected on
    /// failure.
    private func handleTransientFailure() async {
        guard currentSpeaker != nil else { return }
        do {
            let status = try await connection.getStatus()
            log.info("Health check passed (status=\(status.rawValue, privacy: .public)). Keeping connection alive.")
            powerStatus = status
            isConnected = true
            // IMPORTANT: do NOT call updateStatus() here. updateStatus() is
            // what got us into this catch path; recursing back into it can
            // produce an unbounded loop if any sub-call (getVolume,
            // getSource, getSongInformation, …) keeps failing.
            // Polling will resync the rest of the state on its next tick.
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if isConnected { startPolling() }
            }
        } catch {
            log.error("Health check failed: \(error.localizedDescription, privacy: .public). Marking disconnected and scheduling reconnect.")
            isConnected = false
            scheduleReconnect()
        }
    }

    // MARK: - Reconnect

    /// Background loop that retries `selectSpeaker` with exponential backoff
    /// (5s → 10s → 20s → 30s, capped) until the connection comes back or the
    /// user picks a different speaker.
    private func scheduleReconnect() {
        guard reconnectTask == nil || reconnectTask?.isCancelled == true else {
            // A reconnect is already running.
            return
        }
        reconnectTask = Task { [weak self] in
            guard let self = self else { return }
            var delay = Constants.Timing.connectionRetryDelay // 5s
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled { break }

                guard let speaker = self.currentSpeaker, !self.isConnected else { break }

                await self.selectSpeaker(speaker, silent: true)
                if self.isConnected { break }

                delay = min(delay * 2, 30)
            }
            self.reconnectTask = nil
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

                    // Detect a transition into powerOn so we can fetch the
                    // current source/volume/etc. The KEF polling queue does
                    // not always deliver an initial value for these paths.
                    let previousStatus = powerStatus
                    if let status = event.speakerStatus {
                        powerStatus = status
                        isConnected = true
                    }
                    let justPoweredOn = previousStatus != .powerOn && powerStatus == .powerOn

                    if powerStatus == .powerOn {
                        await MainActor.run {
                            volume.updateFromEvent(event)
                            source.updateFromEvent(event)
                            playback.updateFromEvent(event)
                        }
                        if justPoweredOn {
                            log.info("Speaker just powered on; refreshing source/volume.")
                            await updateStatus()
                        }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    log.warning("Polling stream ended with error: \(error.localizedDescription, privacy: .public)")
                    await handleTransientFailure()
                }
            }
        }
    }
    
    // MARK: - Control Methods
    
    func setVolume(_ volume: Int) async {
        await error.performOperation(operation: "Set Volume") {
            try await self.volume.setVolume(volume, using: self.connection)
        }
    }
    
    func adjustVolume(by amount: Int) async {
        await error.performOperation(operation: "Adjust Volume") {
            try await self.volume.adjustVolume(by: amount, using: self.connection)
        }
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
        if powerStatus == .powerOn {
            // Powering off is fast; just await it.
            await error.performOperation(operation: "Toggle Power") {
                try await self.connection.shutdown()
                self.powerStatus = .standby
            }
        } else {
            // Powering on is SLOW (the speaker hardware can take 15–30s to wake
            // from standby and only ACKs the HTTP request once it is ready).
            // Flip `isPoweringOn` immediately so the UI shows a spinner and
            // the user knows the command was registered.
            isPoweringOn = true
            await error.performOperation(operation: "Power On") {
                try await self.connection.powerOn()
                // Speaker is now up. Refresh status and resume polling.
                self.powerStatus = .powerOn
                await self.updateStatus()
                Task { self.startPolling() }
            }
            isPoweringOn = false
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
        reconnectTask?.cancel()
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