//
//  CollectionListView.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import SwiftUI

/// The user's shelves: cross-cutting collections a book can belong to many of
/// (unlike folders, which are single-parent). Whatever shows it (a sheet over
/// the library) provides the navigation stack — the detail pushes inside it.
/// Same contract as `ListeningQueueView`.
struct CollectionListView: View {
  @StateObject private var model: Self.Model
  /// Ambient: the presenting sheet's environment already carries it —
  /// a second source here would fork the theme
  @EnvironmentObject private var theme: ThemeViewModel

  /// "New collection" name input — its own alert, on its own binding
  @State private var showingCreateAlert = false
  @State private var createName = ""
  /// Rename target + text — carried on the collection so the alert can
  /// prepopulate with the current title
  @State private var renameTarget: SimpleCollection?
  @State private var renameName = ""

  @Environment(\.loadingState) private var loadingState
  @Environment(\.dismiss) private var dismiss

  init(initModel: @escaping () -> Self.Model) {
    self._model = .init(wrappedValue: initModel())
  }

  var body: some View {
    List {
      ForEach(model.collections) { collection in
        NavigationLink(value: collection) {
          collectionRow(collection)
        }
        .swipeActions(edge: .trailing) {
          Button("delete_button", role: .destructive) {
            model.delete(collection)
          }
        }
        .contextMenu {
          Button {
            renameName = collection.title
            renameTarget = collection
          } label: {
            Label("collection_rename_title", systemImage: "square.and.pencil")
          }
        }
      }
      .listRowBackground(theme.secondarySystemBackgroundColor)
    }
    .applyListStyle(with: theme, background: theme.systemBackgroundColor)
    .navigationTitle("collections_title")
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(for: SimpleCollection.self) { collection in
      CollectionDetailView(collection: collection) {
        model.makeDetailModel(for: collection)
      }
    }
    .overlay {
      if model.collections.isEmpty {
        ContentUnavailableView(
          "collection_empty_title",
          systemImage: "square.stack",
          description: Text("collection_empty_description")
        )
      }
    }
    .alert("collection_new_title", isPresented: $showingCreateAlert) {
      TextField("collection_name_placeholder", text: $createName)
      Button("create_button") {
        model.create(title: createName)
        createName = ""
      }
      .disabled(createName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      Button("cancel_button", role: .cancel) {
        createName = ""
      }
    }
    .alert(
      "collection_rename_title",
      isPresented: Binding(
        get: { renameTarget != nil },
        set: { if !$0 { renameTarget = nil } }
      )
    ) {
      TextField("collection_name_placeholder", text: $renameName)
      Button("save_button") {
        if let renameTarget {
          model.rename(renameTarget, title: renameName)
        }
        renameTarget = nil
      }
      .disabled(renameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      Button("cancel_button", role: .cancel) {
        renameTarget = nil
      }
    }
    .errorAlert(error: loadingState.errorBinding)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .foregroundStyle(theme.linkColor)
        }
        .accessibilityLabel("close_title")
      }
      ToolbarItem(placement: .primaryAction) {
        Button {
          showingCreateAlert = true
        } label: {
          Image(systemName: "plus")
            .foregroundStyle(theme.linkColor)
        }
        .accessibilityLabel("collection_new_title")
      }
    }
    .task {
      model.reload()
    }
  }

  private func collectionRow(_ collection: SimpleCollection) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: Spacing.S4) {
        Text(collection.title)
          .bpFont(.body)
          .foregroundStyle(theme.primaryColor)
          .lineLimit(1)

        Text(
          String.localizedStringWithFormat(
            "collection_items_count".localized,
            collection.itemCount
          )
        )
        .bpFont(.caption)
        .foregroundStyle(theme.secondaryColor)
      }

      Spacer()
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

extension CollectionListView {
  @MainActor
  class Model: ObservableObject {
    @Published var collections = [SimpleCollection]()

    init(collections: [SimpleCollection] = []) {
      self.collections = collections
    }

    func reload() {}
    func create(title: String) {}
    func rename(_ collection: SimpleCollection, title: String) {}
    func delete(_ collection: SimpleCollection) {}
    /// The pushed detail's model — overridden by the service-backed VM, which
    /// is the one holding the services
    func makeDetailModel(for collection: SimpleCollection) -> CollectionDetailView.Model {
      .init(collection: collection)
    }
  }
}
