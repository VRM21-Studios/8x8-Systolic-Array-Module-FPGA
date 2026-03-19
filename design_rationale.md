# Design Rationale

This Systolic Array architecture was built from the ground up focusing on high throughput, deterministic latency, and numerical stability. 

## 1. Pure Dataflow Pipelining (Stall-Free)
Unlike state-machine-driven accelerators that suffer from pipeline bubbles or complex synchronization issues, this core utilizes a pure, fully-unrolled dataflow architecture. Input skewing (delay lines) and output deskewing are managed entirely by synchronous shift registers. Once the pipeline is filled, the core outputs one computed row per clock cycle indefinitely, achieving 100% DSP utilization.

## 2. AXI-Native Architecture
By wrapping the core with standard AXI4-Lite and AXI4-Stream interfaces, we eliminate the need for a dedicated soft-core processor (like RISC-V) to manage data choreography. The Processing System (ARM) orchestrates the heavy lifting of `Img2Col` and data-shaping via software, while the FPGA strictly accelerates the dense Matrix Multiplication (MAC) workload.

## 3. Q-Format Fixed-Point & Bulletproof Saturation
AI and DSP algorithms are highly sensitive to integer overflow. 
- The internal accumulators automatically scale their bit-width (`WIDTH * 2 + $clog2(ROWS)`) to prevent internal overflow during deep MAC operations.
- The final output stage implements Verilog-2001 safe combinatorial hard-clipping saturation. If a computed value exceeds the 16-bit boundary after the fractional right-shift, it is safely clamped to the maximum/minimum signed 16-bit limits rather than wrapping around.