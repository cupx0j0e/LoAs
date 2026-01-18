`timescale 1ns/1ps
`default_nettype none

// ============================================================
// MODULE 3: LAGGY PREFIX-SUM
// ============================================================
module prefix_sum_laggy #(
    parameter WIDTH = 8,
    parameter PTR_W = 8,
    parameter NUM_ADDERS = 4
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire [WIDTH-1:0] bitmask,
    output reg  [WIDTH*PTR_W-1:0] prefix_flat,
    output reg  ready
);
    localparam CYCLES = (WIDTH + NUM_ADDERS - 1) / NUM_ADDERS;
    reg [$clog2(CYCLES+2)-1:0] cycle_cnt;
    reg [WIDTH-1:0] bm_captured;
    reg [PTR_W-1:0] prefix_arr [0:WIDTH-1];
    integer j;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready <= 0;
            cycle_cnt <= 0;
            prefix_flat <= 0;
            for (j = 0; j < WIDTH; j = j + 1)
                prefix_arr[j] <= 0;
        end else begin
            if (start) begin
                bm_captured <= bitmask;
                cycle_cnt <= 1;
                ready <= 0;
                prefix_arr[0] <= bitmask[0] ? 1 : 0;
            end else if (cycle_cnt > 0 && cycle_cnt <= CYCLES) begin
                for (j = (cycle_cnt-1)*NUM_ADDERS + 1; 
                     j < cycle_cnt*NUM_ADDERS + 1 && j < WIDTH; 
                     j = j + 1) begin
                    prefix_arr[j] <= prefix_arr[j-1] + (bm_captured[j] ? 1 : 0);
                end
                if (cycle_cnt == CYCLES) begin
                    ready <= 1;
                    for (j = 0; j < WIDTH; j = j + 1)
                        prefix_flat[j*PTR_W +: PTR_W] <= prefix_arr[j];
                end
                cycle_cnt <= cycle_cnt + 1;
            end
        end
    end
endmodule

`default_nettype wire
