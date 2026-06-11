import SwiftUI

struct AppShellView: View {
  @EnvironmentObject private var model: OpenVitalsAppModel
  @EnvironmentObject private var router: AppRouter
  @StateObject private var healthStore = HealthDataStore()
  @StateObject private var moreStore = MoreDataStore()
  @State private var homeSelectedDate = Date()

  var body: some View {
    TabView(selection: tabSelection) {
      ForEach(OpenVitalsAppTab.bottomTabs) { tab in
        tabNavigationStack(for: tab)
        .tabItem {
          Label(tab.title, systemImage: tab.systemImage)
        }
        .tag(tab)
      }
    }
    .tint(OpenVitalsTheme.accent)
  }

  private var tabSelection: Binding<OpenVitalsAppTab> {
    Binding {
      OpenVitalsAppTab.bottomTabs.contains(router.selectedTab) ? router.selectedTab : .home
    } set: { newTab in
      if newTab == router.selectedTab {
        router.reselect(newTab)
        return
      }
      router.selectedTab = newTab
      model.recordUIAction("tab.selected", detail: newTab.title)
    }
  }

  @ViewBuilder
  private func tabNavigationStack(for tab: OpenVitalsAppTab) -> some View {
    if tab == .home {
      NavigationStack(path: $router.healthPath) {
        tabContent(for: tab)
          .navigationDestination(for: HealthRoute.self) { route in
            HealthRouteDestinationView(route: route, store: healthStore, selectedDate: $homeSelectedDate)
          }
      }
    } else if tab == .health {
      NavigationStack(path: $router.healthPath) {
        tabContent(for: tab)
      }
    } else if tab == .more {
      NavigationStack(path: $router.morePath) {
        tabContent(for: tab)
      }
    } else {
      NavigationStack {
        tabContent(for: tab)
      }
    }
  }

  @ViewBuilder
  private func tabContent(for tab: OpenVitalsAppTab) -> some View {
    switch tab {
    case .home:
      HomeDashboardView(
        healthStore: healthStore,
        selectedDate: $homeSelectedDate,
        openHealthRoute: openHomeHealthRoute
      )
    case .health:
      HealthView(store: healthStore)
    case .coach:
      CoachView(healthStore: healthStore)
    case .debug:
      MoreDebugView(healthStore: healthStore, store: moreStore)
    case .more:
      MoreView(healthStore: healthStore, store: moreStore)
    }
  }

  private func openHomeHealthRoute(_ route: HealthRoute) {
    router.openHealth(route)
  }
}

enum OpenVitalsAppTab: String, CaseIterable, Identifiable {
  case home
  case health
  case coach
  case debug
  case more

  var id: String { rawValue }

  static let bottomTabs: [OpenVitalsAppTab] = [
    .home,
    // .health,
    // .coach,
    .debug,
    .more,
  ]

  var title: String {
    switch self {
    case .home: "Home"
    case .health: "Health"
    case .coach: "Coach"
    case .debug: "Debug"
    case .more: "More"
    }
  }

  var systemImage: String {
    switch self {
    case .home: "house"
    case .health: "heart.text.square"
    case .coach: "sparkles"
    case .debug: "terminal"
    case .more: "ellipsis.circle"
    }
  }

}
