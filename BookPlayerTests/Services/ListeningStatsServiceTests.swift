//
//  ListeningStatsServiceTests.swift
//  BookPlayerTests
//
//  Created by Gianni Carlo on 3/8/26.
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//
//

@testable import Narratix
@testable import BookPlayerKit
import CoreData
import XCTest

/// `@MainActor`: the service is `@MainActor` (its store reads are
/// view-context reads on behalf of views) — same rationale as
/// `PlaybackHistoryServiceTests`.
@MainActor
final class ListeningStatsServiceTests: XCTestCase {
  var dataManager: DataManager!
  var sut: ListeningStatsService!
  var defaults: UserDefaults!

  override func setUp() {
    DataTestUtils.clearFolderContents(url: DataManager.getProcessedFolderURL())
    dataManager = DataManager(coreDataStack: CoreDataStack(testPath: "/dev/null"))
    defaults = UserDefaults(suiteName: "ListeningStatsServiceTests-\(UUID().uuidString)")
    sut = ListeningStatsService()
    sut.setup(dataManager: dataManager, defaults: defaults)
  }

  override func tearDown() {
    sut = nil
    defaults = nil
    dataManager = nil
  }

  // MARK: - Helpers

  private func addRecord(daysAgo: Int, seconds: Double) {
    let context = dataManager.getContext()
    let day = Calendar.current.date(
      byAdding: .day,
      value: -daysAgo,
      to: Calendar.current.startOfDay(for: Date())
    )!
    let record = PlaybackRecord.create(in: context)
    record.date = day
    record.time = seconds
    dataManager.saveContext()
  }

  /// The session's `item` relationship is all the per-book totals read —
  /// the book doesn't need library membership for them
  private func addBook(_ title: String) -> Book {
    let book = StubFactory.book(dataManager: dataManager, title: title, duration: 100)
    dataManager.saveContext()
    return book
  }

  private func addSession(for book: Book, daysAgo: Int, seconds: Double) {
    let context = dataManager.getContext()
    let session = PlaybackSession.create(in: context)
    session.date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
    session.duration = seconds
    session.position = 10
    session.item = book
    dataManager.saveContext()
  }

  // MARK: - Daily totals

  func testDailyTotalsZeroFillsGaps() {
    addRecord(daysAgo: 2, seconds: 600)
    addRecord(daysAgo: 0, seconds: 300)

    let days = sut.dailyTotals(days: 3)

    XCTAssertEqual(days.count, 3)
    XCTAssertEqual(days.map(\.time), [600, 0, 300])
  }

  func testListeningTodaySumsTodayOnly() {
    addRecord(daysAgo: 1, seconds: 900)
    addRecord(daysAgo: 0, seconds: 120)

    XCTAssertEqual(sut.listeningToday(), 120, accuracy: 0.001)
  }

  // MARK: - Streaks

  func testCurrentStreakCountsBackFromToday() {
    addRecord(daysAgo: 0, seconds: 60)
    addRecord(daysAgo: 1, seconds: 60)
    addRecord(daysAgo: 3, seconds: 60)

    let streaks = sut.streaks()

    XCTAssertEqual(streaks.current, 2)
    XCTAssertEqual(streaks.longest, 2)
  }

  /// A day not yet played doesn't break the streak — yesterday's run is
  /// still alive until the day ends with no listening
  func testStreakSurvivesUnplayedToday() {
    addRecord(daysAgo: 1, seconds: 60)
    addRecord(daysAgo: 2, seconds: 60)

    XCTAssertEqual(sut.streaks().current, 2)
  }

  /// But a fully missed day does break it
  func testStreakEndsAfterMissedDay() {
    addRecord(daysAgo: 2, seconds: 60)
    addRecord(daysAgo: 3, seconds: 60)

    XCTAssertEqual(sut.streaks().current, 0)
  }

  func testLongestStreakBeatsCurrent() {
    /// 3-day run last week, 2-day run now
    addRecord(daysAgo: 0, seconds: 30)
    addRecord(daysAgo: 1, seconds: 30)
    addRecord(daysAgo: 5, seconds: 30)
    addRecord(daysAgo: 6, seconds: 30)
    addRecord(daysAgo: 7, seconds: 30)

    let streaks = sut.streaks()

    XCTAssertEqual(streaks.current, 2)
    XCTAssertEqual(streaks.longest, 3)
  }

  func testNoRecordsMeansNoStreak() {
    let streaks = sut.streaks()

    XCTAssertEqual(streaks.current, 0)
    XCTAssertEqual(streaks.longest, 0)
  }

  /// Zero-time rows can't fabricate a listening day
  func testZeroTimeRecordsDontCount() {
    addRecord(daysAgo: 0, seconds: 0)

    XCTAssertEqual(sut.streaks().longest, 0)
    XCTAssertEqual(sut.listeningToday(), 0, accuracy: 0.001)
  }

  // MARK: - Per-book totals

  func testPerItemTotalsSumAndOrder() {
    let a = addBook("a-book")
    let b = addBook("b-book")

    addSession(for: a, daysAgo: 2, seconds: 100)
    addSession(for: a, daysAgo: 1, seconds: 50)
    addSession(for: b, daysAgo: 1, seconds: 500)

    let totals = sut.perItemTotals(limit: 10)

    XCTAssertEqual(totals.map(\.relativePath), [b.relativePath, a.relativePath])
    XCTAssertEqual(totals.first?.seconds ?? 0, 500, accuracy: 0.001)
    XCTAssertEqual(totals.last?.seconds ?? 0, 150, accuracy: 0.001)
    XCTAssertEqual(totals.last?.title, "a-book")
  }

  func testPerItemTotalsHonorsLimit() {
    let a = addBook("a")
    let b = addBook("b")
    addSession(for: a, daysAgo: 0, seconds: 100)
    addSession(for: b, daysAgo: 0, seconds: 200)

    XCTAssertEqual(sut.perItemTotals(limit: 1).count, 1)
  }

  // MARK: - Goal

  func testGoalRoundtrip() {
    XCTAssertEqual(sut.dailyGoalMinutes, 0)
    XCTAssertNil(sut.dailyGoalSeconds)

    sut.dailyGoalMinutes = 45

    XCTAssertEqual(sut.dailyGoalMinutes, 45)
    XCTAssertEqual(sut.dailyGoalSeconds ?? 0, 2700, accuracy: 0.001)
    /// Back to no-goal
    sut.dailyGoalMinutes = 0
    XCTAssertNil(sut.dailyGoalSeconds)
  }
}
