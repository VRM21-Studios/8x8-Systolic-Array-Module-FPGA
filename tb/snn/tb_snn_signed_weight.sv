`timescale 1ns / 1ps

// ============================================================================
// TESTBENCH: tb_snn_signed_weight
// DESCRIPTION:
//   Verifies signed weight accumulation and membrane potential behavior in
//   the SNN core, including negative-to-positive state transitions across
//   multiple timesteps.
//
// TEST SCENARIO:
//   1. Clear the membrane state and apply a negative weight.
//   2. Verify that the negative membrane potential does not generate spikes.
//   3. Apply a positive weight and verify that the accumulated state remains
//      below the configured threshold.
//   4. Apply an additional positive weight and verify threshold crossing.
//
// EXPECTED RESULT:
//   The SNN core must correctly preserve signed membrane potential values
//   and generate spikes only when the configured threshold is reached.
// ============================================================================

module tb_snn_signed_weight();

    // =========================================================================
    // SNN TEST PARAMETERS
    // =========================================================================

    parameter PARALLEL_NEURONS = 64;
    parameter WEIGHT_W         = 16;
    parameter HEADROOM_BITS    = 10;
    parameter VMEM_W           = 32;
    parameter MAX_CHUNKS       = 4;
    parameter LEAK_FRAC_BITS   = 15;
    parameter FIFO_DEPTH       = 128;
    parameter ADDR_W           = 2;

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
        .RAM_STYLE("block"),
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
    // Sends a sequence of input spikes for one virtual-memory chunk.
    // The same signed weight is applied to all parallel neurons.

    integer n;
    reg [WEIGHT_BUS_W-1:0] test_weights;

    task push_chunk(
        input integer num_spikes,
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

                // Wait until both input streams accept the transaction.
                do begin
                    @(posedge aclk);
                    #1;
                end while (!(s_axis_spike_tready && s_axis_weight_tready));
            end

            // Deassert the input streams after the chunk has been accepted.
            s_axis_spike_tvalid  <= 1'b0;
            s_axis_weight_tvalid <= 1'b0;
            s_axis_spike_tlast   <= 1'b0;
        end
    endtask

    // =========================================================================
    // OUTPUT MONITOR AND CHECKER
    // =========================================================================
    // Compares each accepted output vector against the expected spike pattern
    // and records TLAST to detect completion of the current timestep.

    reg spike_tlast_caught;
    reg clear_spike_flag;

    integer chunk_count_out;
    integer current_timestep;
    integer error_count;

    reg [PARALLEL_NEURONS-1:0] expected_vector;

    always @(posedge aclk) begin
        if (!aresetn || clear_spike_flag) begin
            spike_tlast_caught <= 1'b0;
        end
        else if (m_axis_spike_tvalid && m_axis_spike_tready) begin

            if (m_axis_spike_tdata !== expected_vector) begin
                $display(
                    "   [ERROR] Timestep %0d Chunk %0d | Expected: %h | Got: %h",
                    current_timestep,
                    chunk_count_out,
                    expected_vector,
                    m_axis_spike_tdata
                );

                error_count = error_count + 1;
            end
            else begin
                $display(
                    "   [MONITOR] Timestep %0d Chunk %0d | Output: %0h | PASS",
                    current_timestep,
                    chunk_count_out,
                    m_axis_spike_tdata
                );
            end

            if (m_axis_spike_tlast) begin
                spike_tlast_caught <= 1'b1;
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
        $display("SNN SIGNED WEIGHT VERIFICATION");
        $display("=========================================================");

        // ---------------------------------------------------------------------
        // Initial signal values
        // ---------------------------------------------------------------------

        aresetn              = 1'b0;
        ctrl_new_timestep    = 1'b0;
        ctrl_clear_vmem      = 1'b0;

        s_axis_spike_tvalid  = 1'b0;
        s_axis_weight_tvalid = 1'b0;

        m_axis_spike_tready  = 1'b1;

        clear_spike_flag     = 1'b0;

        error_count          = 0;
        chunk_count_out      = 0;
        current_timestep     = 1;
        expected_vector      = {PARALLEL_NEURONS{1'b0}};

        // Threshold = 100.
        i_thresh = 100;

        // Q1.15 representation of approximately 1.0.
        // This configuration effectively disables leakage for this test.
        i_leak_factor = 16'h7FFF;

        // Last valid chunk address.
        i_max_chunks = MAX_CHUNKS - 1;

        // ---------------------------------------------------------------------
        // Reset release
        // ---------------------------------------------------------------------

        #100;
        aresetn = 1'b1;
        #100;

        // =====================================================================
        // TIMESTEP 1: NEGATIVE WEIGHT
        // =====================================================================
        // Starting from zero membrane potential, apply -100 to every neuron.
        // Expected membrane potential: -100.
        // Expected output: no spikes.

        current_timestep = 1;
        chunk_count_out  = 0;
        expected_vector  = {PARALLEL_NEURONS{1'b0}};

        $display("");
        $display("[1] TIMESTEP 1: Negative Weight");
        $display("    Applied weight: -100");
        $display("    Expected membrane potential: -100");
        $display("    Expected output: no spikes");

        @(posedge aclk);
        #1;

        ctrl_clear_vmem   = 1'b1;
        ctrl_new_timestep = 1'b1;

        @(posedge aclk);
        #1;

        ctrl_clear_vmem   = 1'b0;
        ctrl_new_timestep = 1'b0;

        for (c = 0; c < MAX_CHUNKS; c = c + 1) begin
            push_chunk(1, -16'd100);
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
        // TIMESTEP 2: POSITIVE ACCUMULATION
        // =====================================================================
        // Continue from the previous membrane state:
        //
        //     Vmem = -100 + 150 = 50
        //
        // Since 50 < 100, no spike is expected.

        current_timestep = 2;
        chunk_count_out  = 0;
        expected_vector  = {PARALLEL_NEURONS{1'b0}};

        $display("");
        $display("[2] TIMESTEP 2: Positive Weight Accumulation");
        $display("    Applied weight: +150");
        $display("    Expected membrane potential: 50");
        $display("    Expected output: no spikes");

        @(posedge aclk);
        #1;

        ctrl_new_timestep = 1'b1;

        @(posedge aclk);
        #1;

        ctrl_new_timestep = 1'b0;

        for (c = 0; c < MAX_CHUNKS; c = c + 1) begin
            push_chunk(1, 16'd150);
        end

        while (spike_tlast_caught == 1'b0) begin
            @(posedge aclk);
            #1;
        end

        clear_spike_flag = 1'b1;
        @(posedge aclk);
        #1;
        clear_spike_flag = 1'b0;

        // =====================================================================
        // TIMESTEP 3: THRESHOLD CROSSING
        // =====================================================================
        // Continue from the previous membrane state:
        //
        //     Vmem = 50 + 60 = 110
        //
        // Since 110 >= 100, every neuron is expected to generate a spike.

        current_timestep = 3;
        chunk_count_out  = 0;
        expected_vector  = {PARALLEL_NEURONS{1'b1}};

        $display("");
        $display("[3] TIMESTEP 3: Threshold Crossing");
        $display("    Applied weight: +60");
        $display("    Expected membrane potential: 110");
        $display("    Expected output: all neurons spike");

        @(posedge aclk);
        #1;

        ctrl_new_timestep = 1'b1;

        @(posedge aclk);
        #1;

        ctrl_new_timestep = 1'b0;

        for (c = 0; c < MAX_CHUNKS; c = c + 1) begin
            push_chunk(1, 16'd60);
        end

        while (spike_tlast_caught == 1'b0) begin
            @(posedge aclk);
            #1;
        end

        // =====================================================================
        // TEST RESULT
        // =====================================================================

        $display("");
        $display("=========================================================");

        if (error_count == 0) begin
            $display("TEST PASSED");
            $display("Signed weight accumulation and threshold behavior");
            $display("matched the expected results.");
        end
        else begin
            $display("TEST FAILED");
            $display("Detected %0d output mismatches.", error_count);
        end

        $display("=========================================================");

        #100;
        $finish;
    end

    // =========================================================================
    // INTERNAL DEBUG MONITOR
    // =========================================================================
    // Displays the calculated membrane potential for neuron 0 on the first
    // output chunk of each observed timestep.

    always @(posedge aclk) begin
        if (m_axis_spike_tvalid &&
            m_axis_spike_tready &&
            chunk_count_out == 0) begin

            $display(
                "       [DEBUG] Neuron 0 membrane potential = %0d",
                $signed(DUT.GEN_NEURON_HW[0].v_sum[VMEM_W-1:0])
            );
        end
    end

endmodule
