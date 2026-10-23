//
//  CoverSearchView.swift
//  BookPlayer
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Kingfisher
import SwiftUI

/// Online cover lookup, presented from an item's artwork options. Picking a
/// result downloads its full image and hands it back through `onSelect` — the
/// caller (item details) stores it through the same path as a picked photo.
struct CoverSearchView: View {
  @StateObject private var viewModel: CoverSearchViewModel
  let onSelect: (UIImage) -> Void

  @EnvironmentObject private var theme: ThemeViewModel
  @Environment(\.dismiss) private var dismiss

  private let columns = [
    GridItem(.flexible(), spacing: Spacing.S),
    GridItem(.flexible(), spacing: Spacing.S),
    GridItem(.flexible(), spacing: Spacing.S),
  ]

  init(query: String, onSelect: @escaping (UIImage) -> Void) {
    self._viewModel = .init(wrappedValue: CoverSearchViewModel(query: query))
    self.onSelect = onSelect
  }

  var body: some View {
    NavigationStack {
      content
        .navigationTitle("cover_search_title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("cancel_button", role: .cancel) { dismiss() }
          }
        }
        .searchable(text: $viewModel.query, prompt: "cover_search_placeholder")
        .onSubmit(of: .search) {
          Task { await viewModel.search() }
        }
        .task {
          await viewModel.search()
        }
        .errorAlert(error: $viewModel.error)
        .tint(theme.linkColor)
        .toolbarColorScheme(theme.useDarkVariant ? .dark : .light, for: .navigationBar)
    }
  }

  @ViewBuilder
  private var content: some View {
    if viewModel.isLoading {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.systemBackgroundColor)
    } else if viewModel.results.isEmpty {
      emptyState
    } else {
      resultsGrid
    }
  }

  @ViewBuilder
  private var emptyState: some View {
    if viewModel.didSearch {
      ContentUnavailableView {
        Label("cover_search_empty_title", systemImage: "photo.on.rectangle.angled")
      } description: {
        Text("cover_search_empty_description")
      }
      .foregroundStyle(theme.primaryColor)
      .background(theme.systemBackgroundColor)
    } else {
      ContentUnavailableView {
        Label("cover_search_hint_title", systemImage: "magnifyingglass")
      } description: {
        Text("cover_search_hint_description")
      }
      .foregroundStyle(theme.primaryColor)
      .background(theme.systemBackgroundColor)
    }
  }

  private var resultsGrid: some View {
    ScrollView {
      LazyVGrid(columns: columns, spacing: Spacing.S) {
        ForEach(viewModel.results) { result in
          coverCell(result)
        }
      }
      .padding(Spacing.S)
    }
    .background(theme.systemBackgroundColor)
  }

  private func coverCell(_ result: CoverSearchResult) -> some View {
    Button {
      Task {
        if let image = await viewModel.select(result) {
          onSelect(image)
          dismiss()
        }
      }
    } label: {
      ZStack {
        KFImage(result.thumbnailURL)
          .resizable()
          .aspectRatio(1, contentMode: .fill)
          .clipped()
          .accessibilityHidden(true)

        if viewModel.applyingResultID == result.id {
          Rectangle().fill(.black.opacity(0.4))
          ProgressView().tint(.white)
        }
      }
      .cornerRadius(Spacing.S1)
    }
    .buttonStyle(.plain)
    .disabled(viewModel.applyingResultID != nil)
    .accessibilityLabel(Text("\(result.title), \(result.author)"))
    .accessibilityHint("cover_search_pick_hint")
  }
}
