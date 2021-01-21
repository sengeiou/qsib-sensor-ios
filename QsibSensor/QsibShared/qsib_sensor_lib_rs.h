#include <stdint.h>
#include <stdbool.h>

/*!
 * This must be called before using the library.
 * It may be called several times and is thread-safe.
 */
void qs_init();

/*!
 * Get a human readable string VERSION for this library
 *
 * A library owned C String w/ nul-terminator is returned
 * with the expectation of the user calling the drop function.
 */
const char *qs_version_get();
void qs_version_drop(const char *free_me_please);

/*!
 * Routines that result in error conditions may queue
 * error messages to be explored by the user.
 *
 * A library owned C String w/ nul-terminator is returned
 * with the expectation of the user calling the drop function.
 */
const char *qs_errors_pop();
void qs_errors_drop(const char *free_me_please);

/*!
 * Create or drop a measurement that is tracked
 * by the uint32_t id produced during creation. It
 * will remain valid and no other measurements will
 * become associated with the id.
 *
 * Interactions with measurements are threadsafe,
 * spinning on a RwLock that is biased towards readers.
 */
uint32_t qs_create_measurement(uint8_t signal_channels);
bool qs_drop_measurement(uint32_t measurement_id);

/*!
 * Ingests a signal notification from a QSIB sensor
 * with validity checks. Failures are due to invalid
 * payload serialization.
 *
 * Error messages may be popped with the error
 * messaging API with a limit of 16 pending messages.
 *
 * Similarly thread-safe to measurement allocation.
 *
 * @return 0 on failure else number of samples consumed per channel
 */
uint32_t qs_add_signals(uint32_t measurement_id, const uint8_t *buf, uint16_t len);

/*!
 * Populates timestamp and channel buffers with data. Data is downsampled over a window
 * defined by trailing_s.
 *
 * The window may include all data and the downsampling parameters may include all data.
 *
 * Using the input sampling rate, we infer using the
 * notification counters and known samples per payload
 * to compute the device-side timestamp that is
 * accurate relative to other signals produced by this sensor.
 *
 * Note this does not provide accuracy in delay incurred due to
 * serde or transmission of signals, this information is lost.
 *
 * Error messages may be popped with the error
 * messaging API with a limit of 16 pending messages.
 *
 * Similarly thread-safe to measurement allocation.
 *
 * @param[in] hz          The rate of sampling in Hz (1 second period)
 * @param[in] rate_scaler The multiplier on the Hz period (ie 1 second * rate_scaler)
 * @param[in] downsample_seed The seed for a random number generator used to downsample data
 * @param[in] downsample_threshold The inclusive threshold to accept values after mod downsample_scale
 * @param[in] downsample_scale The mod to map random values into a continuous domain [0, scale]
 * @param[in] trailing_s If > 0, constrains eligble data points to the final trailing_s seconds of the measurement
 * @param[out] timestamp_data The buffer that will hold the result of interpreting the data
 * @param[out] channel_data The 2D matrix of [channel][samples]. [samples] is parallel to timestamp_data.
 * @param[in|out] num_total_samples (Capacity before call, Actual number after).
 *                        The number of samples each channel has in the buffer. Same for timestamp_data
 *
 * @return success or failure
 */
bool qs_export_signals(uint32_t measurement_id, float hz, float rate_scaler, uint64_t downsample_seed, uint32_t downsample_threshold, uint32_t downsample_scale, float trailing_s, double *timestamp_data, double **channel_data, uint32_t *num_total_samples);
