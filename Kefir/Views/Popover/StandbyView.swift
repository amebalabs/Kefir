import SwiftUI

struct StandbyView: View {
    @ObservedObject var appState: AppState
    let speaker: SpeakerProfile
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon — animates while powering on
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 80, height: 80)

                if appState.isPoweringOn {
                    ProgressView()
                        .controlSize(.large)
                        .progressViewStyle(.circular)
                        .tint(.orange)
                } else {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: appState.isPoweringOn)

            // Text
            VStack(spacing: 8) {
                Text(speaker.name)
                    .font(.system(size: 20, weight: .semibold))

                Text(appState.isPoweringOn ? "Powering On…" : "In Standby")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)

                Text(appState.isPoweringOn
                     ? "This can take 15–30 seconds while the speaker wakes up"
                     : "Speaker is connected but powered down")
                    .font(.system(size: 13))
                    .foregroundColor(Color.secondary.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            // Power on button
            Button(action: {
                Task { await appState.togglePower() }
            }) {
                Label(appState.isPoweringOn ? "Powering On…" : "Power On",
                      systemImage: "power")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(appState.isPoweringOn
                                ? Color.accentColor.opacity(0.5)
                                : Color.accentColor)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .focusable(false)
            .disabled(appState.isPoweringOn)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    let appState = AppState()
    let speaker = SpeakerProfile(
        name: "Living Room",
        host: "192.168.1.100",
        isDefault: true
    )
    
    return StandbyView(appState: appState, speaker: speaker)
        .frame(width: 360, height: 420)
}