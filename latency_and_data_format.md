# Latency & Data Format

## Data Precision (Q-Format)
The core utilizes fixed-point arithmetic parameterized by `FRAC_BIT` (Default: `10`, representing Q6.10 format).
- **Input Activations (A):** 16-bit Signed Integer.
- **Weights (W):** 16-bit Signed Integer.
- **Biases (B):** 35-bit Signed Integer (Injected internally as Q12.20 to match the unshifted multiplier output).
- **Output (Y):** 16-bit Signed Integer (Truncated and saturated back to Q6.10).

## AXI-Stream Format
The default configuration uses a `128-bit` wide AXI-Stream data bus.
- **Input Stream (`s_axis_tdata`):** Contains a 1D vector of 8 elements (16-bit each).
- **Output Stream (`m_axis_tdata`):** Contains the computed 1D vector of 8 elements (16-bit each).
- **TLAST Metadata:** The `TLAST` signal is perfectly synchronized and delayed alongside the valid data path, ensuring that DMA burst boundaries are respected without manual software intervention.

## Pipeline Latency
Because the systolic array delays data diagonally (wavefront processing), there is an initial pipeline depth latency before the first valid output emerges.
- **Formula:** `TOTAL_DELAY = ROWS + COLS - 1`
- **8x8 Configuration:** The core takes `15 clock cycles` from the first asserted `s_valid` input to produce the first `m_valid` output. Once filled, throughput is 1 output vector per clock cycle.