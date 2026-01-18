`timescale 1ns/1ps
`default_nettype none

// ============================================================
// MODULE 4: FTP INNER-JOIN
// ============================================================
module inner_join_ftp #(
    parameter BITMASK_W = 8,
    parameter PTR_W = 8,
    parameter T = 4
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire [BITMASK_W-1:0] bm_a,
    input  wire [BITMASK_W-1:0] bm_b,
    output reg  match_valid,
    output reg  [PTR_W-1:0] offset_a,
    output reg  [PTR_W-1:0] offset_b,
    output reg  [PTR_W-1:0] match_pos,
    output reg  done
);
    wire [BITMASK_W*PTR_W-1:0] prefix_b_flat;
    prefix_sum_fast #(.WIDTH(BITMASK_W), .PTR_W(PTR_W)) u_fast (
        .bitmask(bm_b),
        .prefix_flat(prefix_b_flat)
    );
    
    wire [BITMASK_W*PTR_W-1:0] prefix_a_flat;
    wire prefix_a_ready;
    prefix_sum_laggy #(.WIDTH(BITMASK_W), .PTR_W(PTR_W), .NUM_ADDERS(4)) u_laggy (
        .clk(clk), .rst_n(rst_n),
        .start(start),
        .bitmask(bm_a),
        .prefix_flat(prefix_a_flat),
        .ready(prefix_a_ready)
    );
    
    reg [BITMASK_W-1:0] and_result;
    reg [PTR_W-1:0] fifo_match_pos [0:BITMASK_W-1];
    reg [PTR_W-1:0] fifo_offset_b [0:BITMASK_W-1];
    reg [2:0] fifo_wr, fifo_rd;
    reg [3:0] fifo_cnt;
    
    localparam S_IDLE = 0, S_SCAN = 1, S_WAIT = 2, S_EMIT = 3;
    reg [1:0] state;
    reg [PTR_W-1:0] scan_idx;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            match_valid <= 0;
            done <= 0;
            fifo_wr <= 0;
            fifo_rd <= 0;
            fifo_cnt <= 0;
            match_pos <= 0;
        end else begin
            match_valid <= 0;
            done <= 0;
            
            case (state)
                S_IDLE: if (start) begin
                    and_result <= bm_a & bm_b;
                    scan_idx <= 0;
                    fifo_wr <= 0;
                    fifo_rd <= 0;
                    fifo_cnt <= 0;
                    state <= S_SCAN;
                end
                
                S_SCAN: begin
                    if (scan_idx < BITMASK_W) begin
                        if (and_result[scan_idx]) begin
                            fifo_match_pos[fifo_wr] <= scan_idx;
                            fifo_offset_b[fifo_wr] <= prefix_b_flat[scan_idx*PTR_W +: PTR_W] > 0 ? 
                                                       prefix_b_flat[scan_idx*PTR_W +: PTR_W] - 1 : 0;
                            fifo_wr <= fifo_wr + 1;
                            fifo_cnt <= fifo_cnt + 1;
                        end
                        scan_idx <= scan_idx + 1;
                        if (scan_idx == BITMASK_W - 1)
                            state <= S_WAIT;
                    end
                end
                
                S_WAIT: begin
                    if (prefix_a_ready)
                        state <= S_EMIT;
                end
                
                S_EMIT: begin
                    if (fifo_cnt > 0) begin
                        match_valid <= 1;
                        match_pos <= fifo_match_pos[fifo_rd];
                        offset_a <= prefix_a_flat[fifo_match_pos[fifo_rd]*PTR_W +: PTR_W] > 0 ? 
                                    prefix_a_flat[fifo_match_pos[fifo_rd]*PTR_W +: PTR_W] - 1 : 0;
                        offset_b <= fifo_offset_b[fifo_rd];
                        fifo_rd <= fifo_rd + 1;
                        fifo_cnt <= fifo_cnt - 1;
                    end else begin
                        done <= 1;
                        state <= S_IDLE;
                    end
                end
            endcase
        end
    end
endmodule

`default_nettype wire
