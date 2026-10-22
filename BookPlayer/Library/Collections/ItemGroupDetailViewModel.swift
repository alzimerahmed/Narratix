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
  private let playbackService: PlaybackService
  private let playerLoaderService: PlayerLoaderService
  private let playerState: PlayerState
  private let loadingState: LoadingOverlayState

  init(
    group: SimpleItemGroup,
    playbackService: PlaybackService,
    playerLoaderService: PlayerLoaderService,
    playerState: PlayerState,
    loadingState: LoadingOverlayState
  ) {
    self.playbackService = playbackService
    self.playerLoaderService = playerLoaderService
    self.playerState = playerState
    self.loadingState = loadingState

    super.init(group: group)
  }

  override func handleSelect(_ item: SimpleLibraryItem) {
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
}
