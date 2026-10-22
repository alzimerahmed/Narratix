//
//  EQPreset.swift
//  BookPlayer
//
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Foundation

/// The kind of biquad section a band applies.
enum EQBandKind: Int32, Equatable, Sendable {
  case peaking
  case lowShelf
  case highShelf
}

/// One equalizer band: a second-order IIR section described by shape,
/// center/corner frequency, gain and Q. Pure value type — safe to pass into
/// the tap context, computed into coefficients per `prepare()` call so the
/// filter follows whatever sample rate the render pipeline negotiates.
struct EQBandSpec: Equatable, Sendable {
  var kind: EQBandKind
  /// Hertz
  var frequency: Double
  /// Decibels — negative cuts, positive boosts
  var gainDb: Double
  /// Quality factor — peaking bands only; shelves use a fixed S = 1 slope
  var q: Double
}

/// Normalized coefficients of one biquad section (a0 folded in).
struct EQBiquadCoefficients: Equatable, Sendable {
  var b0: Float
  var b1: Float
  var b2: Float
  var a1: Float
  var a2: Float
}

/// RBJ Audio-EQ-Cookbook biquad math. Kept as pure functions so the coefficient
/// derivation is unit-testable without any audio plumbing.
enum EQBiquad {
  static let identity = EQBiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

  /// Band frequencies are clamped inside [10 Hz, 0.45 × Fs] — below 10 Hz a
  /// shelf is inaudible work, and past ~Nyquist a biquad coefficient set blows up.
  static func coefficients(for spec: EQBandSpec, sampleRate: Double) -> EQBiquadCoefficients {
    let fs = max(sampleRate, 8000)
    let frequency = min(max(spec.frequency, 10), fs * 0.45)
    let w0 = 2 * Double.pi * frequency / fs
    let cosW0 = cos(w0)
    let sinW0 = sin(w0)
    let amplitude = pow(10.0, spec.gainDb / 40.0)

    let b0, b1, b2, a0, a1, a2: Double

    switch spec.kind {
    case .peaking:
      let q = max(spec.q, 0.01)
      let alpha = sinW0 / (2 * q)
      b0 = 1 + alpha * amplitude
      b1 = -2 * cosW0
      b2 = 1 - alpha * amplitude
      a0 = 1 + alpha / amplitude
      a1 = -2 * cosW0
      a2 = 1 - alpha / amplitude

    case .lowShelf:
      // Slope S = 1 → alpha = sin(w0)/2 · √2
      let alpha = sinW0 / 2 * sqrt(2.0)
      let sqrtA = sqrt(amplitude)
      b0 = amplitude * ((amplitude + 1) - (amplitude - 1) * cosW0 + 2 * sqrtA * alpha)
      b1 = 2 * amplitude * ((amplitude - 1) - (amplitude + 1) * cosW0)
      b2 = amplitude * ((amplitude + 1) - (amplitude - 1) * cosW0 - 2 * sqrtA * alpha)
      a0 = (amplitude + 1) + (amplitude - 1) * cosW0 + 2 * sqrtA * alpha
      a1 = -2 * ((amplitude - 1) + (amplitude + 1) * cosW0)
      a2 = (amplitude + 1) + (amplitude - 1) * cosW0 - 2 * sqrtA * alpha

    case .highShelf:
      let alpha = sinW0 / 2 * sqrt(2.0)
      let sqrtA = sqrt(amplitude)
      b0 = amplitude * ((amplitude + 1) + (amplitude - 1) * cosW0 + 2 * sqrtA * alpha)
      b1 = -2 * amplitude * ((amplitude - 1) + (amplitude + 1) * cosW0)
      b2 = amplitude * ((amplitude + 1) + (amplitude - 1) * cosW0 - 2 * sqrtA * alpha)
      a0 = (amplitude + 1) - (amplitude - 1) * cosW0 + 2 * sqrtA * alpha
      a1 = 2 * ((amplitude - 1) - (amplitude + 1) * cosW0)
      a2 = (amplitude + 1) - (amplitude - 1) * cosW0 - 2 * sqrtA * alpha
    }

    guard a0.isFinite, a0 != 0 else { return identity }

    return EQBiquadCoefficients(
      b0: Float(b0 / a0),
      b1: Float(b1 / a0),
      b2: Float(b2 / a0),
      a1: Float(a1 / a0),
      a2: Float(a2 / a0)
    )
  }
}

/// The curated preset set. A small fixed set beats a broken ten-band UI: each
/// preset is a short biquad chain tuned for spoken-word audio.
enum EQPreset: String, CaseIterable, Identifiable, Sendable {
  /// EQ bypassed entirely — no audio mix is attached, zero processing overhead.
  case off
  /// EQ enabled but neutral. Also resolves to no bands, so no mix is attached;
  /// kept as an explicit choice so "enable EQ, do nothing yet" is a valid state.
  case flat
  /// Speech clarity: rumble cut, presence lift.
  case voice
  case bassBoost
  /// Brightness for dull recordings / older narrators.
  case treble

  var id: String { rawValue }

  var titleKey: String {
    switch self {
    case .off: return "eq_preset_off"
    case .flat: return "eq_preset_flat"
    case .voice: return "eq_preset_voice"
    case .bassBoost: return "eq_preset_bass_boost"
    case .treble: return "eq_preset_treble"
    }
  }

  var bands: [EQBandSpec] {
    switch self {
    case .off, .flat:
      return []
    case .voice:
      return [
        EQBandSpec(kind: .lowShelf, frequency: 100, gainDb: -4, q: 0.707),
        EQBandSpec(kind: .peaking, frequency: 300, gainDb: -2, q: 1.0),
        EQBandSpec(kind: .peaking, frequency: 3000, gainDb: +4, q: 1.0),
        EQBandSpec(kind: .highShelf, frequency: 8000, gainDb: +2, q: 0.707),
      ]
    case .bassBoost:
      return [
        EQBandSpec(kind: .lowShelf, frequency: 120, gainDb: +6, q: 0.707),
        EQBandSpec(kind: .peaking, frequency: 3000, gainDb: -1.5, q: 1.0),
      ]
    case .treble:
      return [
        EQBandSpec(kind: .lowShelf, frequency: 90, gainDb: -3, q: 0.707),
        EQBandSpec(kind: .highShelf, frequency: 4000, gainDb: +5, q: 0.707),
      ]
    }
  }
}

/// Persisted equalizer settings. Global, not per-book: EQ corrects the output
/// side (headphones, speaker, hearing profile) more than the content, and the
/// simplest reading of `SpeedService` semantics — a plain UserDefaults-backed
/// player preference — is what the rest of the controls sheet already does.
enum AudioEQSettings {
  /// Extra presence-band emphasis stacked on top of the selected preset. The
  /// low-shelf cut keeps rumble from masking the lifted speech band.
  static let voiceBoostBands: [EQBandSpec] = [
    EQBandSpec(kind: .lowShelf, frequency: 80, gainDb: -3, q: 0.707),
    EQBandSpec(kind: .peaking, frequency: 2800, gainDb: +5, q: 1.0),
  ]

  /// Hard cap on the rendered chain — bounds the per-frame work in `process`
  /// no matter how the band lists evolve.
  static let maxBands = 6

  static var preset: EQPreset {
    get {
      guard
        let raw = UserDefaults.standard.string(forKey: Constants.UserDefaults.equalizerPreset),
        let preset = EQPreset(rawValue: raw)
      else { return .off }
      return preset
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: Constants.UserDefaults.equalizerPreset)
    }
  }

  static var voiceBoostEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: Constants.UserDefaults.voiceBoostEnabled) }
    set { UserDefaults.standard.set(newValue, forKey: Constants.UserDefaults.voiceBoostEnabled) }
  }

  /// The full chain to render: preset bands followed by the voice-boost pair.
  /// `.off` means no EQ at all — a persisted voice boost stays inert rather
  /// than forming a chain of its own. Empty when nothing should color the
  /// audio — callers must treat that as "attach no mix at all", which is what
  /// keeps the off path zero-overhead.
  static var effectiveBands: [EQBandSpec] {
    guard preset != .off else { return [] }
    var bands = preset.bands
    if voiceBoostEnabled {
      bands += voiceBoostBands
    }
    return Array(bands.prefix(maxBands))
  }

  /// Linear preamp that heads off clipping when bands boost. Heuristic, not a
  /// limiter: pull down by the overshoot above 3 dB of headroom, capped at −6 dB.
  static func preamp(for bands: [EQBandSpec]) -> Float {
    let maxBoost = bands.map(\.gainDb).max() ?? 0
    guard maxBoost > 3 else { return 1 }
    let preampDb = max(-6, -(maxBoost - 3))
    return Float(pow(10.0, preampDb / 20.0))
  }
}
