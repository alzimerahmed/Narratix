//
//  PhoneLibraryView.swift
//  BookPlayerWatch
//
//  Created by Gianni Carlo on 3/8/26.
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerWatchKit
import SwiftUI

/// Read/browse view of the PHONE's library for watches without their own
/// account: folders drill down, a book tap remote-plays it on the phone, and
/// books with a remote copy can have their phone-side download managed from
/// here. Pages come from the phone over `sendMessageData` — see
/// `WatchLibraryCommand` in BookPlayerKit.
struct PhoneLibraryView: View {
  @EnvironmentObject var contextManager: ContextManager

  /// nil = library root
  let path: String?
  private let screenTitle: String

  @State private var items = [WatchLibraryItem]()
  @State private var loadState: LoadState = .loading
  @State private var hasMore = false
  @State private var isLoadingMore = false
  @State private var showPlayer = false
  @State private var error: Error?
  @State private var itemPendingOffload: WatchLibraryItem?
  /// Brief confirmation the request reached the phone — the download itself
  /// is the phone's background job
  @State private var showDownloadStarted = false

  private enum LoadState {
    case loading, loaded, unavailable
  }

  /// Remote errors turned into the watch's own wording — the phone replies
  /// with codes, not sentences
  private struct CommandError: LocalizedError {
    let kind: ContextManager.WatchItemCommandError

    var errorDescription: String? {
      switch kind {
      case .unreachable:
        return "watchapp_browse_unavailable_description".localized
      case .noRemoteCopy:
        return "watchapp_browse_no_remote_copy".localized
      case .notDownloaded:
        return "watchapp_browse_not_downloaded".localized
      case .nowPlaying:
        return "watchapp_browse_now_playing".localized
      case .uploadInProgress:
        return "watchapp_browse_upload_in_progress".localized
      case .notFound, .failed:
        return "watchapp_download_failed_title".localized
      }
    }
  }

  init(path: String? = nil, title: String? = nil) {
    self.path = path
    self.screenTitle = title ?? "watchapp_browse_library_title".localized
  }

  var body: some View {
    Group {
      switch loadState {
      case .loading:
        ProgressView()
      case .unavailable:
        unavailableView
      case .loaded:
        listView
      }
    }
    .navigationTitle(screenTitle)
    .onAppear {
      reload()
    }
    /// Same auto-show the recent list uses: the phone answers the play
    /// command with its own `play` broadcast, which lands here
    .onReceive(NotificationCenter.default.publisher(for: .bookPlaying)) { _ in
      showPlayer = true
      contextManager.isPlaying = true
    }
    .onReceive(NotificationCenter.default.publisher(for: .bookPaused)) { _ in
      contextManager.isPlaying = false
    }
    .background(
      NavigationLink(
        destination: NowPlayingView().environmentObject(contextManager),
        isActive: $showPlayer
      ) {
        EmptyView()
      }
      .opacity(0)
    )
    .confirmationDialog(
      "watchapp_remove_download_confirm_title",
      isPresented: Binding(
        get: { itemPendingOffload != nil },
        set: { if !$0 { itemPendingOffload = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("storage_remove_downloads_button".localized, role: .destructive) {
        if let item = itemPendingOffload {
          requestRemoveDownload(for: item)
        }
      }
      Button("cancel_button".localized, role: .cancel) {}
    } message: {
      Text("watchapp_remove_download_confirm_description")
    }
    .alert("watchapp_download_started_title", isPresented: $showDownloadStarted) {
      Button("ok_button".localized, role: .cancel) {}
    }
    .errorAlert(error: $error)
  }

  // MARK: - Content

  private var listView: some View {
    List {
      ForEach(items) { item in
        if item.isFolder {
          NavigationLink {
            PhoneLibraryView(path: item.relativePath, title: item.title)
          } label: {
            PhoneLibraryCell(item: item)
          }
        } else {
          Button {
            contextManager.handlePhoneItemSelected(item)
            /// No optimistic open: Now Playing follows the phone's `play`
            /// broadcast (.bookPlaying above) — an unreachable phone drops
            /// the command silently and a pushed player would sit dead
          } label: {
            PhoneLibraryCell(item: item)
          }
          .swipeActions {
            actionButtons(for: item)
          }
          .accessibilityHint("queue_row_play_hint".localized)
        }
      }

      if hasMore {
        Button {
          loadMore()
        } label: {
          if isLoadingMore {
            ProgressView()
              .frame(maxWidth: .infinity)
          } else {
            Text("watchapp_browse_load_more_title")
              .frame(maxWidth: .infinity)
          }
        }
        .disabled(isLoadingMore)
      }
    }
    .overlay {
      if items.isEmpty {
        Text("watchapp_browse_empty_title")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var unavailableView: some View {
    VStack(spacing: 12) {
      Image(systemName: "iphone.slash")
        .font(.title2)
        .foregroundStyle(.secondary)
      Text("watchapp_browse_unavailable_title")
        .font(.headline)
      Text("watchapp_browse_unavailable_description")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button("watchapp_browse_retry_button".localized) {
        reload()
      }
      .buttonStyle(.bordered)
    }
    .padding()
  }

  @ViewBuilder
  private func actionButtons(for item: WatchLibraryItem) -> some View {
    switch item.downloadState {
    case "notDownloaded":
      Button {
        requestDownload(for: item)
      } label: {
        Image(systemName: "arrow.down.circle")
          .imageScale(.large)
      }
      .accessibilityLabel("download_title".localized)
    case "downloaded" where item.canOffload:
      Button {
        itemPendingOffload = item
      } label: {
        Image(systemName: "arrow.up.circle")
          .imageScale(.large)
      }
      .accessibilityLabel("remove_downloaded_file_title".localized)
    default:
      EmptyView()
    }
  }

  // MARK: - Data

  private func reload() {
    loadState = .loading
    contextManager.requestPhoneLibrary(path: path, offset: 0) { page in
      guard let page else {
        loadState = .unavailable
        return
      }
      items = page.items
      hasMore = page.hasMore
      loadState = .loaded
    }
  }

  private func loadMore() {
    guard !isLoadingMore else { return }
    isLoadingMore = true
    contextManager.requestPhoneLibrary(path: path, offset: items.count) { page in
      isLoadingMore = false
      guard let page else { return }
      items.append(contentsOf: page.items)
      hasMore = page.hasMore
    }
  }

  private func requestDownload(for item: WatchLibraryItem) {
    contextManager.requestPhoneItemDownload(relativePath: item.relativePath) { result in
      switch result {
      case .success:
        showDownloadStarted = true
        updateState(of: item, to: "downloading", canOffload: false)
      case .failure(let commandError):
        error = CommandError(kind: commandError)
      }
    }
  }

  private func requestRemoveDownload(for item: WatchLibraryItem) {
    contextManager.requestPhoneItemRemoveDownload(relativePath: item.relativePath) { result in
      switch result {
      case .success:
        updateState(of: item, to: "notDownloaded", canOffload: false)
      case .failure(let commandError):
        error = CommandError(kind: commandError)
      }
    }
  }

  /// Patch the row's download state after an accepted command — the page
  /// would say the same thing on the next reload
  private func updateState(of item: WatchLibraryItem, to state: String, canOffload: Bool) {
    guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
    items[index] = WatchLibraryItem(
      relativePath: item.relativePath,
      title: item.title,
      details: item.details,
      type: item.type,
      isFinished: item.isFinished,
      percentCompleted: item.percentCompleted,
      duration: item.duration,
      downloadState: state,
      canOffload: canOffload
    )
  }
}

/// Compact row: title, author/details line, and a state glyph mirroring the
/// recent-items cells (progress dot for downloading, checkmark on device,
/// cloud badge when remote)
private struct PhoneLibraryCell: View {
  let item: WatchLibraryItem

  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        Text(item.title)
          .lineLimit(2)
        Text(item.details)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        stateLine
      }
      Spacer()
      if item.isFolder {
        Image(systemName: "chevron.forward")
      }
    }
  }

  @ViewBuilder
  private var stateLine: some View {
    switch item.downloadState {
    case "downloading":
      Text(Image(systemName: "icloud.and.arrow.down.fill"))
        .font(.caption2)
        .foregroundStyle(.secondary)
    case "downloaded":
      Text(Image(systemName: "iphone"))
        .font(.caption2)
        .foregroundStyle(.secondary)
    case "notDownloaded":
      Text(Image(systemName: "icloud.fill"))
        .font(.caption2)
        .foregroundStyle(.secondary)
    default:
      EmptyView()
    }
  }
}
