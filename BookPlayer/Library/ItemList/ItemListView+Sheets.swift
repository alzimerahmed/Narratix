//
//  ItemListView+Sheets.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 4/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import SwiftUI

// MARK: - Sheet Content Builders
extension ItemListView {
  @ViewBuilder
  func sheetContent(for sheet: ItemListSheet) -> some View {
    switch sheet {
    case .itemDetails(let item):
      itemDetailsSheet(for: item)
    case .queuedTasks:
      // Own stack so the title and the info button show inside the sheet
      NavigationStack {
        QueuedTasksView()
      }
    case .foldersSelection:
      foldersSelectionSheet()
    case .libraryOptions:
      libraryOptionsSheet()
    case .collections:
      collectionsSheet()
    case .collectionPicker:
      collectionPickerSheet()
    case .seriesBrowser:
      seriesBrowserSheet()
    }
  }

  @ViewBuilder
  private func libraryOptionsSheet() -> some View {
    let location = currentLocation
    LibraryOptionsView(
      location: location,
      onSelectionChange: { effective in
        switch effective {
        case .automatic(let sort):
          // Persists the sticky pref; the list re-fetches with the rule's
          // query-time sort descriptors.
          model.handleSort(by: sort)
        case .custom:
          // Freezes the currently-visible order into orderRank (WYSIWYG) and
          // flips the pref — the frozen arrangement syncs like a manual drag.
          model.handleSetCustomSort()
        }
      },
      onReverseOrder: {
        // Reverses orderRank locally; LibraryService writes `.custom` ahead of the rebuild,
        // so the sticky picker re-renders to "Custom" via @AppStorage.
        model.handleReverseOrder()
      }
    )
  }



  @ViewBuilder
  private func itemDetailsSheet(for item: SimpleLibraryItem) -> some View {
    NavigationStack {
      ItemDetailsView {
        ItemDetailsViewModel(
          item: item,
          libraryService: libraryService,
          syncService: syncService,
          hardcoverService: hardcoverService,
          listState: listState
        )
      }
    }
  }
  
  @ViewBuilder
  private func foldersSelectionSheet() -> some View {
    ItemListSelectionView(items: model.getAvailableFolders()) { folder in
      model.handleMoveIntoFolder(folder)
    }
  }

  /// The collections browser — own stack so the title/toolbar/detail push
  /// live inside the sheet
  @ViewBuilder
  private func collectionsSheet() -> some View {
    NavigationStack {
      CollectionListView {
        CollectionListViewModel(
          libraryService: libraryService,
          playbackService: playbackService,
          playerLoaderService: playerLoaderService,
          playerState: playerState,
          loadingState: loadingState
        )
      }
    }
  }

  /// The selection's membership picker — captures the selected items when the
  /// sheet opens (clearing edit mode afterwards can't lose them)
  @ViewBuilder
  private func collectionPickerSheet() -> some View {
    NavigationStack {
      CollectionPickerView {
        CollectionPickerViewModel(
          libraryService: libraryService,
          items: model.selectedItems
        )
      }
    }
  }

  /// Browse by series / author — own stack like the collections sheet
  @ViewBuilder
  private func seriesBrowserSheet() -> some View {
    NavigationStack {
      SeriesBrowseView {
        SeriesBrowseViewModel(
          libraryService: libraryService,
          playbackService: playbackService,
          playerLoaderService: playerLoaderService,
          playerState: playerState,
          loadingState: loadingState
        )
      }
    }
  }
}
