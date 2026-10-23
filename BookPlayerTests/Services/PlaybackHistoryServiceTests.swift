//
//  PlaybackHistoryServiceTests.swift
//  BookPlayerTests
//
//  Created by Gianni Carlo on 12/5/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

@testable import BookPlayer
@testable import BookPlayerKit
import CoreData
import UIKit
import XCTest

/// Main actor: the service is `@MainActor` and the playback notifications it
/// consumes are posted there (same rationale as `ListeningQueueServiceTests`).
/// Sessions under two seconds are noise and never persist — tests that need a
/// row to survive `endSession` wait out the minimum.
@MainActor
final class PlaybackHistoryServiceTests: XCTestCase {
  var dataManager: DataManager!
  var libraryService: LibraryService!
  var sut: PlaybackHistoryService!

  /// `PlaybackHistoryService.minimumSessionDuration` — a session must outlive
  /// this for `endSession` to keep it
  private let minimumSessionWait: UInt64 = 2_100_000_000

  override func setUp() {
    DataTestUtils.clearFolderContents(url: DataManager.getProcessedFolderURL())
    dataManager = DataManager(coreDataStack: CoreDataStack(testPath: "/dev/null"))
    libraryService = LibraryService()
    libraryService.setup(dataManager: dataManager, audioMetadataService: AudioMetadataService())
    _ = libraryService.getLibrary()
    sut = PlaybackHistoryService()
    sut.setup(dataManager: dataManager)
    sut.observePlayback()
  }

  override func tearDown() {
    /// Releasing the service drops its cancellables — a lingering sut would
    /// keep answering notifications for the rest of the suite
    sut = nil
    dataManager = nil
    libraryService = nil
  }

  private func addBook(_ title: String) -> Book {
    let book = StubFactory.book(dataManager: dataManager, title: title, duration: 100)
    libraryService.getLibraryReference().addToItems(book)
    dataManager.saveContext()
    return book
  }

  private func playableItem(for book: Book, at position: Double = 0) -> PlayableItem {
    let chapter = PlayableChapter(
      title: book.title,
      author: book.details,
      start: 0,
      duration: book.duration,
      relativePath: book.relativePath,
      remoteURL: nil,
      externalURL: nil,
      index: 0
    )
    return PlayableItem(
      title: book.title,
      author: book.details,
      chapters: [chapter],
      currentTime: position,
      duration: book.duration,
      relativePath: book.relativePath,
      uuid: book.uuid,
      parentFolder: nil,
      percentCompleted: 0,
      lastPlayDate: nil,
      isFinished: false,
      isBoundBook: false
    )
  }

  /// The service subscribes with `receive(on: .main)` — the post must clear
  /// the hop before the next step runs
  private func settle() async {
    try? await Task.sleep(nanoseconds: 50_000_000)
  }

  private func postPlayed(_ item: PlayableItem) async {
    NotificationCenter.default.post(name: .bookPlayed, object: nil, userInfo: ["book": item])
    await settle()
  }

  private func post(_ name: Notification.Name) async {
    NotificationCenter.default.post(name: name, object: nil)
    await settle()
  }

  func testPlayedThenPausedRecordsSession() async throws {
    let book = addBook("book")
    let item = playableItem(for: book)

    await postPlayed(item)
    item.currentTime = 42
    try await Task.sleep(nanoseconds: minimumSessionWait)
    await post(.bookPaused)

    let sessions = sut.fetchSessions()
    XCTAssertEqual(sessions.count, 1)
    XCTAssertEqual(sessions.first?.itemRelativePath, book.relativePath)
    /// The position saved is where the session was left, not where it started
    XCTAssertEqual(sessions.first?.position ?? 0, 42, accuracy: 0.001)
    XCTAssertGreaterThanOrEqual(sessions.first?.duration ?? 0, 2)
  }

  /// A load swap doesn't post `.bookPaused` — the next `.bookPlayed` closes
  /// the previous session itself
  func testPlayingAnotherItemClosesTheFirstSession() async throws {
    let a = addBook("a-book")
    let b = addBook("b-book")

    await postPlayed(playableItem(for: a))
    try await Task.sleep(nanoseconds: minimumSessionWait)
    await postPlayed(playableItem(for: b))
    /// b's session ends sub-minimum — it drops, leaving only a's row
    await post(.bookPaused)

    XCTAssertEqual(sut.fetchSessions().map(\.itemRelativePath), [a.relativePath])
  }

  func testBookEndClosesSession() async throws {
    let book = addBook("book")

    await postPlayed(playableItem(for: book))
    try await Task.sleep(nanoseconds: minimumSessionWait)
    await post(.bookEnd)

    XCTAssertEqual(sut.fetchSessions().map(\.itemRelativePath), [book.relativePath])
  }

  func testSessionShorterThanMinimumIsDropped() async {
    let book = addBook("book")

    await postPlayed(playableItem(for: book))
    await post(.bookPaused)

    XCTAssertEqual(sut.fetchSessions(), [])
  }

  /// A mid-play tick persists the row early; ending before the minimum still
  /// deletes it — the cap is on session length, not on row existence
  func testShortSessionDeletesItsPersistedRow() async {
    let book = addBook("book")

    await postPlayed(playableItem(for: book))
    await post(.bookPlaying)
    XCTAssertEqual(sut.fetchSessions().count, 1)

    await post(.bookPaused)
    XCTAssertEqual(sut.fetchSessions(), [])
  }

  func testMidPlayPersistIsThrottled() async {
    let book = addBook("book")
    let item = playableItem(for: book)

    await postPlayed(item)

    item.currentTime = 10
    await post(.bookPlaying)
    XCTAssertEqual(sut.fetchSessions().first?.position, 10)

    /// Inside the persist interval a second tick is swallowed
    item.currentTime = 20
    await post(.bookPlaying)
    XCTAssertEqual(sut.fetchSessions().first?.position, 10)

    /// Backgrounding bypasses the throttle so a kill loses little
    item.currentTime = 30
    await post(UIApplication.didEnterBackgroundNotification)
    XCTAssertEqual(sut.fetchSessions().first?.position, 30)
  }

  func testPruneKeepsThirtyMostRecentSessionsPerItem() async throws {
    let book = addBook("book")

    /// Pre-seed the cap: the incoming session becomes the 31st and the oldest goes
    let context = dataManager.getContext()
    for index in 0..<30 {
      let session = PlaybackSession.create(in: context)
      session.date = Date().addingTimeInterval(-Double(index + 1) * 60)
      session.position = Double(index)
      session.duration = 60
      session.item = book
    }
    dataManager.saveContext()

    let item = playableItem(for: book, at: 999)
    await postPlayed(item)
    try await Task.sleep(nanoseconds: minimumSessionWait)
    await post(.bookPaused)

    let sessions = sut.fetchSessions(for: book.relativePath)
    XCTAssertEqual(sessions.count, 30)
    /// Newest first: the session that just closed survives the prune
    XCTAssertEqual(sessions.first?.position, 999)
  }
}
