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
  /// The shared select→download→cancel→play flow (`LibraryItemActionHandler`)
  private let actions: LibraryItemActionHandler

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
    self.actions = LibraryItemActionHandler(
      playbackService: playbackService,
      playerLoaderService: playerLoaderService,
      syncService: syncService,
      playerState: playerState,
      loadingState: loadingState
    )

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
    actions.handleSelect(item) { [weak self] in self?.cancelDownloadTarget = $0 }
  }

  /// Confirm action of the cancel-download alert
  override func cancelDownload(of item: SimpleLibraryItem) {
    actions.cancelDownload(of: item)
    cancelDownloadTarget = nil
  }

  /// Removes the item from THIS collection — the book, its progress and its
  /// folder placement all survive (Nullify on the relationship).
  override func remove(_ item: SimpleLibraryItem) {
    libraryService.removeFromCollection(uuid: collection.uuid, items: [item.relativePath])
    reload()
  }
}
