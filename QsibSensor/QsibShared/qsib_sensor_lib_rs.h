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
uint32_t qs_measurement_create();
bool qs_measurement_drop(uint32_t measurement_id);

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
 * @param[in] buf           The raw payload to consume for the measurement_id
 * @param[in] len           The number of bytes to read in buf
 * @param[out] modality_id  The unique id for a retire-able mode identified in the payload
 * @param[out] modality_type The [0,15] modality enumeration that mapped to the modality_id
 * @param[out] num_channels The number of channels in the payload
 * @param[out] num_samples  The number of samples in the payload
 *
 * @return success or failure to add signals
 */
bool qs_measurement_consume(uint32_t measurement_id, const uint8_t *buf, uint16_t len, int64_t *modality_id, uint8_t *modality_type, uint8_t *num_channels, uint32_t *num_samples);

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
 * @param[in] modality_id The id for a partition of data for a measurement. (Potentially no longer actively consuming payloads).
 * @param[in] hz          The rate of sampling in Hz (1 second period)
 * @param[in] rate_scaler The multiplier on the Hz period (ie 1 second * rate_scaler)
 * @param[in] downsample_seed The seed for a random number generator used to downsample data
 * @param[in] downsample_threshold The inclusive threshold to accept values after mod downsample_scale
 * @param[in] downsample_scale The mod to map random values into a continuous domain [0, scale]
 * @param[in] trailing_s If > 0, constrains eligble data points to the final trailing_s seconds of the measurement
 *
 * @param[out] buffer_id      The output buffers timestamp_data and channel_data are identified by this id.
 * @param[out] num_total_samples The number of samples in the timestamp and per channel in channel_data.
 * @param[out] num_channels      The number of channels in channel_data.
 * @param[out] timestamp_data    The buffer that will hold the result of interpreting the timestamps of each sample.
 *                                  2D like [overwritten pointer][timestamps].
 * @param[out] channel_data      The buffer that will hold the samples per channel parallel on per channel and timestamps.
 *                                  3D like [overwritten pointer][channel][samples].
 *                                  Each [samples] is of the same length as [timestamps]
 * @return success or failure
 */
bool qs_measurement_export(
    uint32_t measurement_id,
    uint32_t modality_id,
    float hz,
    float rate_scaler,
    uint64_t downsample_seed,
    uint32_t downsample_threshold,
    uint32_t downsample_scale,
    float trailing_s,
    uint32_t *buffer_id,
    uint32_t *num_total_samples,
    uint8_t *num_channels,
    double **timestamp_data,
    double ***channel_data);

/*!
 * Allows re-use of buffers assoicated with the provided id.
 *
 * If buffers are not returned, they are re-allocated every time and never free'd.
 *
 * @param[in] buffer_id  The buffer id associated with timestamp_data and channel_data from a preceding export.
 *
 * @return true if the buffer was checked out (meaning you did return a valid buffer id)
 */
bool qs_buffer_return(uint32_t buffer_id);

/*!
 * Marks a modality for a measurement as no longer active. If payloads rollover, to
 * the enumeration that indicated the modality previously, they will now reference a new
 * modality.
 *
 * Data can still be exported for this modality.
 *
 * @param[in] modality_id The id for a partition of data for a measurement. (Potentially no longer actively consuming payloads).
 */
bool qs_measurement_modality_retire(uint32_t measurement_id, uint32_t modality_id);
