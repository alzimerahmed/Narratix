//
//  ListeningQueueView.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/5/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import SwiftUI

/// The user-managed Up Next queue. Whatever shows it (a sheet, the panel beside
/// the player) provides the navigation stack and the way out — same contract as
/// `BookmarksView`.
struct ListeningQueueView: View {
  @StateObject private var model: Self.Model
  @StateObject private var theme = ThemeViewModel()

  /// Reordering needs the list's edit mode; swipe-to-remove works without it
  @State private var editMode: EditMode = .inactive
  /// Load failures from the model land here — the player surfaces have no
  /// shared alert modifier, so the view carries its own
  @Environment(\.loadingState) private var loadingState

  /// Called after a queued item is picked, e.g. to close the sheet the list is in
  private let onSelect: () -> Void

  init(onSelect: @escaping () -> Void = {}, initModel: @escaping () -> Self.Model) {
    self.onSelect = onSelect
    self._model = .init(wrappedValue: initModel())
  }

  var body: some View {
    List {
      ForEach(model.items) { item in
        queueRow(item)
      }
      .onMove { source, destination in
        model.move(fromOffsets: source, toOffset: destination)
      }
      .onDelete { offsets in
        model.delete(at: offsets)
      }
    }
    .environmentObject(theme)
    .environment(\.editMode, $editMode)
    .listStyle(.sidebar)
    .applyListStyle(with: theme, background: theme.systemBackgroundColor)
    .navigationTitle("queue_title")
    .navigationBarTitleDisplayMode(.inline)
    .errorAlert(error: $loadingState.error)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        EditButton()
          .foregroundStyle(theme.linkColor)
      }
    }
    .overlay {
      if model.items.isEmpty {
        ContentUnavailableView(
          "queue_empty_title",
          systemImage: "text.line.last.and.arrowtriangle.forward",
          description: Text("queue_empty_description")
        )
      }
    }
  }

  @ViewBuilder
  private func queueRow(_ item: SimpleLibraryItem) -> some View {
    Button {
      model.handleSelect(item)
      onSelect()
    } label: {
      HStack(spacing: Spacing.S2) {
        VStack(alignment: .leading, spacing: Spacing.S4) {
          Text(item.title)
            .bpFont(.body)
            .foregroundStyle(theme.primaryColor)
            .lineLimit(1)

          Text(subtitle(for: item))
            .bpFont(.caption)
            .foregroundStyle(theme.secondaryColor)
            .lineLimit(1)
        }

        Spacer()

        Text(TimeParser.formatTime(item.duration))
          .bpFont(.caption)
          .foregroundStyle(theme.secondaryColor)
      }
    }
    .accessibilityHint("queue_row_play_hint")
    .listRowBackground(theme.secondarySystemBackgroundColor)
  }

  /// The row's detail line: author, falling back to the parent folder's name
  private func subtitle(for item: SimpleLibraryItem) -> String {
    let details = item.details.trimmingCharacters(in: .whitespacesAndNewlines)
    if !details.isEmpty { return details }
    return item.parentFolder ?? ""
  }
}

extension ListeningQueueView {
  @MainActor
  class Model: ObservableObject {
    @Published var items = [SimpleLibraryItem]()

    init(items: [SimpleLibraryItem] = []) {
      self.items = items
    }

    /// Play the queued item now (it leaves the queue — it's what's playing)
    func handleSelect(_ item: SimpleLibraryItem) {}
    /// Persist a reorder — the service renumbers 0…n-1 and the list refetches
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {}
    func delete(at offsets: IndexSet) {}
  }
}

#Preview {
  @Previewable var item1 = SimpleLibraryItem(
    title: "The Martian",
    details: "Andy Weir",
    speed: 1.0,
    currentTime: 0,
    duration: 36_000,
    percentCompleted: 0,
    isFinished: false,
    relativePath: "the-martian.m4b",
    remoteURL: nil,
    artworkURL: nil,
    orderRank: 0,
    parentFolder: nil,
    originalFileName: "the-martian.m4b",
    lastPlayDate: nil,
    type: .book,
    uuid: UUID().uuidString
  )

  @Previewable var item2 = SimpleLibraryItem(
    title: "Project Hail Mary",
    details: "Andy Weir",
    speed: 1.0,
    currentTime: 1200,
    duration: 60_000,
    percentCompleted: 2,
    isFinished: false,
    relativePath: "phm.m4b",
    remoteURL: nil,
    artworkURL: nil,
    orderRank: 1,
    parentFolder: nil,
    originalFileName: "phm.m4b",
    lastPlayDate: nil,
    type: .book,
    uuid: UUID().uuidString
  )

  ListeningQueueView {
    .init(items: [item1, item2])
  }
}
