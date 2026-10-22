//
//  BackupViewModel.swift
//  BookPlayer
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// `FileDocument` wrapper for the JSON backup — drives `.fileExporter`
struct LibraryBackupDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }

  var data: Data

  init(data: Data) {
    self.data = data
  }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw LibraryBackupError.unreadableFile
    }
    self.data = data
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

/// Backs `BackupView`: export to Files/share sheet, restore from a picked or
/// saved backup, and the history of backups the app keeps on device.
@MainActor
final class BackupViewModel: ObservableObject, BPLogger {
  /// Concrete `LibraryService` in, not the protocol — the backup service is
  /// app-layer and the indirection bought nothing here
  let service: LibraryBackupService

  /// Non-nil while the export sheet is up; the document feeds `.fileExporter`
  @Published var exportDocument: LibraryBackupDocument?
  @Published var exporting = false
  @Published var importing = false
  @Published var restoreConfirmation: LibraryBackup?
  /// The URL a restore confirmation came from — shown in the dialog
  @Published private(set) var restoreSourceName: String?
  @Published var lastReport: LibraryRestoreReport?
  /// Backup files already sitting in the app's library-backup folder
  @Published private(set) var savedBackups: [URL] = []
  @Published var error: Error?
  @Published var isWorking = false

  init(libraryService: LibraryService) {
    self.service = LibraryBackupService(libraryService: libraryService)
  }

  func prepareExport() {
    do {
      let backup = try service.export()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      exportDocument = LibraryBackupDocument(data: try encoder.encode(backup))
      exporting = true
    } catch {
      self.error = error
    }
  }

  /// The copy the app keeps for itself in its backup folder — runs after the
  /// export sheet finishes so a canceled save still leaves one on device
  func recordLocalCopy() {
    guard exportDocument != nil else { return }
    do {
      _ = try service.exportFile()
    } catch {
      Self.logger.error("Local backup copy failed: \(error.localizedDescription)")
    }
    exportDocument = nil
    refreshSavedBackups()
  }

  func refreshSavedBackups() {
    let folder = DataManager.getLibraryBackupFolderURL()
    let contents = (try? FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    )) ?? []
    savedBackups = contents
      .filter { $0.pathExtension.lowercased() == "json" }
      .sorted { $0.lastPathComponent > $1.lastPathComponent }
  }

  /// Read the picked/saved file and stage the confirmation — the restore only
  /// runs once the user confirms
  func stageRestore(from url: URL) {
    do {
      restoreConfirmation = try service.loadBackup(from: url)
      restoreSourceName = url.lastPathComponent
    } catch {
      self.error = error
    }
  }

  func confirmRestore() async {
    guard let backup = restoreConfirmation else { return }
    restoreConfirmation = nil
    isWorking = true
    let report = await service.restore(backup)
    isWorking = false
    lastReport = report
  }

  var defaultFilename: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HHmmss"
    return "Narratix-Backup-\(formatter.string(from: Date()))"
  }
}
