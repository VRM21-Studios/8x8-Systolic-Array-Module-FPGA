```verilog
`timescale 1ns / 1ps

// ============================================================================
// Module: vrm_snn_core
// Description:
//   Parameterized spiking neural network (SNN) processing core implementing
//   a parallel Leaky Integrate-and-Fire (LIF) neuron datapath.
//
//   The core processes streamed binary input spikes together with a vector
//   of synaptic weights. Synaptic accumulation is performed across input
//   chunks, followed by membrane-potential update, leakage, threshold
//   comparison, and spike generation.
//
//   The membrane state of all parallel neurons is stored in an external
//   VRM RAM core instance. The output spike vector is buffered through the
//   VRM FIFO core.
//
//   The default configuration provides 64 parallel neurons and a 4096-entry
//   virtual-neuron state space.
//
// Interface:
//   - AXI4-Stream-like input for binary spikes.
//   - AXI4-Stream-like input for parallel synaptic weights.
//   - AXI4-Stream-like output for generated spike vectors.
//   - Synchronous control inputs for timestep and membrane-state management.
//
// Notes:
//   - The implementation uses fixed-point arithmetic.
//   - RAM_STYLE defaults to UltraRAM-oriented inference.
//   - The input spike stream is scalar; the same input spike controls the
//     corresponding synaptic weight vector for all parallel neurons.
// ============================================================================

module vrm_snn_core #(
    parameter PARALLEL_NEURONS = 64,
    parameter WEIGHT_W         = 16,
    parameter HEADROOM_BITS    = 10,
    parameter VMEM_W           = 32,
    parameter MAX_CHUNKS       = 4096,
    parameter LEAK_FRAC_BITS   = 15,
    parameter FIFO_DEPTH       = 8192,
    parameter RAM_STYLE        = "ultra",
    parameter ADDR_W           = $clog2(MAX_CHUNKS)
)(
    input  wire aclk,
    input  wire aresetn,

    // ------------------------------------------------------------------------
    // Control and LIF Configuration
    // ------------------------------------------------------------------------
    input  wire ctrl_new_timestep,
    input  wire ctrl_clear_vmem,
    input  wire signed [VMEM_W-1:0] i_thresh,
    input  wire [15:0] i_leak_factor,
    input  wire [ADDR_W-1:0] i_max_chunks,

    // ------------------------------------------------------------------------
    // Spike Input Stream
    // ------------------------------------------------------------------------
    input  wire                                  s_axis_spike_tvalid,
    input  wire                                  s_axis_spike_tdata,
    input  wire                                  s_axis_spike_tlast,
    output wire                                  s_axis_spike_tready,

    // ------------------------------------------------------------------------
    // Synaptic Weight Input Stream
    // ------------------------------------------------------------------------
    input  wire                                  s_axis_weight_tvalid,
    input  wire [(PARALLEL_NEURONS*WEIGHT_W)-1:0] s_axis_weight_tdata,
    output wire                                  s_axis_weight_tready,

    // ------------------------------------------------------------------------
    // Spike Output Stream
    // ------------------------------------------------------------------------
    output wire [PARALLEL_NEURONS-1:0]           m_axis_spike_tdata,
    output wire                                  m_axis_spike_tvalid,
    output wire                                  m_axis_spike_tlast,
    input  wire                                  m_axis_spike_tready
);

    localparam ACC_W = WEIGHT_W + HEADROOM_BITS;
    localparam BUS_W = PARALLEL_NEURONS * VMEM_W;

    // =========================================================================
    // 0. Global Control and Pipeline Synchronization
    // =========================================================================

    wire fifo_almost_full;

    // Processing advances only when both input streams are valid and the
    // output FIFO has sufficient space.
    wire pipe_en = s_axis_spike_tvalid &&
                   s_axis_weight_tvalid &&
                   !fifo_almost_full;

    // Both input streams must be presented simultaneously because each
    // spike is processed together with its corresponding weight vector.
    assign s_axis_spike_tready  = s_axis_weight_tvalid && !fifo_almost_full;
    assign s_axis_weight_tready = s_axis_spike_tvalid && !fifo_almost_full;

    wire current_spike = s_axis_spike_tdata;

    // Indicates completion of the current input chunk and initiates the
    // membrane-state read path.
    reg mac_done_valid;

    always @(posedge aclk) begin
        if (!aresetn)
            mac_done_valid <= 1'b0;
        else if (pipe_en)
            mac_done_valid <= s_axis_spike_tlast;
        else if (!fifo_almost_full)
            mac_done_valid <= 1'b0;
    end

    // Virtual-neuron chunk address. The address is reset at the beginning
    // of a timestep and wraps after the configured final chunk.
    reg [ADDR_W-1:0] chunk_addr;

    always @(posedge aclk) begin
        if (!aresetn || ctrl_new_timestep) begin
            chunk_addr <= 0;
        end else if (mac_done_valid && !fifo_almost_full) begin
            chunk_addr <= (chunk_addr == i_max_chunks) ?
                          {ADDR_W{1'b0}} :
                          chunk_addr + 1;
        end
    end

    // =========================================================================
    // 1. Virtual Membrane-State Memory
    // =========================================================================

    wire             ram_we;
    wire [BUS_W-1:0] ram_wr_data_wire;
    wire [BUS_W-1:0] ram_rd_data;
    reg  [ADDR_W-1:0] addr_s3;

    // The VRM RAM core stores the membrane potential of all parallel neurons
    // associated with each virtual-neuron chunk.
    vrm_ram_core #(
        .DATA_WIDTH(BUS_W),
        .ADDR_WIDTH(ADDR_W),
        .RAM_STYLE(RAM_STYLE)
    ) vmem_ram (
        .clk(aclk),
        .rstn(aresetn),
        .we(ram_we),
        .wr_addr(addr_s3),
        .wr_data(ram_wr_data_wire),
        .re(mac_done_valid),
        .rd_addr(chunk_addr),
        .rd_data(ram_rd_data)
    );

    // =========================================================================
    // 2. Stage 2: Memory Read Alignment
    // =========================================================================

    reg              valid_s2;
    reg [ADDR_W-1:0] addr_s2;
    reg              clear_s2;

    always @(posedge aclk) begin
        if (!aresetn) begin
            valid_s2 <= 1'b0;
            addr_s2  <= 0;
            clear_s2 <= 1'b0;
        end else if (!fifo_almost_full) begin
            valid_s2 <= mac_done_valid;
            addr_s2  <= chunk_addr;
            clear_s2 <= ctrl_clear_vmem;
        end
    end

    // =========================================================================
    // 3. Stage 3: LIF Update and Write-Back Control
    // =========================================================================

    reg valid_s3;

    always @(posedge aclk) begin
        if (!aresetn) begin
            valid_s3 <= 1'b0;
            addr_s3  <= 0;
        end else if (!fifo_almost_full) begin
            valid_s3 <= valid_s2;
            addr_s3  <= addr_s2;
        end
    end

    assign ram_we = valid_s3;

    // =========================================================================
    // 4. Parallel Per-Neuron Datapath
    // =========================================================================

    wire [PARALLEL_NEURONS-1:0] spike_vector;

    // The leak factor is zero-extended before signed arithmetic.
    wire signed [16:0] leak_factor_signed =
        $signed({1'b0, i_leak_factor});

    genvar i;
    generate
        for (i = 0; i < PARALLEL_NEURONS; i = i + 1) begin : GEN_NEURON_HW

            // -----------------------------------------------------------------
            // 4.1 Synaptic Accumulation
            // -----------------------------------------------------------------

            // Each neuron receives one weight from the flattened weight bus.
            wire signed [WEIGHT_W-1:0] w_in =
                $signed(s_axis_weight_tdata[
                    (i*WEIGHT_W) +: WEIGHT_W
                ]);

            reg signed [ACC_W-1:0] acc_reg;
            reg signed [ACC_W-1:0] psum_out_reg;

            // Accumulate the weighted contribution of all input spikes in
            // the current chunk. The final contribution is transferred to
            // psum_out_reg when TLAST marks the end of the chunk.
            always @(posedge aclk) begin
                if (!aresetn) begin
                    acc_reg      <= 0;
                    psum_out_reg <= 0;
                end else if (pipe_en) begin
                    if (s_axis_spike_tlast) begin
                        psum_out_reg <= acc_reg +
                                        (current_spike ?
                                         w_in :
                                         $signed({WEIGHT_W{1'b0}}));
                        acc_reg <= 0;
                    end else if (current_spike) begin
                        acc_reg <= acc_reg + w_in;
                    end
                end
            end

            // -----------------------------------------------------------------
            // 4.2 LIF Membrane-State Read and Leak Multiplication
            // -----------------------------------------------------------------

            wire signed [VMEM_W-1:0] v_old_raw =
                ram_rd_data[(i*VMEM_W) +: VMEM_W];

            // When requested, the previous membrane state is replaced with
            // zero before applying the leak operation.
            wire signed [VMEM_W-1:0] v_old_masked =
                clear_s2 ? {VMEM_W{1'b0}} : v_old_raw;

            // Fixed-point multiplication between membrane state and the
            // configured leak factor.
            wire signed [VMEM_W+16:0] mult_res =
                v_old_masked * leak_factor_signed;

            reg signed [ACC_W-1:0] psum_s2_reg;

            always @(posedge aclk) begin
                if (!aresetn)
                    psum_s2_reg <= 0;
                else if (!fifo_almost_full)
                    psum_s2_reg <= psum_out_reg;
            end

            // -----------------------------------------------------------------
            // 4.3 LIF Integration and Pipeline Alignment
            // -----------------------------------------------------------------

            reg signed [ACC_W-1:0] psum_s3_reg;
            reg signed [VMEM_W-1:0] v_leak_s3_reg;

            always @(posedge aclk) begin
                if (!aresetn) begin
                    psum_s3_reg   <= 0;
                    v_leak_s3_reg <= 0;
                end else if (!fifo_almost_full) begin
                    psum_s3_reg <= psum_s2_reg;

                    // Convert the leak multiplication result back from
                    // fixed-point representation by removing the fractional
                    // bits through an arithmetic right-aligned slice.
                    v_leak_s3_reg <=
                        mult_res[
                            VMEM_W + LEAK_FRAC_BITS - 1 :
                            LEAK_FRAC_BITS
                        ];
                end
            end

            // Integrate the leaked membrane state with the accumulated
            // synaptic contribution.
            wire signed [VMEM_W:0] v_sum =
                $signed(v_leak_s3_reg) +
                $signed(psum_s3_reg);

            // LIF threshold comparison. A spike is generated when the
            // updated membrane potential reaches or exceeds the threshold.
            wire is_spike =
                (v_sum >= $signed(i_thresh));

            assign spike_vector[i] = is_spike;

            // Reset the membrane state after firing; otherwise retain the
            // updated membrane potential.
            assign ram_wr_data_wire[(i*VMEM_W) +: VMEM_W] =
                is_spike ?
                {VMEM_W{1'b0}} :
                v_sum[VMEM_W-1:0];

        end
    endgenerate

    // =========================================================================
    // 5. Spike Output FIFO
    // =========================================================================

    // TLAST identifies the final chunk of the configured virtual-neuron
    // processing range.
    wire is_last_chunk =
        valid_s3 && (addr_s3 == i_max_chunks);

    vrm_fifo #(
        .DATA_WIDTH(PARALLEL_NEURONS),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) out_spike_fifo (
        .aclk(aclk),
        .aresetn(aresetn),

        .s_axis_tdata(spike_vector),
        .s_axis_tlast(is_last_chunk),
        .s_axis_tvalid(valid_s3),
        .s_axis_tready(),
        .s_axis_almost_full(fifo_almost_full),

        .m_axis_tdata(m_axis_spike_tdata),
        .m_axis_tlast(m_axis_spike_tlast),
        .m_axis_tvalid(m_axis_spike_tvalid),
        .m_axis_tready(m_axis_spike_tready)
    );

endmodule
```
