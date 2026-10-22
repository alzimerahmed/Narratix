//
//  PlaybackHistoryViewModel.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/5/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import Combine
import Foundation

/// Restore flow: load the session's book through the same loader a library row
/// tap uses, then seek to the position the session was left at. The row's
/// position is book-time, which is exactly what `jumpTo` takes.
final class PlaybackHistoryViewModel: PlaybackHistoryView.Model {
  private let historyService: PlaybackHistoryService
  private let playerManager: PlayerManagerProtocol
  private let playerLoaderService: PlayerLoaderService
  private let loadingState: LoadingOverlayState

  init(
    historyService: PlaybackHistoryService,
    playerManager: PlayerManagerProtocol,
    playerLoaderService: PlayerLoaderService,
    loadingState: LoadingOverlayState
  ) {
    self.historyService = historyService
    self.playerManager = playerManager
    self.playerLoaderService = playerLoaderService
    self.loadingState = loadingState

    super.init(sessions: historyService.fetchSessions())
  }

  override func reload() {
    sessions = historyService.fetchSessions()
  }

  override func handleSelect(_ session: SimplePlaybackSession) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await playerLoaderService.loadPlayer(session.itemRelativePath, autoplay: true)
        /// The loader resolves to the stored position — the session's is the
        /// one the user asked for
        playerManager.jumpTo(session.position, recordBookmark: false)
      } catch {
        loadingState.error = error
      }
    }
  }

  override func delete(at offsets: IndexSet) {
    for index in offsets {
      historyService.deleteSession(id: sessions[index].id)
    }
    sessions.remove(atOffsets: offsets)
  }
}
