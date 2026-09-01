# VRM21 NPU Series

A collection of FPGA-oriented AI accelerator RTL designs developed by **VRM21-Studios**, covering both conventional tensor-style computation and event-driven neuromorphic processing.

The repository currently contains two independent accelerator architectures:

* **8x8 Weight-Stationary Systolic Array** — a pipelined matrix-multiplication accelerator using 64 parallel MAC processing elements.
* **Spiking Neural Network (SNN) Accelerator** — a parameterized event-driven neural processing architecture based on Leaky Integrate-and-Fire (LIF) dynamics and virtual neuron scaling.

Both designs are implemented in synthesizable Verilog RTL and are designed around AXI-based interfaces for FPGA integration.

Target platform: **AMD Kria KV260 Vision AI Starter Kit**

---

## Overview

The purpose of this repository is to provide clean RTL implementations of hardware-oriented AI accelerator architectures.

Rather than implementing a complete machine-learning software stack, the repository focuses on the underlying digital hardware:

* spatial dataflow computation
* parallel MAC processing
* event-driven neural computation
* fixed-point arithmetic
* FPGA-oriented memory architectures
* AXI-Stream data movement
* AXI-Lite control interfaces
* parameterized hardware structures
* RTL verification and hardware-oriented validation

Each accelerator is maintained as an independent design with its own RTL, testbenches, and documentation.

---

## Accelerator Architectures

### 1. 8x8 Systolic Array

The systolic-array accelerator implements an **8x8 weight-stationary matrix multiplication engine**.

```text
AXI-Stream
   |
   v
+-----------------------------+
| Input Skewing               |
+-----------------------------+
   |
   v
+-----------------------------+
|      8 x 8 Systolic Array   |
|                             |
|  64 Parallel MAC Elements   |
|                             |
+-----------------------------+
   |
   v
+-----------------------------+
| Output Deskewing / Saturate |
+-----------------------------+
   |
   v
AXI-Stream
```

Key characteristics:

* 8x8 processing-element array
* 64 parallel MAC units
* weight-stationary dataflow
* fully pipelined execution
* Q-format fixed-point arithmetic
* deterministic pipeline latency
* AXI-Stream data interface
* AXI-Lite configuration interface
* FPGA DSP-oriented implementation
* hardware validation on the AMD Kria KV260

This design is intended as a compact reference for spatial matrix-computation architectures rather than as a complete TPU or general-purpose NPU framework.

See:

* [`docs/systolic-array/`](docs/systolic-array/)

---

### 2. Spiking Neural Network Accelerator

The SNN accelerator implements an event-driven neural computation architecture based on **Leaky Integrate-and-Fire (LIF)** neuron dynamics.

Instead of continuously processing multi-bit activation values, the accelerator operates on binary spike events and accumulates signed synaptic weights into virtual neuron membrane states.

```text
             Spike Stream
                  |
                  v
        +-------------------+
        | Spike Processing  |
        +-------------------+
                  |
                  v
        +-------------------+
        | Synaptic Weight   |
        | Accumulation       |
        +-------------------+
                  |
                  v
        +-------------------+
        | LIF Dynamics      |
        | Leak / Threshold  |
        +-------------------+
                  |
                  v
            Spike Vector
```

The architecture is parameterized for large virtual neuron populations while processing multiple neurons in parallel.

Key characteristics:

* event-driven spike processing
* Leaky Integrate-and-Fire dynamics
* signed fixed-point synaptic weights
* parameterized parallel neuron processing
* virtual neuron scaling through chunked processing
* BRAM / UltraRAM-oriented membrane-state storage
* AXI-Stream input and output
* AXI-Lite control wrapper
* signed-weight verification
* large-scale virtual-neuron verification
* checkerboard spike-pattern verification
* LIF dynamic behavior verification

The SNN design is intentionally maintained separately from the systolic-array architecture because the two accelerators represent fundamentally different computation models.

See:

* [`docs/snn/`](docs/snn/)
* [`rtl/snn/README.md`](rtl/snn/README.md)

---

## Repository Structure

```text
.
├── rtl/
│   ├── systolic-array/
│   │   ├── ...
│   │   └── README.md
│   │
│   └── snn/
│       ├── ...
│       └── README.md
│
├── tb/
│   ├── systolic-array/
│   │   ├── tb_systolic_core_engine.v
│   │   └── tb_systolic_axi_wrapper.v
│   │
│   └── snn/
│       ├── tb_snn_signed_weight.v
│       ├── tb_snn_scale.v
│       ├── tb_snn_spike_pattern.v
│       ├── tb_snn_lif_dynamics.v
│       └── tb_snn_axi_wrapper.v
│
├── docs/
│   ├── systolic-array/
│   │   ├── address_map.md
│   │   ├── build_overview.md
│   │   ├── design_rationale.md
│   │   ├── latency_and_data_format.md
│   │   └── validation_notes.md
│   │
│   └── snn/
│       ├── architecture.md
│       ├── memory_architecture.md
│       ├── lif_dynamics.md
│       ├── verification.md
│       └── validation_notes.md
│
└── README.md
```

The exact file organization may evolve as additional accelerator architectures are added.

---

## Verification

Each accelerator has an independent verification environment.

### Systolic Array

The systolic-array testbenches verify:

* fixed-point MAC arithmetic
* accumulator precision
* saturation behavior
* input skewing
* output deskewing
* pipeline alignment
* AXI-Stream signaling
* AXI-Lite configuration

The design has also been validated on the **AMD Kria KV260** using an AXI-DMA-based hardware test environment.

### SNN

The SNN verification environment covers several independent aspects of the architecture:

| Testbench                | Verification Target                          |
| ------------------------ | -------------------------------------------- |
| `tb_snn_signed_weight.v` | Signed synaptic-weight accumulation          |
| `tb_snn_scale.v`         | Large virtual-neuron scaling                 |
| `tb_snn_spike_pattern.v` | Deterministic mixed spike pattern            |
| `tb_snn_lif_dynamics.v`  | LIF temporal dynamics and membrane evolution |
| `tb_snn_axi_wrapper.v`   | AXI-Lite control and AXI-Stream integration  |

The scale-oriented verification exercises up to **4096 chunks × 64 parallel neurons**, corresponding to **262,144 virtual neurons**.

---

## Design Philosophy

The accelerator architectures in this repository are intentionally different.

The **systolic array** emphasizes:

* spatial parallelism
* deterministic dataflow
* dense arithmetic
* high MAC utilization
* pipeline throughput

The **SNN accelerator** emphasizes:

* event-driven computation
* sparse temporal activity
* binary spike communication
* signed synaptic accumulation
* memory-centric neuron-state processing

This makes the repository a collection of complementary hardware approaches to AI acceleration rather than a single unified accelerator architecture.

---

## Shared RTL Dependencies

Some low-level hardware components are shared across multiple VRM21-Studios repositories.

For example, the SNN implementation uses the reusable:

`vrm_ram_core.v`

This module is maintained in the separate **VRM21-RTL-Utilities** repository rather than duplicated here.

See:

[`VRM21-RTL-Utilities`](https://github.com/VRM21-Studios/VRM21-RTL-Utilities)

and [`rtl/snn/README.md`](rtl/snn/README.md) for the dependency information.

---

## Scope

This repository focuses on **RTL-level AI accelerator architecture**.

It does not attempt to provide:

* a complete machine-learning framework
* a neural-network compiler
* model training software
* a general-purpose TPU implementation
* a complete inference runtime
* a commercial production IP package

Software and board-specific integration code may be used during validation but are intentionally kept outside the core RTL implementation where appropriate.

---

## Target Platform

The primary FPGA target for hardware-oriented development and validation is:

**AMD Kria KV260 Vision AI Starter Kit**

The RTL itself is written to remain sufficiently parameterized and modular for adaptation to other FPGA platforms where the required memory and AXI resources are available.

---

## Project Status

The repository is an active collection of independent AI accelerator RTL designs.

The original 8x8 systolic-array accelerator is considered a completed reference implementation.

The SNN accelerator is maintained as a separate neuromorphic accelerator architecture with dedicated RTL verification and documentation.

Future additions may introduce other accelerator architectures while preserving the principle of keeping each design independently understandable and verifiable.

---

## License

Licensed under the MIT License.

Provided as-is, without warranty.
