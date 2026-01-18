`timescale 1ns/1ps
`default_nettype none

// ============================================================
// MODULE 1: FTP-FRIENDLY SPIKE COMPRESSION
// ============================================================
module spike_compressor_ftp #(
    parameter N = 16,
    parameter T = 4,
    parameter SILENCE_THRESH = 1
)(
    input  wire clk,
    input  wire rst_n,
    input  wire [N-1:0] spike_vec,
    input  wire spike_valid,
    output reg  [N-1:0] fiber_bitmask,
    output reg  [N*T-1:0] fiber_packed_data,
    output reg  fiber_valid,
    input  wire fiber_ready
);
    reg [T-1:0] spike_history [0:N-1];
    reg [$clog2(T+1)-1:0] t_cnt;
    reg [$clog2(T+2)-1:0] spike_count [0:N-1];
    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fiber_valid <= 0;
            fiber_bitmask <= 0;
            fiber_packed_data <= 0;
            t_cnt <= 0;
            for (i = 0; i < N; i = i + 1) begin
                spike_history[i] <= 0;
                spike_count[i] <= 0;
            end
        end else begin
            fiber_valid <= 0;
            
            if (spike_valid && (!fiber_valid || fiber_ready)) begin
                for (i = 0; i < N; i = i + 1) begin
                    spike_history[i][t_cnt] <= spike_vec[i];
                    if (spike_vec[i])
                        spike_count[i] <= spike_count[i] + 1;
                end
                
                if (t_cnt == T-1) begin
                    fiber_bitmask <= 0;
                    for (i = 0; i < N; i = i + 1) begin
                        if (spike_count[i] > SILENCE_THRESH) begin
                            fiber_bitmask[i] <= 1'b1;
                            fiber_packed_data[i*T +: T] <= spike_history[i];
                        end else begin
                            fiber_bitmask[i] <= 1'b0;
                            fiber_packed_data[i*T +: T] <= 0;
                        end
                    end
                    fiber_valid <= 1'b1;
                    t_cnt <= 0;
                    
                    for (i = 0; i < N; i = i + 1) begin
                        spike_history[i] <= 0;
                        spike_count[i] <= 0;
                    end
                end else begin
                    t_cnt <= t_cnt + 1;
                end
            end
        end
    end
endmodule

`default_nettype wire
