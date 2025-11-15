# Dual Frame Size Controller Implementation Summary

## Overview
The SPI_memory_controller_backup now supports alternating frame sizes:
- **CNN Frames**: 28×28 pixels (784 bytes) → Buffers A, B, C (10-bit addressing)
- **VGA Frames**: 200×200 pixels (40,000 bytes) → Buffers D, E, F (16-bit addressing)

## Frame Alternation Pattern
1. First SPI receive: 28×28 frame → Store in CNN triple-buffer (A/B/C)
2. Second SPI receive: 200×200 frame → Store in VGA triple-buffer (D/E/F)  
3. Third SPI receive: 28×28 frame → CNN buffers
4. Fourth SPI receive: 200×200 frame → VGA buffers
5. (Repeat...)

## Data Routing
- **CNN Interface**: Reads from buffers A/B/C (28×28 data)
- **VGA Interface**: Reads from buffers D/E/F (200×200 data)

## Key Changes Made

### 1. Generics
```vhdl
CNN_IMAGE_WIDTH : integer := 28;
CNN_BUFFER_SIZE : integer := 784;
VGA_IMAGE_WIDTH : integer := 200;
VGA_BUFFER_SIZE : integer := 40000;
```

### 2. New Components
- `BRAM_dual_port`: Original 10-bit addressing for CNN (A,B,C)
- `BRAM_dual_port_large`: New 16-bit addressing for VGA (D,E,F)

### 3. Frame Type Tracking
- `current_frame_type`: 0=CNN (28×28), 1=VGA (200×200)
- `next_frame_type`: Alternates after each complete frame
- Initial state: Expects CNN frame first

### 4. Separate Triple Buffers
**CNN Buffers (A, B, C)**:
- 10-bit addressing (0-783)
- Connected to CNN read interface (data_out port)
- Status signals: BRAM_A/B/C_busy, BRAM_A/B/C_last_written

**VGA Buffers (D, E, F)**:
- 16-bit addressing (0-39999)
- Connected to VGA display (port B only, read-only)
- Status signals: BRAM_D/E/F_busy, BRAM_D/E/F_last_written

### 5. Control FSM Modifications Needed
The `control_process_ABC` needs these changes:

**IDLE State**:
- Check `current_frame_type` to determine target buffer set
- If CNN frame (type=0): Route to A/B/C buffers
- If VGA frame (type=1): Route to D/E/F buffers

**WRITE States**:
- Add WRITE_D, WRITE_E, WRITE_F states for VGA buffers
- Use 16-bit counters (write_addr_D/E/F, pixel_count_D/E/F)
- Compare against MAX_PIXELS_VGA (40000)

**TRANSITION State**:
- Toggle `next_frame_type` after completing frame
- Update appropriate last_written flags (CNN or VGA set)
- Select next buffer from correct set based on busy flags

**Frame Size Detection**:
- Use `current_frame_type` signal set at start of each frame
- After completing frame, set `current_frame_type <= next_frame_type`
- Toggle `next_frame_type` for alternation

### 6. Address Width Changes
- `calc_address` function now returns 16-bit unsigned
- VGA address extended from 10-bit to 16-bit: `vga_addr_extended <= "000000" & vga_addr;`

### 7. Port B Routing
- CNN buffers (A, B, C): Port B tied off (not used for VGA anymore)
- VGA buffers (D, E, F): Port B connected to extended VGA address
- VGA data mux selects from D/E/F doutb based on `vga_buffer_select`

## Still TODO in FSM

1. Expand state machine to include WRITE_D, WRITE_E, WRITE_F states
2. Add frame type decision logic in IDLE state
3. Modify TRANSITION to toggle frame type
4. Update reset logic to include VGA buffer counters and flags
5. Add memory reset support for D/E/F buffers

## Testing Strategy
1. Send 28×28 test pattern → Verify stored in buffer A
2. Send 200×200 test pattern → Verify stored in buffer D  
3. Read from CNN interface → Should get 28×28 data
4. VGA display → Should show 200×200 image
5. Repeat alternation → Verify triple-buffering works for both sizes

## Resource Impact
- **BRAM Usage**: 
  - CNN: 3 × 784 bytes = 2,352 bytes
  - VGA: 3 × 40,000 bytes = 120,000 bytes
  - **Total**: ~122KB of BRAM

## Notes
- The BRAM_dual_port_large component needs to be created as a Vivado IP
- Configure as True Dual Port RAM, 16-bit address width, 8-bit data width
- Enable output registers for better timing
