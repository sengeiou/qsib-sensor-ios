# Qsib Sensor iOS Utility

This repository contains a iOS/iPadOS/macOS utility for controlling devices that support the QSS BLE profile. The primary features include
* Device discovery with updating RSSI values
* Device connection
* Device configuration
* Project specific mode activation
* Accurate timestamped data export
* Real-time graphing of downsampled or trailing window of all channels
* Large partitioned measurements
    * Change hyper parameters mid measurement
    * Automatic partition and flush to disk for GBs of data in single measurement
* Well-tested internals: https://github.com/qsib-cbie/qsib-sensor-lib-rs

## Data Timestamping

The data exported via the QSS signal characteristic encodes the notification event for each payload. This provides near-clock accuracy of timestamps for individual sampling events. However, the iOS utility is one half of the equation.

If the firmware implementation is loose with its initiation or duration of sampling events, then the accuracy of the calculated timestamps will average the error over a payload but cannot correct the sampling rate error.

## Projects

The following projects are supported to a degree under mainline on the repository

### Oximetry Sensor (Naloxone Project)

An implantable oximeter with multiple channel streams on the order of 50-100Hz. The Biomed BLE service is directly analagous to QSS BLE service; it is temporarily supported and adapted through the existing state machine. Project mode configurations are exposed including component register configuration all the way through.

Sensor side operation is opaque for this project.

### Multiwave PPG

The PPG sensor has several configurable modes of operation during sampling. It can change the mode of operation while sampling is active or inactive. This can change the effective sampling rate on the fly. Data rates are upper bounded on the order of single KB/s in most configurations.

The PPG applies an LED stimulus while sampling a spectral sensor.

#### Components

* AS7341: Spectral Sensor
* : Accelerometer
* : PMIC

### Shunt Monitor

The monitor applies an LED stimulus and samples SAADC over various channels. The data rate is rather low as the monitoring project has an innate need for low power consumption and long sampling durations.

#### Components

* SAADC: NRF ADC


### Milk Sensor

The sensor applies an LED stimulus and samples SAADC over a single channel connected to a custom phtotodetector array. The data rate and sampling duration is configurable.

#### Components

* SAADC: NRF ADC


### Mechano-acoustic Sensor

The sensor monitors accelerometer data to export for all sorts of analysis.

#### Components
* : Accelerometer
* : PMIC

