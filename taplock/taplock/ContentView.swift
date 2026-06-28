import SwiftUI
import FamilyControls
import ManagedSettings

struct ContentView: View {
    @ObservedObject private var authorizationCenter = AuthorizationCenter.shared
    @StateObject private var nfcScanner = NFCScanner()

    @State private var activitySelection = FamilyActivitySelection()
    @State private var isShowingActivityPicker = false
    @State private var statusMessage = "Set up Screen Time access first."
    @State private var isRequestingPermission = false
    @AppStorage("taplock.isLocked") private var isLocked = false
    @AppStorage("taplock.pairedNFCCardID") private var pairedCardID = ""

    private let savedSelectionKey = "taplock.familyActivitySelection"
    private let managedSettingsStore = ManagedSettingsStore()

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

                    VStack(spacing: 8) {
                        Button {
                            openAppPicker()
                        } label: {
                            Label(selectedItemCount == 0 ? "Choose Apps to Block" : "Edit Apps to Block", systemImage: "square.grid.2x2")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TapLockButtonStyle())
                        .disabled(isLocked)
                        .opacity(isLocked ? 0.45 : 1.0)

                        Text(selectionSummary)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(isLocked ? 0.38 : 0.52))
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        scanNFCCard()
                    } label: {
                        Label(nfcScanner.isScanning ? "Scanning..." : "Scan NFC Card", systemImage: "wave.3.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TapLockPrimaryButtonStyle())
                    .disabled(nfcScanner.isScanning)
                }
                .padding(.horizontal, 22)

                Spacer()

                Text("Open app → tap card → lock/unlock apps")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.bottom, 12)
            }
        }
        .familyActivityPicker(
            headerText: "Choose the apps, categories, or websites TapLock should block.",
            footerText: "Tap Done when your block list looks right.",
            isPresented: $isShowingActivityPicker,
            selection: $activitySelection
        )
        .onAppear(perform: loadSavedSelection)
        .onChange(of: activitySelection) { _, newSelection in
            saveSelection(newSelection)
            updateStatusForSelection(newSelection)
        }
    }

    private var selectedItemCount: Int {
        activitySelection.applicationTokens.count
            + activitySelection.categoryTokens.count
            + activitySelection.webDomainTokens.count
    }

    private var isScreenTimeApproved: Bool {
        switch authorizationCenter.authorizationStatus {
        case .approved, .approvedWithDataAccess:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    private var selectionSummary: String {
        let details = selectionDetails(for: activitySelection)
        if isLocked {
            return details.isEmpty ? "Unlock with your NFC card to choose apps." : "\(details) locked. Unlock with your NFC card to edit."
        }

        return details.isEmpty ? "No apps selected yet." : "\(details) selected."
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

    private func openAppPicker() {
        guard !isLocked else {
            statusMessage = "Unlock with your NFC card before changing blocked apps."
            return
        }

        guard isScreenTimeApproved else {
            statusMessage = "Grant Screen Time permission first, then choose apps to block."
            return
        }

        isShowingActivityPicker = true
    }

    private func scanNFCCard() {
        guard selectedItemCount > 0 else {
            statusMessage = "Choose at least one app before scanning your NFC card."
            return
        }

        statusMessage = pairedCardID.isEmpty
            ? "Hold your NFC card near the top of your iPhone to pair it."
            : "Hold your paired NFC card near the top of your iPhone."

        nfcScanner.scan { result in
            switch result {
            case .success(let cardID):
                handleScannedCard(cardID)
            case .failure(let error):
                statusMessage = error.userMessage
            }
        }
    }

    private func handleScannedCard(_ cardID: String) {
        if pairedCardID.isEmpty {
            pairedCardID = cardID
            toggleLock(statusPrefix: "Card paired.")
            return
        }

        guard pairedCardID == cardID else {
            statusMessage = "That is not your paired TapLock card. Scan the original card to lock or unlock."
            return
        }

        toggleLock(statusPrefix: "Card verified.")
    }

    private func toggleLock(statusPrefix: String) {
        isLocked.toggle()

        if isLocked {
            applyShieldSettings()
            statusMessage = "\(statusPrefix) TapLock is locked. Selected apps are blocked."
        } else {
            clearShieldSettings()
            statusMessage = "\(statusPrefix) TapLock is unlocked."
        }
    }

    private func loadSavedSelection() {
        guard let data = UserDefaults.standard.data(forKey: savedSelectionKey) else {
            if isLocked {
                clearShieldSettings()
                isLocked = false
                statusMessage = "No saved app selection found. Choose apps again."
            }

            return
        }

        do {
            activitySelection = try JSONDecoder().decode(FamilyActivitySelection.self, from: data)

            let details = selectionDetails(for: activitySelection)
            if !details.isEmpty {
                if isLocked {
                    applyShieldSettings()
                    statusMessage = "TapLock is locked. \(details) blocked."
                } else {
                    statusMessage = "Loaded \(details). Next: scan your NFC card."
                }
            }
        } catch {
            UserDefaults.standard.removeObject(forKey: savedSelectionKey)
            clearShieldSettings()
            isLocked = false
            statusMessage = "Saved app selection could not be loaded. Choose apps again."
        }
    }

    private func saveSelection(_ selection: FamilyActivitySelection) {
        do {
            let data = try JSONEncoder().encode(selection)
            UserDefaults.standard.set(data, forKey: savedSelectionKey)
        } catch {
            statusMessage = "Could not save app selection: \(error.localizedDescription)"
        }
    }

    private func updateStatusForSelection(_ selection: FamilyActivitySelection) {
        let details = selectionDetails(for: selection)

        if details.isEmpty {
            clearShieldSettings()
            isLocked = false
            statusMessage = "Choose at least one app before scanning the NFC card."
        } else {
            if isLocked {
                applyShieldSettings()
                statusMessage = "Updated lock list. \(details) blocked."
            } else {
                statusMessage = "Saved \(details). Next: scan your NFC card."
            }
        }
    }

    private func applyShieldSettings() {
        managedSettingsStore.shield.applications = activitySelection.applicationTokens.isEmpty
            ? nil
            : activitySelection.applicationTokens

        managedSettingsStore.shield.applicationCategories = activitySelection.categoryTokens.isEmpty
            ? nil
            : .specific(activitySelection.categoryTokens)

        managedSettingsStore.shield.webDomains = activitySelection.webDomainTokens.isEmpty
            ? nil
            : activitySelection.webDomainTokens
    }

    private func clearShieldSettings() {
        managedSettingsStore.shield.applications = nil
        managedSettingsStore.shield.applicationCategories = nil
        managedSettingsStore.shield.webDomains = nil
        managedSettingsStore.shield.webDomainCategories = nil
    }

    private func selectionDetails(for selection: FamilyActivitySelection) -> String {
        [
            countText(selection.applicationTokens.count, singular: "app", plural: "apps"),
            countText(selection.categoryTokens.count, singular: "category", plural: "categories"),
            countText(selection.webDomainTokens.count, singular: "website", plural: "websites")
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private func countText(_ count: Int, singular: String, plural: String) -> String? {
        guard count > 0 else {
            return nil
        }

        return "\(count) \(count == 1 ? singular : plural)"
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
