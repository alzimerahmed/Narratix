//
//  BackupView.swift
//  BookPlayer
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import SwiftUI

/// Settings → Backup: export the library's metadata to a JSON file, restore a
/// file back, and reuse backups the app has already written. Files only —
/// credentials and server links never enter a backup.
struct BackupView: View {
  @StateObject private var viewModel: BackupViewModel

  init(libraryService: LibraryService) {
    self._viewModel = .init(wrappedValue: BackupViewModel(libraryService: libraryService))
  }

  @EnvironmentObject private var theme: ThemeViewModel

  var body: some View {
    Form {
      ThemedSection {
        Button {
          viewModel.prepareExport()
        } label: {
          Label("backup_export_button", systemImage: "square.and.arrow.up")
            .foregroundStyle(theme.linkColor)
        }

        Button {
          viewModel.importing = true
        } label: {
          Label("backup_restore_button", systemImage: "square.and.arrow.down")
            .foregroundStyle(theme.linkColor)
        }
      } header: {
        Text("backup_section_title")
          .foregroundStyle(theme.secondaryColor)
      } footer: {
        Text("backup_description")
          .foregroundStyle(theme.secondaryColor)
      }

      if !viewModel.savedBackups.isEmpty {
        ThemedSection {
          ForEach(viewModel.savedBackups, id: \.self) { url in
            HStack {
              Button {
                viewModel.stageRestore(from: url)
              } label: {
                Text(url.deletingPathExtension().lastPathComponent)
                  .foregroundStyle(theme.primaryColor)
                  .lineLimit(1)
              }
              .accessibilityHint("backup_saved_restore_hint")
              Spacer()
              ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up")
                  .foregroundStyle(theme.linkColor)
              }
            }
          }
        } header: {
          Text("backup_saved_title")
            .foregroundStyle(theme.secondaryColor)
        }
      }
    }
    .applyListStyle(with: theme, background: theme.systemGroupedBackgroundColor)
    .navigationTitle("backup_section_title")
    .navigationBarTitleDisplayMode(.inline)
    .overlay {
      if viewModel.isWorking {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color.black.opacity(0.2))
      }
    }
    .fileExporter(
      isPresented: $viewModel.exporting,
      document: viewModel.exportDocument,
      contentType: .json,
      defaultFilename: viewModel.defaultFilename
    ) { _ in
      viewModel.recordLocalCopy()
    }
    .fileImporter(isPresented: $viewModel.importing, allowedContentTypes: [.json]) { result in
      if case .success(let url) = result {
        viewModel.stageRestore(from: url)
      }
    }
    .alert(
      "backup_restore_confirm_title",
      isPresented: Binding(
        get: { viewModel.restoreConfirmation != nil },
        set: { if !$0 { viewModel.restoreConfirmation = nil } }
      ),
      presenting: viewModel.restoreConfirmation
    ) { _ in
      Button("backup_restore_button") { viewModel.confirmRestore() }
      Button("cancel_button", role: .cancel) {}
    } message: { backup in
      Text(
        String.localizedStringWithFormat(
          "backup_restore_confirm_description".localized,
          backup.library.items.count,
          backup.library.bookmarks.count,
          backup.library.collections.count
        )
      )
    }
    .alert(
      "backup_report_title",
      isPresented: Binding(
        get: { viewModel.lastReport != nil },
        set: { if !$0 { viewModel.lastReport = nil } }
      ),
      presenting: viewModel.lastReport
    ) { _ in
      Button("ok_button", role: .cancel) {}
    } message: { report in
      Text(reportMessage(report))
    }
    .errorAlert(error: $viewModel.error)
    .onAppear { viewModel.refreshSavedBackups() }
  }

  private func reportMessage(_ report: LibraryRestoreReport) -> String {
    var text = String.localizedStringWithFormat(
      "backup_report_description".localized,
      report.itemsUpdated,
      report.bookmarksCreated,
      report.collectionsRestored
    )
    if !report.skipped.isEmpty {
      text += String.localizedStringWithFormat(
        "backup_report_skipped".localized,
        report.skipped.count,
        report.skipped.prefix(3).joined(separator: ", ")
      )
    }
    return text
  }
}
