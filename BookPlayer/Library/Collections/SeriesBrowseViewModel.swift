//
//  SeriesBrowseViewModel.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import Foundation

/// The real browse model: `LibraryService` fetches pre-grouped,
/// pre-ordered snapshots — series contents arrive ordered by book number
/// (unordered last) then title; author contents by title.
final class SeriesBrowseViewModel: SeriesBrowseView.Model {
  private let libraryService: LibraryService
  private let playbackService: PlaybackService
  private let playerLoaderService: PlayerLoaderService
  private let syncService: SyncService
  private let playerState: PlayerState
  private let loadingState: LoadingOverlayState

  init(
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

    super.init()
    /// No init reload: the view's `.task` reloads on open — fetching here
    /// too ran the whole group query twice per sheet
  }

  override func reload() {
    seriesGroups = libraryService.fetchSeriesGroups()
    authorGroups = libraryService.fetchAuthorGroups()
  }

  override func makeDetailModel(for group: SimpleItemGroup) -> ItemGroupDetailView.Model {
    ItemGroupDetailViewModel(
      group: group,
      playbackService: playbackService,
      playerLoaderService: playerLoaderService,
      syncService: syncService,
      playerState: playerState,
      loadingState: loadingState
    )
  }
}
