//
//  WebDAVBrowserView.swift
//  BookPlayer
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import SwiftUI

/// The WebDAV import sheet: a connection form (server URL + credentials kept in
/// the Keychain), a directory browser with multi-select, and a download stage
/// that hands staged files to the regular import operation.
struct WebDAVBrowserView: View {
  @StateObject private var viewModel: WebDAVBrowserViewModel

  init(initModel: @escaping () -> WebDAVBrowserViewModel) {
    self._viewModel = .init(wrappedValue: initModel())
  }

  @EnvironmentObject private var theme: ThemeViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      content
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            if viewModel.phase == .browse, !viewModel.path.isEmpty {
              Button {
                viewModel.navigateUp()
              } label: {
                Label("back_title", systemImage: "chevron.left")
              }
            } else {
              Button("cancel_button", role: .cancel) { dismiss() }
            }
          }
          ToolbarItem(placement: .confirmationAction) {
            if viewModel.phase == .browse {
              Button("import_button") {
                viewModel.importSelection()
              }
              .disabled(!viewModel.canImport)
            }
          }
        }
        .errorAlert(error: $viewModel.error)
        .tint(theme.linkColor)
        .toolbarColorScheme(theme.useDarkVariant ? .dark : .light, for: .navigationBar)
    }
    .interactiveDismissDisabled(viewModel.phase == .downloading)
    .onAppear { viewModel.restore() }
    .onDisappear { viewModel.dismissFlow() }
  }

  private var navigationTitle: LocalizedStringKey {
    switch viewModel.phase {
    case .connect: return "webdav_title"
    case .browse:
      return viewModel.path.last?.name.map { LocalizedStringKey($0) } ?? "webdav_title"
    case .downloading: return "webdav_downloading_title"
    }
  }

  @ViewBuilder
  private var content: some View {
    switch viewModel.phase {
    case .connect:
      connectForm
    case .browse:
      browserList
    case .downloading:
      downloadState
    }
  }

  // MARK: - Connect

  private var connectForm: some View {
    Form {
      ThemedSection {
        TextField("webdav_server_url_placeholder", text: $viewModel.serverURL)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityLabel(Text("webdav_server_url_placeholder"))
        TextField("webdav_username_placeholder", text: $viewModel.username)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityLabel(Text("webdav_username_placeholder"))
        SecureField("webdav_password_placeholder", text: $viewModel.password)
          .accessibilityLabel(Text("webdav_password_placeholder"))
        Toggle("webdav_remember_title", isOn: $viewModel.rememberCredentials)
          .tint(theme.linkColor)
      } header: {
        Text("webdav_server_section_title")
          .foregroundStyle(theme.secondaryColor)
      }

      ThemedSection {
        Button {
          Task { await viewModel.connect() }
        } label: {
          HStack {
            Text("webdav_connect_button")
              .foregroundStyle(theme.linkColor)
            Spacer()
            if viewModel.isLoading {
              ProgressView()
            }
          }
        }
        .disabled(viewModel.isLoading || viewModel.serverURL.isEmpty)

        if viewModel.hasSavedConnection {
          Button("webdav_forget_button", role: .destructive) {
            viewModel.forgetConnection()
          }
        }
      } footer: {
        Text("webdav_credentials_footer")
          .foregroundStyle(theme.secondaryColor)
      }
    }
    .applyListStyle(with: theme, background: theme.systemGroupedBackgroundColor)
  }

  // MARK: - Browse

  private var browserList: some View {
    List {
      if viewModel.isLoading {
        HStack {
          Spacer()
          ProgressView()
          Spacer()
        }
        .listRowBackground(Color.clear)
      } else if viewModel.entries.isEmpty {
        ContentUnavailableView {
          Label("webdav_empty_folder_title", systemImage: "folder")
            .foregroundStyle(theme.primaryColor)
        }
        .listRowBackground(Color.clear)
      } else {
        ForEach(viewModel.entries) { entry in
          entryRow(entry)
            .listRowBackground(theme.systemBackgroundColor)
        }
      }
    }
    .applyListStyle(with: theme, background: theme.systemBackgroundColor)
    .refreshable { await viewModel.refresh() }
  }

  private func entryRow(_ entry: WebDAVEntry) -> some View {
    HStack(spacing: Spacing.S1) {
      if entry.isCollection {
        Button {
          viewModel.navigate(to: entry)
        } label: {
          HStack(spacing: Spacing.S1) {
            Image(systemName: "folder.fill")
              .foregroundStyle(theme.linkColor)
            Text(entry.name)
              .foregroundStyle(theme.primaryColor)
              .lineLimit(1)
            Spacer()
          }
        }
        .accessibilityHint("webdav_open_folder_hint")
      } else {
        Button {
          viewModel.toggle(entry)
        } label: {
          HStack(spacing: Spacing.S1) {
            Image(systemName: viewModel.selection.contains(entry.url) ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(viewModel.selection.contains(entry.url) ? theme.linkColor : theme.secondaryColor)
            VStack(alignment: .leading, spacing: 2) {
              Text(entry.name)
                .foregroundStyle(theme.primaryColor)
                .lineLimit(1)
              if let size = entry.formattedSize {
                Text(size)
                  .bpFont(.caption)
                  .foregroundStyle(theme.secondaryColor)
              }
            }
            Spacer()
          }
        }
        .accessibilityHint("webdav_select_file_hint")
      }
    }
  }

  // MARK: - Downloading

  private var downloadState: some View {
    VStack(spacing: Spacing.S) {
      if let progress = viewModel.downloadProgress {
        ProgressView(value: progress.fraction)
          .progressViewStyle(.linear)
          .padding(.horizontal, Spacing.S)

        Text(
          String.localizedStringWithFormat(
            "import_preparing_detail_title".localized,
            progress.total,
            progress.currentName
          )
        )
        .bpFont(.subheadline)
        .foregroundStyle(theme.secondaryColor)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.S)

        Button("cancel_button") {
          viewModel.dismissFlow()
          dismiss()
        }
        .foregroundStyle(theme.linkColor)
      } else {
        ProgressView()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.systemBackgroundColor)
  }
}
