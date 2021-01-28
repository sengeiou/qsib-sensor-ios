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

public struct MeasurementParams {
    var rsId: UInt32
    var modalities: [ModalityParams]
}

public class ModalityParams {
    var modalityId: UInt32?
    var channels: UInt8?
    let hz: Float32
    let scaler: Float32
    
    init(modalityId: UInt32, channels: UInt8?, hz: Float32, scaler: Float32) {
        self.modalityId = modalityId
        self.channels = channels
        self.hz = hz
        self.scaler = scaler
    }
}

public protocol DataSetProtocol {
    func getStart() -> Date?
    func getParams() -> MeasurementParams
    func getTrailingData(modality: ModalityParams, secondsInTrailingWindow: Float) -> TimeSeriesData
    func getDownsampledData(modality: ModalityParams, targetCardinality: UInt64?) -> TimeSeriesData
    func getAllData() -> NullableTimeSeriesData
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

public class NullableTimeSeriesData {
    var timestamps: [Double]
    var channels: [[Double?]]
    var shifted: Bool
    
    init(_ timestamps: [Double], _ channels: [[Double?]], _ shifted: Bool = false) {
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
    var params: MeasurementParams
    
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
    
    init(measurementParams: MeasurementParams, timestampOffset: Double) {
        params = measurementParams
        
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
        let success = qs_measurement_drop(params.rsId)
        LOGGER.trace("Dropped Measurement \(params.rsId) with result \(success)")
        
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
    
    public func getParams() -> MeasurementParams {
        return params
    }
        
    public func asURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("data_\(params.rsId).csv")
        LOGGER.debug("Writing RamDataSet \(params.rsId) to \(url.absoluteString)")
        
        // Get all of the data to place in a file using the measurement id
        let tsd: NullableTimeSeriesData = getAllData()
        let ts = tsd.timestamps
        let cs = tsd.channels
        
        // Dump all of the data to a file as CSV
        let channelHeaders = (0..<cs.count).map { "Channel\($0)" }.joined(separator: ",")
        let csvData = "TimestampSinceCaptureStart,\(channelHeaders)\n" + zip(ts, (0..<Int(cs[0].count)))
            .map { (t, i) in
                let channelValues = (0..<cs.count)
                    .map { cs[$0][i] }
                    .map { $0 == nil ? "" : String.init(format: "%.3f", $0!) }.joined(separator: ",")
                return "\(String.init(format: "%.6f", t + timestampOffset)),\(channelValues)"
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
    
    public func getTrailingData(modality: ModalityParams, secondsInTrailingWindow: Float) -> TimeSeriesData {
        // target cardinality is blanket across all payloads.
        // trailing window / total measurement is percent of payloads that may be downsampled
        // sampling 500 from that portion requires higher target cardinality
        let secondsInMeasurement = Float(max(sampleCount, 1)) / (modality.hz * modality.scaler)
        let targetCardinality = UInt64(500.0 / (max(secondsInTrailingWindow, 1.0) / max(secondsInMeasurement, 1.0)))
        return getData(modality: modality, targetCardinality: max(500, targetCardinality), secondsInTrailingWindow: secondsInTrailingWindow)
    }

    public func getDownsampledData(modality: ModalityParams, targetCardinality: UInt64?) -> TimeSeriesData {
        return getData(modality: modality, targetCardinality: targetCardinality ?? 500)
    }
    
    public func getAllData() -> NullableTimeSeriesData {
        // TODO: Sort and interleave data
        let unsortedData = params.modalities.map {
            getData(modality: $0)
        }
        let totalChannels: Int = unsortedData.map { $0.channels.count }.reduce(0, { $0 + $1 })
        var cj = Array(repeating: 0, count: unsortedData.count)
        for i in 1..<unsortedData.count {
            cj[i] = unsortedData[i].channels.count + cj[i - 1]
        }

        
        var loop = true
        let sorted = NullableTimeSeriesData([], Array(repeating: [], count: totalChannels))
        var tj = Array(repeating: 0, count: unsortedData.count)
        while loop {
            var next: Int? = nil
            var nextStamp: Double? = nil
            for (i, data) in unsortedData.enumerated() {
                if next == nil || nextStamp == nil {
                    if !data.timestamps[tj[i]].isInfinite {
                        next = i
                        nextStamp = data.timestamps[tj[i]]
                    } else {
                        continue
                    }
                } else if nextStamp! > data.timestamps[tj[i]] {
                    next = i
                    nextStamp = data.timestamps[tj[i]]
                }
            }
            
            if let next = next {
                // Add the next timestamp
                sorted.timestamps.append(unsortedData[next].timestamps[tj[next]])
                
                // Add null for preceding modality channels
                for cji in 0..<cj[next] {
                    sorted.channels[cji].append(nil)
                }
                
                // Add next modality channels
                for cji in 0..<unsortedData[next].channels.count {
                    sorted.channels[cj[next] + cji].append(unsortedData[next].channels[cji][tj[next]])
                }
                
                // Add null for following modality channels
                for cji in cj[next]+unsortedData[next].channels.count..<totalChannels {
                    sorted.channels[cji].append(nil)
                }
                
                // Advance sorted samples for this modality
                tj[next] += 1
                
                // Allow over indexing into sentinel infinity
                if tj[next] == unsortedData[next].timestamps.count {
                    unsortedData[next].timestamps.append(Double.infinity)
                }
            } else {
                loop = false
                break
            }
        }
        
        return sorted
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
        
        let modalityId = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
        let numChannels = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        let numSamples = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        defer {
            modalityId.deallocate()
            numChannels.deallocate()
            numSamples.deallocate()
        }
        var success: Bool = false
        data.withUnsafeBytes({ (buf_ptr: UnsafeRawBufferPointer) in
            let ptr = buf_ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            success = qs_measurement_consume(self.params.rsId, ptr, UInt16(len), modalityId, numChannels, numSamples)
        })
        if !success {
            LOGGER.error("Failed to consume payload for \(self.params.rsId)")
            return nil
        }
        
        if self.params.modalities.contains(where: { $0.modalityId ?? 0 == modalityId.pointee }) {
            let modality = self.params.modalities.first(where: { $0.modalityId ?? 0 == modalityId.pointee })!
            modality.channels = numChannels.pointee
        } else if modalityId.pointee > 0 && modalityId.pointee < UINT32_MAX {
            // TODO hz will not be set correctly but the data will be recorded
            LOGGER.warning("Found unexpected modality \(modalityId.pointee) with \(numChannels.pointee) channels")
            self.params.modalities.append(ModalityParams(modalityId: UInt32(modalityId.pointee), channels: numChannels.pointee, hz: 1, scaler: 1))
        }
        
        sampleCount += UInt64(numSamples.pointee)
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

        return numSamples.pointee
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
        let totalChannels = self.params.modalities.map { $0.channels ?? 0 }.reduce(0, { $0 + $1})
        let totalSamples = Int(totalChannels + 1) * Int(sampleCount)
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
        // TODO: Be more efficient with the number to allocate
        let totalChannels = self.params.modalities.map { _ in 12 }.reduce(0, { $0 + $1})
        if let _ = _channelData {
            for i in 0..<totalChannels {
                _channelData![Int(i)]!.deallocate()
            }
            _channelData!.deallocate()
        }
        _channelData = UnsafeMutablePointer<UnsafeMutablePointer<Double>?>.allocate(capacity: Int(totalChannels))
        for i in 0..<totalChannels {
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
        
    private func getData(modality: ModalityParams, targetCardinality: UInt64? = nil, secondsInTrailingWindow: Float = -1) -> TimeSeriesData {
        LOGGER.trace("Copying signals for RamDataSet \(self.params.rsId)")
        
        guard self.sampleCount < UINT32_MAX else {
            fatalError("Sample count too large to copy signals")
        }
        
        guard let channels = modality.channels else {
            LOGGER.warning("Attempting to get data for modality that has not interpretted any channels")
            return TimeSeriesData([], [])
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
                
        let success = qs_measurement_export(
            self.params.rsId,
            modality.modalityId ?? 0,
            modality.hz,
            modality.scaler,
            0xDEADBEEF,
            downsampleThreshold,
            downsampleScale,
            secondsInTrailingWindow,
            timestampData,
            channelData,
            numTotalSamplesData)
        
        if success {
            LOGGER.trace("Copied \(numTotalSamplesData[0]) samples over \(channels) channels for RamDataSet \(self.params.rsId)")
            let timestamps = [Double](UnsafeBufferPointer(start: timestampData, count: Int(numTotalSamplesData[0])))
            let channels: [[Double]] = (0..<channels).map { channelIndex in
                let v = [Double](UnsafeBufferPointer(start: channelData[Int(channelIndex)]!, count: Int(numTotalSamplesData[0])))
                return v
            }
             
            return TimeSeriesData(timestamps, channels)
        } else {
            LOGGER.error("Failed to export signals for RamDataSet \(self.params.rsId)")
            LOGGER.error("QS_SENSOR_LIB error message: \(String(describing: QS_LIB.getError()))")
            fatalError(String(describing: QS_LIB.getError()))
        }
    }
}

public class FileDataSet: DataSetProtocol {
    let start: Date?
    let params: MeasurementParams
    let file: URL
    
    var downsampledDataByModality: [UInt32: TimeSeriesData]
    
    init(ramDataSet: RamDataSet) {
        // Keep copy of ram params and data set
        start = ramDataSet.start
        params = ramDataSet.params
        file = ramDataSet.asURL()
        
        downsampledDataByModality = [:]
        
        // Cache its graphables with dataset timestamp offsets
        for modality in ramDataSet.params.modalities {
            let downsampledData = ramDataSet.getDownsampledData(modality: modality, targetCardinality: 100)
            downsampledData.shift(ramDataSet.timestampOffset)
            downsampledDataByModality[modality.modalityId ?? 0] = downsampledData
        }
    }
    
    public func getStart() -> Date? {
        return start
    }
    
    public func getParams() -> MeasurementParams {
        return params
    }
    
    public func getAllData() -> NullableTimeSeriesData {
        LOGGER.error("FileDataSet.getAllData is intentionally a nop")
        return NullableTimeSeriesData([], Array(repeating: [], count: params.modalities.map { Int($0.channels ?? 0) }.reduce(0, +)))
    }
    
    public func getTrailingData(modality: ModalityParams, secondsInTrailingWindow: Float) -> TimeSeriesData {
        return TimeSeriesData([], [])
    }
    
    public func getDownsampledData(modality: ModalityParams, targetCardinality: UInt64?) -> TimeSeriesData {
        return downsampledDataByModality[modality.modalityId ?? 0] ?? TimeSeriesData([], [])
    }
    
    public func asURL() -> URL {
        return file
    }
}

class QSMeasurement {
    let uuid = UUID()
    var state: MeasurementState
    var dataSets: [DataSetProtocol]
    let holdInRam: Bool
    
    // Data set index already cached in time series data, Time series downsampled + shifted data
    var downsampled: (Int, [TimeSeriesData])
    
    var _payloadLock = pthread_mutex_t()

    
    public init(holdInRam: Bool) {
        LOGGER.trace("Allocating QsMeasurement with holdInRam=\(holdInRam)...")
        
        self.dataSets = []
        
        self.state = .initial
        self.holdInRam = holdInRam
        self.downsampled = (-1, [])

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
            startNewDataSet(currParams: activeSet.getParams(), acquireLock: false)
        }
        return result
    }
    
    public func getParams(hzMap: [UInt32: Float], defaultHz: Float = 1.0) -> MeasurementParams {
        var params = MeasurementParams(rsId: 0, modalities: hzMap.sorted(by: { $0.0 < $1.0}).map { ModalityParams(modalityId: $0.0, channels: nil, hz: $0.1, scaler: 1.0)})
        if let last = dataSets.last {
            for modality in last.getParams().modalities {
                if let params = params.modalities.first(where: { $0.modalityId ?? 0 == modality.modalityId ?? 0}) {
                    params.channels = modality.channels
                } else {
                    params.modalities.append(ModalityParams(modalityId: modality.modalityId ?? 0, channels: modality.channels, hz: defaultHz, scaler: 1))
                }
            }
        }
        params.modalities.sort { $0.modalityId ?? 0 < $1.modalityId ?? 0 }
        LOGGER.trace("Got params from using hz map \(hzMap): \(params)")
        return params
    }
    
    public func startNewDataSet(currParams: MeasurementParams, acquireLock: Bool = true) {
        if acquireLock {
            pthread_mutex_lock(&self._payloadLock)
        }
        
        defer {
            if acquireLock {
                pthread_mutex_unlock(&self._payloadLock)
            }
        }


        // Create a new active data set in Ram
        var newParams = currParams
        newParams.rsId = qs_measurement_create()
        LOGGER.trace("Allocated a QS_SENSOR_LIB measurement with id \(newParams.rsId)")
        
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
        dataSets.append(RamDataSet(measurementParams: newParams, timestampOffset: offset))
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
    
    public func getAllRamData() -> NullableTimeSeriesData {
        var resultingData: NullableTimeSeriesData? = nil
        for dataSet in dataSets {
            if let dataSet = dataSet as? RamDataSet {
                let data = dataSet.getAllData()
                data.shift(dataSet.timestampOffset)
                
                if resultingData == nil {
                    resultingData = data
                } else {
                    resultingData!.timestamps.append(contentsOf: data.timestamps)
                    for i in 0..<resultingData!.channels.count {
                        resultingData!.channels[i].append(contentsOf: data.channels[i])
                    }
                }
            }
        }
        return resultingData ?? NullableTimeSeriesData([], [])
    }
    
    public func getTrailingData(secondsInTrailingWindow: Float) -> [TimeSeriesData] {
        if let dataSet = dataSets.last {
            if let ramDataSet = dataSet as? RamDataSet {
                var retval: [TimeSeriesData] = []
                for modality in ramDataSet.getParams().modalities {
                    let data = ramDataSet.getTrailingData(modality: modality, secondsInTrailingWindow: secondsInTrailingWindow)
                    data.shift(ramDataSet.timestampOffset)
                    retval.append(data)
                }
                return retval
            }
        }
        
        return getDownsampledData()
    }
    
    /*
     * [ fileDataSet, fileDataSet, ramDataSet ]
     * cache downsampled data from fileDataSet, append downsampled + shifted data from ramDataSet
     
     TODO handle modalities changing channels cross data sets
     */
    public func getDownsampledData() -> [TimeSeriesData] {
        var (dataSetCachedIndex, timeSeriesData) = downsampled
        var newDataSetCachedIndex = dataSetCachedIndex
        var appendingOngoingTimeSeries: [[TimeSeriesData]] = []
        for (index, dataSet) in dataSets.enumerated() {
            if dataSetCachedIndex >= index {
                continue
            }
            
            for (i, modality) in dataSet.getParams().modalities.enumerated() {
                let data = dataSet.getDownsampledData(modality: modality, targetCardinality: nil)
                if let ramDataSet = dataSet as? RamDataSet {
                    data.shift(ramDataSet.timestampOffset)
                    if i + 1 < appendingOngoingTimeSeries.count {
                        // Don't need while because we are going from 0 up by 1, guaranteed to hit on a previous loop if file, file, ram pattern is followed
                        appendingOngoingTimeSeries.append([])
                    }
                    appendingOngoingTimeSeries[i].append(data)
                } else {
                    if i + 1 < timeSeriesData.count {
                        // Don't need while because we are going from 0 up by 1, guaranteed to hit on a previous loop if file, file, ram pattern is followed
                        timeSeriesData.append(TimeSeriesData([], Array(repeating: [], count: Int(modality.channels ?? 0))))
                    }

                    timeSeriesData[i].timestamps.append(contentsOf: data.timestamps)
                    for i in 0..<timeSeriesData[i].channels.count {
                        timeSeriesData[i].channels[i].append(contentsOf: data.channels[i])
                    }
                    
                    // set multiple times per modality because they are identical cases for dataset type
                    newDataSetCachedIndex = index
                }
            }
        }
        
        downsampled = (newDataSetCachedIndex, timeSeriesData)
        
        let resultingData = timeSeriesData.map { TimeSeriesData($0.timestamps, $0.channels, true) }
        for (i, modalityAppendingSeries) in appendingOngoingTimeSeries.enumerated() {
            for ongoingData in modalityAppendingSeries {
                resultingData[i].timestamps.append(contentsOf: ongoingData.timestamps)
                for j in 0..<resultingData[i].channels.count {
                    resultingData[i].channels[j].append(contentsOf: ongoingData.channels[j])
                }
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
    
    public func getVersion() -> String? {
        let result = qs_version_get();
        if result != nil {
            let string = String(cString: result!)
            qs_version_drop(result)
            return string
        }
        return nil
    }  
}
