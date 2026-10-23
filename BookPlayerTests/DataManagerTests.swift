//
//  DataManagerTests.swift
//  BookPlayerTests
//
//  Created by Gianni Carlo on 5/18/18.
//  Copyright © 2018 BookPlayer LLC. All rights reserved.
//

@testable import Narratix
@testable import BookPlayerKit
import Combine
import CoreData
import XCTest

class DataManagerTests: XCTestCase {
  var dataManager: DataManager!

  override func setUp() {
    super.setUp()
    self.dataManager = DataManager(coreDataStack: CoreDataStack(testPath: "/dev/null"))
    // Put setup code here. This method is called before the invocation of each test method in the class.
    let documentsFolder = DataManager.getDocumentsFolderURL()
    DataTestUtils.clearFolderContents(url: documentsFolder)
    let processedFolder = DataManager.getProcessedFolderURL()
    DataTestUtils.clearFolderContents(url: processedFolder)
  }
}

// MARK: - processFiles()

class ProcessFilesTests: DataManagerTests {
  var importManager: ImportManager!
  var subscription: AnyCancellable?

  override func setUp() {
    self.subscription?.cancel()
    super.setUp()
  }

  func testProcessOneFile() {
    let filename = "file.txt"
    let bookContents = "bookcontents".data(using: .utf8)!
    let documentsFolder = DataManager.getDocumentsFolderURL()

    // Add test file to Documents folder
    let fileUrl = DataTestUtils.generateTestFile(name: filename, contents: bookContents, destinationFolder: documentsFolder)

    let expectation = XCTestExpectation(description: "File import notification")

    let audioMetadataService = AudioMetadataService()
    let libraryService = LibraryService()
    libraryService.setup(dataManager: self.dataManager, audioMetadataService: audioMetadataService)
    self.importManager = ImportManager(libraryService: libraryService)

    self.subscription = self.importManager.observeFiles().sink { files in
      guard !files.isEmpty else { return }

      expectation.fulfill()
    }

    self.importManager.process(fileUrl)

    wait(for: [expectation], timeout: 15)
  }
}

/// Guards the v11→v12 manual migration: `shouldInferMappingModelAutomatically` is OFF,
/// so if the v12 `.xcdatamodel` is ever edited after `MappingModel_v11_to_v12` was
/// generated, the checksum mismatch makes `migrateStore` throw at launch for every
/// existing install. This must fail in CI first.
class MigrationV11ToV12Tests: XCTestCase {
  func testMappingModelMatchesModelsAndMigratesStore() throws {
    let v11 = DBVersion.v11.model()
    let v12 = DBVersion.v12.model()
    XCTAssertFalse(v11.entities.isEmpty, "v11 model failed to load from the bundle")
    XCTAssertFalse(v12.entities.isEmpty, "v12 model failed to load from the bundle")
    XCTAssertTrue(v12.entitiesByName.keys.contains("ExternalResource"))

    // The lookup validates BOTH sides' entity checksums — this is exactly what
    // breaks when a model is edited after its mapping model was generated
    let mapping = NSMappingModel(from: [Bundle.main], forSourceModel: v11, destinationModel: v12)
    let unwrappedMapping = try XCTUnwrap(mapping, "MappingModel_v11_to_v12 no longer matches the v11/v12 models")

    // End-to-end: run a real v11 store through the migration and verify the
    // result opens as a v12 store
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let sourceURL = tempDir.appendingPathComponent("v11.sqlite")
    let destinationURL = tempDir.appendingPathComponent("v12.sqlite")

    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v11)
    let store = try coordinator.addPersistentStore(
      ofType: NSSQLiteStoreType,
      configurationName: nil,
      at: sourceURL,
      options: nil
    )
    try coordinator.remove(store)

    let manager = NSMigrationManager(sourceModel: v11, destinationModel: v12)
    try manager.migrateStore(
      from: sourceURL,
      sourceType: NSSQLiteStoreType,
      options: nil,
      with: unwrappedMapping,
      toDestinationURL: destinationURL,
      destinationType: NSSQLiteStoreType,
      destinationOptions: nil
    )

    let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
      ofType: NSSQLiteStoreType,
      at: destinationURL,
      options: nil
    )
    XCTAssertTrue(
      v12.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata),
      "migrated store is not compatible with the v12 model"
    )
  }
}

/// Guards the v12→v14 staged chain: v13 and v14 ship no `.cdm` mapping model,
/// so `migrateStoreAt` falls back to `NSMappingModel.inferredMappingModel` —
/// a model edit that breaks inference throws at launch for every install
/// more than a version behind. This must fail in CI first.
class MigrationV12ToV14Tests: XCTestCase {
  /// Name resolution + the inferred path are all these versions have
  func testV13AndV14ModelsLoadAndStayInferred() {
    let v13 = DBVersion.v13.model()
    let v14 = DBVersion.v14.model()
    XCTAssertFalse(v13.entities.isEmpty, "v13 model failed to load from the bundle")
    XCTAssertFalse(v14.entities.isEmpty, "v14 model failed to load from the bundle")
    /// A named mapping would take over from inference — flag it so this
    /// test's premise stays honest
    XCTAssertNil(DBVersion.v13.mappingModelName(), "v13 gained a mapping model — inference no longer runs")
    XCTAssertNil(DBVersion.v14.mappingModelName(), "v14 gained a mapping model — inference no longer runs")
  }

  /// A real v12 store walks v12→v13→v14 on inferred mappings and opens as
  /// v14 — the same steps a two-versions-behind install takes at launch
  func testV12StoreMigratesToV14OnInferredMappings() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    var storeURL = tempDir.appendingPathComponent("v12.sqlite")

    var model = DBVersion.v12.model()
    XCTAssertFalse(model.entities.isEmpty, "v12 model failed to load from the bundle")

    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
    let store = try coordinator.addPersistentStore(
      ofType: NSSQLiteStoreType,
      configurationName: nil,
      at: storeURL,
      options: nil
    )
    try coordinator.remove(store)

    for nextVersion in [DBVersion.v13, DBVersion.v14] {
      let nextModel = nextVersion.model()
      XCTAssertFalse(nextModel.entities.isEmpty, "\(nextVersion) model failed to load from the bundle")
      /// The launch path's fallback — no .cdm ships for these steps
      let mapping = try NSMappingModel.inferredMappingModel(
        forSourceModel: model,
        destinationModel: nextModel
      )
      let destinationURL = tempDir.appendingPathComponent("\(UUID().uuidString).sqlite")
      let manager = NSMigrationManager(sourceModel: model, destinationModel: nextModel)
      try manager.migrateStore(
        from: storeURL,
        sourceType: NSSQLiteStoreType,
        options: nil,
        with: mapping,
        toDestinationURL: destinationURL,
        destinationType: NSSQLiteStoreType,
        destinationOptions: nil
      )
      storeURL = destinationURL
      model = nextModel
    }

    let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
      ofType: NSSQLiteStoreType,
      at: storeURL,
      options: nil
    )
    XCTAssertTrue(
      model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata),
      "migrated store is not compatible with the v14 model"
    )
  }
}
