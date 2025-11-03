# CNN Simulation Mode for SPI Controller

## Overview
The `arty_spi_top` module now supports two operating modes controlled by switch SW[0] on the Arty A7-100T board:

### Mode 0: Echo Mode (SW[0] = OFF)
- **Behavior**: SPI slave immediately echoes back an incrementing counter value (0x00, 0x01, 0x02, ...)
- **Use Case**: Basic SPI communication testing and verification
- **LEDs**: Display last received byte

### Mode 1: CNN Simulation Mode (SW[0] = ON)
- **Behavior**: Simulates a CNN inference pipeline for 28×28 grayscale image classification
- **Status Byte Protocol**: SPI slave returns status information during processing
  - **0x00**: IDLE state (waiting for image)
  - **0x1X**: COLLECTING state (X shows progress, 0-F for pixels 0-783)
  - **0x20**: PROCESSING state (computing for 2ms)
  - **0x8X**: RESULT_READY state (X is the classification result 0-F)
- **Process**:
  1. **Collecting Phase**: Receives exactly 784 bytes (28×28 pixels) from SPI master
     - **Full-duplex operation**: For each pixel byte sent, master receives a status byte back
     - Status bytes progress from 0x10 → 0x1F showing collection progress
     - Example: Send pixel[0] → receive 0x00 (IDLE), Send pixel[1] → receive 0x10, ..., Send pixel[783] → receive 0x1F
  2. **Processing Phase**: Waits 2ms to simulate CNN computation
     - SPI slave responds with 0x20 if polled during processing
  3. **Result Phase**: Returns result byte with MSB set (0x8X)
     - After 2ms delay, status byte changes to 0x8X where X is the classification result
     - Master can detect result ready by checking if MSB is set (status & 0x80)
- **Use Case**: Testing CNN integration with external host

## LED Status Indicators

### RGB LED0 (Status)
- **Red (led0_r)**: Blinks when data received
- **Green (led0_g)**: **CNN Mode Indicator** - ON when SW[0] is high (CNN mode), shows TX ready in echo mode
- **Blue (led0_b)**: **CNN Processing** - lights up during 2ms computation delay

### RGB LED1 (Data bits 4-6)
- Shows bits 4-6 of last received byte

### RGB LED2 (MSB + State)
- **Red (led2_r)**: Bit 7 of last received byte
- **Green (led2_g)**: **CNN Collecting** - lights up while receiving 784 pixels
- **Blue (led2_b)**: **Result Ready** - lights up when result is ready to read (SENDING_RESULT state)

### Regular LEDs (led[3:0])
- Display lower 4 bits of last received byte

## FSM States (CNN Mode)

```
IDLE → COLLECTING → PROCESSING → SENDING_RESULT → IDLE
```

1. **IDLE**: Waiting for first pixel with CNN mode enabled
2. **COLLECTING**: Receiving pixels 0-783 (pixel counter displayed on LED2_g)
3. **PROCESSING**: 2ms delay simulation (LED0_b on)
4. **SENDING_RESULT**: Transmit classification result back to master
5. **IDLE**: Return to idle, ready for next image

## Timing Specifications

- **CNN_INPUT_SIZE**: 784 bytes (28×28)
- **CNN_DELAY_CYCLES**: 200,000 cycles
- **Processing Time**: 2ms at 100 MHz system clock
- **Dummy Result**: Computed as sum of lower nibbles (bits 3:0) of all 784 received pixels, modulo 16
  - Result value = (sum of all pixel[3:0]) mod 16
  - Displayed as 0x0X where X is the result digit

## Status Byte Protocol (CNN Mode)

The FPGA returns a **status byte** for every SPI transaction, allowing the master to monitor progress:

| Status Byte | State | Description |
|-------------|-------|-------------|
| `0x00` | IDLE | Waiting for image data (CNN ready) |
| `0x10-0x1F` | COLLECTING | Receiving pixels (nibble shows progress: 0=0-63 pixels, F=720-783 pixels) |
| `0x20` | PROCESSING | Computing CNN result (2ms delay) |
| `0x80-0x8F` | RESULT_READY | Result available (lower nibble is classification: 0-9 or 0-F) |

**Detection Logic:**
```python
if status == 0x00:
    # Idle - ready for new image
elif (status & 0xF0) == 0x10:
    # Collecting pixels
    progress = (status & 0x0F) * 64  # Approximate pixel count
elif status == 0x20:
    # Processing (wait or continue polling)
elif (status & 0x80) == 0x80:
    # Result ready!
    result = status & 0x0F
```

## Pin Assignments

### Switches (from constraint file)
- SW[0]: A8 (CNN mode enable)
- SW[1]: C11 (reserved)
- SW[2]: C10 (reserved)
- SW[3]: A10 (reserved)

## Usage Example (Python/SPI Master)

```python
import spidev
import time

spi = spidev.SpiDev()
spi.open(0, 0)
spi.max_speed_hz = 1000000  # 1 MHz

# Create 28x28 test image
image_data = [i % 256 for i in range(784)]

# Send image - FPGA returns status bytes showing progress
print("Sending image...")
response = spi.xfer2(image_data)

# First byte returns previous state (0x00 = IDLE)
# Subsequent bytes return collection status (0x10-0x1F)
print(f"Response[0]: 0x{response[0]:02X} (should be 0x00 from IDLE)")
print(f"Response[1]: 0x{response[1]:02X} (should be 0x10, collecting started)")
print(f"Response[783]: 0x{response[783]:02X} (should be 0x1F, near completion)")

# Verify we got status progression
status_values = set(response[1:])
print(f"Unique status values during collection: {sorted([f'0x{s:02X}' for s in status_values])}")

# Poll status until result is ready
print("Waiting for result...")
max_polls = 100
for i in range(max_polls):
    status = spi.xfer2([0xFF])[0]
    print(f"Poll {i}: Status = 0x{status:02X}", end="")
    
    if status == 0x20:
        print(" (Processing...)")
    elif status & 0x80:  # MSB set = result ready
        result = status & 0x0F
        print(f" (Result ready!)")
        print(f"Predicted digit: {result}")
        break
    else:
        print(f" (State: {'IDLE' if status == 0x00 else 'COLLECTING' if (status & 0xF0) == 0x10 else 'Unknown'})")
    
    time.sleep(0.001)  # Poll every 1ms
else:
    print("Timeout waiting for result!")
```

## Future Enhancements

When integrating with real CNN hardware:
1. Replace `cnn_result` dummy computation with actual CNN output
2. Add `cnn_start` signal to trigger real CNN pipeline
3. Connect `cnn_done` signal to transition to SENDING_RESULT state
4. Replace 2ms fixed delay with actual CNN completion signal
5. Add error checking for incomplete transfers (timeout, wrong pixel count)

## Testing

To verify CNN simulation mode:
1. Program bitstream to Arty A7-100T
2. Turn ON switch SW[0]
3. **LED0_g (green) turns ON** - confirms CNN mode is active
4. Send 784 bytes via SPI master
5. Observe LED2_g (green) during collection
6. Observe LED0_b (blue) during 2ms processing
7. Observe LED2_b (blue) when result is ready
8. Receive single result byte (0x80-0x8F)
9. LEDs show last received pixel data

To verify echo mode:
1. Turn OFF switch SW[0]
2. **LED0_g (green) shows TX ready status** (flickers with SPI activity)
3. Send any byte via SPI
4. Receive incrementing counter immediately
5. LEDs show last received data
