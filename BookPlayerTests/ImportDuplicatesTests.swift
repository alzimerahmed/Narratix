//
//  ImportDuplicatesTests.swift
//  BookPlayerTests
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import XCTest

@testable import BookPlayer
@testable import BookPlayerKit

/// `ImportDuplicateDetector` catches an import that reproduces a book the
/// library already has — same normalized title, duration inside the tolerance —
/// without flagging the import against itself or against different books.
@MainActor
final class ImportDuplicatesTests: XCTestCase {
  private var libraryService: LibraryService!

  override func setUpWithError() throws {
    try super.setUpWithError()
    DataTestUtils.clearFolderContents(url: DataManager.getProcessedFolderURL())
    libraryService = LibraryService()
    libraryService.setup(
      dataManager: DataManager(coreDataStack: CoreDataStack(testPath: "/dev/null")),
      audioMetadataService: AudioMetadataService()
    )
    _ = libraryService.getLibrary()
  }

  override func tearDown() {
    DataTestUtils.clearFolderContents(url: DataManager.getProcessedFolderURL())
    super.tearDown()
  }

  private func libraryBook(title: String, duration: Double) -> Book {
    let book = StubFactory.book(dataManager: libraryService.dataManager, title: title, duration: duration)
    libraryService.getLibraryReference().addToItems(book)
    libraryService.dataManager.saveContext()
    return book
  }

  private func book(_ title: String, duration: Double, path: String) -> SimpleLibraryItem {
    SimpleLibraryItem(
      title: title,
      details: "",
      speed: 1,
      currentTime: 0,
      duration: duration,
      percentCompleted: 0,
      isFinished: false,
      relativePath: path,
      remoteURL: nil,
      artworkURL: nil,
      orderRank: 0,
      parentFolder: nil,
      originalFileName: "\(path).mp3",
      lastPlayDate: nil,
      type: .book,
      uuid: UUID().uuidString
    )
  }

  // MARK: - Matching rules

  func testDurationsMatchWithinTolerance() {
    XCTAssertTrue(ImportDuplicateDetector.durationsMatch(100, 102))
    XCTAssertTrue(ImportDuplicateDetector.durationsMatch(3600, 3670))
    XCTAssertFalse(ImportDuplicateDetector.durationsMatch(3600, 3700))
    XCTAssertFalse(ImportDuplicateDetector.durationsMatch(10, 60))
  }

  func testNormalizedIgnoresCaseAndDiacritics() {
    XCTAssertEqual(
      ImportDuplicateDetector.normalized("  Les Misérables "),
      ImportDuplicateDetector.normalized("les miserables")
    )
    XCTAssertNotEqual(
      ImportDuplicateDetector.normalized("Book One"),
      ImportDuplicateDetector.normalized("Book Two")
    )
  }

  // MARK: - Detection

  func testImportMatchingLibraryBookIsFlagged() {
    _ = libraryBook(title: "The Way of Kings", duration: 162000)

    let imported = [book("The Way of Kings", duration: 162030, path: "way-of-kings-copy.m4b")]
    let matches = ImportDuplicateDetector.findDuplicates(of: imported, libraryService: libraryService)

    XCTAssertEqual(matches.count, 1)
    XCTAssertEqual(matches.first?.existing.relativePath, "The Way of Kings.txt")
  }

  func testSameTitleDifferentDurationIsNotFlagged() {
    _ = libraryBook(title: "The Way of Kings", duration: 162000)

    let imported = [book("The Way of Kings", duration: 300, path: "sample.m4b")]
    XCTAssertTrue(ImportDuplicateDetector.findDuplicates(of: imported, libraryService: libraryService).isEmpty)
  }

  func testDifferentTitleIsNotFlagged() {
    _ = libraryBook(title: "The Way of Kings", duration: 162000)

    let imported = [book("Rhythm of War", duration: 162000, path: "row.m4b")]
    XCTAssertTrue(ImportDuplicateDetector.findDuplicates(of: imported, libraryService: libraryService).isEmpty)
  }

  /// The import's own rows are excluded from the "existing" side, so a batch
  /// of same-titled books can't flag each other
  func testImportDoesNotMatchItself() {
    let one = libraryBook(title: "Part One", duration: 100)
    let two = libraryBook(title: "Part Two", duration: 100)
    /// Same title + duration as each other — the only reason nothing matches
    /// is that both paths are the import's
    two.title = "Part One"
    libraryService.dataManager.saveContext()

    let imported = [
      libraryService.getSimpleItem(with: one.relativePath)!,
      libraryService.getSimpleItem(with: two.relativePath)!,
    ]
    XCTAssertTrue(ImportDuplicateDetector.findDuplicates(of: imported, libraryService: libraryService).isEmpty)
  }

  /// A folder row carries its books — a book inside an imported folder still
  /// matches a library book
  func testBooksInsideImportedFolderAreChecked() throws {
    _ = libraryBook(title: "Chapter 1", duration: 60)

    let folder = try StubFactory.folder(dataManager: libraryService.dataManager, title: "Dropped")
    libraryService.getLibraryReference().addToItems(folder)
    let nested = StubFactory.book(dataManager: libraryService.dataManager, title: "Chapter 1", duration: 60)
    nested.relativePath = "Dropped/ch1.m4b"
    folder.addToItems(nested)
    libraryService.dataManager.saveContext()

    let folderItem = libraryService.getSimpleItem(with: folder.relativePath)!
    let matches = ImportDuplicateDetector.findDuplicates(of: [folderItem], libraryService: libraryService)

    XCTAssertEqual(matches.count, 1)
    XCTAssertEqual(matches.first?.imported.relativePath, "Dropped/ch1.m4b")
    XCTAssertEqual(matches.first?.existing.relativePath, "Chapter 1.txt")
  }
}
