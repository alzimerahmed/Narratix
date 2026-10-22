//
//  CollectionPickerViewModel.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import Foundation

/// The real picker model. Membership is evaluated over the WHOLE selection:
/// a row is checked only when every selected item belongs, and toggling a
/// partially-member row adds the missing items (it never removes).
final class CollectionPickerViewModel: CollectionPickerView.Model {
  private let libraryService: LibraryService
  /// The selection's identity across the sheet's lifetime — paths survive a
  /// rename/reload where ids could change
  private let selectedPaths: [String]

  init(libraryService: LibraryService, items: [SimpleLibraryItem]) {
    self.libraryService = libraryService
    self.selectedPaths = items.map(\.relativePath)

    super.init()
    reload()
  }

  override func reload() {
    let all = libraryService.fetchCollections()
    collections = all
    fullyMemberUuids = Set(
      all.filter {
        libraryService.collectionMembership(uuid: $0.uuid, of: selectedPaths).count == selectedPaths.count
      }
      .map(\.uuid)
    )
  }

  override func toggle(_ collection: SimpleCollection) {
    if isFullyMember(collection) {
      libraryService.removeFromCollection(uuid: collection.uuid, items: selectedPaths)
    } else {
      libraryService.addToCollection(uuid: collection.uuid, items: selectedPaths)
    }
    reload()
  }

  override func create(title: String) {
    if let collection = libraryService.createCollection(title: title) {
      libraryService.addToCollection(uuid: collection.uuid, items: selectedPaths)
    }
    reload()
  }
}
