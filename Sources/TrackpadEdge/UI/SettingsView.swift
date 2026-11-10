import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            if !state.trackpadAvailable {
                Section {
                    Label("Trackpad not available", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                    Text("TrackpadEdge reads the trackpad through macOS's MultitouchSupport framework, which this Mac doesn't offer.")
                        .foregroundStyle(.secondary)
                }
            }
            if !state.isTrusted {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Accessibility permission needed", systemImage: "hand.raised.fill")
                            .font(.headline)
                        Text("While you change the volume or brightness, TrackpadEdge holds back scrolling so the page under the pointer stays still, and it ignores the trackpad right after you type. Both need Accessibility.")
                            .foregroundStyle(.secondary)
                        Button("Grant Permission…") { state.requestPermission() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Trackpad edges") {
                Toggle("Volume and brightness from the trackpad edges", isOn: $settings.enabled)
                Toggle("Swap left and right", isOn: $settings.swapEdges)
                Text(howTo)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                VariantPicker(selection: $settings.hudVariant)
                HStack {
                    Text("\(settings.hudVariant) · \(HUDVariant.name(settings.hudVariant))")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Button("Show on Screen") { HUDController.shared.preview(settings.hudVariant) }
                }
            } header: {
                Text("Indicator")
            } footer: {
                Text("Shown only for the trackpad edges. The volume and brightness keys keep macOS's own indicator.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }))
                if let error = state.launchAtLoginError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
                LabeledContent("Accessibility") {
                    Text(state.isTrusted ? "Granted" : "Not granted")
                        .foregroundStyle(state.isTrusted ? .green : .secondary)
                }
            }

            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
                Text("Free and open source under the MIT license.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 640, height: 760)
    }

    private var howTo: String {
        let right = settings.swapEdges ? "brightness" : "volume"
        let left = settings.swapEdges ? "volume" : "brightness"
        return "Put two fingers on the right edge of the trackpad, slide them inward a little, then move up or down to change the \(right). The left edge does the \(left). Moving up or down without sliding in first is an ordinary scroll and never changes anything."
    }
}

/// All ten indicator designs, drawn live with made-up values. Click one to use it.
struct VariantPicker: View {
    @Binding var selection: Int
    @State private var content = HUDContent()
    @State private var step = 0

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    private let values = [0.62, 0.81, 0.44, 0.7]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(HUDVariant.all, id: \.self) { n in
                card(n)
            }
        }
        .padding(.vertical, 4)
        .task {
            // A slow loop of made-up values, so every design shows how it moves.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.3))
                step += 1
                withAnimation(hudValueAnim) {
                    let value = values[step % values.count]
                    if step % 8 < 4 {
                        content.kind = .volume; content.volume = value
                    } else {
                        content.kind = .brightness; content.brightness = value
                    }
                }
            }
        }
    }

    private func card(_ n: Int) -> some View {
        let selected = n == selection
        let size = HUDLayout.size(n, notchWidth: nil)
        let scale = min(1, 168 / size.width, 104 / size.height)
        return Button { selection = n } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.36), Color(red: 0.36, green: 0.30, blue: 0.48)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    HUDVariantView(variant: n, content: content)
                        .scaleEffect(scale)
                        .frame(width: size.width * scale, height: size.height * scale)
                        .foregroundStyle(.white)
                        .environment(\.colorScheme, .dark)
                        .allowsHitTesting(false)
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 3 : 1)
                }
                HStack(spacing: 4) {
                    Text("\(n) · \(HUDVariant.name(n))").font(.caption.weight(.semibold)).lineLimit(1)
                    if n == HUDVariant.defaultVariant {
                        Text("Default").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                }
                Text(HUDVariant.detail(n)).font(.caption2).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(HUDVariant.name(n)) indicator")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
