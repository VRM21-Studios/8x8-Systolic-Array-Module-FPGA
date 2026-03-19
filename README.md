# 8x8 Systolic Array Accelerator (AXI-Native) on FPGA
This repository provides a **reference RTL implementation** of a
**weight-stationary systolic array**
implemented in **Verilog** and integrated with **AXI-Stream** and **AXI-Lite**.

Target platform: **AMD Kria KV260** Focus: **RTL architecture, dataflow pipelining, and AXI correctness**

The module is designed for **continuous high-throughput matrix multiplication (MAC operations)**, not
software-emulated processing.

---

## Overview

This module implements:

* **Function**: 8x8 Matrix Multiplication acceleration (Y = A * W + B)
* **Architecture type**: Weight-stationary systolic array with pure dataflow pipelining
* **Scope**: Minimal, single-purpose AI/DSP compute building block

The design is intentionally **not generic** and **not a complete TPU**.  
It exists to demonstrate **how a spatial compute array is implemented in FPGA hardware**,  
not to provide a turnkey software-driven AI framework.

---

## Key Characteristics

* RTL written in **Verilog-2001**
* **AXI-Stream** data interface (activations & results)
* **AXI-Lite** control interface (weights, biases & soft-reset)
* Pure synchronous dataflow (stall-free, no complex FSMs)
* Built-in Q-format fixed-point saturation logic
* Designed and verified for **hardware acceleration via DMA**
* No software runtime included (verified via PYNQ for testing only)

---

## Architecture

High-level structure:

```text
AXI-Stream In (Activations, 128-bit)
|
v
+-----------------------------------+
| Systolic Wrapper                  |
| +-------------------------------+ |
| | Core Engine (8x8)             | |
| | - Input skewing (delay lines) | |
| | - 64x MAC Processing Elements | |
| | - Output deskewing            | |
| | - Hardclip saturation logic   | |
| +-------------------------------+ |
+-----------------------------------+
|
v
AXI-Stream Out (Results, 128-bit)
```

Design notes:

* Processing is **fully synchronous**
* Dense math and DSP-slice mapping are isolated in `systolic_core_engine`
* AXI protocol handling and memory-mapped unpacking are isolated in `systolic_axi_wrapper`
* No hidden state outside the RTL

---

## Data Format

* AXI-Stream width: **128-bit** (8 elements × 16-bit)
* Arithmetic format:
  * Signed **16-bit** Fixed-Point (**Q6.10**)
  * Internal accumulators expand to **35-bit** to prevent internal overflow
* Configuration (Weights & Biases):
  * Written via AXI-Lite 32-bit registers
  * Weights are packed densely (two 16-bit weights per 32-bit register)

---

## Latency

* **Fixed internal latency**: **15 clock cycles**
  * Derived from the wavefront propagation formula: `ROWS + COLS - 1`
* Control signals (`tvalid`, `tlast`) are aligned perfectly with the data path pipeline

Latency is:

* highly deterministic
* completely pipelined (throughput is 1 vector per clock cycle after initial latency)
* independent of the input values

This behavior is intentional and suitable for high-speed streaming DMA pipelines.

---

## Control Interface (AXI-Lite)

The control interface exposes the memory map for the core configuration:

| Offset | Register | Description |
|-------:|----------|-------------|
| 0x000  | CTRL     | Soft Clear / Flush pipeline (Bit 0) |
| 0x100  | WEIGHT_BASE | Base address for 64 weights (packed into 32 registers) |
| 0x180  | BIAS_BASE | Base address for 8 biases (35-bit each, packed into 9 registers) |

* Write `1` then `0` to `CTRL` to flush accumulators
* Matrix configuration relies on the Processing System (PS) to flatten the 2D arrays before writing
* Detailed documentation is available in `/docs/address_map.md`.

---

## Verification & Validation

Verification was performed at two levels:

### 1. RTL Simulation

Dedicated testbenches (`tb_systolic_core_engine` and `tb_systolic_axi_wrapper`) verify:

* Mathematical precision of Q6.10 arithmetic and 35-bit accumulation
* Output bounding and hardclip saturation correctness
* Pipeline skewing and deskewing alignment
* AXI-Stream `tvalid` and `tlast` propagation
* Simulation results are exported as CSV files for offline analysis via Python Pandas  
(see `/sim_results`).

---

### 2. System-Level Validation

The AXI-integrated design was validated using:

* Xilinx AXI DMA (Direct Memory Access)
* Zynq UltraScale+ Processing System
* **Hardware verified on the AMD Kria KV260 Vision AI Starter Kit** using the PYNQ framework.

This validates correct memory-mapped configuration and burst streaming behavior under realistic physical conditions.

Software-oriented scripts (Python/Jupyter) and bitstreams are **intentionally not included**
to keep the repository focused on RTL design and hardware architecture.

---

## Design Rationale (Summary)

Key design decisions:

* **Pure Dataflow over FSMs** for stall-free maximum DSP utilization
* Explicit **safety saturation** (hardclipping) to prevent integer wrap-around
* AXI-Native design to eliminate soft-core CPU (e.g., RISC-V) instruction overhead
* Centralized AXI-Lite wrapping for scalable memory mapping

These decisions reflect **engineering trade-offs**, prioritizing pipeline throughput over dynamic software flexibility.

More detailed explanations are available in `/docs/design_rationale.md`.

---

## What This Repository Is

* A **clean RTL reference**
* A demonstration of:
  * spatial computing architecture in FPGA
  * continuous pipelining without stalling
  * AXI-Stream and AXI-Lite integration for ML accelerators
* A reusable building block for larger FPGA AI/DSP pipelines

---

## What This Repository Is Not

* ❌ A complete AI framework (like TensorFlow/PyTorch)
* ❌ A floating-point unit (FPU)
* ❌ A software-driven dynamically reconfigurable TPU
* ❌ A drop-in commercial IP

The scope is intentionally constrained to the hardware acceleration core.

---

## Project Status

This repository is considered **complete**.

* RTL is stable
* Simulation coverage is sufficient and verified against hardware
* AXI integration is silicon-proven
* No further feature development is planned for this 8x8 configuration

The design is published as a **reference implementation**.

---

## Documentation

Additional documentation is available in `/docs`:

* `address_map.md`
* `build_overview.md`
* `design_rationale.md`
* `latency_and_data_format.md`
* `validation_notes.md`

---

## License

Licensed under the MIT License.  
Provided as-is, without warranty.

---

## Notes

> **This repository demonstrates design decisions, not design possibilities.**
