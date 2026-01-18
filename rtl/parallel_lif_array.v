`timescale 1ns/1ps
`default_nettype none

// ============================================================
// MODULE 6: PARALLEL LIF
// ============================================================
module parallel_lif_array #(
    parameter T = 4,
    parameter VMEM_W = 16,
    parameter SCORE_W = 16,
    parameter LEAK_SHIFT = 4,
    parameter NUM_NEURONS = 4
)(
    input  wire clk,
    input  wire rst_n,
    input  wire score_valid,
    input  wire [1:0] neuron_id,
    input  wire [T*SCORE_W-1:0] score_in_flat,
    input  wire [VMEM_W-1:0] threshold,
    output reg  [T-1:0] spike_out,
    output reg  [1:0] spike_neuron_id,
    output reg  spike_out_valid
);
    reg [VMEM_W-1:0] vmem [0:NUM_NEURONS-1][0:T-1];
    reg [VMEM_W-1:0] vmem_with_input [0:T-1];
    reg [VMEM_W-1:0] leak [0:T-1];
    reg [VMEM_W-1:0] vmem_after_leak [0:T-1];
    
    integer t, n;
    
    always @(*) begin
        for (t = 0; t < T; t = t + 1) begin
            vmem_with_input[t] = vmem[neuron_id][t] + 
                                 (score_valid ? score_in_flat[t*SCORE_W +: SCORE_W] : {VMEM_W{1'b0}});
            leak[t] = vmem_with_input[t] >> LEAK_SHIFT;
            vmem_after_leak[t] = (vmem_with_input[t] > leak[t]) ? 
                                 (vmem_with_input[t] - leak[t]) : {VMEM_W{1'b0}};
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spike_out <= {T{1'b0}};
            spike_out_valid <= 1'b0;
            spike_neuron_id <= 2'b0;
            for (n = 0; n < NUM_NEURONS; n = n + 1) begin
                for (t = 0; t < T; t = t + 1) begin
                    vmem[n][t] <= {VMEM_W{1'b0}};
                end
            end
        end else begin
            spike_out <= {T{1'b0}};
            spike_out_valid <= 1'b0;
            
            if (score_valid) begin
                reg any_spike;
                any_spike = 1'b0;
                
                for (t = 0; t < T; t = t + 1) begin
                    if (vmem_after_leak[t] >= threshold) begin
                        spike_out[t] <= 1'b1;
                        vmem[neuron_id][t] <= {VMEM_W{1'b0}};
                        any_spike = 1'b1;
                    end else begin
                        vmem[neuron_id][t] <= vmem_after_leak[t];
                    end
                end
                
                spike_out_valid <= any_spike;
                if (any_spike) begin
                    spike_neuron_id <= neuron_id;
                end
            end
        end
    end
endmodule

`default_nettype wire
