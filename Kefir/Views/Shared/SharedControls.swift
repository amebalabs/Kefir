import SwiftUI

// MARK: - Modern Slider

struct ModernSlider: View {
    @Binding var value: Double
    @Binding var isDragging: Bool

    /// Local "in-flight" value while the user is dragging. We avoid writing to
    /// the binding on every drag delta because the binding's setter triggers an
    /// async HTTP request to the speaker — doing that 60+ times per second
    /// (a) spams the speaker and (b) makes the thumb appear stuck because the
    /// async update hasn't propagated back through `value` yet.
    @State private var dragValue: Double?

    private var displayValue: Double {
        dragValue ?? value
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color(NSColor.separatorColor).opacity(0.3))
                    .frame(height: 6)

                // Fill
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * CGFloat(displayValue / 100), height: 6)

                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                    .overlay(
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                    )
                    .offset(x: geometry.size.width * CGFloat(displayValue / 100) - 11)
                    .scaleEffect(isDragging ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        let newValue = min(100, max(0, Double(drag.location.x / geometry.size.width) * 100))
                        // Only update local state during drag — no HTTP call yet.
                        dragValue = newValue
                    }
                    .onEnded { _ in
                        if let final = dragValue {
                            // Commit the final value to the speaker once. We
                            // intentionally KEEP dragValue set here so the
                            // thumb doesn't snap back to the (stale) binding
                            // value while the async HTTP round-trip catches up.
                            value = final
                        }
                        isDragging = false
                        // Safety net: if the binding never catches up (e.g.,
                        // HTTP failed or speaker capped the value differently),
                        // surrender to the binding after a short delay.
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 800_000_000)
                            dragValue = nil
                        }
                    }
            )
            .onChange(of: value) { _, newValue in
                if let dv = dragValue, abs(dv - newValue) < 1.0 {
                    dragValue = nil
                }
            }
        }
        .frame(height: 22)
        .focusable(false)
    }
}

// MARK: - Control Button

struct ControlButton: View {
    let icon: String
    var isLarge: Bool = false
    var isAccent: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isAccent ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                    .overlay(
                        Circle()
                            .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
                    )
                    .frame(width: isLarge ? 50 : 40, height: isLarge ? 50 : 40)
                
                Image(systemName: icon)
                    .font(.system(size: isLarge ? 22 : 16, weight: .medium))
                    .foregroundColor(isAccent ? .white : .primary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .focusable(false)
    }
}

// MARK: - Play Button

struct PlayButton: View {
    enum Size { case small, large }
    
    let icon: String
    let size: Size
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(size == .large ? Color.accentColor : Color.clear)
                    .overlay(
                        Circle()
                            .stroke(size == .large ? Color.clear : Color(NSColor.separatorColor), lineWidth: 2)
                    )
                    .frame(width: size == .large ? 56 : 40, height: size == .large ? 56 : 40)
                
                Image(systemName: icon)
                    .font(.system(size: size == .large ? 22 : 16, weight: .medium))
                    .foregroundColor(size == .large ? .white : .primary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .focusable(false)
    }
}

// MARK: - Sound Wave Animation

struct SoundWaveAnimation: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4) { index in
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: animating ? 24 : 12)
                    .animation(
                        Animation.easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - Album Art View

struct AlbumArtView: View {
    let coverURL: String?
    @State private var albumImage: NSImage?
    @State private var isLoading = false
    @State private var currentURL: String?
    
    var body: some View {
        ZStack {
            if let image = albumImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(
                        colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 28))
                        .foregroundColor(.accentColor)
                }
            }
        }
        .task(id: coverURL) {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        // Reset state if URL changes or is nil
        if coverURL != currentURL {
            albumImage = nil
            currentURL = coverURL
        }
        
        guard let urlString = coverURL,
              let url = URL(string: urlString) else {
            albumImage = nil
            isLoading = false
            return
        }
        
        // Don't reload if we already have the image for this URL
        if currentURL == urlString && albumImage != nil {
            return
        }
        
        isLoading = true
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            if let image = NSImage(data: data) {
                albumImage = image
                isLoading = false
            } else {
                albumImage = nil
                isLoading = false
            }
        } catch {
            albumImage = nil
            isLoading = false
        }
    }
}
