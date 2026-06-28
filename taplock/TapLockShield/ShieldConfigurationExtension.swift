import ManagedSettings
import ManagedSettingsUI
import UIKit

final class TapLockShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        TapLockShieldConfiguration.makeShield(
            title: title(for: application.localizedDisplayName, fallback: "This app is locked")
        )
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        let categoryName = category.localizedDisplayName
        let fallback = categoryName.map { "Apps in \($0) are locked" } ?? "This app is locked"

        return TapLockShieldConfiguration.makeShield(
            title: title(for: application.localizedDisplayName, fallback: fallback)
        )
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        TapLockShieldConfiguration.makeShield(
            title: title(for: webDomain.domain, fallback: "This website is locked")
        )
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        let categoryName = category.localizedDisplayName
        let fallback = categoryName.map { "Websites in \($0) are locked" } ?? "This website is locked"

        return TapLockShieldConfiguration.makeShield(
            title: title(for: webDomain.domain, fallback: fallback)
        )
    }

    private func title(for name: String?, fallback: String) -> String {
        guard let name, !name.isEmpty else {
            return fallback
        }

        return "\(name) is locked"
    }
}

private enum TapLockShieldConfiguration {
    static func makeShield(title: String) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .dark,
            backgroundColor: hardBlack,
            icon: lockIcon,
            title: ShieldConfiguration.Label(
                text: title,
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Blocked by TapLock. Open TapLock and scan your NFC card to unlock.",
                color: UIColor.white.withAlphaComponent(0.72)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Stay Locked",
                color: .black
            ),
            primaryButtonBackgroundColor: .white
        )
    }

    private static let hardBlack = UIColor(
        red: 0,
        green: 0,
        blue: 0,
        alpha: 1
    )

    private static var lockIcon: UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 56, weight: .semibold)
        return UIImage(systemName: "lock.fill", withConfiguration: configuration)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
    }
}
