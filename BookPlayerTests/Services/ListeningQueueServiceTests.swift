//
//  ListeningQueueServiceTests.swift
//  BookPlayerTests
//
//  Created by Gianni Carlo on 12/5/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

@testable import BookPlayer
@testable import BookPlayerKit
import CoreData
import XCTest

/// Main actor: the service and the library's view context are main-queue bound
/// (same rationale as `LibraryServiceTests`).
@MainActor
final class ListeningQueueServiceTests: XCTestCase {
  var dataManager: DataManager!
  var libraryService: LibraryService!
  var sut: ListeningQueueService!

  override func setUp() {
    DataTestUtils.clearFolderContents(url: DataManager.getProcessedFolderURL())
    dataManager = DataManager(coreDataStack: CoreDataStack(testPath: "/dev/null"))
    libraryService = LibraryService()
    libraryService.setup(dataManager: dataManager, audioMetadataService: AudioMetadataService())
    _ = libraryService.getLibrary()
    sut = ListeningQueueService()
    sut.setup(dataManager: dataManager, libraryService: libraryService)
  }

  private func addBook(_ title: String) -> Book {
    let book = StubFactory.book(dataManager: dataManager, title: title, duration: 100)
    libraryService.getLibraryReference().addToItems(book)
    dataManager.saveContext()
    return book
  }

  private func queuedPaths() -> [String] {
    sut.fetchQueue().map(\.relativePath)
  }

  func testQueueStartsEmpty() {
    XCTAssertEqual(queuedPaths(), [])
    XCTAssertEqual(sut.count(), 0)
  }

  func testEnqueueAppendsInOrder() {
    let a = addBook("a-book")
    let b = addBook("b-book")

    sut.enqueue(a.relativePath)
    sut.enqueue(b.relativePath)

    XCTAssertEqual(queuedPaths(), [a.relativePath, b.relativePath])
    XCTAssertTrue(sut.isQueued(relativePath: b.relativePath))
  }

  func testEnqueueDeduplicatesKeepingOriginalPosition() {
    let a = addBook("a-book")
    let b = addBook("b-book")

    sut.enqueue(a.relativePath)
    sut.enqueue(b.relativePath)
    sut.enqueue(a.relativePath)

    XCTAssertEqual(queuedPaths(), [a.relativePath, b.relativePath])
    XCTAssertEqual(sut.count(), 2)
  }

  func testEnqueueNextMovesToHead() {
    let a = addBook("a-book")
    let b = addBook("b-book")
    let c = addBook("c-book")

    sut.enqueue(a.relativePath)
    sut.enqueue(b.relativePath)
    sut.enqueueNext(c.relativePath)
    sut.enqueueNext(b.relativePath)

    XCTAssertEqual(queuedPaths(), [b.relativePath, c.relativePath, a.relativePath])
  }

  func testMoveReordersAndRenumbers() {
    let a = addBook("a-book")
    let b = addBook("b-book")
    let c = addBook("c-book")
    sut.enqueue(a.relativePath)
    sut.enqueue(b.relativePath)
    sut.enqueue(c.relativePath)

    sut.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)

    XCTAssertEqual(queuedPaths(), [b.relativePath, c.relativePath, a.relativePath])
  }

  func testRemoveClosesGaps() {
    let a = addBook("a-book")
    let b = addBook("b-book")
    let c = addBook("c-book")
    sut.enqueue(a.relativePath)
    sut.enqueue(b.relativePath)
    sut.enqueue(c.relativePath)

    sut.remove(b.relativePath)

    XCTAssertEqual(queuedPaths(), [a.relativePath, c.relativePath])
    XCTAssertFalse(sut.isQueued(relativePath: b.relativePath))
  }

  func testRemoveAll() {
    let a = addBook("a-book")
    let b = addBook("b-book")
    let c = addBook("c-book")
    sut.enqueue(a.relativePath)
    sut.enqueue(b.relativePath)
    sut.enqueue(c.relativePath)

    sut.removeAll([a.relativePath, c.relativePath])

    XCTAssertEqual(queuedPaths(), [b.relativePath])
  }

  func testDequeueNextReturnsHeadAndRemovesIt() {
    let a = addBook("a-book")
    let b = addBook("b-book")
    sut.enqueue(a.relativePath)
    sut.enqueue(b.relativePath)

    let next = sut.dequeueNext()

    XCTAssertEqual(next?.relativePath, a.relativePath)
    XCTAssertEqual(queuedPaths(), [b.relativePath])
  }

  func testDequeueNextSkipsStaleEntry() {
    let a = addBook("a-book")
    let b = addBook("b-book")
    sut.enqueue(a.relativePath)
    sut.enqueue(b.relativePath)

    /// A book deleted while queued must not block the queue — the head row is
    /// freed and the next entry comes up
    dataManager.getContext().delete(a)
    dataManager.saveContext()

    let next = sut.dequeueNext()

    XCTAssertEqual(next?.relativePath, b.relativePath)
    XCTAssertEqual(sut.count(), 0)
  }

  func testFetchQueueDropsStaleRows() {
    let a = addBook("a-book")
    sut.enqueue(a.relativePath)

    dataManager.getContext().delete(a)
    dataManager.saveContext()

    XCTAssertEqual(queuedPaths(), [])
    XCTAssertEqual(sut.count(), 0)
  }

  func testEnqueueUnknownPathIsIgnored() {
    sut.enqueue("no/such/book.m4b")

    XCTAssertEqual(sut.count(), 0)
  }

  func testClearEmptiesTheQueue() {
    let a = addBook("a-book")
    let b = addBook("b-book")
    sut.enqueue(a.relativePath)
    sut.enqueue(b.relativePath)

    sut.clear()

    XCTAssertEqual(queuedPaths(), [])
  }

  /// Folder rows are queued as-is — enqueue is filtered to playable items by
  /// the callers; a folder at the head simply resolves to nothing at
  /// playback time
  func testEnqueueFolderDoesNotCrash() throws {
    let folder = try StubFactory.folder(dataManager: dataManager, title: "test-folder")
    libraryService.getLibraryReference().addToItems(folder)
    dataManager.saveContext()

    sut.enqueue(folder.relativePath)

    XCTAssertTrue(sut.isQueued(relativePath: folder.relativePath))
    /// The service returns the entry as queued — the folder-vs-book choice is
    /// the player's (`playNextItem` consumes it and falls through, since a
    /// folder isn't playable); the row still leaves the queue
    XCTAssertEqual(sut.dequeueNext()?.relativePath, folder.relativePath)
    XCTAssertEqual(sut.count(), 0)
  }
}
