//
//  SeriesBrowseView.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import SwiftUI

/// Browse-by surfaces: series (grouped by `seriesName`, ordered by book
/// number) and authors (grouped by `details`). Whatever shows it (a sheet over
/// the library) provides the navigation stack — group details push inside it.
struct SeriesBrowseView: View {
  private enum Segment: Int {
    case series, authors
  }

  @StateObject private var model: Self.Model
  @StateObject private var theme = ThemeViewModel()
  @State private var segment: Segment = .series

  @Environment(\.loadingState) private var loadingState
  @Environment(\.dismiss) private var dismiss

  init(initModel: @escaping () -> Self.Model) {
    self._model = .init(wrappedValue: initModel())
  }

  private var groups: [SimpleItemGroup] {
    segment == .series ? model.seriesGroups : model.authorGroups
  }

  var body: some View {
    VStack(spacing: 0) {
      Picker("browse_picker", selection: $segment) {
        Text("series_title").tag(Segment.series)
        Text("authors_title").tag(Segment.authors)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(.horizontal, Spacing.S2)
      .padding(.bottom, Spacing.S2)

      List {
        ForEach(groups) { group in
          NavigationLink(value: group) {
            groupRow(group)
          }
          .listRowBackground(theme.secondarySystemBackgroundColor)
        }
      }
      .applyListStyle(with: theme, background: theme.systemBackgroundColor)
      .overlay {
        if groups.isEmpty {
          ContentUnavailableView(
            segment == .series ? "series_empty_title" : "authors_empty_title",
            systemImage: "books.vertical",
            description: Text(
              segment == .series
                ? "series_empty_description"
                : "authors_empty_description"
            )
          )
        }
      }
    }
    .environmentObject(theme)
    .background(theme.systemBackgroundColor)
    .navigationTitle("browse_title")
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(for: SimpleItemGroup.self) { group in
      ItemGroupDetailView(group: group) {
        model.makeDetailModel(for: group)
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
        .accessibilityLabel("done_title")
      }
    }
    .task {
      model.reload()
    }
  }

  private func groupRow(_ group: SimpleItemGroup) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: Spacing.S4) {
        Text(group.name)
          .bpFont(.body)
          .foregroundStyle(theme.primaryColor)
          .lineLimit(1)

        Text(
          String.localizedStringWithFormat(
            "collection_items_count".localized,
            group.items.count
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

extension SeriesBrowseView {
  @MainActor
  class Model: ObservableObject {
    @Published var seriesGroups = [SimpleItemGroup]()
    @Published var authorGroups = [SimpleItemGroup]()

    init(seriesGroups: [SimpleItemGroup] = [], authorGroups: [SimpleItemGroup] = []) {
      self.seriesGroups = seriesGroups
      self.authorGroups = authorGroups
    }

    func reload() {}
    /// The pushed detail's model — overridden by the service-backed VM
    func makeDetailModel(for group: SimpleItemGroup) -> ItemGroupDetailView.Model {
      .init(group: group)
    }
  }
}
