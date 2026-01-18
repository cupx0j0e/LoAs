`timescale 1ns/1ps
`default_nettype none

// ============================================================
// MODULE 8: WINDOW MANAGER
// ============================================================
module window_manager #(
    parameter T = 4
)(
    input  wire clk,
    input  wire rst_n,
    input  wire fiber_valid,
    output reg  window_start,
    output reg  window_end,
    output reg  [$clog2(T+1)-1:0] window_count
);
    reg [$clog2(T+1)-1:0] fiber_cnt;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fiber_cnt <= 0;
            window_start <= 0;
            window_end <= 0;
            window_count <= 0;
        end else begin
            window_start <= 0;
            window_end <= 0;
            
            if (fiber_valid) begin
                if (fiber_cnt == 0) begin
                    window_start <= 1;
                end
                
                fiber_cnt <= fiber_cnt + 1;
                
                if (fiber_cnt == T - 1) begin
                    window_end <= 1;
                    fiber_cnt <= 0;
                    window_count <= window_count + 1;
                end
            end
        end
    end
endmodule

`default_nettype wire
