`timescale 1ns / 1ps

// ============================================================================
// TESTBENCH: tb_snn_scale
// DESCRIPTION:
//   Verifies large-scale virtual neuron processing using sequential memory
//   chunks. The test configures 64 physical neurons and processes 4096 chunks,
//   representing 262,144 virtual neuron states.
//
// TEST OBJECTIVES:
//   - Verify continuous processing across the configured chunk range.
//   - Verify sequential virtual-memory addressing.
//   - Verify stable operation across a large number of processed chunks.
//   - Verify that negative membrane accumulation does not generate false
//     spikes.
//   - Verify TLAST generation at the end of the configured chunk sequence.
//
// TEST CONFIGURATION:
//   Physical neurons : 64
//   Memory chunks    : 4096
//   Virtual neurons  : 262,144
//
// EXPECTED RESULT:
//   All 4096 output chunks must be generated without false spikes.
//   TLAST must be asserted on the final output chunk.
// ============================================================================

module tb_snn_scale();

    // =========================================================================
    // SNN TEST PARAMETERS
    // =========================================================================

    parameter PARALLEL_NEURONS = 64;
    parameter WEIGHT_W         = 16;
    parameter HEADROOM_BITS    = 10;
    parameter VMEM_W           = 32;
    parameter MAX_CHUNKS       = 4096;
    parameter LEAK_FRAC_BITS   = 15;
    parameter FIFO_DEPTH       = 8192;
    parameter ADDR_W           = 12;

    localparam WEIGHT_BUS_W = PARALLEL_NEURONS * WEIGHT_W;

    // =========================================================================
    // CLOCK AND RESET
    // =========================================================================

    reg aclk;
    reg aresetn;

    // =========================================================================
    // SNN CONTROL INTERFACE
    // =========================================================================

    reg ctrl_new_timestep;
    reg ctrl_clear_vmem;

    reg signed [VMEM_W-1:0] i_thresh;
    reg [15:0]              i_leak_factor;
    reg [ADDR_W-1:0]        i_max_chunks;

    // =========================================================================
    // INPUT SPIKE STREAM
    // =========================================================================

    reg  s_axis_spike_tvalid;
    reg  s_axis_spike_tdata;
    reg  s_axis_spike_tlast;
    wire s_axis_spike_tready;

    // =========================================================================
    // INPUT WEIGHT STREAM
    // =========================================================================

    reg  s_axis_weight_tvalid;
    reg  [WEIGHT_BUS_W-1:0] s_axis_weight_tdata;
    wire s_axis_weight_tready;

    // =========================================================================
    // OUTPUT SPIKE STREAM
    // =========================================================================

    wire [PARALLEL_NEURONS-1:0] m_axis_spike_tdata;
    wire                         m_axis_spike_tvalid;
    wire                         m_axis_spike_tlast;
    reg                          m_axis_spike_tready;

    // =========================================================================
    // DEVICE UNDER TEST
    // =========================================================================

    vrm_snn_core #(
        .PARALLEL_NEURONS(PARALLEL_NEURONS),
        .WEIGHT_W(WEIGHT_W),
        .HEADROOM_BITS(HEADROOM_BITS),
        .VMEM_W(VMEM_W),
        .MAX_CHUNKS(MAX_CHUNKS),
        .LEAK_FRAC_BITS(LEAK_FRAC_BITS),
        .FIFO_DEPTH(FIFO_DEPTH),
        .RAM_STYLE("ultra"),
        .ADDR_W(ADDR_W)
    ) DUT (
        .aclk(aclk),
        .aresetn(aresetn),

        .ctrl_new_timestep(ctrl_new_timestep),
        .ctrl_clear_vmem(ctrl_clear_vmem),
        .i_thresh(i_thresh),
        .i_leak_factor(i_leak_factor),
        .i_max_chunks(i_max_chunks),

        .s_axis_spike_tvalid(s_axis_spike_tvalid),
        .s_axis_spike_tdata(s_axis_spike_tdata),
        .s_axis_spike_tlast(s_axis_spike_tlast),
        .s_axis_spike_tready(s_axis_spike_tready),

        .s_axis_weight_tvalid(s_axis_weight_tvalid),
        .s_axis_weight_tdata(s_axis_weight_tdata),
        .s_axis_weight_tready(s_axis_weight_tready),

        .m_axis_spike_tdata(m_axis_spike_tdata),
        .m_axis_spike_tvalid(m_axis_spike_tvalid),
        .m_axis_spike_tlast(m_axis_spike_tlast),
        .m_axis_spike_tready(m_axis_spike_tready)
    );

    // =========================================================================
    // CLOCK GENERATOR
    // =========================================================================
    // 100 MHz clock: 10 ns period.

    initial begin
        aclk = 1'b0;
        forever #5 aclk = ~aclk;
    end

    // =========================================================================
    // INPUT TRANSACTION TASK
    // =========================================================================
    // Generates input transactions for one virtual-memory chunk.
    // The same signed weight is replicated across all physical neurons.

    integer n;
    reg [WEIGHT_BUS_W-1:0] test_weights;

    task push_chunk(
        input integer num_spikes,
        input integer chunk_id,
        input signed [15:0] weight_val
    );
        integer s;
        begin
            // Replicate the test weight across all physical neurons.
            test_weights = 0;

            for (n = 0; n < PARALLEL_NEURONS; n = n + 1) begin
                test_weights[(n*WEIGHT_W) +: WEIGHT_W] = weight_val;
            end

            // Transmit the requested number of spike transactions.
            for (s = 0; s < num_spikes; s = s + 1) begin
                s_axis_spike_tvalid  <= 1'b1;
                s_axis_spike_tdata   <= 1'b1;
                s_axis_spike_tlast   <= (s == num_spikes - 1) ? 1'b1 : 1'b0;

                s_axis_weight_tvalid <= 1'b1;
                s_axis_weight_tdata  <= test_weights;

                // Wait for both input streams to accept the transaction.
                do begin
                    @(posedge aclk);
                    #1;
                end while (!(s_axis_spike_tready &&
                             s_axis_weight_tready));
            end

            // Deassert the input streams after the chunk has been accepted.
            s_axis_spike_tvalid  <= 1'b0;
            s_axis_weight_tvalid <= 1'b0;
            s_axis_spike_tlast   <= 1'b0;
        end
    endtask

    // =========================================================================
    // OUTPUT COMPLETION MONITOR
    // =========================================================================
    // Detects TLAST on the output stream to determine when all configured
    // chunks have been processed.

    reg spike_tlast_caught;
    reg clear_spike_flag;

    always @(posedge aclk) begin
        if (!aresetn || clear_spike_flag) begin
            spike_tlast_caught <= 1'b0;
        end
        else if (m_axis_spike_tvalid && m_axis_spike_tready) begin
            if (m_axis_spike_tlast) begin
                spike_tlast_caught <= 1'b1;

                $display(
                    "   [MONITOR] Output TLAST received after %0d chunks.",
                    MAX_CHUNKS
                );
            end
        end
    end

    // =========================================================================
    // OUTPUT CHECKER
    // =========================================================================
    // The test applies a negative weight to every neuron. Starting from a
    // cleared membrane state, the resulting membrane potential remains below
    // threshold and therefore must never produce a spike.

    integer error_count;
    integer chunk_count_out;

    always @(posedge aclk) begin
        if (m_axis_spike_tvalid && m_axis_spike_tready) begin

            // Verify that no false spike is generated.
            if (m_axis_spike_tdata !== {PARALLEL_NEURONS{1'b0}}) begin
                $display(
                    "   [ERROR] Chunk %0d generated an unexpected spike. Data: %h",
                    chunk_count_out,
                    m_axis_spike_tdata
                );

                error_count = error_count + 1;
            end

            // Limit console output for the large-scale test.
            if (chunk_count_out < 3 ||
                chunk_count_out >= MAX_CHUNKS - 3) begin

                $display(
                    "   [MONITOR] Chunk %0d | Output: %0h | Expected: 0 | %s",
                    chunk_count_out,
                    m_axis_spike_tdata,
                    (m_axis_spike_tdata == 0) ? "PASS" : "FAIL"
                );
            end
            else if (chunk_count_out == 3) begin

                $display(
                    "   [MONITOR] Intermediate output chunks hidden."
                );
            end

            chunk_count_out = chunk_count_out + 1;
        end
    end

    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================

    integer c;

    initial begin
        $display("=========================================================");
        $display("SNN LARGE-SCALE PROCESSING VERIFICATION");
        $display("=========================================================");
        $display("Physical neurons : %0d", PARALLEL_NEURONS);
        $display("Memory chunks    : %0d", MAX_CHUNKS);
        $display("Virtual neurons  : %0d",
                 PARALLEL_NEURONS * MAX_CHUNKS);
        $display("=========================================================");

        // ---------------------------------------------------------------------
        // Initial signal values
        // ---------------------------------------------------------------------

        aresetn              = 1'b0;

        ctrl_new_timestep    = 1'b0;
        ctrl_clear_vmem      = 1'b0;

        s_axis_spike_tvalid  = 1'b0;
        s_axis_spike_tdata   = 1'b0;
        s_axis_spike_tlast   = 1'b0;

        s_axis_weight_tvalid = 1'b0;
        s_axis_weight_tdata  = 0;

        // Continuously drain the output FIFO.
        m_axis_spike_tready  = 1'b1;

        spike_tlast_caught   = 1'b0;
        clear_spike_flag     = 1'b0;

        error_count          = 0;
        chunk_count_out      = 0;

        // Threshold = 100.
        i_thresh = 100;

        // Q1.15 representation of approximately 1.0.
        // This configuration effectively disables leakage for this test.
        i_leak_factor = 16'h7FFF;

        // Last valid chunk address: 4095 for 4096 chunks.
        i_max_chunks = MAX_CHUNKS - 1;

        // ---------------------------------------------------------------------
        // Reset release
        // ---------------------------------------------------------------------

        #100;
        aresetn = 1'b1;
        #100;

        // =====================================================================
        // INITIALIZE MEMBRANE STATE
        // =====================================================================

        $display("");
        $display("Starting large-scale chunk processing...");
        $display("Each chunk applies weight = -100 to all %0d neurons.",
                 PARALLEL_NEURONS);
        $display("Expected result: no output spikes.");

        @(posedge aclk);
        #1;

        ctrl_clear_vmem   = 1'b1;
        ctrl_new_timestep = 1'b1;

        @(posedge aclk);
        #1;

        ctrl_clear_vmem   = 1'b0;
        ctrl_new_timestep = 1'b0;

        // =====================================================================
        // LARGE-SCALE INPUT PROCESSING
        // =====================================================================
        // Process all configured memory chunks without intentional gaps
        // between transactions.

        for (c = 0; c < MAX_CHUNKS; c = c + 1) begin
            push_chunk(1, c, -16'd100);
        end

        // Wait until the final output transaction is accepted.
        while (spike_tlast_caught == 1'b0) begin
            @(posedge aclk);
            #1;
        end

        clear_spike_flag = 1'b1;
        @(posedge aclk);
        #1;
        clear_spike_flag = 1'b0;

        // =====================================================================
        // TEST RESULT
        // =====================================================================

        $display("");
        $display("=========================================================");

        if (error_count == 0 &&
            chunk_count_out == MAX_CHUNKS) begin

            $display("TEST PASSED");
            $display(
                "Successfully processed %0d virtual neuron states",
                PARALLEL_NEURONS * MAX_CHUNKS
            );
            $display(
                "across %0d chunks without false spikes.",
                MAX_CHUNKS
            );
        end
        else begin

            $display("TEST FAILED");
            $display(
                "Detected %0d output errors across %0d processed chunks.",
                error_count,
                chunk_count_out
            );
        end

        $display("=========================================================");

        #200;
        $finish;
    end

endmodule
