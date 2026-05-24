import SwiftUI

struct VolumeCard: View {
    @Binding var volume: Int
    @Binding var isMuted: Bool
    @Binding var isDragging: Bool
    let onVolumeChange: (Int) -> Void
    let onMuteToggle: () -> Void
    let onAdjust: (Int) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Title
            HStack {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                Text("Volume")
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                Text("\(volume)%")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(isDragging ? .accentColor : .primary)
            }
            
            // Slider
            ModernSlider(
                value: Binding(
                    get: { Double(volume) },
                    set: { onVolumeChange(Int($0)) }
                ),
                isDragging: $isDragging
            )
            
            // Buttons
            GlassGroup(spacing: 40) {
                HStack(spacing: 40) {
                    ControlButton(
                        icon: "minus",
                        action: { onAdjust(-5) }
                    )

                    ControlButton(
                        icon: isMuted ? "speaker.slash.fill" : "speaker.fill",
                        isLarge: true,
                        isAccent: isMuted,
                        action: onMuteToggle
                    )

                    ControlButton(
                        icon: "plus",
                        action: { onAdjust(5) }
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .focusable(false)
        }
        .padding(20)
        .glassCard(cornerRadius: 12)
    }
}
