import SwiftUI
import UIKit

enum OpenVitalsAppearancePreference: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  static let storageKey = "openVitals.appearancePreference"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }

  var detail: String {
    switch self {
    case .system: "Follow the appearance selected on this iPhone."
    case .light: "Use the brighter OpenVitals interface."
    case .dark: "Use the darker OpenVitals interface."
    }
  }

  var systemImage: String {
    switch self {
    case .system: "iphone"
    case .light: "sun.max"
    case .dark: "moon"
    }
  }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }

  static func preference(for rawValue: String) -> OpenVitalsAppearancePreference {
    OpenVitalsAppearancePreference(rawValue: rawValue) ?? .dark
  }
}

enum OpenVitalsTheme {
  static let deviceBackground = Color(red: 0.06, green: 0.09, blue: 0.11)

  static let appBackground = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark ? deviceBackgroundUIColor : .systemGroupedBackground
  })

  static let plainBackground = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark ? deviceBackgroundUIColor : .systemBackground
  })

  static func configureAppearance() {
    UIWindow.appearance().backgroundColor = appBackgroundUIColor
    UITableView.appearance().backgroundColor = appBackgroundUIColor
    UICollectionView.appearance().backgroundColor = appBackgroundUIColor

    let navigationAppearance = UINavigationBarAppearance()
    navigationAppearance.configureWithTransparentBackground()
    navigationAppearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
    navigationAppearance.backgroundColor = navigationBarBackgroundUIColor
    navigationAppearance.shadowColor = .clear
    UINavigationBar.appearance().standardAppearance = navigationAppearance
    UINavigationBar.appearance().compactAppearance = navigationAppearance
    UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance

    let tabAppearance = UITabBarAppearance()
    tabAppearance.configureWithOpaqueBackground()
    tabAppearance.backgroundColor = appBackgroundUIColor
    tabAppearance.shadowColor = .clear
    UITabBar.appearance().standardAppearance = tabAppearance
    UITabBar.appearance().scrollEdgeAppearance = tabAppearance
  }

  private static let deviceBackgroundUIColor = UIColor(
    red: 0.06,
    green: 0.09,
    blue: 0.11,
    alpha: 1
  )

  private static let appBackgroundUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark ? deviceBackgroundUIColor : .systemGroupedBackground
  }

  private static let navigationBarBackgroundUIColor = UIColor { traits in
    let alpha: CGFloat = traits.userInterfaceStyle == .dark ? 0.58 : 0.46
    return appBackgroundUIColor.resolvedColor(with: traits).withAlphaComponent(alpha)
  }
}

struct OpenVitalsLogoMark: View {
  let size: CGFloat
  let cornerRadius: CGFloat

  init(size: CGFloat = 44, cornerRadius: CGFloat = 8) {
    self.size = size
    self.cornerRadius = cornerRadius
  }

  var body: some View {
    Image("openvitals_logo")
      .resizable()
      .scaledToFill()
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(.white.opacity(0.16), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
      .accessibilityHidden(true)
  }
}

extension View {
  func openVitalsScreenBackground() -> some View {
    background(OpenVitalsTheme.appBackground.ignoresSafeArea())
  }

  func openVitalsPlainBackground() -> some View {
    background(OpenVitalsTheme.plainBackground.ignoresSafeArea())
  }

  func openVitalsListBackground() -> some View {
    scrollContentBackground(.hidden)
      .background(OpenVitalsTheme.appBackground.ignoresSafeArea())
  }
}
