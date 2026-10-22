//
//  CollectionDetailViewModel.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import Foundation

/// The real collection-detail model: `LibraryService` is the source of truth —
/// every mutation refetches so a row can never disagree with the store.
final class CollectionDetailViewModel: CollectionDetailView.Model {
  private let libraryService: LibraryService
  private let playbackService: PlaybackService
  private let playerLoaderService: PlayerLoaderService
  private let syncService: SyncService
  private let playerState: PlayerState
  private let loadingState: LoadingOverlayState

  init(
    collection: SimpleCollection,
    libraryService: LibraryService,
    playbackService: PlaybackService,
    playerLoaderService: PlayerLoaderService,
    syncService: SyncService,
    playerState: PlayerState,
    loadingState: LoadingOverlayState
  ) {
    self.libraryService = libraryService
    self.playbackService = playbackService
    self.playerLoaderService = playerLoaderService
    self.syncService = syncService
    self.playerState = playerState
    self.loadingState = loadingState

    super.init(collection: collection)
    reload()
  }

  override func reload() {
    items = libraryService.fetchCollectionItems(uuid: collection.uuid)
  }

  /// The same gate the library's artwork tap applies: a missing file
  /// downloads, an in-flight download offers to cancel, and only a file
  /// that's actually on disk loads the player.
  override func handleSelect(_ item: SimpleLibraryItem) {
    switch syncService.getDownloadState(for: item) {
    case .notDownloaded:
      startDownload(of: item)
    case .downloading:
      cancelDownloadTarget = item
    case .downloaded:
      play(item)
    }
  }

  /// Confirm action of the cancel-download alert
  override func cancelDownload(of item: SimpleLibraryItem) {
    do {
      try syncService.cancelDownload(of: item)
    } catch {
      loadingState.error = error
    }
    cancelDownloadTarget = nil
  }

  /// Same body as `ItemListViewModel.startDownload` — backing folder for
  /// containers, then the remote files
  private func startDownload(of item: SimpleLibraryItem) {
    Task { @MainActor [weak self] in
      guard let self else { return }
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

  /// A book plays itself; a folder plays its next unfinished book (same rule
  /// the library list applies), then the player comes up.
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

  /// Removes the item from THIS collection — the book, its progress and its
  /// folder placement all survive (Nullify on the relationship).
  override func remove(_ item: SimpleLibraryItem) {
    libraryService.removeFromCollection(uuid: collection.uuid, items: [item.relativePath])
    reload()
  }
}
