//
//  QsibSensorLib.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 11/18/20.
//

import Foundation

class QsMeasurement {
    let rs_id: UInt32
    let signalChannels: UInt8
    var sampleCount: UInt64

    var graphableTimestamps: [Double]?
    var graphableChannels: [[Double]]?
    
    public init(signalChannels: UInt8) {
        LOGGER.trace("Allocating QsMeasurment with \(signalChannels)")
        self.rs_id = qs_create_measurement(signalChannels)
        self.signalChannels = signalChannels
        self.sampleCount = 0
        LOGGER.trace("Allocated QsMeasurement \(self.rs_id)")
    }
    
    deinit {
        LOGGER.trace("Dropping QsMeasumrent \(self.rs_id)")
        let success = qs_drop_measurement(self.rs_id)
        LOGGER.trace("Dropped QsMeasurement \(self.rs_id) with result \(success)")
    }
    
    public func addPayload(data: Data) -> UInt32? {
        LOGGER.trace("Adding signals from \(data)")
        guard sampleCount - 255 > UINT32_MAX else {
            LOGGER.error("Not enough space to continue allocating samples")
            return nil
        }
        
        guard data.count < 255 else {
            LOGGER.error("Payload buffer is too big to be valid")
            return nil
        }
        let len = UInt8(data.count)
        
        var samples: UInt32? = nil
        data.withUnsafeBytes({ (buf_ptr: UnsafeRawBufferPointer) in
            let ptr = buf_ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            samples = qs_add_signals(self.rs_id, ptr, len)
        })
        
        LOGGER.trace("Added \(String(describing: samples)) samples")
        sampleCount += UInt64(samples ?? 0)

        return samples
    }
    
    public func interpretTimestamps(hz: Float32, rateScaler: Float32) -> (UInt32, [Double])? {
        LOGGER.trace("Interpretting timestamps for QsMeasurement \(self.rs_id) with \(hz) Hz and \(rateScaler) scaler")
        
        guard self.sampleCount < UINT32_MAX else {
            LOGGER.error("Sample count too large to interpret timestamps")
            return nil
        }
        
        let bufSize = UInt32(min(UInt64(pow(2, ceil(log(Double(self.sampleCount)) / log(2)))), UInt64(UINT32_MAX)))
        let timestamps = UnsafeMutablePointer<Double>.allocate(capacity: Int(bufSize))
        let numTimestamps = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        numTimestamps[0] = bufSize
        let success = qs_interpret_timestamps(self.rs_id, hz, rateScaler, timestamps, numTimestamps)
        
        if success {
            LOGGER.trace("Interpretted \(numTimestamps[0]) timestamps for QsMeasurment \(self.rs_id)")
            return (numTimestamps[0], [Double](UnsafeBufferPointer(start: timestamps, count: Int(numTimestamps[0]))))
        } else {
            LOGGER.error("Failed to interpret timestamps for QsMeasurement \(self.rs_id)")
            LOGGER.error("QS_LIB error message: \(String(describing: QS_LIB.getError()))")
            return nil
        }
    }
 
    public func getSignals() -> (UInt32, [[Double]])? {
        LOGGER.trace("Copying signals for QsMeasurement \(self.rs_id)")
        
        guard self.sampleCount < UINT32_MAX else {
            LOGGER.error("Sample count too large to copy signals")
            return nil
        }
        
        let bufSize = UInt32(min(UInt64(pow(2, ceil(log(Double(self.sampleCount)) / log(2)))), UInt64(UINT32_MAX)))
        
        let channelData = UnsafeMutablePointer<UnsafeMutablePointer<Double>?>.allocate(capacity: Int(self.signalChannels))
        for i in 0..<self.signalChannels {
            channelData[Int(i)] = UnsafeMutablePointer<Double>.allocate(capacity: Int(bufSize))
        }
        let numSamplesPerChannel = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        numSamplesPerChannel[0] = bufSize
        
        let success = qs_copy_signals(self.rs_id, channelData, numSamplesPerChannel)
        if success {
            LOGGER.trace("Copied \(numSamplesPerChannel[0]) samples per channel \(self.signalChannels) for QsMeasurment \(self.rs_id)")
            let channels = (0...self.signalChannels).map { channelIndex in
                [Double](UnsafeBufferPointer(start: channelData[Int(channelIndex)]!, count: Int(numSamplesPerChannel[0])))
            }
            return (numSamplesPerChannel[0], channels)
        } else {
            LOGGER.error("Failed to interpret timestamps for QsMeasurement \(self.rs_id)")
            LOGGER.error("QS_LIB error message: \(String(describing: QS_LIB.getError()))")
            return nil
        }
    }
}


class QsibSensorLib {
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
