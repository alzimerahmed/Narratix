//
//  LibraryBackupServiceTests.swift
//  BookPlayerTests
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import XCTest

@testable import BookPlayer
@testable import BookPlayerKit

/// The backup round trip: export serializes the library's metadata, restore
/// writes it back onto matching items and reports what it skipped.
@MainActor
final class LibraryBackupServiceTests: XCTestCase {
  private var libraryService: LibraryService!
  private var sut: LibraryBackupService!

  override func setUpWithError() throws {
    try super.setUpWithError()
    DataTestUtils.clearFolderContents(url: DataManager.getProcessedFolderURL())
    libraryService = LibraryService()
    libraryService.setup(
      dataManager: DataManager(coreDataStack: CoreDataStack(testPath: "/dev/null")),
      audioMetadataService: AudioMetadataService()
    )
    _ = libraryService.getLibrary()
    sut = LibraryBackupService(libraryService: libraryService)
  }

  override func tearDown() {
    DataTestUtils.clearFolderContents(url: DataManager.getProcessedFolderURL())
    super.tearDown()
  }

  @discardableResult
  private func addBook(title: String, duration: Double = 100) -> Book {
    let book = StubFactory.book(dataManager: libraryService.dataManager, title: title, duration: duration)
    libraryService.getLibraryReference().addToItems(book)
    libraryService.dataManager.saveContext()
    return book
  }

  // MARK: - Export

  func testExportOnEmptyLibraryThrows() {
    XCTAssertThrowsError(try sut.export()) { error in
      XCTAssertEqual(error as? LibraryBackupError, .emptyLibrary)
    }
  }

  func testExportCapturesItemState() throws {
    let book = addBook(title: "Dune", duration: 3600)
    libraryService.markAsFinished(flag: true, relativePath: book.relativePath)
    libraryService.markAsDidNotFinish(flag: true, relativePath: book.relativePath)
    libraryService.updateNote("a note", at: book.relativePath)
    libraryService.updateSeriesInfo(name: "Dune Saga", order: 1, at: book.relativePath)
    _ = libraryService.createBookmark(at: 60, relativePath: book.relativePath, uuid: "bm1", type: .user)
    libraryService.setLibraryLastBook(with: book.relativePath)

    let backup = try sut.export()

    XCTAssertEqual(backup.formatVersion, LibraryBackup.currentFormatVersion)
    XCTAssertEqual(backup.library.items.count, 1)
    let record = try XCTUnwrap(backup.library.items.first)
    XCTAssertEqual(record.title, "Dune")
    XCTAssertTrue(record.isFinished)
    XCTAssertTrue(record.didNotFinish)
    XCTAssertEqual(record.note, "a note")
    XCTAssertEqual(record.seriesName, "Dune Saga")
    XCTAssertEqual(record.seriesOrder, 1)
    XCTAssertEqual(backup.library.bookmarks.count, 1)
    XCTAssertEqual(backup.library.bookmarks.first?.type, "user")
    XCTAssertEqual(backup.library.lastPlayedPath, book.relativePath)
  }

  // MARK: - Restore

  func testRestoreAppliesProgressNotesAndCollections() throws {
    let book = addBook(title: "Dune", duration: 3600)

    let backup = LibraryBackup(
      formatVersion: 1,
      createdAt: Date(),
      app: "test",
      appVersion: nil,
      library: .init(
        lastPlayedPath: book.relativePath,
        items: [
          .init(
            uuid: book.uuid,
            relativePath: book.relativePath,
            type: "book",
            title: "Dune",
            details: "Frank Herbert",
            originalFileName: "Dune.m4b",
            duration: 3600,
            currentTime: 900,
            percentCompleted: 25,
            isFinished: false,
            didNotFinish: false,
            note: "halfway",
            seriesName: "Dune Saga",
            seriesOrder: 1,
            speed: 1.5,
            lastPlayDate: Date(),
            orderRank: 0
          )
        ],
        bookmarks: [
          .init(time: 120, type: "user", note: "here", itemUuid: book.uuid, itemPath: book.relativePath)
        ],
        collections: [
          .init(uuid: "col-1", title: "Sci-fi", itemPaths: [book.relativePath], itemUuids: [book.uuid])
        ]
      )
    )

    let report = sut.restore(backup)

    XCTAssertEqual(report.itemsUpdated, 1)
    XCTAssertEqual(report.bookmarksCreated, 1)
    XCTAssertEqual(report.collectionsRestored, 1)
    XCTAssertTrue(report.skipped.isEmpty)

    let restored = libraryService.getSimpleItem(with: book.relativePath)!
    XCTAssertEqual(restored.currentTime, 900)
    XCTAssertEqual(restored.speed, 1.5)
    XCTAssertEqual(restored.note, "halfway")
    XCTAssertEqual(restored.seriesName, "Dune Saga")
    XCTAssertEqual(restored.seriesOrder, 1)
    XCTAssertEqual(restored.details, "Frank Herbert")

    let bookmarks = libraryService.getBookmarks(of: .user, relativePath: book.relativePath) ?? []
    XCTAssertEqual(bookmarks.count, 1)
    XCTAssertEqual(bookmarks.first?.note, "here")

    let collections = libraryService.fetchCollections()
    XCTAssertEqual(collections.count, 1)
    XCTAssertEqual(collections.first?.title, "Sci-fi")
    let members = libraryService.fetchCollectionItems(uuid: collections.first!.uuid)
    XCTAssertEqual(members.map(\.relativePath), [book.relativePath])

    XCTAssertEqual(libraryService.getLibraryLastItem()?.relativePath, book.relativePath)
  }

  /// Terminal-forward only: a `false` flag or absent metadata in the backup
  /// never clears what this device already has — folder records would cascade
  /// the regression into every descendant
  func testRestoreNeverRegressesFlagsOrMetadata() async throws {
    let book = addBook(title: "Dune", duration: 3600)
    libraryService.markAsFinished(flag: true, relativePath: book.relativePath)
    libraryService.updateNote("keep me", at: book.relativePath)
    libraryService.updateSeriesInfo(name: "Dune Saga", order: 2, at: book.relativePath)

    let backup = LibraryBackup(
      formatVersion: 1,
      createdAt: Date(),
      app: "test",
      appVersion: nil,
      library: .init(
        lastPlayedPath: nil,
        items: [
          .init(
            uuid: book.uuid, relativePath: book.relativePath, type: "book",
            title: "Dune", details: "", originalFileName: "", duration: 3600,
            currentTime: 0, percentCompleted: 0, isFinished: false,
            didNotFinish: false, note: nil, seriesName: nil, seriesOrder: nil,
            speed: 1, lastPlayDate: nil, orderRank: 0
          )
        ],
        bookmarks: [],
        collections: []
      )
    )

    _ = await sut.restore(backup)

    let restored = libraryService.getSimpleItem(with: book.relativePath)!
    XCTAssertTrue(restored.isFinished)
    XCTAssertEqual(restored.note, "keep me")
    XCTAssertEqual(restored.seriesName, "Dune Saga")
    XCTAssertEqual(restored.seriesOrder, 2)
  }

  /// A backup that knows about a book the library doesn't must skip it, and a
  /// path match still finds an item whose uuid changed on re-import
  func testRestoreMatchesByPathAndSkipsUnknownItems() async throws {
    let book = addBook(title: "Dune", duration: 3600)

    let backup = LibraryBackup(
      formatVersion: 1,
      createdAt: Date(),
      app: "test",
      appVersion: nil,
      library: .init(
        lastPlayedPath: nil,
        items: [
          .init(
            uuid: "no-such-uuid",
            relativePath: book.relativePath,
            type: "book",
            title: "Dune",
            details: "",
            originalFileName: "",
            duration: 3600,
            currentTime: 500,
            percentCompleted: 14,
            isFinished: true,
            didNotFinish: false,
            note: nil,
            seriesName: nil,
            seriesOrder: nil,
            speed: 1,
            lastPlayDate: nil,
            orderRank: 0
          ),
          .init(
            uuid: "gone",
            relativePath: "gone.m4b",
            type: "book",
            title: "Ghost",
            details: "",
            originalFileName: "",
            duration: 1,
            currentTime: 1,
            percentCompleted: 100,
            isFinished: true,
            didNotFinish: false,
            note: nil,
            seriesName: nil,
            seriesOrder: nil,
            speed: 1,
            lastPlayDate: nil,
            orderRank: 0
          ),
        ],
        bookmarks: [],
        collections: []
      )
    )

    let report = sut.restore(backup)

    XCTAssertEqual(report.itemsUpdated, 1)
    XCTAssertEqual(report.skipped, ["Ghost"])

    let restored = libraryService.getSimpleItem(with: book.relativePath)!
    XCTAssertEqual(restored.currentTime, 500)
    XCTAssertTrue(restored.isFinished)
  }

  /// Restoring is idempotent: a second run creates no duplicate bookmark
  func testRestoreIsIdempotent() throws {
    let book = addBook(title: "Dune", duration: 3600)
    let backup = LibraryBackup(
      formatVersion: 1,
      createdAt: Date(),
      app: "test",
      appVersion: nil,
      library: .init(
        lastPlayedPath: nil,
        items: [
          .init(
            uuid: book.uuid, relativePath: book.relativePath, type: "book",
            title: "Dune", details: "", originalFileName: "", duration: 3600,
            currentTime: 0, percentCompleted: 0, isFinished: false,
            didNotFinish: false, note: nil, seriesName: nil, seriesOrder: nil,
            speed: 1, lastPlayDate: nil, orderRank: 0
          )
        ],
        bookmarks: [
          .init(time: 42, type: "user", note: nil, itemUuid: book.uuid, itemPath: book.relativePath)
        ],
        collections: [
          .init(uuid: "c", title: "Sci-fi", itemPaths: [book.relativePath], itemUuids: [book.uuid])
        ]
      )
    )

    _ = sut.restore(backup)
    let second = sut.restore(backup)

    XCTAssertEqual(second.bookmarksCreated, 0)
    XCTAssertEqual(libraryService.getBookmarks(of: .user, relativePath: book.relativePath)?.count, 1)
    XCTAssertEqual(libraryService.fetchCollections().count, 1)
  }

  func testNewerFormatVersionIsRejected() throws {
    let backup = LibraryBackup(
      formatVersion: 99, createdAt: Date(), app: "test", appVersion: nil,
      library: .init(lastPlayedPath: nil, items: [], bookmarks: [], collections: [])
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("future.json")
    try encoder.encode(backup).write(to: url)

    XCTAssertThrowsError(try sut.loadBackup(from: url)) { error in
      XCTAssertEqual(error as? LibraryBackupError, .unsupportedFormat(99))
    }
  }
}
