import Foundation

/// App-wide constants
enum Constants {
    /// Timing constants
    enum Timing {
        /// Default polling interval in seconds
        static let defaultPollingInterval = 10
        
        /// Connection retry delay in seconds
        static let connectionRetryDelay = 5.0
        
        /// HTTP client shutdown delay in seconds
        static let httpClientShutdownDelay = 0.1
        
        /// Animation duration for UI transitions
        static let animationDuration = 0.2
        
        /// HTTP connection timeout in seconds
        static let httpConnectTimeout = 5.0
        
        /// HTTP read timeout in seconds
        static let httpReadTimeout = 10.0

        /// How long to wait for the speaker to report `powerOn` after a
        /// power-on request before giving up, in seconds. The speaker ACKs the
        /// request immediately but takes time to physically wake.
        static let powerOnTimeout = 30.0

        /// How often to poll the speaker's status while waiting for it to wake,
        /// in seconds.
        static let powerOnPollInterval = 2.0
    }
    
    /// Volume constants
    enum Volume {
        static let min = 0
        static let max = 100
        static let step = 5
    }
    
    /// UI constants
    enum UI {
        /// Popover dimensions
        static let popoverWidth = 400
        
        /// Mini player dimensions
        static let miniPlayerWidth = 280
        static let miniPlayerHeight = 74
        static let miniPlayerHeightWithProgress = 82
        
        /// Settings window dimensions
        static let settingsWidth = 600
        static let settingsHeight = 500
        
        /// Connection indicator size
        static let connectionIndicatorSize = 8.0
        
        /// Corner radius values
        static let defaultCornerRadius = 8.0
        static let smallCornerRadius = 3.0
    }
    
    /// Configuration constants
    enum Config {
        static let directoryName = ".config/kefir"
        static let fileName = "config.json"
    }
    
    /// App metadata
    enum App {
        static let name = "Kefir"
        static let version: String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        }()
        static let githubURL = "https://github.com/melonamin/kefir"
        static let issuesURL = "https://github.com/melonamin/kefir/issues"
        static let copyright = "© 2026 Ameba Labs"
    }
    
    /// System symbols
    enum Symbols {
        static let speaker = "hifispeaker.fill"
        static let speakerPair = "hifispeaker.2.fill"
        static let volumeUp = "speaker.wave.3.fill"
        static let volumeDown = "speaker.wave.1.fill"
        static let volumeMute = "speaker.slash.fill"
        static let play = "play.fill"
        static let pause = "pause.fill"
        static let next = "forward.fill"
        static let previous = "backward.fill"
        static let power = "power"
        static let settings = "gearshape.fill"
        static let plus = "plus"
        static let minus = "minus"
        static let pipEnter = "rectangle.bottomthird.inset.filled"
        static let pipExit = "pip.exit"
        static let info = "info.circle"
        static let keyboard = "keyboard"
        static let link = "link"
        static let exclamation = "exclamationmark.bubble"
    }
}
