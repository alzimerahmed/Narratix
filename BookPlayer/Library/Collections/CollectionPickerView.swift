//
//  CollectionPickerView.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import SwiftUI

/// The "Add to Collection" picker from an item's options: lists every
/// collection with a checkmark when the whole selection already belongs.
/// Tapping a fully-member row removes the selection; any other row adds it.
/// "New Collection" creates the shelf AND adds the selection in one step.
struct CollectionPickerView: View {
  @StateObject private var model: Self.Model
  @StateObject private var theme = ThemeViewModel()

  @State private var showingCreateAlert = false
  @State private var createName = ""

  @Environment(\.loadingState) private var loadingState
  @Environment(\.dismiss) private var dismiss

  init(initModel: @escaping () -> Self.Model) {
    self._model = .init(wrappedValue: initModel())
  }

  var body: some View {
    List {
      Section {
        Button {
          showingCreateAlert = true
        } label: {
          Label("collection_new_title", systemImage: "plus")
            .foregroundStyle(theme.linkColor)
        }
      }
      .listRowBackground(theme.secondarySystemBackgroundColor)

      Section {
        ForEach(model.collections) { collection in
          Button {
            model.toggle(collection)
          } label: {
            HStack {
              Text(collection.title)
                .bpFont(.body)
                .foregroundStyle(theme.primaryColor)
                .lineLimit(1)
              Spacer()
              if model.isFullyMember(collection) {
                Image(systemName: "checkmark")
                  .foregroundStyle(theme.linkColor)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityValue(
            Text(model.isFullyMember(collection) ? "collection_member_value" : "collection_not_member_value")
          )
        }
      }
      .listRowBackground(theme.secondarySystemBackgroundColor)
    }
    .environmentObject(theme)
    .applyListStyle(with: theme, background: theme.systemBackgroundColor)
    .navigationTitle("collection_picker_title")
    .navigationBarTitleDisplayMode(.inline)
    .overlay {
      if model.collections.isEmpty {
        ContentUnavailableView(
          "collection_empty_title",
          systemImage: "square.stack",
          description: Text("collection_picker_empty_description")
        )
      }
    }
    .alert("collection_new_title", isPresented: $showingCreateAlert) {
      TextField("collection_name_placeholder", text: $createName)
      Button("collection_create_and_add_title") {
        model.create(title: createName)
        createName = ""
      }
      .disabled(createName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      Button("cancel_button", role: .cancel) {
        createName = ""
      }
    }
    .errorAlert(error: $loadingState.error)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("done_title") {
          dismiss()
        }
        .foregroundStyle(theme.linkColor)
        .bold()
      }
    }
    .task {
      model.reload()
    }
  }
}

extension CollectionPickerView {
  @MainActor
  class Model: ObservableObject {
    @Published var collections = [SimpleCollection]()
    /// Collections containing EVERY selected item — partial membership doesn't
    /// earn the checkmark (toggling it adds the missing ones)
    @Published var fullyMemberUuids = Set<String>()

    init(collections: [SimpleCollection] = [], fullyMemberUuids: Set<String> = []) {
      self.collections = collections
      self.fullyMemberUuids = fullyMemberUuids
    }

    func reload() {}
    func toggle(_ collection: SimpleCollection) {}
    /// Creates the collection and immediately adds the selection
    func create(title: String) {}
    func isFullyMember(_ collection: SimpleCollection) -> Bool {
      fullyMemberUuids.contains(collection.uuid)
    }
  }
}
