# Validation Notes

The design has been thoroughly verified through a bottom-up methodology, ensuring both algorithmic correctness and protocol compliance.

## 1. RTL Simulation
Two distinct testbenches are provided and verified using Xilinx Vivado Simulator:
- **`tb_systolic_core_engine.v`:** A bare-metal testbench that directly injects weights and input vectors into the core to verify the matrix multiplication math, Q-format shifting, and DSP saturation logic.
- **`tb_systolic_axi_wrapper.v`:** A system-level testbench that simulates AXI4-Lite burst writes for configuration and AXI4-Stream `128-bit` vectors for data processing. 
*Note: Both testbenches automatically export stimulus and MAC results to CSV files for cross-verification using Python/Pandas.*

## 2. Hardware Deployment (Silicon Verified)
The synthesized bitstream was deployed on the **Kria KV260 FPGA**. 
Using the **PYNQ framework** running on the ARM Cortex-A53 Processing System:
- Memory-mapped weights (Identity Matrix) and biases were successfully written to the PL via AXI-Lite.
- Quantized data buffers were allocated in contiguous memory and transferred using the Xilinx AXI DMA IP.
- The hardware returned the mathematically precise Q6.10 fixed-point results (e.g., successfully processing `Input + Bias` vectors across the pipeline) with zero mismatch compared to software-based floating-point expectations.
