`timescale 1ns/1ps
`default_nettype none

// ============================================================
// MODULE 5: TPPE WITH PSEUDO + CORRECTION
// ============================================================
module tppe_ftp #(
    parameter T = 4,
    parameter DATA_W = 16,
    parameter SCORE_W = 16,
    parameter BITMASK_W = 8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire window_start,
    input  wire window_end,
    input  wire match_valid,
    input  wire [DATA_W-1:0] weight_data,
    input  wire [BITMASK_W*T-1:0] spike_fiber,
    input  wire [BITMASK_W-1:0] spike_bitmask,
    input  wire [$clog2(BITMASK_W)-1:0] match_pos,
    output reg  score_valid,
    output reg  [T*SCORE_W-1:0] score_out_flat
);
    reg [SCORE_W-1:0] pseudo_acc;
    reg [SCORE_W-1:0] correction_acc [0:T-1];
    reg [SCORE_W-1:0] score_arr [0:T-1];
    
    integer t;
    wire [T-1:0] actual_spikes;
    
    assign actual_spikes = spike_bitmask[match_pos] ? 
                           spike_fiber[match_pos*T +: T] : {T{1'b0}};
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pseudo_acc <= 0;
            score_valid <= 0;
            score_out_flat <= 0;
            for (t = 0; t < T; t = t + 1) begin
                correction_acc[t] <= 0;
                score_arr[t] <= 0;
            end
        end else begin
            score_valid <= 0;
            
            if (window_start) begin
                pseudo_acc <= 0;
                for (t = 0; t < T; t = t + 1)
                    correction_acc[t] <= 0;
            end
            
            if (match_valid) begin
                pseudo_acc <= pseudo_acc + weight_data;
                
                for (t = 0; t < T; t = t + 1) begin
                    if (!actual_spikes[t]) begin
                        correction_acc[t] <= correction_acc[t] + weight_data;
                    end
                end
            end
            
            if (window_end) begin
                for (t = 0; t < T; t = t + 1) begin
                    score_arr[t] <= pseudo_acc - correction_acc[t];
                    score_out_flat[t*SCORE_W +: SCORE_W] <= pseudo_acc - correction_acc[t];
                end
                score_valid <= 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
