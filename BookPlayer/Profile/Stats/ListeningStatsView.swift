//
//  ListeningStatsView.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 3/8/26.
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import SwiftUI

/// The listening-stats screen behind the Profile "total listening" row:
/// streaks, a user-set daily goal, the last 30 days as a bar chart, and the
/// books the user has spent the most time with. Read-only — every figure is
/// derived from `PlaybackRecord` days and `PlaybackSession` rows.
struct ListeningStatsView: View {
  @StateObject private var model: Self.Model
  @EnvironmentObject private var theme: ThemeViewModel

  init(initModel: @escaping () -> Self.Model) {
    self._model = .init(wrappedValue: initModel())
  }

  var body: some View {
    List {
      todaySection
      streakSection
      chartSection
      goalSection
      if !model.itemTotals.isEmpty {
        perBookSection
      }
    }
    .listStyle(.sidebar)
    .applyListStyle(with: theme, background: theme.systemBackgroundColor)
    .navigationTitle("stats_title")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      model.reload()
    }
    .overlay {
      if !model.hasData {
        ContentUnavailableView(
          "stats_empty_title",
          systemImage: "chart.bar",
          description: Text("stats_empty_description")
        )
      }
    }
  }

  // MARK: - Sections

  private var todaySection: some View {
    Section {
      HStack {
        Text("stats_today_title")
          .bpFont(.body)
          .foregroundStyle(theme.primaryColor)
        Spacer()
        Text(todayLabel)
          .bpFont(.body)
          .foregroundStyle(theme.secondaryColor)
          .monospacedDigit()
      }
      .accessibilityElement(children: .combine)

      if let goalSeconds = model.goalSeconds {
        ProgressView(value: min(model.todaySeconds / goalSeconds, 1))
          .tint(theme.linkColor)
          .accessibilityLabel(todayLabel)
      }
    } header: {
      Text("stats_today_header")
    }
    .listRowBackground(theme.secondarySystemBackgroundColor)
  }

  private var todayLabel: String {
    if let goalSeconds = model.goalSeconds {
      return String.localizedStringWithFormat(
        "stats_today_progress".localized,
        Self.formatDuration(model.todaySeconds),
        Self.formatDuration(goalSeconds)
      )
    } else {
      return Self.formatDuration(model.todaySeconds)
    }
  }

  private var streakSection: some View {
    Section {
      HStack {
        Label("stats_current_streak", systemImage: "flame.fill")
          .bpFont(.body)
          .foregroundStyle(theme.primaryColor)
        Spacer()
        Text(Self.formatDays(model.streakCurrent))
          .bpFont(.body)
          .foregroundStyle(theme.secondaryColor)
      }
      .accessibilityElement(children: .combine)

      HStack {
        Label("stats_longest_streak", systemImage: "calendar.badge.clock")
          .bpFont(.body)
          .foregroundStyle(theme.primaryColor)
        Spacer()
        Text(Self.formatDays(model.streakLongest))
          .bpFont(.body)
          .foregroundStyle(theme.secondaryColor)
      }
      .accessibilityElement(children: .combine)
    } header: {
      Text("stats_streak_header")
    }
    .listRowBackground(theme.secondarySystemBackgroundColor)
  }

  private var chartSection: some View {
    Section {
      ListeningStatsChartView(
        records: model.dailyRecords,
        accentColor: theme.linkColor,
        secondaryColor: theme.secondaryColor
      )
      .listRowBackground(theme.secondarySystemBackgroundColor)
    } header: {
      Text("stats_month_header")
    }
  }

  private var goalSection: some View {
    Section {
      Picker("stats_daily_goal_title", selection: goalMinutesBinding) {
        ForEach(ListeningStatsService.goalPresetMinutes, id: \.self) { minutes in
          Text(goalLabel(for: minutes)).tag(minutes)
        }
      }
      .tint(theme.linkColor)
      .accessibilityHint("stats_daily_goal_hint")
    } header: {
      Text("stats_goal_header")
    }
    .listRowBackground(theme.secondarySystemBackgroundColor)
  }

  private var perBookSection: some View {
    Section {
      ForEach(model.itemTotals) { total in
        HStack {
          Text(total.title)
            .bpFont(.body)
            .foregroundStyle(theme.primaryColor)
            .lineLimit(2)
          Spacer()
          Text(Self.formatDuration(total.seconds))
            .bpFont(.body)
            .foregroundStyle(theme.secondaryColor)
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
      }
    } header: {
      Text("stats_per_book_header")
    } footer: {
      Text("stats_per_book_footer")
    }
    .listRowBackground(theme.secondarySystemBackgroundColor)
  }

  // MARK: - Helpers

  private var goalMinutesBinding: Binding<Int> {
    Binding(
      get: { model.goalMinutes },
      set: { model.setGoal(minutes: $0) }
    )
  }

  private func goalLabel(for minutes: Int) -> String {
    guard minutes > 0 else {
      return "stats_goal_off".localized
    }
    return Self.formatDuration(Double(minutes) * 60)
  }

  /// "2h 15m"-style abbreviated duration — same shape as the total-listening
  /// figure on Profile (DateComponentsFormatter, abbreviated units)
  static func formatDuration(_ seconds: Double) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: seconds) ?? "0m"
  }

  static func formatDays(_ days: Int) -> String {
    String.localizedStringWithFormat("stats_days_count".localized, days)
  }
}

extension ListeningStatsView {
  @MainActor
  class Model: ObservableObject {
    @Published var todaySeconds: Double = 0
    @Published var goalMinutes: Int = 0
    /// Nil when the user set no goal — the progress row hides
    @Published var goalSeconds: Double? = nil
    @Published var streakCurrent: Int = 0
    @Published var streakLongest: Int = 0
    @Published var dailyRecords: [SimplePlaybackRecord] = []
    @Published var itemTotals: [ListeningStatsService.ListeningItemTotal] = []
    /// Any listening on record at all — drives the empty state
    @Published var hasData: Bool = false

    func reload() {}
    func setGoal(minutes: Int) {}
  }
}

#Preview {
  NavigationStack {
    ListeningStatsView {
      let model = Model()
      model.todaySeconds = 1470
      model.goalMinutes = 30
      model.goalSeconds = 1800
      model.streakCurrent = 4
      model.streakLongest = 11
      model.hasData = true
      model.dailyRecords = (0..<30).compactMap {
        guard let day = Calendar.current.date(byAdding: .day, value: $0 - 29, to: Date()) else {
          return nil
        }
        return SimplePlaybackRecord(time: Double(($0 * 977) % 5400), date: day)
      }
      model.itemTotals = [
        .init(relativePath: "a.m4b", title: "The Martian", seconds: 25400),
        .init(relativePath: "b.m4b", title: "Project Hail Mary", seconds: 12100),
      ]
      return model
    }
    .environmentObject(ThemeViewModel())
  }
}
