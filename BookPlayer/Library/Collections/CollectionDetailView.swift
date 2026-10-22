//
//  CollectionDetailView.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import SwiftUI

/// One collection's contents. Tap plays; swiping removes the item from THIS
/// shelf only — its file and library placement are untouched (that's the whole
/// point of collections being cross-cutting).
struct CollectionDetailView: View {
  let collection: SimpleCollection
  @StateObject private var model: Self.Model
  @StateObject private var theme = ThemeViewModel()

  @Environment(\.loadingState) private var loadingState

  init(collection: SimpleCollection, initModel: @escaping () -> Self.Model) {
    self.collection = collection
    self._model = .init(wrappedValue: initModel())
  }

  var body: some View {
    List {
      ForEach(model.items) { item in
        CollectionItemRow(item: item) {
          model.handleSelect(item)
        }
        .swipeActions(edge: .trailing) {
          /// Removing from a collection isn't destructive — the book keeps
          /// its file and folder — so no destructive tint either
          Button {
            model.remove(item)
          } label: {
            Text("collection_remove_title")
          }
        }
      }
      .listRowBackground(theme.secondarySystemBackgroundColor)
    }
    .environmentObject(theme)
    .applyListStyle(with: theme, background: theme.systemBackgroundColor)
    .navigationTitle(collection.title)
    .navigationBarTitleDisplayMode(.inline)
    .overlay {
      if model.items.isEmpty {
        ContentUnavailableView(
          "collection_detail_empty_title",
          systemImage: "book",
          description: Text("collection_detail_empty_description")
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
    .task {
      model.reload()
    }
  }
}

extension CollectionDetailView {
  @MainActor
  class Model: ObservableObject {
    let collection: SimpleCollection
    @Published var items = [SimpleLibraryItem]()
    /// Row mid-download awaiting the cancel confirmation — drives the alert
    @Published var cancelDownloadTarget: SimpleLibraryItem?

    init(collection: SimpleCollection, items: [SimpleLibraryItem] = []) {
      self.collection = collection
      self.items = items
    }

    func reload() {}
    /// Play the item (a folder plays its next unfinished book) — gated on
    /// its download state, like the library's artwork tap
    func handleSelect(_ item: SimpleLibraryItem) {}
    /// Confirm action of the cancel-download alert
    func cancelDownload(of item: SimpleLibraryItem) {}
    /// Remove it from this collection only
    func remove(_ item: SimpleLibraryItem) {}
  }
}
