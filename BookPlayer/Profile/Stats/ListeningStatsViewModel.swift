//
//  ListeningStatsViewModel.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 3/8/26.
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import Combine
import Foundation

/// Live stats for the screen: recomputes on appear, when the goal changes,
/// and when a listening session ends while the screen is up (the history
/// service's `updates` also fires on the mid-play row refresh, which moves
/// the per-book totals forward — the debounce keeps that cheap).
final class ListeningStatsViewModel: ListeningStatsView.Model {
  private let statsService: ListeningStatsService
  private var disposeBag = Set<AnyCancellable>()

  /// Most recent days charted
  private static let chartDays = 30
  /// Most-listened books listed
  private static let perBookLimit = 10

  init(
    statsService: ListeningStatsService,
    playbackHistoryService: PlaybackHistoryService? = nil
  ) {
    self.statsService = statsService
    super.init()

    reload()

    statsService.updates
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        self?.reload()
      }
      .store(in: &disposeBag)

    playbackHistoryService?.updates
      .receive(on: DispatchQueue.main)
      .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
      .sink { [weak self] in
        self?.reload()
      }
      .store(in: &disposeBag)
  }

  override func reload() {
    let streaks = statsService.streaks()

    todaySeconds = statsService.listeningToday()
    goalMinutes = statsService.dailyGoalMinutes
    goalSeconds = statsService.dailyGoalSeconds
    streakCurrent = streaks.current
    streakLongest = streaks.longest
    dailyRecords = statsService.dailyTotals(days: Self.chartDays)
    itemTotals = statsService.perItemTotals(limit: Self.perBookLimit)
    hasData = streaks.longest > 0 || todaySeconds > 0
  }

  override func setGoal(minutes: Int) {
    statsService.dailyGoalMinutes = minutes
    /// The service's `updates` reloads the derived figures; the local read
    /// below keeps the picker's selection responsive in the same frame
    goalMinutes = statsService.dailyGoalMinutes
    goalSeconds = statsService.dailyGoalSeconds
  }
}
