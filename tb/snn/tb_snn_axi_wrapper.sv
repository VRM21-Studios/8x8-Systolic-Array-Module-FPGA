`timescale 1ns / 1ps

/* ============================================================================
 * TESTBENCH: tb_snn_axi_wrapper
 *
 * PURPOSE:
 *   Validate the AXI-Lite control interface and AXI4-Stream data interface
 *   of the SNN AXI wrapper.
 *
 * TEST SCENARIOS:
 *   1. Configure SNN parameters through AXI-Lite writes.
 *   2. Verify AXI-Lite register readback.
 *   3. Verify automatic clearing of the trigger_new_timestep control bit.
 *   4. Inject AXI4-Stream spike and weight data.
 *   5. Monitor the output AXI4-Stream transaction and TLAST propagation.
 *
 * NOTE:
 *   The SNN configuration is intentionally reduced to a small scale so that
 *   the simulation remains fast while still exercising the wrapper interface.
 * ============================================================================ */

module tb_snn_axi_wrapper();

    // =========================================================================
    // SNN CORE PARAMETERS
    // =========================================================================
    parameter PARALLEL_NEURONS = 4;
    parameter WEIGHT_W         = 16;
    parameter HEADROOM_BITS    = 10;
    parameter VMEM_W           = 32;
    parameter MAX_CHUNKS       = 8;
    parameter LEAK_FRAC_BITS   = 15;
    parameter FIFO_DEPTH       = 16;

    // =========================================================================
    // AXI-LITE PARAMETERS
    // =========================================================================
    parameter C_S_AXI_DATA_WIDTH = 32;
    parameter C_S_AXI_ADDR_WIDTH = 5;

    localparam WEIGHT_BUS_W = PARALLEL_NEURONS * WEIGHT_W;

    // =========================================================================
    // CLOCK AND RESET
    // =========================================================================
    reg aclk;
    reg aresetn;

    // =========================================================================
    // AXI-LITE WRITE CHANNEL
    // =========================================================================
    reg  [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr;
    reg                           s_axi_awvalid;
    wire                          s_axi_awready;

    reg  [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata;
    reg  [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb;
    reg                           s_axi_wvalid;
    wire                          s_axi_wready;

    wire [1:0] s_axi_bresp;
    wire       s_axi_bvalid;
    reg        s_axi_bready;

    // =========================================================================
    // AXI-LITE READ CHANNEL
    // =========================================================================
    reg  [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr;
    reg                           s_axi_arvalid;
    wire                          s_axi_arready;

    wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata;
    wire [1:0]                    s_axi_rresp;
    wire                          s_axi_rvalid;
    reg                           s_axi_rready;

    // =========================================================================
    // AXI4-STREAM INPUT
    // =========================================================================
    reg                       s_axis_spike_tvalid;
    reg                       s_axis_spike_tdata;
    reg                       s_axis_spike_tlast;
    wire                      s_axis_spike_tready;

    reg                       s_axis_weight_tvalid;
    reg [WEIGHT_BUS_W-1:0]   s_axis_weight_tdata;
    wire                      s_axis_weight_tready;

    // =========================================================================
    // AXI4-STREAM OUTPUT
    // =========================================================================
    wire [PARALLEL_NEURONS-1:0] m_axis_spike_tdata;
    wire                        m_axis_spike_tvalid;
    wire                        m_axis_spike_tlast;
    reg                         m_axis_spike_tready;

    // =========================================================================
    // DUT INSTANTIATION
    // =========================================================================
    snn_axi_wrapper #(
        .PARALLEL_NEURONS(PARALLEL_NEURONS),
        .WEIGHT_W(WEIGHT_W),
        .HEADROOM_BITS(HEADROOM_BITS),
        .VMEM_W(VMEM_W),
        .MAX_CHUNKS(MAX_CHUNKS),
        .LEAK_FRAC_BITS(LEAK_FRAC_BITS),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) DUT (
        .s_axi_aclk(aclk),
        .s_axi_aresetn(aresetn),

        // AXI-Lite Write Address Channel
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awprot(3'b000),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),

        // AXI-Lite Write Data Channel
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),

        // AXI-Lite Write Response Channel
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),

        // AXI-Lite Read Address Channel
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arprot(3'b000),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),

        // AXI-Lite Read Data Channel
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),

        // AXI4-Stream Spike Input
        .s_axis_spike_tvalid(s_axis_spike_tvalid),
        .s_axis_spike_tdata(s_axis_spike_tdata),
        .s_axis_spike_tlast(s_axis_spike_tlast),
        .s_axis_spike_tready(s_axis_spike_tready),

        // AXI4-Stream Weight Input
        .s_axis_weight_tvalid(s_axis_weight_tvalid),
        .s_axis_weight_tdata(s_axis_weight_tdata),
        .s_axis_weight_tready(s_axis_weight_tready),

        // AXI4-Stream Spike Output
        .m_axis_spike_tdata(m_axis_spike_tdata),
        .m_axis_spike_tvalid(m_axis_spike_tvalid),
        .m_axis_spike_tlast(m_axis_spike_tlast),
        .m_axis_spike_tready(m_axis_spike_tready)
    );

    // =========================================================================
    // CLOCK GENERATOR
    // 100 MHz clock, 10 ns period.
    // =========================================================================
    initial begin
        aclk = 1'b0;
        forever #5 aclk = ~aclk;
    end

    // =========================================================================
    // AXI-LITE WRITE TASK
    //
    // Equivalent to a software register write such as:
    //     ip.write(addr, data)
    // =========================================================================
    task axi_write(
        input [C_S_AXI_ADDR_WIDTH-1:0] addr,
        input [31:0] data
    );
        begin
            @(posedge aclk);

            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;

            s_axi_wdata   <= data;
            s_axi_wstrb   <= 4'hF;
            s_axi_wvalid  <= 1'b1;

            s_axi_bready  <= 1'b1;

            // Wait until both address and data channels are accepted.
            wait(s_axi_awready && s_axi_wready);

            @(posedge aclk);

            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;

            // Wait for the write response.
            wait(s_axi_bvalid);

            @(posedge aclk);

            s_axi_bready <= 1'b0;

            $display(
                "[%0t] AXI-Lite WRITE -> Addr: 0x%0h | Data: %0d",
                $time,
                addr,
                data
            );
        end
    endtask

    // =========================================================================
    // AXI-LITE READ TASK
    //
    // Equivalent to a software register read such as:
    //     ip.read(addr)
    // =========================================================================
    task axi_read(
        input  [C_S_AXI_ADDR_WIDTH-1:0] addr,
        output [31:0] read_data
    );
        begin
            @(posedge aclk);

            s_axi_araddr  <= addr;
            s_axi_arvalid <= 1'b1;
            s_axi_rready  <= 1'b1;

            // Wait until the read address is accepted.
            wait(s_axi_arready);

            @(posedge aclk);

            s_axi_arvalid <= 1'b0;

            // Wait for the read response.
            wait(s_axi_rvalid);

            read_data = s_axi_rdata;

            @(posedge aclk);

            s_axi_rready <= 1'b0;

            $display(
                "[%0t] AXI-Lite READ  <- Addr: 0x%0h | Data: %0d",
                $time,
                addr,
                read_data
            );
        end
    endtask

    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================
    reg [31:0] readback_val;

    integer chunk_id;
    integer cycle;

    initial begin

        // ---------------------------------------------------------------------
        // INITIALIZATION
        // ---------------------------------------------------------------------
        aresetn = 1'b0;

        s_axi_awaddr  = 0;
        s_axi_awvalid = 1'b0;
        s_axi_wdata   = 0;
        s_axi_wstrb   = 0;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b0;

        s_axi_araddr  = 0;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b0;

        s_axis_spike_tvalid  = 1'b0;
        s_axis_spike_tdata   = 1'b0;
        s_axis_spike_tlast   = 1'b0;

        s_axis_weight_tvalid = 1'b0;
        s_axis_weight_tdata  = 0;

        // Always accept output stream data.
        m_axis_spike_tready = 1'b1;

        readback_val = 0;
        chunk_id     = 0;
        cycle        = 0;

        // ---------------------------------------------------------------------
        // RELEASE RESET
        // ---------------------------------------------------------------------
        #50;
        aresetn = 1'b1;
        #50;

        // =====================================================================
        // PHASE 1: AXI-LITE CONFIGURATION
        // =====================================================================
        $display("\n=======================================================");
        $display("[%0t] PHASE 1: AXI-LITE PARAMETER CONFIGURATION", $time);
        $display("=======================================================");

        // Register map:
        //   0x00 : Control
        //   0x04 : Threshold
        //   0x08 : Leak Factor
        //   0x0C : Maximum Chunk Address

        axi_write(5'h04, 32'd1000);
        axi_write(5'h08, 32'd29491);
        axi_write(5'h0C, 32'd1);

        // ---------------------------------------------------------------------
        // Verify threshold register.
        // ---------------------------------------------------------------------
        axi_read(5'h04, readback_val);

        if (readback_val !== 32'd1000) begin
            $display(
                "[ERROR] Threshold register readback failed. Expected: 1000, Got: %0d",
                readback_val
            );
        end
        else begin
            $display("[PASS] Threshold register readback verified.");
        end

        // ---------------------------------------------------------------------
        // Verify maximum chunk register.
        // ---------------------------------------------------------------------
        axi_read(5'h0C, readback_val);

        if (readback_val !== 32'd1) begin
            $display(
                "[ERROR] Max-chunks register readback failed. Expected: 1, Got: %0d",
                readback_val
            );
        end
        else begin
            $display("[PASS] Max-chunks register readback verified.");
        end

        // =====================================================================
        // PHASE 2: TIMESTEP TRIGGER AND AUTO-CLEAR VALIDATION
        // =====================================================================
        $display("\n=======================================================");
        $display("[%0t] PHASE 2: TIMESTEP TRIGGER / AUTO-CLEAR", $time);
        $display("=======================================================");

        // Control register:
        //   Bit 0 = clear_vmem
        //   Bit 1 = trigger_new_timestep
        //
        // Write value 3:
        //   32'b...0011
        //
        // The trigger_new_timestep bit is expected to clear automatically
        // after being consumed by the wrapper.

        axi_write(5'h00, 32'd3);

        #20;

        axi_read(5'h00, readback_val);

        if (readback_val === 32'd1) begin
            $display(
                "[PASS] Auto-clear of trigger_new_timestep verified. Control register: %0d",
                readback_val
            );
        end
        else begin
            $display(
                "[ERROR] Auto-clear failed. Control register: %0d",
                readback_val
            );
        end

        // =====================================================================
        // PHASE 3: AXI4-STREAM DATA INJECTION
        // =====================================================================
        $display("\n=======================================================");
        $display("[%0t] PHASE 3: AXI4-STREAM DATA INJECTION", $time);
        $display("=======================================================");

        // Max Chunks = 1 means that two chunks are processed:
        //   Chunk 0
        //   Chunk 1
        //
        // Each chunk contains four spike/weight transactions.

        for (chunk_id = 0; chunk_id <= 1; chunk_id = chunk_id + 1) begin

            $display(
                "[%0t] Injecting AXI4-Stream Chunk %0d",
                $time,
                chunk_id
            );

            for (cycle = 0; cycle < 4; cycle = cycle + 1) begin

                @(posedge aclk);

                s_axis_spike_tvalid <= 1'b1;
                s_axis_spike_tdata  <= 1'b1;

                // Assert TLAST on the final transaction of each chunk.
                s_axis_spike_tlast <= (cycle == 3) ? 1'b1 : 1'b0;

                s_axis_weight_tvalid <= 1'b1;
                s_axis_weight_tdata  <= {
                    16'd10,
                    16'd10,
                    16'd10,
                    16'd10
                };

            end
        end

        // ---------------------------------------------------------------------
        // Deassert input stream after all transactions have been injected.
        // ---------------------------------------------------------------------
        @(posedge aclk);

        s_axis_spike_tvalid  <= 1'b0;
        s_axis_weight_tvalid <= 1'b0;
        s_axis_spike_tlast   <= 1'b0;

        // Allow the DUT to drain and complete the output stream.
        #200;

        // =====================================================================
        // TEST COMPLETION
        // =====================================================================
        $display("\n=======================================================");
        $display("[%0t] SNN AXI WRAPPER TEST COMPLETED", $time);
        $display("=======================================================");

        $finish;
    end

    // =========================================================================
    // OUTPUT STREAM MONITOR
    // =========================================================================
    always @(posedge aclk) begin

        if (m_axis_spike_tvalid && m_axis_spike_tready) begin

            $display(
                "[%0t] AXI4-Stream OUTPUT | Data: 0x%0h | TLAST: %b",
                $time,
                m_axis_spike_tdata,
                m_axis_spike_tlast
            );

        end

    end

endmodule
