//
//  MiniPlayerAccessoryView.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 6/9/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import SwiftUI

struct MiniPlayerAccessoryView: View {
  let relativePath: String
  let showPlayer: () -> Void

  @State private var isPlaying: Bool = false
  /// Downward drag while the swipe-to-dismiss is in flight
  @State private var dismissDrag: CGFloat = 0
  /// The drag this far unloads the book — less than the accessory's own height, so a swipe
  /// that visibly moves it dismisses it
  private let dismissThreshold: CGFloat = 30
  @EnvironmentObject private var theme: ThemeViewModel
  @EnvironmentObject private var playerManager: PlayerManager
  @Environment(\.libraryService) private var libraryService
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Dismiss = unload, not just hide: the accessory is the loaded book's presence, so the
  /// last-book marker clears with it or the next launch would bring it back
  private func dismiss() {
    playerManager.stop()
    libraryService.setLibraryLastBook(with: nil)
  }

  var voiceOverLabel: String {
    let voiceOverTitle = playerManager.currentItem?.title ?? "voiceover_no_title".localized
    let voiceOverSubtitle = playerManager.currentItem?.author ?? "voiceover_no_author".localized

    return "voiceover_miniplayer_hint".localized
      + ", "
      + String(
        describing: String.localizedStringWithFormat(
          "voiceover_currently_playing_title".localized,
          voiceOverTitle,
          voiceOverSubtitle
        )
      )
  }

  var body: some View {
    Group {
      HStack(spacing: 12) {
        MiniPlayerArtworkView(
          relativePath: relativePath,
          artworkLength: 34
        )
        .accessibilityHidden(true)
        .padding(.leading, 8)

        VStack(alignment: .leading, spacing: 0) {
          Text(verbatim: playerManager.currentItem?.title ?? "")
            .foregroundStyle(.primary)
            .bpFont(.miniPlayerTitle)
            .lineLimit(1)

          Text(verbatim: playerManager.currentItem?.author ?? "")
            .foregroundStyle(.secondary)
            .bpFont(.miniPlayerAuthor)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(voiceOverLabel)
        .accessibilityIdentifier("miniPlayer.info")
        // The swipe has no VoiceOver counterpart — dismissing is a custom action instead
        .accessibilityAction(named: "close_title") {
          dismiss()
        }
        Button {
          UIImpactFeedbackGenerator(style: .medium).impactOccurred()
          playerManager.rewind()
        } label: {
          Image(
            systemName: "arrow.counterclockwise"
          )
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 24, height: 20)
          .foregroundStyle(theme.linkColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(VoiceOverService.rewindText())
        Button {
          UIImpactFeedbackGenerator(style: .medium).impactOccurred()
          playerManager.playPause()
        } label: {
          Image(
            systemName: isPlaying
              ? "pause.fill"
              : "play.fill"
          )
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 24, height: 20)
          .foregroundStyle(theme.linkColor)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, Spacing.S1)
      .padding(.trailing, Spacing.S2)
      .contentShape(Rectangle())
      .onTapGesture {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showPlayer()
      }
      .offset(y: reduceMotion ? 0 : max(0, dismissDrag))
      .opacity(reduceMotion ? 1 : 1 - min(dismissDrag / (dismissThreshold * 2), 1))
      .simultaneousGesture(
        /// Down swipes only: sideways stays for the tab bar's own gestures, and the
        /// accessory's buttons keep their taps
        DragGesture(minimumDistance: 10)
          .onChanged { gesture in
            dismissDrag = max(0, gesture.translation.height)
          }
          .onEnded { gesture in
            dismissDrag = 0
            if gesture.translation.height > dismissThreshold {
              dismiss()
            }
          }
      )
      /// Long-press menu, the platform's convention for a Now Playing surface
      .contextMenu {
        Button {
          playerManager.playPause()
        } label: {
          Label(isPlaying ? "pause_title" : "play_title", systemImage: isPlaying ? "pause.fill" : "play.fill")
        }
        Button {
          playerManager.rewind()
        } label: {
          Label(VoiceOverService.rewindText(), systemImage: "arrow.counterclockwise")
        }
        Button {
          playerManager.forward()
        } label: {
          Label(VoiceOverService.fastForwardText(), systemImage: "arrow.clockwise")
        }
        Divider()
        Button {
          playerManager.pause()
          playerManager.jumpTo(0, recordBookmark: false)
        } label: {
          Label("jump_start_title", systemImage: "backward.end")
        }
        Button {
          playerManager.markAsCompleted(!(playerManager.currentItem?.isFinished ?? false))
        } label: {
          Label(
            playerManager.currentItem?.isFinished == true
              ? "mark_unfinished_title"
              : "mark_finished_title",
            systemImage: playerManager.currentItem?.isFinished == true ? "circle" : "checkmark.circle"
          )
        }
        Divider()
        Button {
          dismiss()
        } label: {
          Label("close_title", systemImage: "xmark")
        }
      }
    }
    .onReceive(
      playerManager.isPlayingPublisher()
        .receive(on: DispatchQueue.main)
    ) { isPlaying in
      self.isPlaying = isPlaying
    }
  }
}

#Preview {
  MiniPlayerAccessoryView(relativePath: "path/to/file.mp3") {}
}
