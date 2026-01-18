`timescale 1ns/1ps
`default_nettype none

// ============================================================
// MODULE 7: FIBERCACHE
// ============================================================
module fibercache #(
    parameter ADDR_W = 8,
    parameter DATA_W = 16,
    parameter NUM_FIBERS = 16,
    parameter FIBER_SIZE = 8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire req_valid,
    output reg  req_ready,
    input  wire [ADDR_W-1:0] req_addr,
    output reg  resp_valid,
    input  wire resp_ready,
    output reg  [FIBER_SIZE-1:0] resp_bitmask,
    output reg  [FIBER_SIZE*DATA_W-1:0] resp_data_flat
);
    reg [FIBER_SIZE-1:0] fiber_bitmask [0:NUM_FIBERS-1];
    reg [DATA_W-1:0] fiber_data [0:NUM_FIBERS-1][0:FIBER_SIZE-1];
    
    integer i, j;
    initial begin
        for (i = 0; i < NUM_FIBERS; i = i + 1) begin
            case (i % 4)
                0: fiber_bitmask[i] = 8'b11111111;
                1: fiber_bitmask[i] = 8'b10101010;
                2: fiber_bitmask[i] = 8'b10001000;
                3: fiber_bitmask[i] = 8'b11110000;
            endcase
            
            for (j = 0; j < FIBER_SIZE; j = j + 1) begin
                fiber_data[i][j] = 16'd510 + (i * 10) + j;
            end
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_ready <= 1;
            resp_valid <= 0;
            resp_data_flat <= 0;
        end else begin
            resp_valid <= 0;
            req_ready <= 1;
            
            if (req_valid && req_ready) begin
                resp_bitmask <= fiber_bitmask[req_addr % NUM_FIBERS];
                for (j = 0; j < FIBER_SIZE; j = j + 1)
                    resp_data_flat[j*DATA_W +: DATA_W] <= fiber_data[req_addr % NUM_FIBERS][j];
                resp_valid <= 1;
                req_ready <= 0;
            end
            
            if (resp_valid && resp_ready)
                req_ready <= 1;
        end
    end
endmodule

`default_nettype wire
