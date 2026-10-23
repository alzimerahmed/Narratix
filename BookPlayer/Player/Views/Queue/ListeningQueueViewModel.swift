//
//  ListeningQueueViewModel.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/5/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import Combine
import Foundation

/// The real queue model: the `ListeningQueueService` is the source of truth —
/// every mutation refetches so a row can never disagree with the store (the
/// service's `updates` publisher covers changes from outside the list too, e.g.
/// a dequeue when the player advanced).
final class ListeningQueueViewModel: ListeningQueueView.Model {
  private let queueService: ListeningQueueService
  private let playerLoaderService: PlayerLoaderService
  private let loadingState: LoadingOverlayState

  private var disposeBag = Set<AnyCancellable>()

  init(
    queueService: ListeningQueueService,
    playerLoaderService: PlayerLoaderService,
    loadingState: LoadingOverlayState
  ) {
    self.queueService = queueService
    self.playerLoaderService = playerLoaderService
    self.loadingState = loadingState

    super.init(items: queueService.fetchQueue())

    queueService.updates
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        guard let self else { return }
        self.items = queueService.fetchQueue()
      }
      .store(in: &disposeBag)
  }

  override func handleSelect(_ item: SimpleLibraryItem) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await playerLoaderService.loadPlayer(item.relativePath, autoplay: true)
        /// Playing the entry consumes it — remove only once the load went
        /// through so a failure keeps the queue intact
        queueService.remove(item.relativePath)
      } catch {
        loadingState.error = error
      }
    }
  }

  override func move(fromOffsets source: IndexSet, toOffset destination: Int) {
    queueService.move(fromOffsets: source, toOffset: destination)
  }

  override func delete(at offsets: IndexSet) {
    queueService.removeAll(offsets.map { items[$0].relativePath })
  }
}
