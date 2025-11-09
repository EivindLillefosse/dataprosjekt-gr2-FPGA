# Integration Guide: Request/Response Protocol into Existing CNN

## Overview
This guide shows how to adapt the existing CNN layers to use the request/response protocol while maintaining backward compatibility.

## Strategy: Hybrid Approach

### Phase 1: Add Request/Response Adapters (Non-Invasive)
Keep existing layers unchanged, add thin adapter layers that:
1. Convert request/response protocol ↔ existing valid/ready protocol
2. Handle position tracking
3. Manage request sequencing

### Phase 2: Top-Level Orchestration
Modify `cnn.vhd` to:
1. Generate output requests (what final outputs are needed)
2. Route requests backward through layers
3. Collect responses forward through layers

## Adapter Pattern

### Request Generator Adapter
Converts "generate next output" → "request specific input positions"

```vhdl
entity conv_request_adapter is
    generic (
        IMAGE_SIZE     : integer := 28;
        KERNEL_SIZE    : integer := 3;
        OUTPUT_SIZE    : integer := 26;
        INPUT_CHANNELS : integer := 1;
        NUM_FILTERS    : integer := 8;
        BLOCK_SIZE     : integer := 2
    );
    port (
        clk : in std_logic;
        rst : in std_logic;
        
        -- Request interface (from downstream)
        output_req_valid : in  std_logic;
        output_req_row   : in  integer;
        output_req_col   : in  integer;
        output_req_ready : out std_logic;
        
        -- Response interface (to downstream)
        output_resp_valid : out std_logic;
        output_resp_data  : out WORD_ARRAY(0 to NUM_FILTERS-1);
        output_resp_ready : in  std_logic;
        
        -- Existing conv layer interface
        conv_enable      : out std_logic;
        conv_input_valid : in  std_logic;
        conv_input_pixel : in  WORD_ARRAY(0 to INPUT_CHANNELS-1);
        conv_input_row   : out integer;
        conv_input_col   : out integer;
        conv_input_ready : out std_logic;
        conv_output_valid: in  std_logic;
        conv_output_pixel: in  WORD_ARRAY(0 to NUM_FILTERS-1);
        conv_output_ready: out std_logic;
        
        -- Request interface (to upstream)
        input_req_valid  : out std_logic;
        input_req_row    : out integer;
        input_req_col    : out integer;
        input_req_ready  : in  std_logic;
        
        -- Response interface (from upstream)
        input_resp_valid : in  std_logic;
        input_resp_data  : in  WORD_ARRAY(0 to INPUT_CHANNELS-1);
        input_resp_ready : out std_logic
    );
end conv_request_adapter;
```

**Behavior:**
1. Receives output request [r,c]
2. Generates 9 input requests for 3×3 window
3. Forwards responses to existing conv layer
4. Collects conv output and sends as response

## Modified CNN Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ CNN Top Level (cnn.vhd)                                      │
│                                                               │
│  ┌──────────────┐                                            │
│  │ Output Scan  │ Generates requests for output positions    │
│  │  Generator   │ in block-scan order                        │
│  └──────┬───────┘                                            │
│         │ req[2,3]                                            │
│         ↓                                                     │
│  ┌──────────────────────────────────────────┐                │
│  │         Pool2 Request Adapter            │                │
│  │  Converts 1 output req → 4 input reqs    │                │
│  └──────┬───────────────────────────────────┘                │
│         │ req[4,6], [4,7], [5,6], [5,7]                      │
│         ↓                                                     │
│  ┌──────────────────────────────────────────┐                │
│  │      Conv2 Request Adapter               │                │
│  │  Converts 1 output req → 9 input reqs    │                │
│  │  ┌─────────────────────┐                 │                │
│  │  │ Existing Conv Layer │                 │                │
│  │  └─────────────────────┘                 │                │
│  └──────┬───────────────────────────────────┘                │
│         │ req[4:6, 6:8] (9 positions)                        │
│         ↓                                                     │
│  ┌──────────────────────────────────────────┐                │
│  │         Pool1 Request Adapter            │                │
│  │  Converts 1 output req → 4 input reqs    │                │
│  └──────┬───────────────────────────────────┘                │
│         │ req[8:9, 12:13] (4 positions)                      │
│         ↓                                                     │
│  ┌──────────────────────────────────────────┐                │
│  │      Conv1 Request Adapter               │                │
│  │  Converts 1 output req → 9 input reqs    │                │
│  │  ┌─────────────────────┐                 │                │
│  │  │ Existing Conv Layer │                 │                │
│  │  └─────────────────────┘                 │                │
│  └──────┬───────────────────────────────────┘                │
│         │ req[8:10, 12:14] (9 positions)                     │
│         ↓                                                     │
│  ┌──────────────────────────────────────────┐                │
│  │      Input Buffer / Memory               │                │
│  │  Responds to requests with pixel data    │                │
│  └──────────────────────────────────────────┘                │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Modified cnn.vhd Structure

```vhdl
architecture Structural of cnn_top is
    -- Request signals between layers
    signal pool2_to_conv2_req_valid : std_logic;
    signal pool2_to_conv2_req_row   : integer;
    signal pool2_to_conv2_req_col   : integer;
    signal pool2_to_conv2_req_ready : std_logic;
    
    signal conv2_to_pool1_req_valid : std_logic;
    signal conv2_to_pool1_req_row   : integer;
    signal conv2_to_pool1_req_col   : integer;
    signal conv2_to_pool1_req_ready : std_logic;
    
    -- ... similar for other layer boundaries
    
    -- Response signals between layers
    signal pool1_to_conv2_resp_valid : std_logic;
    signal pool1_to_conv2_resp_data  : WORD_ARRAY(0 to CONV_2_INPUT_CHANNELS-1);
    signal pool1_to_conv2_resp_ready : std_logic;
    
    -- ... similar for other layer boundaries
    
    -- Output scan generator
    signal output_scan_req_valid : std_logic;
    signal output_scan_req_row   : integer;
    signal output_scan_req_col   : integer;
    signal output_scan_done      : std_logic;

begin

    -- Output position generator (drives the entire pipeline)
    output_scanner : entity work.output_scan_generator
        generic map (
            OUTPUT_SIZE => (((CONV_2_IMAGE_SIZE - CONV_2_KERNEL_SIZE + 1) / POOL_2_BLOCK_SIZE)),
            BLOCK_SIZE  => POOL_2_BLOCK_SIZE
        )
        port map (
            clk       => clk,
            rst       => rst,
            enable    => enable,
            req_valid => output_scan_req_valid,
            req_row   => output_scan_req_row,
            req_col   => output_scan_req_col,
            req_ready => pool2_adapter_req_ready,
            done      => output_scan_done
        );
    
    -- Pool2 adapter
    pool2_adapter : entity work.pool_request_adapter
        generic map (
            INPUT_SIZE     => (CONV_2_IMAGE_SIZE - CONV_2_KERNEL_SIZE + 1),
            INPUT_CHANNELS => CONV_2_NUM_FILTERS,
            BLOCK_SIZE     => POOL_2_BLOCK_SIZE
        )
        port map (
            clk => clk,
            rst => rst,
            -- From output scanner
            output_req_valid => output_scan_req_valid,
            output_req_row   => output_scan_req_row,
            output_req_col   => output_scan_req_col,
            output_req_ready => pool2_adapter_req_ready,
            -- To user (final outputs)
            output_resp_valid => output_valid,
            output_resp_data  => output_pixel,
            output_resp_ready => output_ready,
            -- To Conv2
            input_req_valid  => pool2_to_conv2_req_valid,
            input_req_row    => pool2_to_conv2_req_row,
            input_req_col    => pool2_to_conv2_req_col,
            input_req_ready  => pool2_to_conv2_req_ready,
            -- From Conv2
            input_resp_valid => conv2_to_pool2_resp_valid,
            input_resp_data  => conv2_to_pool2_resp_data,
            input_resp_ready => conv2_to_pool2_resp_ready
        );
    
    -- Conv2 adapter + existing conv layer
    conv2_adapter : entity work.conv_request_adapter
        generic map (
            IMAGE_SIZE     => CONV_2_IMAGE_SIZE,
            KERNEL_SIZE    => CONV_2_KERNEL_SIZE,
            INPUT_CHANNELS => CONV_2_INPUT_CHANNELS,
            NUM_FILTERS    => CONV_2_NUM_FILTERS,
            BLOCK_SIZE     => CONV_2_BLOCK_SIZE,
            LAYER_ID       => 1
        )
        port map (
            clk => clk,
            rst => rst,
            -- From Pool2
            output_req_valid => pool2_to_conv2_req_valid,
            output_req_row   => pool2_to_conv2_req_row,
            output_req_col   => pool2_to_conv2_req_col,
            output_req_ready => pool2_to_conv2_req_ready,
            -- To Pool2
            output_resp_valid => conv2_to_pool2_resp_valid,
            output_resp_data  => conv2_to_pool2_resp_data,
            output_resp_ready => conv2_to_pool2_resp_ready,
            -- To Pool1
            input_req_valid  => conv2_to_pool1_req_valid,
            input_req_row    => conv2_to_pool1_req_row,
            input_req_col    => conv2_to_pool1_req_col,
            input_req_ready  => conv2_to_pool1_req_ready,
            -- From Pool1
            input_resp_valid => pool1_to_conv2_resp_valid,
            input_resp_data  => pool1_to_conv2_resp_data,
            input_resp_ready => pool1_to_conv2_resp_ready
        );
    
    -- Similar pattern for Pool1, Conv1...
    
    -- Input buffer (responds to Conv1 requests)
    input_buffer : entity work.input_buffer_adapter
        generic map (
            IMAGE_SIZE     => IMAGE_SIZE,
            INPUT_CHANNELS => CONV_1_INPUT_CHANNELS
        )
        port map (
            clk => clk,
            rst => rst,
            -- External input interface
            ext_input_valid => input_valid,
            ext_input_pixel => input_pixel,
            ext_input_ready => input_ready,
            -- Request interface from Conv1
            req_valid => conv1_to_input_req_valid,
            req_row   => conv1_to_input_req_row,
            req_col   => conv1_to_input_req_col,
            req_ready => conv1_to_input_req_ready,
            -- Response interface to Conv1
            resp_valid => input_to_conv1_resp_valid,
            resp_data  => input_to_conv1_resp_data,
            resp_ready => input_to_conv1_resp_ready
        );

    -- Generate input_row/col for external interface
    input_row <= conv1_to_input_req_row;
    input_col <= conv1_to_input_req_col;
    
    -- Generate output_row/col from output scanner
    output_row <= output_scan_req_row;
    output_col <= output_scan_req_col;
    
    layer_done <= output_scan_done;

end Structural;
```

## Key Components to Implement

### 1. Output Scan Generator
Generates requests for output positions in block-scan order:
```vhdl
entity output_scan_generator is
    generic (
        OUTPUT_SIZE : integer := 5;
        BLOCK_SIZE  : integer := 2
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        enable    : in  std_logic;
        req_valid : out std_logic;
        req_row   : out integer;
        req_col   : out integer;
        req_ready : in  std_logic;  -- Backpressure from downstream
        done      : out std_logic
    );
end output_scan_generator;
```

### 2. Pool Request Adapter
Converts 1 output request → 4 input requests (2×2 block):
```vhdl
entity pool_request_adapter is
    generic (
        INPUT_SIZE     : integer := 11;
        INPUT_CHANNELS : integer := 16;
        BLOCK_SIZE     : integer := 2
    );
    port (
        -- Downstream request/response (output)
        output_req_valid  : in  std_logic;
        output_req_row    : in  integer;
        output_req_col    : in  integer;
        output_req_ready  : out std_logic;
        output_resp_valid : out std_logic;
        output_resp_data  : out WORD_ARRAY(0 to INPUT_CHANNELS-1);
        output_resp_ready : in  std_logic;
        
        -- Upstream request/response (input)
        input_req_valid  : out std_logic;
        input_req_row    : out integer;
        input_req_col    : out integer;
        input_req_ready  : in  std_logic;
        input_resp_valid : in  std_logic;
        input_resp_data  : in  WORD_ARRAY(0 to INPUT_CHANNELS-1);
        input_resp_ready : out std_logic
    );
end pool_request_adapter;
```

### 3. Conv Request Adapter
Converts 1 output request → 9 input requests (3×3 window):
- Wraps existing conv_layer_modular
- Manages request sequencing
- Buffers responses

### 4. Input Buffer Adapter
Stores input image and responds to random-access requests:
- Can be simple dual-port RAM
- Or can forward requests to external memory controller

## Migration Path

### Step 1: Create Adapters (Non-Breaking)
Create adapter entities without modifying existing layers

### Step 2: Create Test CNN with Adapters
Build new `cnn_request_response.vhd` alongside existing `cnn.vhd`

### Step 3: Validate
Compare outputs of both architectures with same inputs

### Step 4: Replace
Once validated, replace old architecture

## Benefits of This Approach

1. **Non-invasive**: Existing layers unchanged
2. **Testable**: Can validate adapters independently
3. **Backward compatible**: Both architectures can coexist
4. **Flexible**: Easy to swap between push/pull models

## Next Steps

Would you like me to implement:
1. **Output scan generator** - Drives the pipeline
2. **Pool request adapter** - Simpler, good starting point
3. **Conv request adapter** - More complex, wraps existing conv layer
4. **Input buffer adapter** - Interface to external input
