`timescale 1ns / 1ps

// ============================================================================
// TESTBENCH: tb_snn_lif_dynamics
// DESCRIPTION:
//   Verifies the temporal behavior of the Leaky Integrate-and-Fire (LIF)
//   dynamics implemented by vrm_snn_core.
//
// TEST CONFIGURATION:
//   - 4 physical neurons processed in parallel
//   - 4 virtual neuron chunks
//   - Threshold = 100
//   - Leak factor = 0.9375 (Q1.15 representation)
//   - 25 consecutive timesteps are evaluated
//   - Input spikes follow a deterministic periodic pattern
//
// The testbench also records internal membrane-potential and pipeline
// information into text files for offline analysis and debugging.
//
// OUTPUT FILES:
//   - vmem_dump.txt : Membrane-potential and spike-output trace
//   - rtl_trace.txt : Detailed internal pipeline trace
// ============================================================================

module tb_snn_lif_dynamics();

    // =========================================================================
    // TEST PARAMETERS
    // =========================================================================

    parameter PARALLEL_NEURONS = 4;
    parameter MAX_CHUNKS       = 4;
    parameter ADDR_W           = 2;
    parameter WEIGHT_W         = 16;
    parameter HEADROOM_BITS    = 10;
    parameter VMEM_W           = 32;
    parameter LEAK_FRAC_BITS   = 15;
    parameter FIFO_DEPTH       = 16;

    localparam WEIGHT_BUS_W = PARALLEL_NEURONS * WEIGHT_W;

    // =========================================================================
    // DUT INTERFACE SIGNALS
    // =========================================================================

    reg aclk;
    reg aresetn;

    reg ctrl_new_timestep;
    reg ctrl_clear_vmem;

    reg signed [VMEM_W-1:0] i_thresh;
    reg [15:0]              i_leak_factor;
    reg [ADDR_W-1:0]        i_max_chunks;

    // Spike input stream
    reg  s_axis_spike_tvalid;
    reg  s_axis_spike_tdata;
    reg  s_axis_spike_tlast;
    wire s_axis_spike_tready;

    // Weight input stream
    reg  [WEIGHT_BUS_W-1:0] s_axis_weight_tvalid;
    reg  [WEIGHT_BUS_W-1:0] s_axis_weight_tdata;
    wire                    s_axis_weight_tready;

    // Spike output stream
    wire [PARALLEL_NEURONS-1:0] m_axis_spike_tdata;
    wire                        m_axis_spike_tvalid;
    wire                        m_axis_spike_tlast;
    reg                         m_axis_spike_tready;

    // =========================================================================
    // TRACE FILE HANDLES
    // =========================================================================

    integer file_vmem;
    integer file_trace;

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
    // 5 ns period = 200 MHz.

    initial begin
        aclk = 1'b0;
        forever #2.5 aclk = ~aclk;
    end

    // =========================================================================
    // INPUT DATA SET
    // =========================================================================
    //
    // A deterministic one-hot pattern is generated for each timestep.
    // The original stimulus contains five input positions and is used to
    // exercise the temporal accumulation behavior of the LIF neuron.

    reg [4:0] input_spikes [0:29];
    reg signed [15:0] weights [0:4];

    integer i;
    integer t;

    initial begin
        // Per-input synaptic weights.
        weights[0] = 16'sd25;
        weights[1] = 16'sd20;
        weights[2] = 16'sd15;
        weights[3] = 16'sd30;
        weights[4] = 16'sd18;

        // Generate a periodic one-hot spike sequence.
        for (t = 0; t < 30; t = t + 1) begin
            input_spikes[t] = 5'b00000;

            for (i = 0; i < 5; i = i + 1) begin
                if ((t % 5) == i)
                    input_spikes[t][i] = 1'b1;
            end
        end
    end

    // =========================================================================
    // TIMESTEP EXECUTION TASK
    // =========================================================================
    //
    // Sends one timestep of input data to the DUT. Each timestep consists of
    // five sequential input samples, with TLAST marking the final sample.

    task run_timestep(
        input integer timestep,
        input integer is_first
    );
        integer n;

        begin
            // Clear membrane memory only at the beginning of the simulation.
            ctrl_clear_vmem <= is_first ? 1'b1 : 1'b0;

            @(posedge aclk);

            // Start a new timestep.
            ctrl_new_timestep <= 1'b1;

            @(posedge aclk);

            ctrl_new_timestep <= 1'b0;

            // Send the five input samples belonging to this timestep.
            for (n = 0; n < 5; n = n + 1) begin

                s_axis_spike_tvalid  <= 1'b1;
                s_axis_spike_tdata   <= input_spikes[timestep][n];
                s_axis_spike_tlast   <= (n == 4);

                s_axis_weight_tvalid <= 1'b1;
                s_axis_weight_tdata  <= weights[n];

                // Wait until both input streams are accepted.
                do begin
                    @(posedge aclk);
                end while (!(s_axis_spike_tvalid &&
                             s_axis_spike_tready &&
                             s_axis_weight_tvalid &&
                             s_axis_weight_tready));
            end

            // Return input interface to the idle state.
            s_axis_spike_tvalid  <= 1'b0;
            s_axis_weight_tvalid <= 1'b0;
            s_axis_spike_tlast   <= 1'b0;

            // Allow the pipeline to complete the current timestep.
            repeat (5) @(posedge aclk);
        end
    endtask

    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================

    initial begin

        // ---------------------------------------------------------------------
        // Initial conditions
        // ---------------------------------------------------------------------

        aresetn = 1'b0;

        ctrl_new_timestep = 1'b0;
        ctrl_clear_vmem   = 1'b0;

        s_axis_spike_tvalid = 1'b0;
        s_axis_spike_tdata  = 1'b0;
        s_axis_spike_tlast  = 1'b0;

        s_axis_weight_tvalid = 1'b0;
        s_axis_weight_tdata  = {WEIGHT_BUS_W{1'b0}};

        // Continuously consume generated spike vectors.
        m_axis_spike_tready = 1'b1;

        // ---------------------------------------------------------------------
        // LIF configuration
        // ---------------------------------------------------------------------

        i_thresh      = 32'sd100;

        // 30720 / 32768 = 0.9375.
        // The value is represented in Q1.15 fixed-point format.
        i_leak_factor = 16'd30720;

        // Only one virtual chunk is required for this temporal test.
        i_max_chunks = 0;

        // ---------------------------------------------------------------------
        // Reset release
        // ---------------------------------------------------------------------

        #100;
        aresetn = 1'b1;
        #100;

        // ---------------------------------------------------------------------
        // Run 25 consecutive timesteps.
        // ---------------------------------------------------------------------

        for (t = 0; t < 25; t = t + 1) begin
            run_timestep(t, (t == 0));
        end

        // Allow remaining pipeline activity to settle.
        #500;

        $display("[%0t] LIF dynamics simulation completed.", $time);

        $finish;
    end

    // =========================================================================
    // MEMBRANE POTENTIAL TRACE
    // =========================================================================
    //
    // Records the membrane potential and spike state for neuron 0 whenever
    // chunk 0 reaches the final processing stage.

    initial begin
        file_vmem = $fopen("vmem_dump.txt", "w");

        $fdisplay(
            file_vmem,
            "TIME,VMEM,SPIKE_OUT"
        );
    end

    always @(posedge aclk) begin
        if (aresetn &&
            DUT.valid_s3 &&
            (DUT.addr_s3 == 0)) begin

            $fdisplay(
                file_vmem,
                "%0t,%d,%b",
                $time,
                $signed(DUT.GEN_NEURON_HW[0].v_sum),
                DUT.spike_vector[0]
            );
        end
    end

    // =========================================================================
    // INTERNAL PIPELINE TRACE
    // =========================================================================
    //
    // Records the internal state of neuron 0 and the associated pipeline
    // control signals. This trace is intended for detailed RTL debugging and
    // verification of the membrane-potential update sequence.

    initial begin
        file_trace = $fopen("rtl_trace.txt", "w");

        $fdisplay(
            file_trace,
            "TIME,CHUNK,ADDR_S2,ADDR_S3,VALID_S2,VALID_S3,"
            "MAC_DONE,PSUM_OUT,PSUM_S2,PSUM_S3,VOLD,VLEAK,VNEXT,SPIKE"
        );
    end

    always @(posedge aclk) begin
        if (aresetn && DUT.valid_s3) begin

            $fdisplay(
                file_trace,
                "%0t,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                $time,
                DUT.chunk_addr,
                DUT.addr_s2,
                DUT.addr_s3,
                DUT.valid_s2,
                DUT.valid_s3,
                DUT.mac_done_valid,
                $signed(DUT.GEN_NEURON_HW[0].psum_out_reg),
                $signed(DUT.GEN_NEURON_HW[0].psum_s2_reg),
                $signed(DUT.GEN_NEURON_HW[0].psum_s3_reg),
                $signed(DUT.ram_rd_data[31:0]),
                $signed(DUT.GEN_NEURON_HW[0].v_leak_s3_reg),
                $signed(DUT.GEN_NEURON_HW[0].v_sum),
                DUT.spike_vector[0]
            );

            // Display the same internal state in the simulator console.
            $display("============== LIF PIPELINE TRACE ==============");
            $display(
                "Vmem previous : %0d",
                $signed(DUT.ram_rd_data[31:0])
            );
            $display(
                "Vmem leaked   : %0d",
                $signed(DUT.GEN_NEURON_HW[0].v_leak_s3_reg)
            );
            $display(
                "Synaptic input: %0d",
                $signed(DUT.GEN_NEURON_HW[0].psum_s3_reg)
            );
            $display(
                "Vmem next     : %0d",
                $signed(DUT.GEN_NEURON_HW[0].v_sum)
            );
            $display(
                "Threshold     : %0d",
                DUT.i_thresh
            );
            $display(
                "Spike         : %0d",
                DUT.spike_vector[0]
            );
        end
    end

endmodule
