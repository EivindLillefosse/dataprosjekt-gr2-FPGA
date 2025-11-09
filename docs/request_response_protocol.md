# CNN Request/Response Protocol Design

## Overview
Pull-based dataflow where downstream layers request data from upstream layers.

## Protocol Signals

### Request Interface (Downstream → Upstream)
```vhdl
input_req_valid : out std_logic;      -- Request is valid
input_req_row   : out integer;        -- Row position requested
input_req_col   : out integer;        -- Column position requested
input_req_ready : in  std_logic;      -- Upstream ready to accept request
```

### Response Interface (Upstream → Downstream)
```vhdl
input_resp_valid : in  std_logic;                    -- Response data valid
input_resp_data  : in  WORD_ARRAY(0 to N-1);         -- Pixel data
input_resp_ready : out std_logic;                    -- Ready to receive data
```

## Handshake Protocol

### Valid-Ready Handshake
- **Request**: Transfer occurs when `input_req_valid=1 AND input_req_ready=1`
- **Response**: Transfer occurs when `input_resp_valid=1 AND input_resp_ready=1`
- Both sides can apply backpressure by deasserting `ready`

### Timing Diagram
```
Clock:    ___/‾‾‾\___/‾‾‾\___/‾‾‾\___/‾‾‾\___
req_valid: ______/‾‾‾‾‾‾‾‾‾‾‾\_______________
req_ready: ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
req_row:   ------< 5  >-----------------------
req_col:   ------< 7  >-----------------------
                 ^
                 Request accepted

resp_valid: _____________/‾‾‾‾‾‾‾\___________
resp_ready: ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
resp_data:  -------------<DATA>--------------
                         ^
                         Response delivered
```

## Layer Behaviors

### Convolution Layer

**As Consumer (requesting from upstream):**
1. Receives output request from downstream layer
2. For each output position [out_r, out_c], needs 3×3 input window
3. Generates 9 sequential requests: [out_r+kr, out_c+kc] for kr,kc ∈ {0,1,2}
4. Accumulates MACs across all kernel positions
5. When kernel complete, provides output response

**As Producer (responding to downstream):**
1. Receives request for position [r, c]
2. Initiates internal computation (as described above)
3. When result ready, asserts `output_resp_valid` with data

**Request Generation Pattern:**
```
Output [5,7] requested →
  Request [5,7], [5,8], [5,9],    // kernel row 0
  Request [6,7], [6,8], [6,9],    // kernel row 1
  Request [7,7], [7,8], [7,9]     // kernel row 2
```

### Pooling Layer

**As Consumer (requesting from upstream):**
1. Receives output request for position [out_r, out_c]
2. Calculates 2×2 input block: [2*out_r : 2*out_r+1, 2*out_c : 2*out_c+1]
3. Generates 4 sequential requests:
   - [2*out_r, 2*out_c]
   - [2*out_r, 2*out_c+1]
   - [2*out_r+1, 2*out_c]
   - [2*out_r+1, 2*out_c+1]
4. Tracks maximum across 4 inputs
5. When block complete, provides output response

**As Producer (responding to downstream):**
1. Receives request
2. Initiates internal computation
3. Returns maximum of 2×2 block

**Request Generation Pattern:**
```
Output [3,4] requested →
  Request [6,8], [6,9],    // row 0 of 2×2 block
  Request [7,8], [7,9]     // row 1 of 2×2 block
```

### Input Layer (Top Level)

**As Producer only:**
1. Receives requests from Conv1
2. Has direct access to input buffer/external memory
3. Looks up requested position
4. Responds with pixel data

**No upstream requests** (source of data)

### Output Layer (Top Level)

**As Consumer only:**
1. Generates requests for final layer outputs
2. Can scan in any order (e.g., block order for efficient processing)
3. Collects results

**No downstream responses** (sink of data)

## State Machine Pattern

### Generic Layer Controller FSM

```
States:
  IDLE          - Waiting for downstream request
  REQUEST       - Issuing upstream requests
  ACCUMULATE    - Processing received data
  RESPOND       - Providing output to downstream

IDLE:
  if output_req_valid = '1' then
    latch output position
    next_state <= REQUEST
    
REQUEST:
  generate input_req_valid + position
  if input_req_ready = '1' then
    if last_request then
      next_state <= ACCUMULATE
    end if
    
ACCUMULATE:
  if input_resp_valid = '1' and input_resp_ready = '1' then
    process data
    if all_data_received then
      next_state <= RESPOND
      
RESPOND:
  assert output_resp_valid + data
  if output_resp_ready = '1' then
    next_state <= IDLE
```

## Pipeline Considerations

### Latency
- Each layer adds latency:
  - **Convolution**: ~9-27 cycles (3×3 kernel × channels)
  - **Pooling**: ~4 cycles (2×2 block)
- Total pipeline depth: ~50-100 cycles for 2-layer CNN

### Throughput
- Can pipeline multiple output positions
- While Conv1 processes output[0], Conv2 can request output[1]
- Requires buffers between stages

### Buffering Strategy
- **Small FIFOs** between layers (depth 2-4)
- Allows producer to continue while consumer processes
- Decouples timing between stages

## Example: Full Request Chain

```
User requests final output [2,3]

Pool2 (Consumer):
  Needs Conv2[4:5, 6:7] (2×2 block)
  Issues 4 requests to Conv2

Conv2 (Consumer):
  Request [4,6] needs Pool1[4:6, 6:8] (3×3 window)
  Issues 9 requests to Pool1

Pool1 (Consumer):
  Request [4,6] needs Conv1[8:9, 12:13] (2×2 block)
  Issues 4 requests to Conv1

Conv1 (Consumer):
  Request [8,12] needs Input[8:10, 12:14] (3×3 window)
  Issues 9 requests to Input layer

Input (Producer):
  Provides pixel[8,12], pixel[8,13], ... pixel[10,14]

(Responses flow back up the chain)
```

## Advantages

1. **Natural backpressure**: Ready signals prevent buffer overflow
2. **On-demand computation**: Only compute what's needed
3. **Flexible ordering**: Output layer controls scan order
4. **Modular**: Each layer is independent
5. **Testable**: Can test each layer with simple request/response stimulus

## Disadvantages

1. **Latency**: Request must propagate to input before data flows back
2. **Complexity**: More complex than pure streaming
3. **State**: Each layer needs request tracking

## Next Steps

1. Implement `request_response_interface` package with signal types
2. Create `conv_layer_request` module with FSM
3. Create `pooling_layer_request` module with FSM
4. Integrate into CNN top-level with request arbitration
