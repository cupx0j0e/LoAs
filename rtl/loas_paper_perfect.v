`timescale 1ns/1ps
`default_nettype none

// ============================================================
// MODULE 10: LOAS TOP-LEVEL
// ============================================================


module loas_paper_perfect #(
    parameter N = 16,
    parameter T = 4,
    parameter NUM_NEURONS = 4
)(
    input  wire clk,
    input  wire rst_n,
    input  wire spike_in_valid,
    input  wire [N-1:0] spike_in_vec,
    input  wire [15:0] neuron_threshold,
    output wire spike_out_valid,
    output wire [1:0] spike_out_neuron_id,
    output wire [1:0] spike_out_timestep,
    output wire [31:0] cycle_count,
    output wire [31:0] total_spikes,
    output wire [31:0] window_count
);
    localparam SCORE_W = 16;
    
    reg [31:0] cycles, spikes;
    assign cycle_count = cycles;
    assign total_spikes = spikes;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycles <= 0;
            spikes <= 0;
        end else begin
            cycles <= cycles + 1;
            if (spike_out_valid)
                spikes <= spikes + 1;
        end
    end
    
    wire [N-1:0] fiber_bitmask;
    wire [N*T-1:0] fiber_packed;
    wire fiber_valid, fiber_ready;
    
    spike_compressor_ftp #(.N(N), .T(T), .SILENCE_THRESH(1)) u_compress (
        .clk(clk), .rst_n(rst_n),
        .spike_vec(spike_in_vec),
        .spike_valid(spike_in_valid),
        .fiber_bitmask(fiber_bitmask),
        .fiber_packed_data(fiber_packed),
        .fiber_valid(fiber_valid),
        .fiber_ready(fiber_ready)
    );
    assign fiber_ready = 1'b1;
    
    wire window_start, window_end;
    wire [2:0] win_cnt;
    
    window_manager #(.T(T)) u_winmgr (
        .clk(clk), .rst_n(rst_n),
        .fiber_valid(fiber_valid),
        .window_start(window_start),
        .window_end(window_end),
        .window_count(win_cnt)
    );
    assign window_count = {29'b0, win_cnt};
    
    reg [1:0] current_neuron;
    reg [1:0] neuron_counter;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_neuron <= 0;
            neuron_counter <= 0;
        end else begin
          
            if (window_start) begin
                current_neuron <= neuron_counter;
                neuron_counter <= (neuron_counter == NUM_NEURONS - 1) ? 0 : neuron_counter + 1;
            end
        end
    end
    
    reg [7:0] cache_addr;
    wire cache_valid, cache_ready;
    wire [7:0] cache_bitmask;
    wire [8*16-1:0] cache_data_flat;
    
    fibercache #(.ADDR_W(8), .DATA_W(16), .NUM_FIBERS(16), .FIBER_SIZE(8)) u_cache (
        .clk(clk), .rst_n(rst_n),
        .req_valid(fiber_valid),
        .req_ready(),
        .req_addr(cache_addr),
        .resp_valid(cache_valid),
        .resp_ready(cache_ready),
        .resp_bitmask(cache_bitmask),
        .resp_data_flat(cache_data_flat)
    );
    assign cache_ready = 1'b1;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cache_addr <= 0;
        else if (fiber_valid)
            cache_addr <= cache_addr + 1;
    end
    
    wire ij_match, ij_done;
    wire [7:0] ij_off_a, ij_off_b;
    wire [7:0] ij_match_pos;
    
    inner_join_ftp #(.BITMASK_W(8), .PTR_W(8), .T(T)) u_join (
        .clk(clk), .rst_n(rst_n),
        .start(cache_valid),
        .bm_a(fiber_bitmask[7:0]),
        .bm_b(cache_bitmask),
        .match_valid(ij_match),
        .offset_a(ij_off_a),
        .offset_b(ij_off_b),
        .match_pos(ij_match_pos),
        .done(ij_done)
    );
    
    reg window_end_pending;
    reg [1:0] pending_neuron;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            window_end_pending <= 0;
            pending_neuron <= 0;
        end else begin
            if (window_end && !ij_done) begin
                // Window ended but inner join still processing - latch it
                window_end_pending <= 1;
                pending_neuron <= current_neuron;
            end else if (window_end_pending && ij_done) begin
                // Inner join done - can clear the pending flag
                window_end_pending <= 0;
            end
        end
    end
    
    wire actual_window_end;
    wire [1:0] actual_neuron;
    
    assign actual_window_end = window_end_pending ? ij_done : (window_end && ij_done);
    assign actual_neuron = window_end_pending ? pending_neuron : current_neuron;
    
    wire [NUM_NEURONS-1:0] neuron_window_start;
    wire [NUM_NEURONS-1:0] neuron_window_end;
    wire [NUM_NEURONS-1:0] neuron_match_valid;
    
    genvar nid;
    generate
        for (nid = 0; nid < NUM_NEURONS; nid = nid + 1) begin : NEURON_SIGNALS
            assign neuron_window_start[nid] = window_start && (current_neuron == nid);
            assign neuron_window_end[nid] = actual_window_end && (actual_neuron == nid);
            assign neuron_match_valid[nid] = ij_match && (current_neuron == nid);
        end
    endgenerate
    
    wire [T*SCORE_W-1:0] tppe_scores_flat [0:NUM_NEURONS-1];
    wire [NUM_NEURONS-1:0] tppe_valid;
    
    generate
        for (nid = 0; nid < NUM_NEURONS; nid = nid + 1) begin : TPPE_ARRAY
            tppe_ftp #(.T(T), .DATA_W(16), .SCORE_W(SCORE_W), .BITMASK_W(8)) u_tppe (
                .clk(clk), .rst_n(rst_n),
                .window_start(neuron_window_start[nid]),
                .window_end(neuron_window_end[nid]),
                .match_valid(neuron_match_valid[nid]),
                .weight_data(cache_data_flat[ij_off_b*16 +: 16]),
                .spike_fiber(fiber_packed[8*T-1:0]),
                .spike_bitmask(fiber_bitmask[7:0]),
                .match_pos(ij_match_pos[2:0]),
                .score_valid(tppe_valid[nid]),
                .score_out_flat(tppe_scores_flat[nid])
            );
        end
    endgenerate
    
    wire [1:0] lif_neuron_sel;
    wire lif_input_valid;
    
    assign lif_input_valid = |tppe_valid;
    assign lif_neuron_sel = tppe_valid[0] ? 2'd0 :
                            tppe_valid[1] ? 2'd1 :
                            tppe_valid[2] ? 2'd2 :
                            2'd3;
    
    wire [T-1:0] lif_spikes;
    wire [1:0] lif_neuron_id;
    wire lif_spike_valid;
    
    parallel_lif_array #(
        .T(T), 
        .VMEM_W(16), 
        .SCORE_W(SCORE_W),
        .NUM_NEURONS(NUM_NEURONS)
    ) u_lif (
        .clk(clk), .rst_n(rst_n),
        .score_valid(lif_input_valid),
        .neuron_id(lif_neuron_sel),
        .score_in_flat(tppe_scores_flat[lif_neuron_sel]),
        .threshold(neuron_threshold),
        .spike_out(lif_spikes),
        .spike_neuron_id(lif_neuron_id),
        .spike_out_valid(lif_spike_valid)
    );
    
    output_router #(.T(T), .NUM_NEURONS(NUM_NEURONS)) u_router (
        .clk(clk), .rst_n(rst_n),
        .spike_in_valid(lif_spike_valid),
        .spike_neuron_id(lif_neuron_id),
        .spike_in(lif_spikes),
        .spike_out_valid(spike_out_valid),
        .spike_out_neuron_id(spike_out_neuron_id),
        .spike_out_timestep(spike_out_timestep)
    );
    
endmodule

`default_nettype wire
