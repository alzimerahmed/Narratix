//
//  ItemGroupDetailView.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import SwiftUI

/// A series' or author's books — the order comes from the fetch (series:
/// book number then title; author: title). Read-only browse: membership
/// edits happen in the collections surfaces or item details, not here.
struct ItemGroupDetailView: View {
  let group: SimpleItemGroup
  @StateObject private var model: Self.Model
  /// Ambient — pushed inside the browse sheet, which carries the theme
  @EnvironmentObject private var theme: ThemeViewModel

  @Environment(\.loadingState) private var loadingState

  init(group: SimpleItemGroup, initModel: @escaping () -> Self.Model) {
    self.group = group
    self._model = .init(wrappedValue: initModel())
  }

  var body: some View {
    List {
      ForEach(model.items) { item in
        CollectionItemRow(item: item) {
          model.handleSelect(item)
        }
      }
      .listRowBackground(theme.secondarySystemBackgroundColor)
    }
    .applyListStyle(with: theme, background: theme.systemBackgroundColor)
    .navigationTitle(group.name)
    .navigationBarTitleDisplayMode(.inline)
    .overlay {
      if model.items.isEmpty {
        ContentUnavailableView(
          "browse_group_empty_title",
          systemImage: "book",
          description: Text("browse_group_empty_description")
        )
      }
    }
    .errorAlert(error: loadingState.errorBinding)
    /// Tapping a row mid-download asks before cancelling, same as the
    /// library's cancel-download alert
    .alert(
      "cancel_download_title",
      isPresented: Binding(
        get: { model.cancelDownloadTarget != nil },
        set: { if !$0 { model.cancelDownloadTarget = nil } }
      )
    ) {
      Button("ok_button") {
        if let item = model.cancelDownloadTarget {
          model.cancelDownload(of: item)
        }
      }
      Button("cancel_button", role: .cancel) {
        model.cancelDownloadTarget = nil
      }
    }
  }
}

extension ItemGroupDetailView {
  @MainActor
  class Model: ObservableObject {
    let group: SimpleItemGroup
    @Published var items = [SimpleLibraryItem]()
    /// Row mid-download awaiting the cancel confirmation — drives the alert
    @Published var cancelDownloadTarget: SimpleLibraryItem?

    init(group: SimpleItemGroup, items: [SimpleLibraryItem] = []) {
      self.group = group
      self.items = items.isEmpty ? group.items : items
    }

    /// Play the item (a folder plays its next unfinished book) — gated on
    /// its download state, like the library's artwork tap
    func handleSelect(_ item: SimpleLibraryItem) {}
    /// Confirm action of the cancel-download alert
    func cancelDownload(of item: SimpleLibraryItem) {}
  }
}
