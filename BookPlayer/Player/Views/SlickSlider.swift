//
//  SlickSlider.swift
//  BookPlayer
//
//  Created by Pedro Iñiguez on 12/2/26.
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import SwiftUI
import BookPlayerKit

/// A chapter's spot on the book-length track: where its tick sits, what VoiceOver's chapter
/// rotor reads, and the book time a jump lands on. Fractions outside 0...1 (a marker for a
/// chapter outside the scrubber's current scope) still get a rotor entry but no tick.
struct ChapterMarker: Equatable {
  var fraction: Double
  var title: String
  /// Book-level seconds the rotor's jump targets
  var start: TimeInterval
}

// MARK: - UISlider subclass for custom track height

class ThinTrackSlider: UISlider {
  var trackHeight: CGFloat = 4
  var thumbShadowColor: UIColor = .clear {
    didSet { updateThumbShadow() }
  }
  /// Chapter ticks on the track and entries in the VoiceOver rotor. Rebuilt only when the
  /// set changes — the per-second value updates must not churn layers or elements
  var chapterMarkers: [ChapterMarker] = [] {
    didSet {
      guard chapterMarkers != oldValue else { return }
      markerElements = nil
      setNeedsLayout()
    }
  }
  var markerTint: UIColor = .secondaryLabel.withAlphaComponent(0.6) {
    didSet { ticksLayer.fillColor = markerTint.cgColor }
  }
  /// The rotor's double-tap: the owner seeks to the marker's book time
  var onMarkerActivate: ((ChapterMarker) -> Void)?

  private let shadowLayer = CALayer()
  private let ticksLayer = CAShapeLayer()
  /// Rotor entries, built once per `chapterMarkers` set: the rotor predicate identifies
  /// the current entry by element identity, so they can't be remade per search
  private var markerElements: [ChapterMarkerElement]?

  override init(frame: CGRect) {
    super.init(frame: frame)
    shadowLayer.shadowOffset = .zero
    shadowLayer.shadowRadius = 6
    shadowLayer.shadowOpacity = 1
    layer.insertSublayer(shadowLayer, at: 0)
    layer.insertSublayer(ticksLayer, above: shadowLayer)
    ticksLayer.fillColor = markerTint.cgColor
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  override func trackRect(forBounds bounds: CGRect) -> CGRect {
    let center = bounds.midY
    return CGRect(
      x: bounds.minX,
      y: center - trackHeight / 2,
      width: bounds.width,
      height: trackHeight
    )
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let thumbFrame = thumbRect(
      forBounds: bounds,
      trackRect: trackRect(forBounds: bounds),
      value: value
    )
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    shadowLayer.frame = thumbFrame
    shadowLayer.shadowPath = UIBezierPath(ovalIn: thumbFrame.offsetBy(
      dx: -thumbFrame.origin.x,
      dy: -thumbFrame.origin.y
    )).cgPath
    layoutTicks()
    CATransaction.commit()
  }

  /// Ticks sit on the track at each marker's fraction — taller than the track so they read
  /// over both its filled and unfilled sides. A marker past the track's ends (the scrubber
  /// is scoped to one chapter) draws nothing but keeps its rotor entry
  private func layoutTicks() {
    let track = trackRect(forBounds: bounds)
    let tickHeight = trackHeight * 2
    let path = UIBezierPath()
    for marker in chapterMarkers where marker.fraction > 0 && marker.fraction < 1 {
      let x = track.minX + CGFloat(marker.fraction) * track.width
      path.append(UIBezierPath(roundedRect: CGRect(
        x: x - 0.75,
        y: track.midY - tickHeight / 2,
        width: 1.5,
        height: tickHeight
      ), cornerRadius: 0.75))
    }
    ticksLayer.path = path.cgPath
    // Element frames move with the track: update them in place — the rotor predicate
    // matches the current entry by element identity, so remaking them on every
    // per-second value write (which re-runs layout) breaks flicks while playing
    if let markerElements, markerElements.count == chapterMarkers.count {
      for (element, marker) in zip(markerElements, chapterMarkers) {
        element.accessibilityFrameInContainerSpace = markerElementFrame(for: marker, in: track)
      }
    } else {
      markerElements = nil
    }
  }

  /// A rotor entry's hit rect: over its tick, tall enough to be a usable target
  private func markerElementFrame(for marker: ChapterMarker, in track: CGRect) -> CGRect {
    let tickHeight = trackHeight * 2
    let x = track.minX + CGFloat(min(max(marker.fraction, 0), 1)) * track.width
    return CGRect(x: x - 11, y: track.midY - tickHeight / 2, width: 22, height: max(tickHeight, 22))
  }

  private func updateThumbShadow() {
    shadowLayer.shadowColor = thumbShadowColor.cgColor
  }
}

// MARK: - SwiftUI wrapper

struct SlickSlider: UIViewRepresentable {
  @Binding var value: Double
  var range: ClosedRange<Double> = 0...100
  var onEditingChanged: (Bool) -> Void = { _ in }
  var onDragValueChanged: ((Double) -> Void)?
  var accentColor = Color(red: 0.35, green: 0.6, blue: 0.9)
  /// Chapter ticks on the track; with entries come the VoiceOver chapter rotor
  var chapterMarkers: [ChapterMarker] = []
  var onMarkerActivate: ((ChapterMarker) -> Void)?

  private let trackHeight: CGFloat = 4
  private let thumbSize: CGFloat = 18

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeUIView(context: Context) -> ThinTrackSlider {
    let slider = ThinTrackSlider()
    slider.trackHeight = trackHeight
    slider.minimumValue = Float(range.lowerBound)
    slider.maximumValue = Float(range.upperBound)
    slider.value = Float(value)
    slider.isContinuous = true

    let uiColor = UIColor(accentColor)
    slider.setMinimumTrackImage(
      Self.makeTrackImage(color: uiColor, height: trackHeight),
      for: .normal
    )
    slider.setMaximumTrackImage(
      Self.makeTrackImage(
        color: UIColor.secondaryLabel.withAlphaComponent(0.2),
        height: trackHeight
      ),
      for: .normal
    )
    slider.setThumbImage(
      Self.makeThumbImage(size: thumbSize, color: uiColor),
      for: .normal
    )
    slider.thumbShadowColor = uiColor.withAlphaComponent(0.6)

    slider.addTarget(
      context.coordinator,
      action: #selector(Coordinator.valueChanged(_:event:)),
      for: .valueChanged
    )

    return slider
  }

  func updateUIView(_ slider: ThinTrackSlider, context: Context) {
    if !context.coordinator.isDragging {
      slider.value = Float(value)
    }

    if context.coordinator.cachedMarkers != chapterMarkers {
      context.coordinator.cachedMarkers = chapterMarkers
      slider.chapterMarkers = chapterMarkers
    }
    slider.onMarkerActivate = onMarkerActivate

    let uiColor = UIColor(accentColor)
    if context.coordinator.cachedAccentColor != uiColor {
      context.coordinator.cachedAccentColor = uiColor
      slider.setMinimumTrackImage(
        Self.makeTrackImage(color: uiColor, height: trackHeight),
        for: .normal
      )
      slider.setMaximumTrackImage(
        Self.makeTrackImage(
          color: UIColor.secondaryLabel.withAlphaComponent(0.2),
          height: trackHeight
        ),
        for: .normal
      )
      slider.setThumbImage(
        Self.makeThumbImage(size: thumbSize, color: uiColor),
        for: .normal
      )
      slider.thumbShadowColor = uiColor.withAlphaComponent(0.6)
    }
  }

  private static func makeThumbImage(size: CGFloat, color: UIColor) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    return renderer.image { ctx in
      color.setFill()
      ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
    }
  }

  private static func makeTrackImage(color: UIColor, height: CGFloat) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: height, height: height))
    let image = renderer.image { ctx in
      let rect = CGRect(x: 0, y: 0, width: height, height: height)
      let path = UIBezierPath(roundedRect: rect, cornerRadius: height / 2)
      color.setFill()
      path.fill()
    }
    let capInset = height / 2
    return image.resizableImage(withCapInsets: UIEdgeInsets(
      top: 0, left: capInset, bottom: 0, right: capInset
    ), resizingMode: .stretch)
  }

  // MARK: - Coordinator

  class Coordinator: NSObject {
    var parent: SlickSlider
    var isDragging = false
    var cachedAccentColor: UIColor?
    var cachedMarkers: [ChapterMarker] = []

    init(_ parent: SlickSlider) {
      self.parent = parent
    }

    @objc func valueChanged(_ slider: UISlider, event: UIEvent) {
      let value = Double(slider.value)

      if let touch = event.allTouches?.first {
        switch touch.phase {
        case .began:
          isDragging = true
          parent.onEditingChanged(true)
          parent.onDragValueChanged?(value)
        case .moved:
          parent.onDragValueChanged?(value)
        case .ended, .cancelled:
          parent.value = value
          parent.onEditingChanged(false)
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isDragging = false
          }
        default:
          break
        }
      } else {
        // VoiceOver adjustments have no touch event
        parent.value = value
        parent.onDragValueChanged?(value)
        parent.onEditingChanged(false)
      }
    }
  }
}

// MARK: - Accessibility

extension ThinTrackSlider {
  override func accessibilityIncrement() {
    value = min(value + accessibilityStep, maximumValue)
    sendActions(for: .valueChanged)
  }

  override func accessibilityDecrement() {
    value = max(value - accessibilityStep, minimumValue)
    sendActions(for: .valueChanged)
  }

  private var accessibilityStep: Float {
    (maximumValue - minimumValue) * 0.01
  }

  override var accessibilityValue: String? {
    get {
      let range = Double(maximumValue - minimumValue)
      let percent = range == 0 ? 0 : Int(((Double(value - minimumValue) / range) * 100).rounded(.up))
      return String.localizedStringWithFormat("progress_complete_description".localized, percent)
    }
    set {}
  }
}

// MARK: - Chapter rotor

/// A rotor entry's element: it sits over its tick, reads the chapter's title and start time,
/// and activating it seeks the player there
private final class ChapterMarkerElement: UIAccessibilityElement {
  let marker: ChapterMarker

  init(marker: ChapterMarker, frame: CGRect, in slider: ThinTrackSlider) {
    self.marker = marker
    super.init(accessibilityContainer: slider)
    accessibilityFrameInContainerSpace = frame
    accessibilityLabel = marker.title
    accessibilityValue = TimeParser.formatTime(marker.start)
    accessibilityHint = "voiceover_chapter_jump_hint".localized
    accessibilityTraits = [.button]
  }

  override func accessibilityActivate() -> Bool {
    guard let slider = accessibilityContainer as? ThinTrackSlider else { return false }
    slider.onMarkerActivate?(marker)
    return true
  }
}

extension ThinTrackSlider {
  private var chapterRotor: UIAccessibilityCustomRotor {
    UIAccessibilityCustomRotor(name: "chapters_title".localized) { [weak self] predicate in
      self?.chapterRotorResult(for: predicate)
    }
  }

  /// The chapters rotor is offered while the scrubber carries markers — book context only;
  /// the callers pass none in chapter context, where the track spans a single chapter
  override var accessibilityCustomRotors: [UIAccessibilityCustomRotor]? {
    get {
      guard !chapterMarkers.isEmpty else { return super.accessibilityCustomRotors }
      return (super.accessibilityCustomRotors ?? []) + [chapterRotor]
    }
    set {}
  }

  private func chapterMarkerElements() -> [ChapterMarkerElement] {
    if let markerElements { return markerElements }
    let track = trackRect(forBounds: bounds)
    let built = chapterMarkers.map { marker in
      ChapterMarkerElement(
        marker: marker,
        frame: markerElementFrame(for: marker, in: track),
        in: self
      )
    }
    markerElements = built
    return built
  }

  private func chapterRotorResult(
    for predicate: UIAccessibilityCustomRotorSearchPredicate
  ) -> UIAccessibilityCustomRotorItemResult? {
    let elements = chapterMarkerElements()
    guard !elements.isEmpty else { return nil }

    let currentIndex: Int
    if let current = predicate.currentItem.targetElement as? ChapterMarkerElement,
       let index = elements.firstIndex(of: current) {
      currentIndex = index
    } else {
      // Focus arrived from anywhere else: "next" lands on the chapter after the playhead,
      // "previous" on the one before it
      let position = maximumValue > minimumValue
        ? Double((value - minimumValue) / (maximumValue - minimumValue))
        : 0
      switch predicate.direction {
      case .next:
        // One before the target, so the step below lands on the first chapter past it
        currentIndex = elements.lastIndex { $0.marker.fraction <= position } ?? -1
      case .previous:
        // One past the target: the step below lands on the last chapter before it
        currentIndex = elements.firstIndex { $0.marker.fraction >= position } ?? elements.count
      @unknown default:
        currentIndex = 0
      }
    }

    let index: Int
    switch predicate.direction {
    case .next: index = min(currentIndex + 1, elements.count - 1)
    case .previous: index = max(currentIndex - 1, 0)
    @unknown default: index = currentIndex
    }
    return UIAccessibilityCustomRotorItemResult(targetElement: elements[index], targetRange: nil)
  }
}

#Preview {
  SlickSlider(value: .constant(0.4))
}
