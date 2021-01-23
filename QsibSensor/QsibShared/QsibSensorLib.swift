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
    func getTrailingData(secondsInTrailingWindow: Float) -> TimeSeriesData
    func getDownsampledData() -> TimeSeriesData
    func getAllData() -> TimeSeriesData
    func asURL() -> URL
}

public class TimeSeriesData {
    var timestamps: [Double]
    var channels: [[Double]]
    var shifted: Bool
    
    init(_ timestamps: [Double], _ channels: [[Double]], _ shifted: Bool = false) {
        self.timestamps = timestamps
        self.channels = channels
        self.shifted = false
    }
    
    func shift(_ timestampOffset: Double) {
        guard !shifted else {
            return
        }
        self.timestamps = self.timestamps.map { $0 + timestampOffset }
        self.shifted = true
    }
}

public class RamDataSet: DataSetProtocol {
    let params: RsParams
    
    var start: Date?
    var payloadCount: UInt64
    var sampleCount: UInt64
    
    var _payloadLock = pthread_mutex_t()
    
    var _bufSize: UInt32
    var _bufLock = pthread_mutex_t()
    var _timestampData: UnsafeMutablePointer<Double>?
    var _channelData: UnsafeMutablePointer<UnsafeMutablePointer<Double>?>?
    var _numTotalSamplesData: UnsafeMutablePointer<UInt32>?
    
    var avgEffectivePayloadSize: UInt32?
    var timestampOffset: Double
    
    init(libParams: RsParams, timestampOffset: Double) {
        params = libParams
        
        start = nil
        payloadCount = 0
        sampleCount = 0
        
        _bufSize = 0
        
        pthread_mutex_init(&_payloadLock, nil)
        pthread_mutex_init(&_bufLock, nil)
        
        avgEffectivePayloadSize = nil
        self.timestampOffset = timestampOffset
    }
    
    deinit {
        let success = qs_drop_measurement(self.params.id)
        LOGGER.trace("Dropped RamDataSet \(self.params.id) with result \(success)")
        
        if let timestampData = _timestampData {
            timestampData.deallocate()
        }
        
        if let channelData = _channelData {
            channelData.deallocate()
        }
        
        if let numTotalSamplesData = _numTotalSamplesData {
            numTotalSamplesData.deallocate()
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
        let tsd = getAllData()
        let ts = tsd.timestamps
        let cs = tsd.channels
        
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
    
    public func getTrailingData(secondsInTrailingWindow: Float) -> TimeSeriesData {
        // target cardinality is blanket across all payloads.
        // trailing window / total measurement is percent of payloads that may be downsampled
        // sampling 500 from that portion requires higher target cardinality
        let secondsInMeasurement = Float(max(sampleCount, 1)) / (params.hz * params.scaler)
        let targetCardinality = UInt64(500.0 / (max(secondsInTrailingWindow, 1.0) / max(secondsInMeasurement, 1.0)))
        return getData(targetCardinality: max(500, targetCardinality), secondsInTrailingWindow: secondsInTrailingWindow)
    }

    public func getDownsampledData() -> TimeSeriesData {
        return getData(targetCardinality: 500)
    }
    
    public func getAllData() -> TimeSeriesData {
        return getData()
    }
    
    public func addPayload(data: Data) -> UInt32? {
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

    private func getBuffers() -> (UnsafeMutablePointer<Double>, UnsafeMutablePointer<UnsafeMutablePointer<Double>?>, UnsafeMutablePointer<UInt32>) {
        
        var newBufSize = UInt64(pow(2, ceil(log(Double(self.sampleCount)) / log(2))))
        newBufSize = min(newBufSize, UInt64(UINT32_MAX))
        newBufSize = max(newBufSize, 4096)
        
        // Skip reallocating if the current buffers are big enough
        if _bufSize >= newBufSize && _timestampData != nil && _channelData != nil && _numTotalSamplesData != nil {
            _numTotalSamplesData![0] = _bufSize
            return (_timestampData!, _channelData!, _numTotalSamplesData!)
        }
        
        _bufSize = UInt32(newBufSize)
        
        // Allocate the timestampData
        if let _ = _timestampData {
            _timestampData!.deallocate()
        }
        _timestampData = UnsafeMutablePointer<Double>.allocate(capacity: Int(_bufSize))

        // Allocate the channelData
        if let _ = _channelData {
            for i in 0..<self.params.channels {
                _channelData![Int(i)]!.deallocate()
            }
            _channelData!.deallocate()
        }
        _channelData = UnsafeMutablePointer<UnsafeMutablePointer<Double>?>.allocate(capacity: Int(self.params.channels))
        for i in 0..<self.params.channels {
            _channelData![Int(i)] = UnsafeMutablePointer<Double>.allocate(capacity: Int(_bufSize))
        }
        
        // Allocate the numTotalSamplesData
        if let _ = _numTotalSamplesData {
            _numTotalSamplesData!.deallocate()
        }
        _numTotalSamplesData = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        _numTotalSamplesData![0] = _bufSize
        
        return (_timestampData!, _channelData!, _numTotalSamplesData!)
    }
        
    private func getData(targetCardinality: UInt64? = nil, secondsInTrailingWindow: Float = -1) -> TimeSeriesData {
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
        
        pthread_mutex_lock(&_bufLock)
        defer {
            pthread_mutex_unlock(&_bufLock)
        }
        let (timestampData, channelData, numTotalSamplesData) = getBuffers()
                
        let success = qs_export_signals(
            self.params.id,
            self.params.hz,
            self.params.scaler,
            0xDEADBEEF,
            downsampleThreshold,
            downsampleScale,
            secondsInTrailingWindow,
            timestampData,
            channelData,
            numTotalSamplesData)
        
        if success {
            LOGGER.trace("Copied \(numTotalSamplesData[0]) samples over \(self.params.channels) channels for RamDataSet \(self.params.id)")
            let timestamps = [Double](UnsafeBufferPointer(start: timestampData, count: Int(numTotalSamplesData[0])))
            let channels: [[Double]] = (0..<self.params.channels).map { channelIndex in
                let v = [Double](UnsafeBufferPointer(start: channelData[Int(channelIndex)]!, count: Int(numTotalSamplesData[0])))
                return v
            }
             
            return TimeSeriesData(timestamps, channels)
        } else {
            LOGGER.error("Failed to export signals for RamDataSet \(self.params.id)")
            LOGGER.error("QS_SENSOR_LIB error message: \(String(describing: QS_LIB.getError()))")
            fatalError(String(describing: QS_LIB.getError()))
        }
    }
}

public class FileDataSet: DataSetProtocol {
    let start: Date?
    let params: RsParams
    let file: URL
    
    let downsampledData: TimeSeriesData
    
    init(ramDataSet: RamDataSet) {
        // Keep copy of ram params and data set
        start = ramDataSet.start
        params = ramDataSet.params
        file = ramDataSet.asURL()
        
        // Cache its graphables with dataset timestamp offsets
        downsampledData = ramDataSet.getDownsampledData()
        downsampledData.shift(ramDataSet.timestampOffset)
    }
    
    public func getStart() -> Date? {
        return start
    }
    
    public func getParams() -> RsParams {
        return params
    }
    
    public func getAllData() -> TimeSeriesData {
        return TimeSeriesData([], [])
    }
    
    public func getTrailingData(secondsInTrailingWindow: Float) -> TimeSeriesData {
        return TimeSeriesData([], [])
    }
    
    public func getDownsampledData() -> TimeSeriesData {
        return downsampledData
    }
    
    public func asURL() -> URL {
        return file
    }
}

class QSMeasurement {
    let uuid = UUID()
    var state: MeasurementState
    var dataSets: [DataSetProtocol]
    let channels: UInt8
    let holdInRam: Bool
    
    // Data set index already cached in time series data, Time series downsampled + shifted data
    var downsampled: (Int, TimeSeriesData)
    
    var _payloadLock = pthread_mutex_t()

    
    public init(signalChannels: UInt8, holdInRam: Bool) {
        LOGGER.trace("Allocating QsMeasurement with \(signalChannels)")
        
        self.dataSets = []
        
        self.state = .initial
        self.channels = signalChannels
        self.holdInRam = holdInRam
        self.downsampled = (-1, TimeSeriesData([], Array(repeating: [], count: Int(signalChannels)), true))

        pthread_mutex_init(&self._payloadLock, nil)
    }
    
    public func id() -> UUID {
        return uuid
    }
    
    public func addPayload(data: Data) -> UInt32? {
        pthread_mutex_lock(&self._payloadLock)
        defer {
            pthread_mutex_unlock(&self._payloadLock)
        }
        
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
        pthread_mutex_lock(&self._payloadLock)
        defer {
            pthread_mutex_unlock(&self._payloadLock)
        }

        // Create a new active data set in Ram
        let params = RsParams(id: qs_create_measurement(self.channels), channels: self.channels, hz: hz, scaler: scaler)
        LOGGER.trace("Allocated a QS_SENSOR_LIB measurement with id \(params.id)")
        
        var offset: Double = 0
        if let firstStart = dataSets.first?.getStart() {
            offset += Double(Date().timeIntervalSince(firstStart))
        }

        // Convert the current active data set to a persisted data set
        if let activeSet = dataSets.last as? RamDataSet {
            if !holdInRam {
                LOGGER.trace("Flushing \(dataSets.count)(th) RamDataSet to FileDataSet")
                dataSets[dataSets.count - 1] = FileDataSet(ramDataSet: activeSet)
            } else {
                LOGGER.trace("Electing to NOT flush \(dataSets.count)(th) RamDataSet")
            }
        }

        // Set the new active data set as active
        dataSets.append(RamDataSet(libParams: params, timestampOffset: offset))
    }
         
    public func archive() throws -> URL? {
        pthread_mutex_lock(&self._payloadLock)
        defer {
            pthread_mutex_unlock(&self._payloadLock)
        }

        LOGGER.debug("Archiving QSMeasurement of \(dataSets.count) data sets ...")
        
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
    
    public func getAllData() -> TimeSeriesData {
        let resultingData = TimeSeriesData([], Array(repeating: [], count: Int(self.channels)), true)
        for dataSet in dataSets {
            let data = dataSet.getAllData()
            if let ramDataSet = dataSet as? RamDataSet {
                data.shift(ramDataSet.timestampOffset)
            }
            resultingData.timestamps.append(contentsOf: data.timestamps)
            for i in 0..<resultingData.channels.count {
                resultingData.channels[i].append(contentsOf: data.channels[i])
            }
        }
        return resultingData
    }
    
    public func getTrailingData(secondsInTrailingWindow: Float) -> TimeSeriesData {
        if let dataSet = dataSets.last {
            if let ramDataSet = dataSet as? RamDataSet {
                let data = ramDataSet.getTrailingData(secondsInTrailingWindow: secondsInTrailingWindow)
                data.shift(ramDataSet.timestampOffset)
                return data
            }
        }
        
        return getDownsampledData()
    }
    
    /*
     * [ fileDataSet, fileDataSet, ramDataSet ]
     * cache downsampled data from fileDataSet, append downsampled + shifted data from ramDataSet
     */
    public func getDownsampledData() -> TimeSeriesData {
        let (dataSetCachedIndex, timeSeriesData) = downsampled
        var newDataSetCachedIndex = dataSetCachedIndex
        var appendingOngoingTimeSeries: [TimeSeriesData] = []
        for (index, dataSet) in dataSets.enumerated() {
            if dataSetCachedIndex >= index {
                continue
            }
            
            let data = dataSet.getDownsampledData()
            if let ramDataSet = dataSet as? RamDataSet {
                data.shift(ramDataSet.timestampOffset)
                appendingOngoingTimeSeries.append(data)
            } else {
                timeSeriesData.timestamps.append(contentsOf: data.timestamps)
                for i in 0..<timeSeriesData.channels.count {
                    timeSeriesData.channels[i].append(contentsOf: data.channels[i])
                }
                newDataSetCachedIndex = index
            }
        }
        
        downsampled = (newDataSetCachedIndex, timeSeriesData)
        
        let resultingData = TimeSeriesData(timeSeriesData.timestamps, timeSeriesData.channels, true)
        for ongoingData in appendingOngoingTimeSeries {
            resultingData.timestamps.append(contentsOf: ongoingData.timestamps)
            for i in 0..<resultingData.channels.count {
                resultingData.channels[i].append(contentsOf: ongoingData.channels[i])
            }
        }
        
        return resultingData
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
