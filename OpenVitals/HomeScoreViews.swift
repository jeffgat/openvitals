import SwiftUI
import UIKit

struct HomeTopScrollFade: View {
  var body: some View {
    GeometryReader { proxy in
      LinearGradient(
        stops: [
          .init(color: OpenVitalsTheme.appBackground, location: 0),
          .init(color: OpenVitalsTheme.appBackground.opacity(0.96), location: 0.56),
          .init(color: OpenVitalsTheme.appBackground.opacity(0), location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .frame(height: max(proxy.safeAreaInsets.top + 44, 82))
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .ignoresSafeArea(edges: .top)
    }
  }
}

struct HomeStartActivityFloatingButton: View {
  @ObservedObject var session: ActivitySessionModel

  var body: some View {
    NavigationLink {
      LiveActivityView()
    } label: {
      Image(systemName: session.isActive ? session.selectedActivity.systemImage : "plus")
        .font(.system(size: 21, weight: .bold))
        .foregroundStyle(OpenVitalsTheme.graphite)
        .frame(width: 54, height: 54)
        .background(OpenVitalsTheme.accent, in: Circle())
        .shadow(color: OpenVitalsTheme.accent.opacity(0.18), radius: 12, x: 0, y: 7)
        .overlay {
          Circle()
            .strokeBorder(OpenVitalsTheme.ivory.opacity(0.22), lineWidth: 1)
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(session.isActive ? "Open Activity" : "Start Activity")
  }
}

struct HomeDailyScoreCard: View {
  let scores: [HealthMetricSnapshot]
  let syncDetail: String
  let syncButtonTitle: String
  let syncIsRunning: Bool
  let syncCanRun: Bool
  let syncAction: () -> Void
  let openScore: (HealthRoute) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Daily Scores")
            .font(.title3.bold())
            .foregroundStyle(OpenVitalsTheme.textPrimary)

          Text(syncDetail)
            .font(.caption.weight(.semibold))
            .foregroundStyle(OpenVitalsTheme.textSecondary)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
        }

        Spacer(minLength: 8)

        Button(action: syncAction) {
          HStack(spacing: 6) {
            if syncIsRunning {
              ProgressView()
                .controlSize(.small)
            } else {
              Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.bold))
            }
            Text(syncButtonTitle)
              .lineLimit(1)
          }
          .font(.subheadline.weight(.bold))
          .foregroundStyle(syncCanRun || syncIsRunning ? OpenVitalsTheme.accent : OpenVitalsTheme.textTertiary)
          .frame(minWidth: 86)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(OpenVitalsTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .strokeBorder(OpenVitalsTheme.border, lineWidth: 1)
          }
        }
        .buttonStyle(.plain)
        .disabled(!syncCanRun)
        .accessibilityLabel("Sync daily scores")
        .accessibilityValue(syncDetail)
      }

      HStack(alignment: .top, spacing: 12) {
        ForEach(scores) { score in
          Button {
            openScore(score.route)
          } label: {
            HomeScoreDial(snapshot: score)
          }
          .buttonStyle(.plain)
        }
      }
      .frame(maxWidth: .infinity)
    }
  }
}

struct HomeMissingDataItem: Identifiable {
  let id: String
  let title: String
  let detail: String
  let systemImage: String
  let tint: Color
  let route: HealthRoute
}

struct HomeMissingDataSection: View {
  let items: [HomeMissingDataItem]
  let openItem: (HomeMissingDataItem) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HomeSectionHeader(title: "Missing Data")

      VStack(spacing: 10) {
        ForEach(items) { item in
          Button {
            openItem(item)
          } label: {
            HomeMissingDataRow(item: item)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

struct HomeMissingDataRow: View {
  let item: HomeMissingDataItem

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: item.systemImage)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(OpenVitalsTheme.accent)
        .frame(width: 34, height: 34)
        .background(OpenVitalsTheme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

      VStack(alignment: .leading, spacing: 3) {
        Text(item.title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(OpenVitalsTheme.textPrimary)
          .lineLimit(1)

        Text(item.detail)
          .font(.caption)
          .foregroundStyle(OpenVitalsTheme.textSecondary)
          .lineLimit(2)
          .minimumScaleFactor(0.78)
      }

      Spacer(minLength: 8)

      Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(OpenVitalsTheme.textTertiary)
    }
    .padding(14)
    .cardSurface(tint: OpenVitalsTheme.accentMuted)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(item.title), \(item.detail)")
  }
}

struct HomeScoreDial: View {
  let snapshot: HealthMetricSnapshot

  var body: some View {
    VStack(spacing: 9) {
      ZStack {
        Circle()
          .stroke(tint.opacity(0.15), lineWidth: 9)
        Circle()
          .trim(from: 0, to: progress)
          .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
          .rotationEffect(.degrees(-90))

        Text(scoreText)
          .font(.system(size: 24, weight: .bold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(OpenVitalsTheme.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.62)
          .padding(8)
      }
      .frame(width: 88, height: 88)

      HStack(spacing: 4) {
        Image(systemName: snapshot.systemImage)
          .font(.caption.weight(.bold))
          .foregroundStyle(tint)
        Text(snapshot.title)
          .font(.caption.weight(.bold))
          .foregroundStyle(OpenVitalsTheme.textPrimary)
      }
      .lineLimit(1)
      .minimumScaleFactor(0.75)
      .padding(.top, 2)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }

  private var scoreText: String {
    snapshot.displayValue
      .replacingOccurrences(of: "%", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var progress: Double {
    let value = firstNumber(in: snapshot.displayValue) ?? 0
    return min(max(value / 100, 0), 1)
  }

  private var tint: Color {
    OpenVitalsTheme.routeTint(snapshot.route)
  }
}

struct HomeStressEnergySection: View {
  let stress: HealthMetricSnapshot
  let energy: HealthMetricSnapshot
  let openStress: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HomeSectionHeader(title: "Stress & Energy")

      Button {
        openStress()
      } label: {
        HStack(spacing: 14) {
          VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
              Circle()
                .fill(OpenVitalsTheme.accent)
                .frame(width: 10, height: 10)
              Text("Today's stress")
                .font(.headline)
                .foregroundStyle(OpenVitalsTheme.textPrimary)
                .lineLimit(1)
              Spacer()
            }

            Text(stress.freshness)
              .font(.caption.weight(.semibold))
              .foregroundStyle(OpenVitalsTheme.textSecondary)

            HStack(spacing: 12) {
              HomeStressStat(value: highestStressText, label: "Highest", color: OpenVitalsTheme.champagne)
              HomeStressStat(value: lowestStressText, label: "Lowest", color: OpenVitalsTheme.bronze)
              HomeStressStat(value: averageStressText, label: "Average", color: OpenVitalsTheme.gold)
            }
          }

          ZStack {
            Circle()
              .stroke(OpenVitalsTheme.accent.opacity(0.14), lineWidth: 8)
            Circle()
              .trim(from: 0, to: stressProgress)
              .stroke(OpenVitalsTheme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
              .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
              Text(stress.value)
                .font(.title3.bold())
              Text(stress.status)
                .font(.caption2.weight(.bold))
                .foregroundStyle(OpenVitalsTheme.textSecondary)
                .lineLimit(1)
            }
          }
          .frame(width: 76, height: 76)

          Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(OpenVitalsTheme.textTertiary)
        }
        .padding(14)
        .cardSurface(tint: OpenVitalsTheme.accent, prominent: true)
      }
      .buttonStyle(.plain)

      HomeEnergyBar(percent: Int(firstNumber(in: energy.displayValue) ?? 0), caption: energy.status)
    }
  }

  private var stressProgress: Double {
    min(max((firstNumber(in: stress.displayValue) ?? 0) / 100, 0), 1)
  }

  private var stressValues: [Double] {
    stress.trend.points.map(\.value)
  }

  private var highestStressText: String {
    stressValues.max().map { "\(Int($0.rounded()))" } ?? "--"
  }

  private var lowestStressText: String {
    stressValues.min().map { "\(Int($0.rounded()))" } ?? "--"
  }

  private var averageStressText: String {
    firstNumber(in: stress.value).map { "\(Int($0.rounded()))" } ?? "--"
  }
}

struct HomeStressStat: View {
  let value: String
  let label: String
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(.headline.bold())
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Text(label)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(OpenVitalsTheme.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct HomeEnergyBar: View {
  let percent: Int
  let caption: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "bolt.fill")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(OpenVitalsTheme.accent)
        .frame(width: 30, height: 30)
        .background(OpenVitalsTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

      HStack(spacing: 3) {
        ForEach(0..<18, id: \.self) { index in
          RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(index < filledSegments ? OpenVitalsTheme.gold : OpenVitalsTheme.separator)
            .frame(height: 18)
        }
      }

      VStack(alignment: .trailing, spacing: 2) {
        Text("\(percent)%")
          .font(.headline.bold())
          .lineLimit(1)
        Text(caption)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(OpenVitalsTheme.textSecondary)
          .lineLimit(1)
      }
    }
    .padding(14)
    .cardSurface(tint: OpenVitalsTheme.accent)
  }

  private var filledSegments: Int {
    Int((Double(percent) / 100 * 18).rounded())
  }
}

struct HomeCardioLoadWidget: View {
  let snapshot: HealthMetricSnapshot
  let days: [CardioLoadDay]
  let openSheet: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HomeSectionHeader(title: "Cardio Load")

      Button(action: openSheet) {
        VStack(alignment: .leading, spacing: 16) {
          HStack(spacing: 10) {
            Image(systemName: "shoeprints.fill")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(OpenVitalsTheme.accent)
              .frame(width: 32, height: 32)
              .background(OpenVitalsTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text("Cardio Load")
              .font(.headline)
              .foregroundStyle(OpenVitalsTheme.textPrimary)
              .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
              .font(.caption.weight(.bold))
              .foregroundStyle(OpenVitalsTheme.textTertiary)
          }

          HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
              Text(valueText)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(OpenVitalsTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

              Text(statusText)
                .font(.caption.weight(.bold))
                .foregroundStyle(OpenVitalsTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            .frame(width: 96, alignment: .leading)

            HomeCardioLoadSparkline(days: days)
              .frame(height: 82)
              .frame(maxWidth: .infinity)
          }
        }
        .padding(14)
        .cardSurface(tint: OpenVitalsTheme.accent, prominent: true)
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Cardio Load, \(valueText), \(statusText)")
    }
  }

  private var valueText: String {
    if let latest = days.last {
      return "\(Int(latest.load.rounded()))"
    }
    return snapshot.value
  }

  private var statusText: String {
    days.last?.status ?? snapshot.status
  }
}
