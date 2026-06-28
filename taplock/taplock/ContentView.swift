import SwiftUI
import FamilyControls

struct ContentView: View {
    @State private var isLocked = false
    @State private var statusMessage = "Set up Screen Time access first."
    @State private var isRequestingPermission = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("TapLock")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(isLocked ? "Locked" : "Unlocked")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isLocked ? .red : .green)
                }

                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                VStack(spacing: 14) {
                    Button {
                        requestScreenTimePermission()
                    } label: {
                        Label(isRequestingPermission ? "Requesting..." : "Request Screen Time Permission", systemImage: "hourglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TapLockButtonStyle())

                    Button {
                        statusMessage = "Next step: open Apple’s app picker here."
                    } label: {
                        Label("Choose Apps to Block", systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TapLockButtonStyle())

                    Button {
                        statusMessage = "Next step: connect this to Core NFC scanning."
                    } label: {
                        Label("Scan NFC Card", systemImage: "wave.3.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TapLockPrimaryButtonStyle())
                }
                .padding(.horizontal, 22)

                Spacer()

                Text("Open app → tap card → lock/unlock apps")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.bottom, 12)
            }
        }
    }
    private func requestScreenTimePermission() {
        isRequestingPermission = true
        statusMessage = "Opening Screen Time permission request..."

        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)

                await MainActor.run {
                    isRequestingPermission = false
                    statusMessage = "Screen Time permission granted. Next: choose apps to block."
                }
            } catch {
                await MainActor.run {
                    isRequestingPermission = false
                    statusMessage = "Screen Time permission failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

private struct TapLockButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(.white.opacity(configuration.isPressed ? 0.16 : 0.10))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TapLockPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.black)
            .padding(.vertical, 18)
            .padding(.horizontal, 18)
            .background(.white.opacity(configuration.isPressed ? 0.75 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    ContentView()
}
