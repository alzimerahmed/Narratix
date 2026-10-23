//
//  LibraryCollectionsTests.swift
//  BookPlayerTests
//
//  Created by Gianni Carlo on 12/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

@testable import Narratix
@testable import BookPlayerKit
import CoreData
import XCTest

/// Collections CRUD/membership + series metadata + browse grouping.
/// Main actor: the service and the library's view context are main-queue bound
/// (same rationale as `LibraryServiceTests`).
@MainActor
final class LibraryCollectionsTests: XCTestCase {
  var dataManager: DataManager!
  var libraryService: LibraryService!

  override func setUp() {
    DataTestUtils.clearFolderContents(url: DataManager.getProcessedFolderURL())
    dataManager = DataManager(coreDataStack: CoreDataStack(testPath: "/dev/null"))
    libraryService = LibraryService()
    libraryService.setup(dataManager: dataManager, audioMetadataService: AudioMetadataService())
    _ = libraryService.getLibrary()
  }

  private func addBook(_ title: String, author: String = "test-author") -> Book {
    let book = StubFactory.book(dataManager: dataManager, title: title, duration: 100)
    book.details = author
    libraryService.getLibraryReference().addToItems(book)
    dataManager.saveContext()
    return book
  }

  // MARK: - CRUD

  func testCreateFetchAndDeleteCollection() {
    let created = libraryService.createCollection(title: "  Favorites  ")
    XCTAssertNotNil(created)
    XCTAssertEqual(created?.title, "Favorites")
    XCTAssertTrue(!created!.uuid.isEmpty)

    XCTAssertEqual(libraryService.fetchCollections().map(\.title), ["Favorites"])

    libraryService.deleteCollection(uuid: created!.uuid)
    XCTAssertTrue(libraryService.fetchCollections().isEmpty)
  }

  func testCreateRejectsEmptyTitle() {
    XCTAssertNil(libraryService.createCollection(title: "   "))
    XCTAssertTrue(libraryService.fetchCollections().isEmpty)
  }

  func testRenameCollection() {
    let collection = libraryService.createCollection(title: "Old")!

    libraryService.renameCollection(uuid: collection.uuid, title: "  New Name  ")

    let fetched = libraryService.fetchCollections()
    XCTAssertEqual(fetched.count, 1)
    XCTAssertEqual(fetched.first?.title, "New Name")
    /// Identity survives renames — the uuid is what the UI tracks
    XCTAssertEqual(fetched.first?.uuid, collection.uuid)
  }

  func testFetchCollectionsSortedByTitle() {
    _ = libraryService.createCollection(title: "Zulu")
    _ = libraryService.createCollection(title: "Alpha")

    XCTAssertEqual(libraryService.fetchCollections().map(\.title), ["Alpha", "Zulu"])
  }

  // MARK: - Membership

  func testItemCanBelongToManyCollections() {
    let book = addBook("book-1")
    let a = libraryService.createCollection(title: "A")!
    let b = libraryService.createCollection(title: "B")!

    libraryService.addToCollection(uuid: a.uuid, items: [book.relativePath!])
    libraryService.addToCollection(uuid: b.uuid, items: [book.relativePath!])

    XCTAssertEqual(
      Set(libraryService.fetchCollections(containing: book.relativePath!).map(\.uuid)),
      [a.uuid, b.uuid]
    )
  }

  func testAddRemoveMembership() {
    let book = addBook("book-1")
    let other = addBook("book-2")
    let collection = libraryService.createCollection(title: "Shelf")!

    libraryService.addToCollection(uuid: collection.uuid, items: [book.relativePath!, other.relativePath!])
    /// Set semantics — adding twice stays put
    libraryService.addToCollection(uuid: collection.uuid, items: [book.relativePath!])

    var items = libraryService.fetchCollectionItems(uuid: collection.uuid)
    XCTAssertEqual(items.count, 2)

    libraryService.removeFromCollection(uuid: collection.uuid, items: [book.relativePath!])
    items = libraryService.fetchCollectionItems(uuid: collection.uuid)
    XCTAssertEqual(items.map(\.relativePath), [other.relativePath])
  }

  func testCollectionMembershipReportsSelectedSubset() {
    let book = addBook("book-1")
    let other = addBook("book-2")
    let collection = libraryService.createCollection(title: "Shelf")!

    libraryService.addToCollection(uuid: collection.uuid, items: [book.relativePath!])

    XCTAssertEqual(
      libraryService.collectionMembership(
        uuid: collection.uuid,
        of: [book.relativePath!, other.relativePath!, "missing/path"]
      ),
      [book.relativePath!]
    )
  }

  func testDeleteCollectionKeepsItems() {
    let book = addBook("book-1")
    let collection = libraryService.createCollection(title: "Shelf")!
    libraryService.addToCollection(uuid: collection.uuid, items: [book.relativePath!])

    libraryService.deleteCollection(uuid: collection.uuid)

    /// The shelf is gone; the book survives in the library
    XCTAssertNotNil(libraryService.getItem(with: book.relativePath!))
    XCTAssertTrue(libraryService.fetchCollections().isEmpty)
  }

  func testDeleteItemNullifiesMembership() {
    let book = addBook("book-1")
    /// Capture before the delete — the deleted object faults its properties
    let path = book.relativePath!
    let collection = libraryService.createCollection(title: "Shelf")!
    libraryService.addToCollection(uuid: collection.uuid, items: [path])

    dataManager.getContext().delete(book)
    dataManager.saveContext()

    XCTAssertTrue(libraryService.fetchCollectionItems(uuid: collection.uuid).isEmpty)
    XCTAssertTrue(libraryService.fetchCollections(containing: path).isEmpty)
  }

  // MARK: - Series metadata

  func testUpdateSeriesInfo() {
    let book = addBook("book-1")

    libraryService.updateSeriesInfo(name: "  Mistborn  ", order: 2.5, at: book.relativePath!)

    let item = libraryService.getItem(with: book.relativePath!)
    XCTAssertEqual(item?.seriesName, "Mistborn")
    XCTAssertEqual(item?.seriesOrder?.doubleValue, 2.5)
  }

  func testClearingSeriesNameClearsOrderToo() {
    let book = addBook("book-1")
    libraryService.updateSeriesInfo(name: "Mistborn", order: 2, at: book.relativePath!)

    libraryService.updateSeriesInfo(name: nil, order: 4, at: book.relativePath!)

    let item = libraryService.getItem(with: book.relativePath!)
    XCTAssertNil(item?.seriesName)
    /// A book number without a series is meaningless — cleared together
    XCTAssertNil(item?.seriesOrder)
  }

  func testSeriesGroupsOrderedByBookNumber() {
    let first = addBook("book-1")
    let second = addBook("book-2")
    let unordered = addBook("book-3")

    libraryService.updateSeriesInfo(name: "Mistborn", order: 2, at: second.relativePath!)
    libraryService.updateSeriesInfo(name: "Mistborn", order: 1, at: first.relativePath!)
    libraryService.updateSeriesInfo(name: "Mistborn", order: nil, at: unordered.relativePath!)

    let groups = libraryService.fetchSeriesGroups()
    XCTAssertEqual(groups.count, 1)
    XCTAssertEqual(groups.first?.name, "Mistborn")
    /// Ordered by book number, unordered last
    XCTAssertEqual(
      groups.first?.items.map(\.relativePath),
      [first.relativePath!, second.relativePath!, unordered.relativePath!]
    )
  }

  func testSeriesGroupsSkipUntaggedItems() {
    _ = addBook("book-1")
    XCTAssertTrue(libraryService.fetchSeriesGroups().isEmpty)
  }

  // MARK: - Author groups

  func testAuthorGroups() throws {
    let book = addBook("book-1", author: "Andy Weir")
    _ = addBook("book-2", author: "Andy Weir")
    _ = addBook("book-3", author: "Ursula K. Le Guin")

    /// A bound volume's `details` is a generated contents summary
    /// ("N files"), not an author — it must never leak into the groups
    let bound = try StubFactory.folder(dataManager: dataManager, title: "collected-works")
    bound.type = .bound
    bound.details = "5 files"
    libraryService.getLibraryReference().addToItems(bound)
    dataManager.saveContext()

    let groups = libraryService.fetchAuthorGroups()
    XCTAssertEqual(groups.map(\.name), ["Andy Weir", "Ursula K. Le Guin"])
    XCTAssertEqual(groups.first?.items.count, 2)
    XCTAssertEqual(groups.first?.items.first?.relativePath, book.relativePath)
  }

  // MARK: - Filename heuristic

  func testSeriesHintParenthesized() {
    let hint = AudioMetadataService.parseSeriesHint(from: "The Way of Kings (Stormlight Archive, Book 1).m4b")
    XCTAssertEqual(hint.name, "Stormlight Archive")
    XCTAssertEqual(hint.order, 1)
  }

  func testSeriesHintDashDelimited() {
    let hint = AudioMetadataService.parseSeriesHint(from: "Mistborn - Book 2 - The Well of Ascension.m4b")
    XCTAssertEqual(hint.name, "Mistborn")
    XCTAssertEqual(hint.order, 2)
  }

  func testSeriesHintAuthorSeriesTitle() {
    let hint = AudioMetadataService.parseSeriesHint(from: "Brandon Sanderson - Mistborn - Book 1 - The Final Empire.m4b")
    /// The segment immediately before "Book N" is the series, not the author
    XCTAssertEqual(hint.name, "Mistborn")
    XCTAssertEqual(hint.order, 1)
  }

  func testSeriesHintHashNumber() {
    let hint = AudioMetadataService.parseSeriesHint(from: "Dune #1.5.m4b")
    XCTAssertEqual(hint.name, "Dune")
    XCTAssertEqual(hint.order, 1.5)
  }

  func testSeriesHintSplitFileNotMisread() {
    /// "Part" is file-chunk naming, not series numbering — deliberately unmatched
    let hint = AudioMetadataService.parseSeriesHint(from: "The Hobbit Part 1.m4b")
    XCTAssertNil(hint.name)
    XCTAssertNil(hint.order)
  }

  func testSeriesHintEmbeddedWordNotMisread() {
    /// "book"/"vol" inside a longer word is not a series marker — "Workbook 3"
    /// and "Facebook 2024" must not parse as "Book 3"
    for fileName in ["Workbook 3.m4b", "Facebook 2024.m4b", "Anthology (Workbook 2).m4b"] {
      let hint = AudioMetadataService.parseSeriesHint(from: fileName)
      XCTAssertNil(hint.name, fileName)
      XCTAssertNil(hint.order, fileName)
    }
  }

  func testSeriesHintUnrelatedFilename() {
    let hint = AudioMetadataService.parseSeriesHint(from: "The Hobbit.m4b")
    XCTAssertNil(hint.name)
    XCTAssertNil(hint.order)
  }
}
