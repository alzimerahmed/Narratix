//
//  CoverSearchViewModel.swift
//  BookPlayer
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Foundation
import UIKit

/// Backs `CoverSearchView`: a query field, the iTunes results, and the pick
/// that downloads the full image. One search at a time — a new query cancels
/// the last, and every `didSet`-era re-search goes through `scheduleSearch` so
/// typing doesn't fire a request per keystroke.
@MainActor
final class CoverSearchViewModel: ObservableObject, BPLogger {
  @Published var query: String {
    didSet {
      if query != oldValue { scheduleSearch() }
    }
  }
  @Published private(set) var results: [CoverSearchResult] = []
  @Published private(set) var isLoading = false
  /// Whether a search has completed — gates the "no covers" empty state
  @Published private(set) var didSearch = false
  /// The result whose full image is being fetched (that cell shows a spinner)
  @Published private(set) var applyingResultID: String?
  @Published var error: Error?

  private let service: CoverSearchService
  private var searchTask: Task<Void, Never>?
  /// Stale-answer guard: a slower earlier request can't overwrite a newer
  /// query's results
  private var searchGeneration = 0

  init(query: String, service: CoverSearchService = CoverSearchService()) {
    self.query = query
    self.service = service
  }

  /// Debounced search — the field's own onSubmit path calls `search` directly
  private func scheduleSearch() {
    searchTask?.cancel()
    let text = query
    searchTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 400_000_000)
      guard !Task.isCancelled else { return }
      await search(text)
    }
  }

  func search() async {
    searchTask?.cancel()
    await search(query)
  }

  private func search(_ text: String) async {
    let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      results = []
      didSearch = false
      return
    }

    searchGeneration += 1
    let generation = searchGeneration
    isLoading = true
    didSearch = true

    do {
      let found = try await service.search(query: query)
      /// A newer search owns the field — discard this stale answer (and leave
      /// `isLoading` for it to clear)
      guard generation == searchGeneration else { return }
      results = found
      isLoading = false
    } catch is CancellationError {
      /// A newer search owns the field now
    } catch {
      self.error = error
      results = []
      isLoading = false
    }
  }

  /// Download the picked cover's full image; nil reports the failure to the view
  func select(_ result: CoverSearchResult) async -> UIImage? {
    applyingResultID = result.id
    defer { applyingResultID = nil }

    do {
      let data = try await service.imageData(for: result)
      guard let image = UIImage(data: data) else {
        error = BookPlayerError.runtimeError("Cover file couldn't be read")
        return nil
      }
      return image
    } catch {
      self.error = error
      return nil
    }
  }
}
