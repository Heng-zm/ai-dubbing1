import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation

enum WaveformGenerator {
    static func generate(from url: URL, bars: Int = 96) async throws -> [Double] {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else { return [] }

        return try await Task.detached(priority: .utility) {
            try readPeaks(asset: asset, track: track, bars: max(16, bars))
        }.value
    }

    private static func readPeaks(
        asset: AVAsset,
        track: AVAssetTrack,
        bars: Int
    ) throws -> [Double] {
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 8_000,
            AVNumberOfChannelsKey: 1
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }

        var peaks: [Double] = []
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &pointer
            )
            guard status == kCMBlockBufferNoErr, let pointer, length >= 2 else { continue }
            let sampleCount = length / MemoryLayout<Int16>.size
            let stride = max(1, sampleCount / 256)
            var peak = 0
            pointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { samples in
                var index = 0
                while index < sampleCount {
                    let value = abs(Int(samples[index]))
                    if value > peak { peak = value }
                    index += stride
                }
            }
            peaks.append(Double(peak) / Double(Int16.max))
        }

        if reader.status == .failed {
            throw reader.error ?? MediaError.metadataFailed
        }
        guard !peaks.isEmpty else { return [] }
        return downsample(peaks, bars: bars)
    }

    static func downsample(_ peaks: [Double], bars: Int) -> [Double] {
        guard !peaks.isEmpty, bars > 0 else { return [] }
        var output: [Double] = []
        output.reserveCapacity(bars)
        let bucketSize = max(1, Int(ceil(Double(peaks.count) / Double(bars))))
        var index = 0
        while index < peaks.count {
            let end = min(index + bucketSize, peaks.count)
            let slice = peaks[index..<end]
            let maxValue = slice.max() ?? 0
            let average = slice.reduce(0, +) / Double(slice.count)
            output.append(max(maxValue * 0.7, average))
            index = end
        }
        while output.count < bars {
            output.append(output.last ?? 0)
        }
        let trimmed = Array(output.prefix(bars))
        guard let maxValue = trimmed.max(), maxValue > 0.0001 else {
            return WaveformFallback.demo(count: bars)
        }
        return trimmed.map { value in
            let normalized = value / maxValue
            return max(0.08, min(1.0, pow(normalized, 0.65)))
        }
    }
}
