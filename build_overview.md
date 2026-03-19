# Build and Integration Overview

This IP is designed as a plug-and-play AXI-Native hardware accelerator. It bypasses custom instruction overhead by utilizing standard AMBA AXI4 interfaces, making it highly compatible with Xilinx Vivado Block Designs.

## Target Hardware
This module has been successfully synthesized, implemented, and **hardware-verified on the Xilinx Kria KV260 Vision AI Starter Kit**. 

## Block Design Integration
To integrate this IP into your Vivado project:
1. **Processing System (PS):** Instantiate the Zynq UltraScale+ MPSoC (or standard Zynq-7000).
2. **AXI DMA:** Add an AXI Direct Memory Access (DMA) IP. Disable Scatter-Gather. Set the Read/Write Channel width to `128-bit` (to match the 8-column x 16-bit configuration).
3. **Control Interface:** Connect the `s_axi` port of the Systolic Wrapper to the PS via an AXI Interconnect/SmartConnect for memory-mapped configuration.
4. **Data Streams:** - Connect the AXI DMA `M_AXIS_MM2S` to the wrapper's `s_axis` (Input Activations).
   - Connect the wrapper's `m_axis` to the AXI DMA `S_AXIS_S2MM` (Output MAC Results).

## Resource Utilization (8x8 Configuration)
The 8x8 array is highly efficient and consumes a minimal footprint on the Kria KV260 (XCK26 FPGA):
- **DSP Slices:** 64 (representing exactly 8x8 MAC units)
- **BRAM:** 0 (Fully distributed logic, no internal block RAM buffering required)
- **LUTs/FFs:** Minimal, primarily utilized for the pipeline shift registers and AXI-Lite decoding.