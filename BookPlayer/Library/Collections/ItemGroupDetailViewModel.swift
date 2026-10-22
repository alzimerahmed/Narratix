//
//  ItemGroupDetailViewModel.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import Foundation

/// The real group-detail model — read-only: the group's snapshot already
/// carries its order; `handleSelect` resolves folders to their next
/// unfinished book, same rule the library list applies.
final class ItemGroupDetailViewModel: ItemGroupDetailView.Model {
  /// The shared select→download→cancel→play flow (`LibraryItemActionHandler`)
  private let actions: LibraryItemActionHandler

  init(
    group: SimpleItemGroup,
    playbackService: PlaybackService,
    playerLoaderService: PlayerLoaderService,
    syncService: SyncService,
    playerState: PlayerState,
    loadingState: LoadingOverlayState
  ) {
    self.actions = LibraryItemActionHandler(
      playbackService: playbackService,
      playerLoaderService: playerLoaderService,
      syncService: syncService,
      playerState: playerState,
      loadingState: loadingState
    )

    super.init(group: group)
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
}
