//
//  QsibSensorLib.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 11/18/20.
//

import Foundation
import ZIPFoundation

enum MeasurementState {
    case initial
    case running
    case paused
    case ended
}

public struct RsParams {
    let id: UInt32
    let channels: UInt8
    let hz: Float32
    let scaler: Float32
}

public protocol DataSetProtocol {
    func getStart() -> Date?
    func getParams() -> RsParams
    func getGraphableTimestamps() -> [Double]
    func getGraphableChannels() -> [[Double]]
    func getAllTimestamps() -> [Double]
    func getAllChannels() -> [[Double]]
    func asURL() -> URL
}

public class RamDataSet: DataSetProtocol {
    let params: RsParams
    
    var start: Date?
    var payloadCount: UInt64
    var sampleCount: UInt64
    var _payloadLock = pthread_mutex_t()
    var _channelBufSize: UInt32
    var _channelLock = pthread_mutex_t()
    var _channelData: UnsafeMutablePointer<UnsafeMutablePointer<Double>?>?
    var _samplesPerChannelData: UnsafeMutablePointer<UInt32>?
    var _timestampBufSize: UInt32
    var _timestampLock = pthread_mutex_t()
    var _timestampsData: UnsafeMutablePointer<Double>?
    var _numTimestampsData: UnsafeMutablePointer<UInt32>?
    
    var avgEffectivePayloadSize: UInt32?
    var timestampOffset: Double
    
    init(libParams: RsParams, timestampOffset: Double) {
        params = libParams
        
        start = nil
        payloadCount = 0
        sampleCount = 0
        
        _channelBufSize = 0
        _timestampBufSize = 0
        
        pthread_mutex_init(&_payloadLock, nil)
        pthread_mutex_init(&_channelLock, nil)
        pthread_mutex_init(&_timestampLock, nil)
        
        avgEffectivePayloadSize = nil
        self.timestampOffset = timestampOffset
    }
    
    deinit {
        let success = qs_drop_measurement(self.params.id)
        LOGGER.trace("Dropped RamDataSet \(self.params.id) with result \(success)")
        
        if let channelData = _channelData {
            channelData.deallocate()
        }
        
        if let samplesPerChannelData = _samplesPerChannelData {
            samplesPerChannelData.deallocate()
        }
    }
    
    public func getStart() -> Date? {
        return start
    }
    
    public func getParams() -> RsParams {
        return params
    }
        
    public func asURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("data_\(params.id).csv")
        LOGGER.debug("Writing RamDataSet \(self.params.id) to \(url.absoluteString)")
        
        // Get all of the data to place in a file using the measurement id
        let ts = getAllTimestamps()
        let cs = getAllChannels()
        
        // Dump all of the data to a file as CSV
        let channelHeaders = (0..<params.channels).map { "Channel\($0)" }.joined(separator: ",")
        let csvData = "TimestampSinceCaptureStart,\(channelHeaders)\n" + zip(ts, (0..<Int(cs[0].count)))
            .map { (t, i) in
                let channelValues = (0..<cs.count)
                    .map { cs[$0][i] }
                    .map { String.init(format: "%.3f", $0) }.joined(separator: ",")
                return "\(t + timestampOffset),\(channelValues)"
            }
            .joined(separator: "\n")
        let uncompressedData = csvData.data(using: String.Encoding.utf8)!

        
        // Actual file IO
        try? FileManager.default.removeItem(at: url)
        guard FileManager.default.createFile(atPath: url.path, contents: uncompressedData, attributes: nil) else {
            fatalError("Failed to write data to file")
        }
        return url
    }
    
    public func getGraphableTimestamps() -> [Double] {
        return getTimestamps(targetCardinality: 100)
    }
    
    public func getGraphableChannels() -> [[Double]] {
        return getChannels(targetCardinality: 100)
    }
    
    public func getAllTimestamps() -> [Double] {
        return getTimestamps(targetCardinality: nil)
    }
    
    public func getAllChannels() -> [[Double]] {
        return getChannels(targetCardinality: nil)
    }
    
    func addPayload(data: Data) -> UInt32? {
//        LOGGER.trace("Adding signals from \(data.prefix(Int(data[0])).hexEncodedString())")
        guard sampleCount < UINT32_MAX - 255 else {
            LOGGER.error("Not enough space to continue allocating samples")
            return nil
        }
        
        guard data.count <= 512 else {
            LOGGER.error("Payload buffer is too big to be valid")
            return nil
        }

        let counter = (UInt64(data[4])
                        + (UInt64(data[5]) << (8 * 1))
                        + (UInt64(data[6]) << (8 * 2))
                        + (UInt64(data[7]) << (8 * 3)))
        if counter % 100 == 0 {
            LOGGER.trace("Found \(counter)th payload counter on a payload of \(data.count) bytes")
        }
        
        let len = min(UInt16(data.count), UInt16(data[0]) + (UInt16(data[1]) << 8))
        
        pthread_mutex_lock(&_payloadLock)
        defer {
            pthread_mutex_unlock(&_payloadLock)
        }
        
        var samples: UInt32? = nil
        data.withUnsafeBytes({ (buf_ptr: UnsafeRawBufferPointer) in
            let ptr = buf_ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            samples = qs_add_signals(self.params.id, ptr, UInt16(len))
        })
        
        sampleCount += UInt64(samples ?? 0)
        payloadCount += 1
        
        let effectiveSize = UInt32(data.count - (2 + 1 + 1 + 4))
        if avgEffectivePayloadSize != nil {
            avgEffectivePayloadSize = ((avgEffectivePayloadSize! * UInt32(payloadCount - 1)) + effectiveSize) / UInt32(payloadCount)
        } else {
            avgEffectivePayloadSize = effectiveSize
        }
        
        if start == nil {
            start = Date()
        }

        return samples
    }
    
    func getReadableDataRate() -> String {
        guard let start = start else {
            return "0 B/s"
        }
        
        let elapsed = Float(Date().timeIntervalSince(start))
        let effectiveBytes = Float(avgEffectivePayloadSize ?? 0) * Float(payloadCount)
        LOGGER.trace("\(payloadCount) payloads had \(avgEffectivePayloadSize ?? 0) effective bytes in \(elapsed) seconds")
        let rate = Int(effectiveBytes / elapsed)
        switch rate {
        case 0...1024:
             return "\(rate)B/s"
        case 1024...(1024*1024):
            return "\(Int(rate / 1024))KB/s"
        case (1024*1024)...:
            return "\(Int(rate / 1024 / 1024))MB/s"
        default:
            return "0 B/s"
        }
    }
    
    func getReadableDataSize(multiplier: Double) -> String {
        // Storage size in RAM as Doubles for current data set
        let totalSamples = Int(params.channels + 1) * Int(sampleCount)
        let numBytes = totalSamples * 8;
        let multipliedBytes = UInt64(multiplier * Double(numBytes))

        switch multipliedBytes {
        case 0...1024:
            return "\(multipliedBytes)B"
        case 1024...(1024*1024):
            return "\(Int(multipliedBytes / 1024))KB"
        case (1024*1024)...:
            return "\(Int(multipliedBytes / 1024 / 1024))MB"
        default:
            return "0B"
        }
    }

    private func getChannelBuffers() -> (UnsafeMutablePointer<UnsafeMutablePointer<Double>?>, UnsafeMutablePointer<UInt32>) {
        
        var newBufSize = UInt64(pow(2, ceil(log(Double(self.sampleCount)) / log(2))))
        newBufSize = min(newBufSize, UInt64(UINT32_MAX))
        newBufSize = max(newBufSize, 4096)
        
        if _channelBufSize >= newBufSize && _channelData != nil && _samplesPerChannelData != nil {
            _samplesPerChannelData![0] = _channelBufSize
            return (_channelData!, _samplesPerChannelData!)
        }
        
        _channelBufSize = UInt32(newBufSize)
        
        if let _ = _channelData {
            for i in 0..<self.params.channels {
                _channelData![Int(i)]!.deallocate()
            }
            _channelData!.deallocate()
            _samplesPerChannelData!.deallocate()
        }
        
        _channelData = UnsafeMutablePointer<UnsafeMutablePointer<Double>?>.allocate(capacity: Int(self.params.channels))
        for i in 0..<self.params.channels {
            _channelData![Int(i)] = UnsafeMutablePointer<Double>.allocate(capacity: Int(_channelBufSize))
        }
        
        _samplesPerChannelData = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        _samplesPerChannelData![0] = _channelBufSize
        
        return (_channelData!, _samplesPerChannelData!)
    }
    
    private func getTimestampBuffers() -> (UnsafeMutablePointer<Double>, UnsafeMutablePointer<UInt32>) {
        var newBufSize = UInt64(pow(2, ceil(log(Double(self.sampleCount)) / log(2))))
        newBufSize = min(newBufSize, UInt64(UINT32_MAX))
        newBufSize = max(newBufSize, 4096)

        if _timestampBufSize >= newBufSize && _timestampsData != nil && _numTimestampsData != nil {
            _numTimestampsData![0] = _timestampBufSize
            return (_timestampsData!, _numTimestampsData!)
        }
        
        _timestampBufSize = UInt32(newBufSize)
        
        if let _ = _timestampsData {
            _timestampsData!.deallocate()
            _numTimestampsData!.deallocate()
        }

        _timestampsData = UnsafeMutablePointer<Double>.allocate(capacity: Int(_timestampBufSize))
        _numTimestampsData = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)

        return (_timestampsData!, _numTimestampsData!)

    }
    
    private func getChannels(targetCardinality: UInt64?) -> [[Double]] {
        LOGGER.trace("Copying signals for RamDataSet \(self.params.id)")
        
        guard self.sampleCount < UINT32_MAX else {
            fatalError("Sample count too large to copy signals")
        }
        
        var downsampleThreshold: UInt32 = 1
        var downsampleScale: UInt32 = 1
        if let targetCardinality = targetCardinality {
            let samples = self.sampleCount > targetCardinality ? self.sampleCount : targetCardinality
            downsampleScale = 1024 * 1024
            downsampleThreshold = UInt32(UInt64(downsampleScale) * targetCardinality / samples)
        }
        
        pthread_mutex_lock(&_channelLock)
        defer {
            pthread_mutex_unlock(&_channelLock)
        }
        let (channelData, numSamplesPerChannel) = getChannelBuffers()
        
        let success = qs_copy_signals(self.params.id, 0xDEADBEEF, downsampleThreshold, downsampleScale, channelData, numSamplesPerChannel)
        if success {
            LOGGER.trace("Copied \(numSamplesPerChannel[0]) samples over \(self.params.channels) channels for RamDataSet \(self.params.id)")
            let channels: [[Double]] = (0..<self.params.channels).map { channelIndex in
                let v = [Double](UnsafeBufferPointer(start: channelData[Int(channelIndex)]!, count: Int(numSamplesPerChannel[0])))
                return v
            }
             
            return channels
        } else {
            LOGGER.error("Failed to interpret timestamps for RamDataSet \(self.params.id)")
            LOGGER.error("QS_SENSOR_LIB error message: \(String(describing: QS_LIB.getError()))")
            fatalError(String(describing: QS_LIB.getError()))
        }
    }
    
    private func getTimestamps(targetCardinality: UInt64?) -> [Double] {
        LOGGER.trace("Interpretting timestamps for RamDataSet \(self.params.id) with \(self.params.hz) Hz and \(self.params.scaler) scaler")
        
        guard self.sampleCount < UINT32_MAX else {
            fatalError("Sample count too large to interpret timestamps")
        }
        
        var downsampleThreshold: UInt32 = 1
        var downsampleScale: UInt32 = 1
        if let targetCardinality = targetCardinality {
            let samples = self.sampleCount > targetCardinality ? self.sampleCount : targetCardinality
            downsampleScale = 1024 * 1024
            downsampleThreshold = UInt32(UInt64(downsampleScale) * targetCardinality / samples)
        }
        
        pthread_mutex_lock(&_timestampLock)
        defer {
            pthread_mutex_unlock(&_timestampLock)
        }
        let (timestamps, numTimestamps) = getTimestampBuffers()
        
        let success = qs_interpret_timestamps(self.params.id, self.params.hz, self.params.scaler, 0xDEADBEEF, downsampleThreshold, downsampleScale, timestamps, numTimestamps)
        if success {
            LOGGER.trace("Interpretted \(numTimestamps[0]) timestamps for RamDataSet \(self.params.id)")
            return [Double](UnsafeBufferPointer(start: timestamps, count: Int(numTimestamps[0])))
        } else {
            LOGGER.error("Failed to interpret timestamps for RamDataSet \(self.params.id)")
            LOGGER.error("QS_SENSOR_LIB error message: \(String(describing: QS_LIB.getError()))")
            fatalError(String(describing: QS_LIB.getError()))
        }
    }
}

public class FileDataSet: DataSetProtocol {
    let start: Date?
    let params: RsParams
    let file: URL
    
    let graphableTimestamps: [Double]
    let graphableChannels: [[Double]]
        
    init(ramDataSet: RamDataSet) {
        // Keep copy of ram params and data set
        start = ramDataSet.start
        params = ramDataSet.params
        file = ramDataSet.asURL()
        
        // Cache its graphables
        graphableTimestamps = ramDataSet.getGraphableTimestamps().map { $0 + ramDataSet.timestampOffset }
        graphableChannels = ramDataSet.getGraphableChannels()
    }
    
    public func getStart() -> Date? {
        return start
    }
    
    public func getParams() -> RsParams {
        return params
    }
    
    public func getGraphableTimestamps() -> [Double] {
        return graphableTimestamps
    }
    
    public func getGraphableChannels() -> [[Double]] {
        return graphableChannels
    }
    
    /*!
     * A FileDataSet will not go to disk to find the rest of the stamps.
     */
    public func getAllTimestamps() -> [Double] {
        return graphableTimestamps
    }
    
    /*!
     * A FileDataSet will not go to disk to find the rest of the channel data.
     */
    public func getAllChannels() -> [[Double]] {
        return graphableChannels
    }
    
    public func asURL() -> URL {
        return file
    }
}

class QsMeasurement {

    var state: MeasurementState
    var dataSets: [DataSetProtocol]
    let channels: UInt8
    
    var graphables: (Date, [Double], [[Double]])
    
    public init(signalChannels: UInt8) {
        LOGGER.trace("Allocating QsMeasurment with \(signalChannels)")
        
        self.dataSets = []
        
        self.state = .initial
        self.channels = signalChannels
        self.graphables = (Date(), [], [])
    }
    
    public func addPayload(data: Data) -> UInt32? {
        // TODO: guard with mutex because only sensor lib is thread safe, UI vars are not this might get called several times concurrently
        let activeSet = dataSets.last! as! RamDataSet
        let result = activeSet.addPayload(data: data)
        let maxSamples = 1000000
        if activeSet.sampleCount > maxSamples {
            LOGGER.info("Detected ongoing measurement with active set surpassing \(maxSamples) samples")
            startNewDataSet(hz: activeSet.params.hz, scaler: activeSet.params.scaler)
        }
        return result
    }
    
    public func startNewDataSet(hz: Float32, scaler: Float32 = 1) {
        // Create a new active data set in Ram
        let params = RsParams(id: qs_create_measurement(self.channels), channels: self.channels, hz: hz, scaler: scaler)
        LOGGER.trace("Allocated a QS_SENSOR_LIB measurement with id \(params.id)")
        
        var offset: Double = 0
        if let firstStart = dataSets.first?.getStart() {
            offset += Double(Date().timeIntervalSince(firstStart))
        }

        // Convert the current active data set to a persisted data set
        if let activeSet = dataSets.last as? RamDataSet {
            dataSets[dataSets.count - 1] = FileDataSet(ramDataSet: activeSet)
        }

        // Set the new active data set as active
        dataSets.append(RamDataSet(libParams: params, timestampOffset: offset))
    }
         
    public func archive() throws -> URL? {
        LOGGER.debug("Archiving QsMeasurement of \(dataSets.count) data sets ...")

        // Create an csv zip for the data
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("archive.zip")
        try? FileManager.default.removeItem(at: url)
        guard let archive = Archive(url: url, accessMode: .create) else  {
            fatalError("Failed to create archive file")
        }
        
        for dataSet in dataSets {
            let dataSetUrl = dataSet.asURL()
            LOGGER.debug("Adding entry: \(dataSetUrl)")
            try archive.addEntry(with: dataSetUrl.lastPathComponent, relativeTo: dataSetUrl.deletingLastPathComponent(), compressionMethod: .deflate)
        }
                    
        return url
    }
    
    func getGraphables() -> ([Double], [[Double]]) {
        if Date().timeIntervalSince(graphables.0) < 1 && graphables.1.count > 0 {
            return (graphables.1, graphables.2)
        }
        
        graphables.0 = Date()
        graphables.1 = getGraphableTimestamps()
        graphables.2 = getGraphableChannels()
        return (graphables.1, graphables.2)
    }
    
    private func getGraphableTimestamps() -> [Double] {
        let asdf: [[Double]] = dataSets.map { dataSet in
            if let ramDataSet = dataSet as? RamDataSet {
                let unshifted = ramDataSet.getGraphableTimestamps()
                let shifted: [Double] = unshifted.map { $0 + ramDataSet.timestampOffset }
                return shifted
            } else {
                // timestamp offset calculation already cached
                let shifted: [Double] = dataSet.getGraphableTimestamps()
                return shifted
            }
        }
        let swiftisdoingdumbshitagain: [Double] = asdf.flatMap { $0 }
        return swiftisdoingdumbshitagain
    }
    
    private func getGraphableChannels() -> [[Double]] {
        return dataSets
            .map { $0.getGraphableChannels() }
            .reduce(Array(repeating: [], count: Int(channels)), { (acc, curr) in
                var result: [[Double]] = []
                for (acc_i, curr_i) in zip(acc, curr) {
                    result.append(acc_i + curr_i)
                }
                return result
            })
    }
}


public class QsibSensorLib {
    let initializer: Void = {
        qs_init();
        return ()
    }()
    
    public func getError() -> String? {
        let result = qs_errors_pop();
        if result != nil {
            let string = String(cString: result!)
            qs_errors_drop(result)
            return string
        }
        return nil
    }
}
