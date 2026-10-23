//
//  PlaybackHistoryView.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/5/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import SwiftUI

/// The playback-history timeline: one row per listening session, newest first.
/// A row's restore point is the position the session was left at — the "undo"
/// for an accidental Next or a skipped chapter. Whatever shows it (a sheet, the
/// panel beside the player) provides the navigation stack and the way out.
struct PlaybackHistoryView: View {
  @StateObject private var model: Self.Model
  /// Deliberately NOT the ambient theme: this sheet can present from player
  /// contexts where the environment theme is cover-scoped — its own source
  /// keeps the timeline on the app theme
  @StateObject private var theme = ThemeViewModel()

  /// Called after a session is picked, e.g. to close the sheet the list is in
  private let onSelect: () -> Void
  /// Load failures from the model land here — the player surfaces have no
  /// shared alert modifier, so the view carries its own
  @Environment(\.loadingState) private var loadingState

  init(onSelect: @escaping () -> Void = {}, initModel: @escaping () -> Self.Model) {
    self.onSelect = onSelect
    self._model = .init(wrappedValue: initModel())
  }

  var body: some View {
    List {
      ForEach(model.sessions) { session in
        sessionRow(session)
      }
      .onDelete { offsets in
        model.delete(at: offsets)
      }
    }
    .environmentObject(theme)
    .listStyle(.sidebar)
    .applyListStyle(with: theme, background: theme.systemBackgroundColor)
    .navigationTitle("history_title")
    .navigationBarTitleDisplayMode(.inline)
    .errorAlert(error: loadingState.errorBinding)
    .task {
      model.reload()
    }
    .overlay {
      if model.sessions.isEmpty {
        ContentUnavailableView(
          "history_empty_title",
          systemImage: "clock.arrow.circlepath",
          description: Text("history_empty_description")
        )
      }
    }
  }

  @ViewBuilder
  private func sessionRow(_ session: SimplePlaybackSession) -> some View {
    Button {
      model.handleSelect(session)
      onSelect()
    } label: {
      HStack(spacing: Spacing.S2) {
        VStack(alignment: .leading, spacing: Spacing.S4) {
          Text(session.itemTitle)
            .bpFont(.body)
            .foregroundStyle(theme.primaryColor)
            .lineLimit(1)

          Text(model.subtitle(for: session))
            .bpFont(.caption)
            .foregroundStyle(theme.secondaryColor)
            .lineLimit(1)
        }

        Spacer()

        VStack(alignment: .trailing, spacing: Spacing.S4) {
          Text(model.dateText(for: session))
            .bpFont(.caption)
            .foregroundStyle(theme.secondaryColor)
          /// Where the session was left — the position a tap restores
          Text(TimeParser.formatTime(session.position))
            .bpFont(.caption)
            .monospacedDigit()
            .foregroundStyle(theme.secondaryColor)
        }
      }
    }
    .accessibilityHint("history_row_restore_hint")
    .listRowBackground(theme.secondarySystemBackgroundColor)
  }
}

extension PlaybackHistoryView {
  @MainActor
  class Model: ObservableObject {
    @Published var sessions = [SimplePlaybackSession]()

    init(sessions: [SimplePlaybackSession] = []) {
      self.sessions = sessions
    }

    func reload() {}
    /// Jump the book back to this session's position
    func handleSelect(_ session: SimplePlaybackSession) {}
    func delete(at offsets: IndexSet) {}

    /// "N:xx played" for the row's detail line
    func subtitle(for session: SimplePlaybackSession) -> String {
      String(format: "history_session_played_format".localized, TimeParser.formatTime(session.duration))
    }

    private static let dateFormatter: DateFormatter = {
      let formatter = DateFormatter()
      formatter.dateStyle = .short
      formatter.timeStyle = .short
      return formatter
    }()

    func dateText(for session: SimplePlaybackSession) -> String {
      Self.dateFormatter.string(from: session.date)
    }
  }
}

#Preview {
  @Previewable var session = SimplePlaybackSession(
    id: "preview-1",
    date: Date(),
    position: 4230,
    duration: 1860,
    itemRelativePath: "book.m4b",
    itemTitle: "The Martian"
  )

  PlaybackHistoryView {
    .init(sessions: [session])
  }
}
