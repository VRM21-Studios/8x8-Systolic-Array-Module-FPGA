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
