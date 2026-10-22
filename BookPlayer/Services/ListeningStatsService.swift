//
//  ListeningStatsService.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 3/8/26.
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import Combine
import CoreData
import Foundation

/// Computes the Profile listening stats — daily totals, streaks, the daily
/// goal, and per-book listening time — from the two honest data sources:
///
/// - `PlaybackRecord` rows (one per day, `time` = seconds listened) back every
///   day-level figure. They predate this feature, so streaks and the monthly
///   chart cover the user's full history.
/// - `PlaybackSession` rows (Phase 3a, per play→pause cycle with its item)
///   back the per-book totals. Books listened to before sessions existed
///   simply have less data — nothing is invented.
///
/// The daily goal is a device-local preference in standard `UserDefaults`
/// (`Constants.UserDefaults.dailyGoalMinutes`); it never enters the library
/// store or any sync payload.
///
/// Follows the CoreServices two-step pattern: `init()` for a no-op
/// placeholder, `setup(dataManager:)` for the real one. State lives on the
/// main actor: the store it reads is the view context and every consumer is
/// a view.
@MainActor
final class ListeningStatsService {
  private var dataManager: DataManager?
  /// Injected for tests; production uses `.standard` (device-local pref)
  private var defaults: UserDefaults

  /// Emitted when the goal preference changes so an open stats view refreshes
  let updates = PassthroughSubject<Void, Never>()

  /// One book's accumulated listening time, for the "Time per book" section
  struct ListeningItemTotal: Identifiable, Hashable {
    var id: String { relativePath }
    let relativePath: String
    let title: String
    /// Total seconds across all recorded sessions for this item
    let seconds: Double
  }

  /// Streak lengths in consecutive days. `current` counts back from today
  /// (a day with no listening yet keeps yesterday's streak alive); `longest`
  /// is the best run ever recorded.
  struct StreakSummary: Hashable {
    let current: Int
    let longest: Int
  }

  /// Presets offered for the daily goal, in minutes. `0` = no goal.
  static let goalPresetMinutes = [0, 15, 30, 45, 60, 90, 120]

  /// `nonisolated` so the type stays usable as an `@Entry` default value —
  /// the placeholder does no actor-bound work; `setup` is the real start
  nonisolated init() {
    self.defaults = .standard
  }

  func setup(dataManager: DataManager, defaults: UserDefaults = .standard) {
    self.dataManager = dataManager
    self.defaults = defaults
  }

  // MARK: - Daily goal

  /// Minutes the user wants to listen per day; `0` means no goal set
  var dailyGoalMinutes: Int {
    get {
      defaults.integer(forKey: Constants.UserDefaults.dailyGoalMinutes)
    }
    set {
      defaults.set(newValue, forKey: Constants.UserDefaults.dailyGoalMinutes)
      updates.send()
    }
  }

  /// The daily goal as a progress target: `nil` when the user set no goal
  var dailyGoalSeconds: Double? {
    let minutes = dailyGoalMinutes
    return minutes > 0 ? Double(minutes) * 60 : nil
  }

  // MARK: - Day-level reads

  /// Seconds listened today (0 when nothing has played)
  func listeningToday() -> Double {
    let today = Calendar.current.startOfDay(for: Date())
    guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else {
      return 0
    }
    return dailyTotalsMap(from: today, to: tomorrow)
      .values
      .reduce(0, +)
  }

  /// Per-day listening totals for the `days` ending today, oldest first.
  /// Days with no listening are zero-filled so a chart shows real gaps.
  func dailyTotals(days: Int) -> [SimplePlaybackRecord] {
    guard days > 0 else { return [] }

    let calendar = Calendar.current
    let startToday = calendar.startOfDay(for: Date())
    guard
      let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: startToday),
      let endDay = calendar.date(byAdding: .day, value: 1, to: startToday)
    else { return [] }

    let totals = dailyTotalsMap(from: startDay, to: endDay)

    return (0..<days).compactMap { offset in
      guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else { return nil }
      return SimplePlaybackRecord(time: totals[day] ?? 0, date: day)
    }
  }

  /// Current + longest streak of consecutive days with at least one second
  /// of recorded listening.
  func streaks() -> StreakSummary {
    let days = allListenedDays()
    guard !days.isEmpty else {
      return StreakSummary(current: 0, longest: 0)
    }

    let calendar = Calendar.current

    var longest = 1
    var run = 1
    for index in 1..<days.count {
      if let expected = calendar.date(byAdding: .day, value: 1, to: days[index - 1]),
         calendar.isDate(days[index], inSameDayAs: expected) {
        run += 1
        longest = max(longest, run)
      } else {
        run = 1
      }
    }

    /// Current streak: walk back from today; if today has no listening yet
    /// the streak still counts when yesterday was a listening day
    let startToday = calendar.startOfDay(for: Date())
    let listenedDays = Set(days.map { calendar.startOfDay(for: $0) })
    var current = 0
    var cursor = startToday
    if !listenedDays.contains(cursor),
       let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) {
      cursor = yesterday
    }
    while listenedDays.contains(cursor) {
      current += 1
      guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
      cursor = previous
    }

    return StreakSummary(current: current, longest: longest)
  }

  // MARK: - Per-book totals

  /// Accumulated listening time per item, most listened first, from
  /// `PlaybackSession` rows. Sessions are capped at 30 per item, so the
  /// fetch is bounded by the library size.
  func perItemTotals(limit: Int) -> [ListeningItemTotal] {
    guard let dataManager else { return [] }
    let context = dataManager.getContext()

    let rows: [[String: Any]] = context.performAndWait {
      let fetch = NSFetchRequest<NSDictionary>(entityName: "PlaybackSession")
      fetch.resultType = .dictionaryResultType
      /// Literal keys: `#keyPath` rejects traversing the `item` relationship
      fetch.propertiesToFetch = ["duration", "item.relativePath", "item.title"]
      return (try? context.fetch(fetch) as? [[String: Any]]) ?? []
    }

    var totals = [String: (title: String, seconds: Double)]()
    for row in rows {
      guard
        let relativePath = row["item.relativePath"] as? String,
        let seconds = row["duration"] as? Double
      else { continue }

      let title = row["item.title"] as? String ?? relativePath
      let existing = totals[relativePath]
      totals[relativePath] = (
        title: title,
        seconds: (existing?.seconds ?? 0) + seconds
      )
    }

    return totals
      .map { ListeningItemTotal(relativePath: $0.key, title: $0.value.title, seconds: $0.value.seconds) }
      .sorted { $0.seconds > $1.seconds }
      .prefix(limit)
      .map { $0 }
  }

  // MARK: - Internals

  /// Day → seconds map built by summing `PlaybackRecord` rows into
  /// `startOfDay` buckets, so records whose `date` isn't exactly midnight
  /// still land on their day.
  private func dailyTotalsMap(from startDate: Date, to endDate: Date) -> [Date: Double] {
    guard let dataManager else { return [:] }
    let context = dataManager.getContext()
    let calendar = Calendar.current

    let records: [SimplePlaybackRecord] = context.performAndWait {
      let fetch = PlaybackRecord.fetchRequest()
      fetch.predicate = NSPredicate(format: "date >= %@ AND date < %@", startDate as NSDate, endDate as NSDate)
      return (try? context.fetch(fetch))?.map { SimplePlaybackRecord(from: $0) } ?? []
    }

    var totals = [Date: Double]()
    for record in records {
      let day = calendar.startOfDay(for: record.date)
      totals[day, default: 0] += record.time
    }
    return totals
  }

  /// Every day on record with at least one second of listening, ascending
  private func allListenedDays() -> [Date] {
    guard let dataManager else { return [] }
    let context = dataManager.getContext()
    let calendar = Calendar.current

    /// Dictionary fetch of just the date column — a full PlaybackRecord read
    /// would materialize every row ever recorded to answer "which days"
    let dates: [Date] = context.performAndWait {
      let fetch = NSFetchRequest<NSDictionary>(entityName: "PlaybackRecord")
      fetch.resultType = .dictionaryResultType
      fetch.propertiesToFetch = ["date"]
      fetch.predicate = NSPredicate(format: "time > 0")
      return (try? context.fetch(fetch) as? [[String: Any]])?
        .compactMap { $0["date"] as? Date } ?? []
    }

    return Array(Set(dates.map { calendar.startOfDay(for: $0) })).sorted()
  }
}
