# Qsib Sensor iOS Utility

This repository contains a iOS/iPadOS/macOS utility for controlling devices that support the QSS BLE profile. The primary features include
* Device discovery with updating RSSI values
* Device connection
* Device configuration
* Project specific mode activation
* Real-time graphing of downsampled data
* Accurate timestamped data export

## Data Timestamping

The data exported via the QSS signal characteristic encodes the notification event for each payload. This provides near-clock accuracy of timestamps for individual sampling events. However, the iOS utility is one half of the equation.

If the firmware implementation is loose with its initiation or duration of sampling events, then the accuracy of the calculated timestamps will average the error over a payload but cannot correct the sampling rate error.

## Projects

The following projects are supported to a degree under mainline on the repository

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

