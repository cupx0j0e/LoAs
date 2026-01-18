`timescale 1ns/1ps
`default_nettype none

// ============================================================
// MODULE 9: OUTPUT ROUTER
// ============================================================
module output_router #(
    parameter T = 4,
    parameter NUM_NEURONS = 4
)(
    input  wire clk,
    input  wire rst_n,
    input  wire spike_in_valid,
    input  wire [1:0] spike_neuron_id,
    input  wire [T-1:0] spike_in,
    output reg  spike_out_valid,
    output reg  [1:0] spike_out_neuron_id,
    output reg  [$clog2(T)-1:0] spike_out_timestep
);
    reg [T-1:0] pending_spikes;
    reg [1:0] pending_neuron_id;
    reg [T-1:0] emit_mask;
    integer t;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spike_out_valid <= 0;
            spike_out_neuron_id <= 0;
            spike_out_timestep <= 0;
            pending_spikes <= 0;
            pending_neuron_id <= 0;
        end else begin
            spike_out_valid <= 0;
            
            if (spike_in_valid && spike_in != 0) begin
                pending_neuron_id <= spike_neuron_id;
                pending_spikes <= spike_in;
                emit_mask = 0;
                for (t = 0; t < T; t = t + 1) begin
                    if (spike_in[t] && emit_mask == 0) begin
                        spike_out_valid <= 1;
                        spike_out_neuron_id <= spike_neuron_id;
                        spike_out_timestep <= t;
                        emit_mask = (1 << t);
                    end
                end
                pending_spikes <= spike_in & ~emit_mask;
            end
            else if (pending_spikes != 0) begin
                emit_mask = 0;
                for (t = 0; t < T; t = t + 1) begin
                    if (pending_spikes[t] && emit_mask == 0) begin
                        spike_out_valid <= 1;
                        spike_out_neuron_id <= pending_neuron_id;
                        spike_out_timestep <= t;
                        emit_mask = (1 << t);
                    end
                end
                pending_spikes <= pending_spikes & ~emit_mask;
            end
        end
    end
endmodule

`default_nettype wire
