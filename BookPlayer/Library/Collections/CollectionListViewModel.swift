//
//  CollectionListViewModel.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import Foundation

/// The real collections model: `LibraryService` is the source of truth — every
/// mutation refetches so a row can never disagree with the store. There is no
/// updates publisher here on purpose: collections are only ever mutated through
/// these views (deleting a library item nullifies its membership in the store
/// itself, and the detail refetches on appear anyway).
final class CollectionListViewModel: CollectionListView.Model {
  private let libraryService: LibraryService
  private let playbackService: PlaybackService
  private let playerLoaderService: PlayerLoaderService
  private let playerState: PlayerState
  private let loadingState: LoadingOverlayState

  init(
    libraryService: LibraryService,
    playbackService: PlaybackService,
    playerLoaderService: PlayerLoaderService,
    playerState: PlayerState,
    loadingState: LoadingOverlayState
  ) {
    self.libraryService = libraryService
    self.playbackService = playbackService
    self.playerLoaderService = playerLoaderService
    self.playerState = playerState
    self.loadingState = loadingState

    super.init()
    reload()
  }

  override func reload() {
    collections = libraryService.fetchCollections()
  }

  override func create(title: String) {
    libraryService.createCollection(title: title)
    reload()
  }

  override func rename(_ collection: SimpleCollection, title: String) {
    libraryService.renameCollection(uuid: collection.uuid, title: title)
    reload()
  }

  override func delete(_ collection: SimpleCollection) {
    libraryService.deleteCollection(uuid: collection.uuid)
    reload()
  }

  override func makeDetailModel(for collection: SimpleCollection) -> CollectionDetailView.Model {
    CollectionDetailViewModel(
      collection: collection,
      libraryService: libraryService,
      playbackService: playbackService,
      playerLoaderService: playerLoaderService,
      playerState: playerState,
      loadingState: loadingState
    )
  }
}
