//
//  PlayerListPanel.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/10/26.
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import SwiftUI

/// The chapters, bookmarks, queue and history beside or below the player, when
/// the screen has room for both, like an open iPhone Duo (beside in landscape,
/// below in portrait)
struct PlayerListPanel: View {
  /// The panel's own picker — a superset of `ListOptionsSectionView.DisplayOption`.
  /// That enum backs the "the player's list button opens" setting with a two-way
  /// bool pref; queue and history are panel-only so the setting stays binary.
  enum PanelList: String, Identifiable, CaseIterable {
    var id: Self { self }
    case chapters, bookmarks, queue, history

    var title: LocalizedStringKey {
      switch self {
      case .chapters: "chapters_title"
      case .bookmarks: "bookmarks_title"
      case .queue: "queue_title"
      case .history: "history_title"
      }
    }
  }

  let playerManager: PlayerManager
  let libraryService: LibraryServiceProtocol
  let syncService: SyncServiceProtocol
  let listeningQueueService: ListeningQueueService
  let playbackHistoryService: PlaybackHistoryService
  let playerLoaderService: PlayerLoaderService
  let loadingState: LoadingOverlayState

  /// Starts on the list the player's list button opens (Player Controls › Opens)
  @State private var list: PanelList =
    UserDefaults.standard.bool(forKey: Constants.UserDefaults.playerListPrefersBookmarks)
    ? .bookmarks
    : .chapters

  var body: some View {
    NavigationStack {
      Group {
        /// Picking a row keeps the panel: there's nothing to close beside the player
        switch list {
        case .chapters:
          ChaptersView {
            ChaptersViewModel(playerManager: playerManager, libraryService: libraryService)
          }
        case .bookmarks:
          BookmarksView {
            BookmarksViewModel(
              playerManager: playerManager,
              libraryService: libraryService,
              syncService: syncService
            )
          }
        case .queue:
          ListeningQueueView {
            ListeningQueueViewModel(
              queueService: listeningQueueService,
              playerLoaderService: playerLoaderService,
              loadingState: loadingState
            )
          }
        case .history:
          PlaybackHistoryView {
            PlaybackHistoryViewModel(
              historyService: playbackHistoryService,
              playerManager: playerManager,
              playerLoaderService: playerLoaderService,
              loadingState: loadingState
            )
          }
        }
      }
      /// The player's buttons are plain, which in a list leaves only a row's text tappable;
      /// here the rows keep the whole-row tap and highlight they have in the sheets
      .buttonStyle(.automatic)
      .toolbar {
        ToolbarItem(placement: .principal) {
          /// No label: VoiceOver reads the segments
          Picker(selection: $list) {
            ForEach(PanelList.allCases) { option in
              Text(option.title)
                .tag(option)
            }
          } label: {
            EmptyView()
          }
          .pickerStyle(.segmented)
          .fixedSize()
        }
      }
    }
  }
}

extension View {
  /// On iOS 27.1, puts `PlayerListPanel` beside or below this view when the screen has room for
  /// both; otherwise the view stays alone, as before
  func playerListPanel(
    playerManager: PlayerManager,
    libraryService: LibraryServiceProtocol,
    syncService: SyncServiceProtocol,
    listeningQueueService: ListeningQueueService,
    playbackHistoryService: PlaybackHistoryService,
    playerLoaderService: PlayerLoaderService,
    loadingState: LoadingOverlayState
  ) -> some View {
    modifier(
      PlayerListPanelModifier(
        playerManager: playerManager,
        libraryService: libraryService,
        syncService: syncService,
        listeningQueueService: listeningQueueService,
        playbackHistoryService: playbackHistoryService,
        playerLoaderService: playerLoaderService,
        loadingState: loadingState
      )
    )
  }
}

extension EnvironmentValues {
  /// Whether `PlayerListPanel` sits below the view, across a fold: iPhone Duo in the L pose
  @Entry var isPlayerAboveLists = false
}

private struct PlayerListPanelModifier: ViewModifier {
  /// A fold runs across the screen, like iPhone Duo half open in portrait (the L pose). Flat or
  /// closed there's none, and in landscape the fold runs top to bottom
  @State private var isFoldedAcross = false
  let playerManager: PlayerManager
  let libraryService: LibraryServiceProtocol
  let syncService: SyncServiceProtocol
  let listeningQueueService: ListeningQueueService
  let playbackHistoryService: PlaybackHistoryService
  let playerLoaderService: PlayerLoaderService
  let loadingState: LoadingOverlayState

  func body(content: Content) -> some View {
    if #available(iOS 27.1, *) {
      ArrangementView {
        /// Told here, in the same update as the split: the player switches its layout as the
        /// lists come in or go
        content
          .environment(\.isPlayerAboveLists, isFoldedAcross)
      } secondary: {
        PlayerListPanel(
          playerManager: playerManager,
          libraryService: libraryService,
          syncService: syncService,
          listeningQueueService: listeningQueueService,
          playbackHistoryService: playbackHistoryService,
          playerLoaderService: playerLoaderService,
          loadingState: loadingState
        )
      }
      /// Across a fold, the lists go below it; otherwise only beside the player: flat in portrait
      /// the player keeps the whole screen
      .arrangementViewStyle(.split.axes(isFoldedAcross ? .vertical : .horizontal))
      .onGeometryChange(for: Bool.self) { proxy in
        proxy.reservedRegions(kind: .division).contains { $0.frame.width > $0.frame.height }
      } action: { isFoldedAcross = $0 }
    } else {
      content
    }
  }
}
