//
//  ListeningStateFilterTests.swift
//  BookPlayerTests
//
//  Created by Gianni Carlo on 12/5/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

@testable import Narratix
@testable import BookPlayerKit
import XCTest

/// The DNF triage state: `ListeningState` derives from the snapshot's flags,
/// `LibraryService.filterContents` narrows to it. DNF is its own group — a
/// book marked DNF leaves Finished but keeps its progress.
@MainActor
final class ListeningStateFilterTests: XCTestCase {
  var dataManager: DataManager!
  var sut: LibraryService!

  override func setUp() {
    DataTestUtils.clearFolderContents(url: DataManager.getProcessedFolderURL())
    dataManager = DataManager(coreDataStack: CoreDataStack(testPath: "/dev/null"))
    sut = LibraryService()
    sut.setup(dataManager: dataManager, audioMetadataService: AudioMetadataService())
    _ = sut.getLibrary()
  }

  private func makeItem(
    currentTime: Double = 0,
    isFinished: Bool = false,
    didNotFinish: Bool = false
  ) -> SimpleLibraryItem {
    SimpleLibraryItem(
      title: "title",
      details: "author",
      speed: 1.0,
      currentTime: currentTime,
      duration: 100,
      percentCompleted: currentTime,
      isFinished: isFinished,
      relativePath: "book.m4b",
      remoteURL: nil,
      artworkURL: nil,
      orderRank: 0,
      parentFolder: nil,
      originalFileName: "book.m4b",
      lastPlayDate: nil,
      type: .book,
      uuid: UUID().uuidString,
      didNotFinish: didNotFinish
    )
  }

  func testStateIsNewForUntouchedItem() {
    XCTAssertEqual(makeItem().listeningState, .notStarted)
  }

  func testStateIsStartedOnceProgressExists() {
    XCTAssertEqual(makeItem(currentTime: 10).listeningState, .inProgress)
  }

  func testStateIsFinishedForCompletedItem() {
    XCTAssertEqual(makeItem(currentTime: 100, isFinished: true).listeningState, .finished)
  }

  func testDidNotFinishWinsOverFinished() {
    XCTAssertEqual(makeItem(isFinished: true, didNotFinish: true).listeningState, .didNotFinish)
  }

  func testDidNotFinishOnPartiallyPlayedItem() {
    XCTAssertEqual(makeItem(currentTime: 50, didNotFinish: true).listeningState, .didNotFinish)
  }

  private func addBook(
    _ title: String,
    currentTime: Double = 0,
    isFinished: Bool = false,
    didNotFinish: Bool = false
  ) -> Book {
    let book = StubFactory.book(dataManager: dataManager, title: title, duration: 100)
    book.currentTime = currentTime
    book.percentCompleted = currentTime
    book.isFinished = isFinished
    book.didNotFinish = didNotFinish
    sut.getLibraryReference().addToItems(book)
    return book
  }

  private func filterPaths(for state: ListeningState) -> [String] {
    (sut.filterContents(
      at: nil,
      query: nil,
      scope: nil,
      listeningState: state,
      limit: nil,
      offset: nil
    ) ?? []).map(\.relativePath)
  }

  func testListeningStateFiltersPartitionTheLibrary() {
    let newBook = addBook("new-book")
    let startedBook = addBook("started-book", currentTime: 30)
    let finishedBook = addBook("finished-book", isFinished: true)
    let dnfBook = addBook("dnf-book", currentTime: 60, didNotFinish: true)
    dataManager.saveContext()

    XCTAssertEqual(filterPaths(for: .notStarted), [newBook.relativePath])
    XCTAssertEqual(filterPaths(for: .inProgress), [startedBook.relativePath])
    XCTAssertEqual(filterPaths(for: .finished), [finishedBook.relativePath])
    XCTAssertEqual(filterPaths(for: .didNotFinish), [dnfBook.relativePath])
  }

  /// A finished book marked DNF joins DNF and leaves Finished — one state, not two
  func testMarkingFinishedItemAsDnfMovesItBetweenGroups() {
    let book = addBook("book", isFinished: true)
    dataManager.saveContext()

    sut.markAsDidNotFinish(flag: true, relativePath: book.relativePath)
    dataManager.saveContext()

    XCTAssertEqual(filterPaths(for: .didNotFinish), [book.relativePath])
    XCTAssertEqual(filterPaths(for: .finished), [])

    sut.markAsDidNotFinish(flag: false, relativePath: book.relativePath)
    dataManager.saveContext()

    XCTAssertEqual(filterPaths(for: .finished), [book.relativePath])
    XCTAssertEqual(filterPaths(for: .didNotFinish), [])
  }

  /// The binary `isFinished` stays untouched: markAsFinished updates it exactly
  /// as before — DNF is additive, upstream semantics preserved
  func testMarkAsFinishedStillWorks() {
    let book = addBook("book")
    dataManager.saveContext()

    sut.markAsFinished(flag: true, relativePath: book.relativePath)
    dataManager.saveContext()

    XCTAssertEqual(filterPaths(for: .finished), [book.relativePath])
  }

  /// Finished and abandoned are exclusive the other way too: an explicit
  /// "finished" clears the DNF flag, so an item can't sit in both groups
  func testMarkAsFinishedClearsDidNotFinish() {
    let book = addBook("book", currentTime: 50, didNotFinish: true)
    dataManager.saveContext()

    sut.markAsFinished(flag: true, relativePath: book.relativePath)
    dataManager.saveContext()

    XCTAssertEqual(filterPaths(for: .finished), [book.relativePath])
    XCTAssertEqual(filterPaths(for: .didNotFinish), [])
  }

  func testUpdateNotePersists() {
    let book = addBook("book")
    dataManager.saveContext()

    sut.updateNote("interesting mid-book", at: book.relativePath)
    dataManager.saveContext()

    let item = sut.getItem(with: book.relativePath)
    XCTAssertEqual(item?.note, "interesting mid-book")

    sut.updateNote(nil, at: book.relativePath)
    dataManager.saveContext()

    XCTAssertNil(sut.getItem(with: book.relativePath)?.note)
  }
}
