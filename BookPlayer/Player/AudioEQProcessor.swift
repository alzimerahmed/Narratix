//
//  AudioEQProcessor.swift
//  BookPlayer
//
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//
//  Equalizer DSP for the single-AVPlayer pipeline: an MTAudioProcessingTap
//  hung off AVPlayerItem.audioMix, so playback stays on AVPlayer (time
//  observers, remote commands, per-book speed and AVAudioSession lifecycle all
//  untouched) while the tap filters decoded PCM in place on the render thread.
//
//  Real-time thread discipline (hard requirement):
//  - `process` runs on a Core Media render thread — no locks, no allocations,
//    no Objective-C messaging, no Swift-object dereferencing inside it.
//  - Everything `process` touches lives in one heap-allocated POD context the
//    tap owns outright: allocated in `EQTap.create`, freed in `finalize`.
//  - Band coefficients are immutable for the tap's lifetime and recomputed in
//    `prepare` from the negotiated format, so format/sample-rate changes are
//    handled by construction. Changing settings means building a NEW mix —
//    there is no cross-thread parameter channel to get wrong.
//

import AVFoundation
import Foundation
import MediaToolbox

/// Builds an `AVAudioMix` carrying the equalizer tap for a player item's asset.
/// Implementations must never throw: EQ can only ever skip processing, it must
/// never be able to break playback.
protocol AudioEQProcessing {
  /// The mix to assign to `AVPlayerItem.audioMix`, or nil when nothing should
  /// color the audio (EQ off, no effective bands, no audio track, or tap
  /// creation failed). Callers assign the result verbatim — nil restores the
  /// unprocessed path.
  func audioMixIfEnabled(for asset: AVAsset) async -> AVAudioMix?
}

final class AudioEQProcessor: AudioEQProcessing {
  func audioMixIfEnabled(for asset: AVAsset) async -> AVAudioMix? {
    let bands = AudioEQSettings.effectiveBands
    guard !bands.isEmpty else { return nil }

    /// The tap binds to real `AVAssetTrack`s. Loading tracks reads the media
    /// header — instant for local files, a range request for remote/progressive
    /// assets. A failure (or an asset with no audio track) simply means no EQ.
    /// Note: MTAudioProcessingTap does not engage on HLS streams — this app only
    /// ever streams progressive file URLs, so non-local sources are supported.
    guard let tracks = try? await asset.load(.tracks) else { return nil }

    var inputParameters = [AVAudioMixInputParameters]()
    let preamp = AudioEQSettings.preamp(for: bands)
    for track in tracks where track.mediaType == .audio {
      guard let tap = EQTap.create(bands: bands, preamp: preamp) else { continue }
      let parameters = AVMutableAudioMixInputParameters(track: track)
      parameters.audioTapProcessor = tap
      inputParameters.append(parameters)
    }
    guard !inputParameters.isEmpty else { return nil }

    let mix = AVMutableAudioMix()
    mix.inputParameters = inputParameters
    return mix
  }
}

// MARK: - Tap internals

/// Channels beyond this pass through unfiltered. Audiobooks are mono/stereo;
/// 8 covers any plausible multichannel file without sizing state dynamically.
private let eqMaxChannels = 8

/// Per-band, per-channel filter memory for the transposed direct-form II
/// sections running in `process`.
private struct EQBiquadState {
  var s1: Float
  var s2: Float
}

/// The render-thread context the tap owns. Plain-old-data only: two pointer
/// fields reference fixed-capacity buffers allocated alongside the context.
/// Lifecycle is exact — `finalize` frees all four allocations, and the tap can
/// only be finalized after its last `process` call returns (Core Media tears
/// the tap down on the render thread).
private struct EQTapContext {
  /// Non-zero until `prepare` has proven the render format is float32 PCM —
  /// `process` then leaves the source audio untouched
  var bypass: UInt8
  var bandCount: Int32
  /// Linear gain applied before the band cascade (anti-clip headroom)
  var preamp: Float
  /// `bandCount` entries — the immutable band specs this tap was built with
  var specs: UnsafeMutablePointer<EQBandSpec>
  /// `bandCount` entries — computed in `prepare` for the negotiated sample rate
  var coefficients: UnsafeMutablePointer<EQBiquadCoefficients>
  /// `bandCount * eqMaxChannels` entries, band-major: `states[band * eqMaxChannels + channel]`
  var states: UnsafeMutablePointer<EQBiquadState>
}

private let eqTapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
  tapStorageOut.pointee = clientInfo
}

private let eqTapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
  let context = MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: EQTapContext.self)
  context.pointee.specs.deallocate()
  context.pointee.coefficients.deallocate()
  context.pointee.states.deallocate()
  context.deallocate()
}

/// Runs before the first `process` call, on the render stream start — allowed
/// to compute and write state (unlike `process`, it is not allocation-bound).
/// Recomputes coefficients from the negotiated format, so a sample-rate or
/// channel-count change between renders is handled by re-preparing, not by
/// racing a settings write.
private let eqTapPrepare: MTAudioProcessingTapPrepareCallback = { tap, _, processingFormat in
  let context = MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: EQTapContext.self)
  let format = processingFormat.pointee

  /// `process` reads Float32 samples — a Float64 LPCM format is "float" but
  /// would be misinterpreted, so it takes the bypass path too
  let isFloatPCM =
    format.mFormatID == kAudioFormatLinearPCM
    && (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
    && format.mBitsPerChannel == 32

  guard isFloatPCM, format.mSampleRate > 0, format.mChannelsPerFrame > 0 else {
    context.pointee.bypass = 1
    return
  }

  context.pointee.bypass = 0

  let bandCount = Int(context.pointee.bandCount)
  for index in 0..<bandCount {
    context.pointee.coefficients[index] = EQBiquad.coefficients(
      for: context.pointee.specs[index],
      sampleRate: format.mSampleRate
    )
  }
  context.pointee.states.assign(
    repeating: EQBiquadState(s1: 0, s2: 0),
    count: bandCount * eqMaxChannels
  )
}

private let eqTapUnprepare: MTAudioProcessingTapUnprepareCallback = { tap in
  let context = MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: EQTapContext.self)
  context.pointee.states.assign(
    repeating: EQBiquadState(s1: 0, s2: 0),
    count: Int(context.pointee.bandCount) * eqMaxChannels
  )
}

/// REAL-TIME PATH — allocation-free, lock-free, ObjC-free by inspection:
/// `GetSourceAudio` fills the buffers, then a scalar biquad cascade filters
/// samples in place. Everything read lives in the POD context; every write is
/// to tap-owned memory or the render buffers themselves.
private let eqTapProcess: MTAudioProcessingTapProcessCallback = { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
  guard
    MTAudioProcessingTapGetSourceAudio(
      tap,
      numberFrames,
      bufferListInOut,
      flagsOut,
      nil,
      numberFramesOut
    ) == noErr
  else {
    /// Source pull failed — the buffers are undefined. Emit silence rather
    /// than letting uninitialized samples reach the output.
    for buffer in UnsafeMutableAudioBufferListPointer(bufferListInOut) {
      if let data = buffer.mData {
        memset(data, 0, Int(buffer.mDataByteSize))
      }
    }
    numberFramesOut.pointee = numberFrames
    flagsOut.pointee = 0
    return
  }

  let context = MTAudioProcessingTapGetStorage(tap).assumingMemoryBound(to: EQTapContext.self)
  let bandCount = Int(context.pointee.bandCount)
  guard context.pointee.bypass == 0, bandCount > 0 else { return }

  let preamp = context.pointee.preamp
  let coefficients = context.pointee.coefficients
  let states = context.pointee.states

  /// Buffers arrive as float32 — non-interleaved in practice, but the loop also
  /// honors a packed layout via `mNumberChannels` as the interleave stride.
  var channelBase = 0
  for buffer in UnsafeMutableAudioBufferListPointer(bufferListInOut) {
    guard let data = buffer.mData else { continue }
    let channelsInBuffer = Int(buffer.mNumberChannels)
    guard channelsInBuffer > 0 else { continue }
    /// `mDataByteSize` is capacity, `numberFrames` is what was actually filled —
    /// a short EOF read must not filter uninitialized tail bytes into the state
    let frames = min(
      Int(buffer.mDataByteSize) / (MemoryLayout<Float>.stride * channelsInBuffer),
      Int(numberFrames)
    )
    let samples = data.assumingMemoryBound(to: Float.self)

    for channelInBuffer in 0..<channelsInBuffer {
      let channel = channelBase + channelInBuffer
      guard channel < eqMaxChannels else { break }

      var sample = samples + channelInBuffer
      for _ in 0..<frames {
        var value = sample.pointee * preamp
        for band in 0..<bandCount {
          let coefficient = coefficients[band]
          let state = states + band * eqMaxChannels + channel
          let output = coefficient.b0 * value + state.pointee.s1
          state.pointee.s1 = coefficient.b1 * value - coefficient.a1 * output + state.pointee.s2
          state.pointee.s2 = coefficient.b2 * value - coefficient.a2 * output
          /// Flush-to-zero: denormal filter state costs orders of magnitude
          /// more per multiply and would burn render budget on silence
          if state.pointee.s1.magnitude < .leastNormalMagnitude { state.pointee.s1 = 0 }
          if state.pointee.s2.magnitude < .leastNormalMagnitude { state.pointee.s2 = 0 }
          value = output
        }
        sample.pointee = value
        sample += channelsInBuffer
      }
    }
    channelBase += channelsInBuffer
  }
}

/// Tap construction. Returns nil when Core Media refuses — callers then attach
/// no mix and audio plays exactly as it does without EQ.
enum EQTap {
  static func create(bands: [EQBandSpec], preamp: Float) -> MTAudioProcessingTap? {
    guard !bands.isEmpty else { return nil }

    /// One owned allocation chain the tap carries to `finalize` — no Swift
    /// object is ever reachable from the render thread.
    let specs = UnsafeMutablePointer<EQBandSpec>.allocate(capacity: bands.count)
    specs.initialize(from: bands, count: bands.count)
    let coefficients = UnsafeMutablePointer<EQBiquadCoefficients>.allocate(capacity: bands.count)
    coefficients.initialize(repeating: .identity, count: bands.count)
    let states = UnsafeMutablePointer<EQBiquadState>.allocate(capacity: bands.count * eqMaxChannels)
    states.initialize(repeating: EQBiquadState(s1: 0, s2: 0), count: bands.count * eqMaxChannels)
    let context = UnsafeMutablePointer<EQTapContext>.allocate(capacity: 1)
    context.initialize(to: EQTapContext(
      bypass: 1,
      bandCount: Int32(bands.count),
      preamp: preamp,
      specs: specs,
      coefficients: coefficients,
      states: states
    ))

    var callbacks = MTAudioProcessingTapCallbacks()
    callbacks.version = kMTAudioProcessingTapCallbacksVersion_0
    callbacks.clientInfo = UnsafeMutableRawPointer(context)
    callbacks.`init` = eqTapInit
    callbacks.finalize = eqTapFinalize
    callbacks.prepare = eqTapPrepare
    callbacks.unprepare = eqTapUnprepare
    callbacks.process = eqTapProcess

    var tapReference: Unmanaged<MTAudioProcessingTap>?
    let status = MTAudioProcessingTapCreate(
      kCFAllocatorDefault,
      &callbacks,
      kMTAudioProcessingTapCreationFlag_PostEffects,
      &tapReference
    )

    guard status == noErr, let tap = tapReference?.takeRetainedValue() else {
      specs.deallocate()
      coefficients.deallocate()
      states.deallocate()
      context.deallocate()
      return nil
    }

    return tap
  }
}
