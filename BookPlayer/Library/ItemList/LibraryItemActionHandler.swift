//
//  LibraryItemActionHandler.swift
//  BookPlayer
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Foundation

/// The row-tap gate the library's browse surfaces share: a missing file
/// downloads, an in-flight download asks to cancel, and a file on disk plays
/// (a folder resolving to its next unfinished book). One owner for what was
/// three copies of the flow — `ItemListViewModel`, `CollectionDetailViewModel`
/// and `ItemGroupDetailViewModel`.
@MainActor
final class LibraryItemActionHandler {
  private let playbackService: PlaybackService
  private let playerLoaderService: PlayerLoaderService
  private let syncService: SyncService
  private let playerState: PlayerState
  private let loadingState: LoadingOverlayState

  init(
    playbackService: PlaybackService,
    playerLoaderService: PlayerLoaderService,
    syncService: SyncService,
    playerState: PlayerState,
    loadingState: LoadingOverlayState
  ) {
    self.playbackService = playbackService
    self.playerLoaderService = playerLoaderService
    self.syncService = syncService
    self.playerState = playerState
    self.loadingState = loadingState
  }

  /// The gate itself: a download starts inline and a playable item resolves
  /// here, while a mid-download tap is handed back — cancelling needs the
  /// caller's confirmation alert, so the view model owns that piece
  func handleSelect(
    _ item: SimpleLibraryItem,
    onCancelRequested: (SimpleLibraryItem) -> Void
  ) {
    switch syncService.getDownloadState(for: item) {
    case .notDownloaded:
      Self.startDownload(of: item, syncService: syncService, loadingState: loadingState)
    case .downloading:
      onCancelRequested(item)
    case .downloaded:
      play(item)
    }
  }

  /// Confirm action of the caller's cancel-download alert
  func cancelDownload(of item: SimpleLibraryItem) {
    Self.cancelDownload(of: item, syncService: syncService, loadingState: loadingState)
  }

  /// A book plays itself; a folder plays its next unfinished book (same rule
  /// the library list applies), then the player comes up
  private func play(_ item: SimpleLibraryItem) {
    let path: String?
    switch item.type {
    case .folder:
      path = (try? playbackService.getFirstPlayableItem(in: item, isUnfinished: true))?.relativePath
    case .bound, .book:
      path = item.relativePath
    }

    guard let path else { return }

    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await playerLoaderService.loadPlayer(path, autoplay: true)
        playerState.showPlayerBinding.wrappedValue = true
      } catch {
        loadingState.error = error
      }
    }
  }

  // MARK: - The download bodies, static
  //
  // `ItemListViewModel` starts downloads outside the gate (the options menu,
  // the resume button) and holds no player-facing services — it shares these
  // directly instead of a whole handler it couldn't build.

  /// Backing folder for containers, then the remote files — spinner up while
  /// it runs
  static func startDownload(
    of item: SimpleLibraryItem,
    syncService: SyncService,
    loadingState: LoadingOverlayState
  ) {
    Task { @MainActor in
      loadingState.show = true

      do {
        let fileURL = item.fileURL
        if item.type == .folder || item.type == .bound {
          try DataManager.createBackingFolderIfNeeded(fileURL)
        }
        try await syncService.downloadRemoteFiles(for: item)
        loadingState.show = false
      } catch {
        loadingState.show = false
        loadingState.error = error
      }
    }
  }

  /// The confirmation's affirmative action
  static func cancelDownload(
    of item: SimpleLibraryItem,
    syncService: SyncService,
    loadingState: LoadingOverlayState
  ) {
    do {
      try syncService.cancelDownload(of: item)
    } catch {
      loadingState.error = error
    }
  }
}
