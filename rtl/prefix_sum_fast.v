`timescale 1ns/1ps
`default_nettype none

// ============================================================
// MODULE 2: FAST PREFIX-SUM
// ============================================================
module prefix_sum_fast #(
    parameter WIDTH = 8,
    parameter PTR_W = 8
)(
    input  wire [WIDTH-1:0] bitmask,
    output wire [WIDTH*PTR_W-1:0] prefix_flat
);
    wire [PTR_W-1:0] prefix_wire [0:WIDTH-1];
    
    assign prefix_wire[0] = bitmask[0] ? 1 : 0;
    
    genvar i;
    generate
        for (i = 1; i < WIDTH; i = i + 1) begin : PREFIX_GEN
            assign prefix_wire[i] = prefix_wire[i-1] + (bitmask[i] ? 1 : 0);
        end
    endgenerate
    
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : FLATTEN
            assign prefix_flat[i*PTR_W +: PTR_W] = prefix_wire[i];
        end
    endgenerate
endmodule

`default_nettype wire
