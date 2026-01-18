`timescale 1ns/1ps
`default_nettype none

// ============================================================
// TESTBENCH
// ============================================================
module tb_loas_perfect;
    parameter N = 16;
    parameter T = 4;
    parameter NUM_NEURONS = 4;
    
    reg clk = 0;
    always #5 clk = ~clk;
    
    reg rst_n;
    reg spike_in_valid;
    reg [N-1:0] spike_in_vec;
    reg [15:0] neuron_threshold;
    
    wire spike_out_valid;
    wire [1:0] spike_out_neuron_id;
    wire [1:0] spike_out_timestep;
    wire [31:0] cycle_count;
    wire [31:0] total_spikes;
    wire [31:0] window_count;
    
    loas_paper_perfect #(.N(N), .T(T), .NUM_NEURONS(NUM_NEURONS)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .spike_in_valid(spike_in_valid),
        .spike_in_vec(spike_in_vec),
        .neuron_threshold(neuron_threshold),
        .spike_out_valid(spike_out_valid),
        .spike_out_neuron_id(spike_out_neuron_id),
        .spike_out_timestep(spike_out_timestep),
        .cycle_count(cycle_count),
        .total_spikes(total_spikes),
        .window_count(window_count)
    );
    
    integer window_spikes [0:15];
    integer neuron_spikes [0:NUM_NEURONS-1];
    integer timestep_spikes [0:T-1];
    integer i;
    
    initial begin
        for (i = 0; i < 16; i = i + 1)
            window_spikes[i] = 0;
        for (i = 0; i < NUM_NEURONS; i = i + 1)
            neuron_spikes[i] = 0;
        for (i = 0; i < T; i = i + 1)
            timestep_spikes[i] = 0;
    end
    
    always @(posedge clk) begin
        if (spike_in_valid)
            $display("[C=%0d]  SPIKE_IN: vec=%b", cycle_count, spike_in_vec);
        
        if (dut.fiber_valid)
            $display("[C=%0d]  FIBER: mask=%b active=%0d", 
                     cycle_count, dut.fiber_bitmask, $countones(dut.fiber_bitmask));
        
        if (dut.window_start)
            $display("[C=%0d]  WINDOW_START: win#=%0d", cycle_count, window_count);
        
        if (dut.cache_valid)
            $display("[C=%0d]   CACHE: addr=%0d bm=%b", 
                     cycle_count, dut.cache_addr, dut.cache_bitmask);
        
        if (dut.u_join.state == 1)
            $display("[C=%0d]  IJ_SCAN: idx=%0d", cycle_count, dut.u_join.scan_idx);
        
        if (dut.ij_match)
            $display("[C=%0d]  MATCH: neuron=%0d pos=%0d", 
                     cycle_count, dut.current_neuron, dut.ij_match_pos);
        
        if (dut.window_end)
            $display("[C=%0d]   WINDOW_END: neuron=%0d", cycle_count, dut.current_neuron);
        
       if (|dut.tppe_valid) begin
    $display("[C=%0d]  TPPE_OUT: neuron=%0d scores=[%0d,%0d,%0d,%0d]", 
             cycle_count, dut.current_neuron,
             dut.tppe_scores_flat[dut.current_neuron][0*16 +: 16],
             dut.tppe_scores_flat[dut.current_neuron][1*16 +: 16],
             dut.tppe_scores_flat[dut.current_neuron][2*16 +: 16],
             dut.tppe_scores_flat[dut.current_neuron][3*16 +: 16]);
    
    // CRITICAL DEBUG
    $display("[C=%0d]  LIF_DEBUG: lif_input_valid=%0d lif_neuron_sel=%0d", 
             cycle_count, dut.lif_input_valid, dut.lif_neuron_sel);
    $display("[C=%0d]  LIF_VMEM_BEFORE: [%0d,%0d,%0d,%0d]", 
             cycle_count,
             dut.u_lif.vmem[dut.lif_neuron_sel][0],
             dut.u_lif.vmem[dut.lif_neuron_sel][1],
             dut.u_lif.vmem[dut.lif_neuron_sel][2],
             dut.u_lif.vmem[dut.lif_neuron_sel][3]);
    $display("[C=%0d]  LIF_INPUT_SCORES: [%0d,%0d,%0d,%0d]", 
             cycle_count,
             dut.tppe_scores_flat[dut.lif_neuron_sel][0*16 +: 16],
             dut.tppe_scores_flat[dut.lif_neuron_sel][1*16 +: 16],
             dut.tppe_scores_flat[dut.lif_neuron_sel][2*16 +: 16],
             dut.tppe_scores_flat[dut.lif_neuron_sel][3*16 +: 16]);
    $display("[C=%0d]  LIF_THRESHOLD: %0d", cycle_count, neuron_threshold);
end
        
        if (dut.lif_spike_valid) begin
            $display("[C=%0d]  LIF_FIRE: neuron=%0d spikes=%b vmem=[%0d,%0d,%0d,%0d]", 
                     cycle_count, dut.lif_neuron_id, dut.lif_spikes,
                     dut.u_lif.vmem[dut.lif_neuron_id][0],
                     dut.u_lif.vmem[dut.lif_neuron_id][1],
                     dut.u_lif.vmem[dut.lif_neuron_id][2],
                     dut.u_lif.vmem[dut.lif_neuron_id][3]);
        end
        if (cycle_count == 127) begin
    $display("[C=%0d]  POST-LIF_VMEM: [%0d,%0d,%0d,%0d]", 
             cycle_count,
             dut.u_lif.vmem[0][0],
             dut.u_lif.vmem[0][1],
             dut.u_lif.vmem[0][2],
             dut.u_lif.vmem[0][3]);
    $display("[C=%0d]  POST-LIF spike_out=%b spike_out_valid=%0d", 
             cycle_count,
             dut.u_lif.spike_out,
             dut.u_lif.spike_out_valid);
end
        if (spike_out_valid) begin
            $display("[C=%0d]  OUTPUT: neuron=%0d timestep=%0d", 
                     cycle_count, spike_out_neuron_id, spike_out_timestep);
            if (window_count < 16)
                window_spikes[window_count] = window_spikes[window_count] + 1;
            neuron_spikes[spike_out_neuron_id] = neuron_spikes[spike_out_neuron_id] + 1;
            timestep_spikes[spike_out_timestep] = timestep_spikes[spike_out_timestep] + 1;
        end
    end
    
    task run_test;
        input [255:0] name;
        input [N-1:0] pattern;
        input integer iterations;
        integer j;
    begin
        $display("\n TEST: %0s (pattern=%b)", name, pattern);
        repeat(iterations) begin
            repeat(T) begin
                @(posedge clk);
                spike_in_valid = 1;
                spike_in_vec = pattern;
            end
            @(posedge clk);
            spike_in_valid = 0;
            repeat(30) @(posedge clk);
        end
    end
    endtask
    
    initial begin
        $dumpfile("loas_perfect.vcd");
        $dumpvars(0, tb_loas_perfect);
        
        $display("\n╔════════════════════════════════════════════════════╗");
        $display("║            LoAS COMPLETE IMPLEMENTATION            ║");
        $display("╚════════════════════════════════════════════════════╝\n");
        
        rst_n = 0;
        spike_in_valid = 0;
        spike_in_vec = 0;
        neuron_threshold = 16'd1500;  // Lower threshold for more spikes
        
        repeat(5) @(posedge clk);
        rst_n = 1;
        $display("[%0t]  Reset complete\n", $time);
        repeat(3) @(posedge clk);
        
        run_test("Dense Pattern", 16'b0000_1111_0000_1111, 5);
        run_test("Medium Pattern", 16'b1010_0101_1010_0101, 5);
        run_test("Sparse Pattern", 16'b0001_0001_0001_0001, 5);
        run_test("Max Density", 16'hFFFF, 4);
        run_test("Clustered", 16'b1111_0000_1111_0000, 4);
        
        repeat(100) @(posedge clk);
        
        $display("\n╔══════════════════════════════════════════════════╗");
        $display("║              FINAL RESULTS                       ║");
        $display("╠══════════════════════════════════════════════════╣");
        $display("║ Total Cycles:           %10d               ║", cycle_count);
        $display("║ Output Spikes:          %10d               ║", total_spikes);
        $display("║ Windows Processed:      %10d               ║", window_count);
        $display("║ Avg Spikes/Window:      %10.2f               ║", 
                 total_spikes * 1.0 / (window_count > 0 ? window_count : 1));
        $display("║ Throughput:          %10.2f sp/Kcyc          ║", 
                 (total_spikes * 1000.0) / cycle_count);
        $display("╠══════════════════════════════════════════════════╣");
        
        $display("║ SPIKE DISTRIBUTION BY NEURON:                    ║");
        for (i = 0; i < NUM_NEURONS; i = i + 1)
        	$display("║   Neuron %0d:             %10d spikes        ║", i, neuron_spikes[i]);
        
        $display("╠══════════════════════════════════════════════════╣");
        $display("║ SPIKE DISTRIBUTION BY TIMESTEP:                  ║");
        for (i = 0; i < T; i = i + 1)
        	$display("║   Timestep %0d:           %10d spikes        ║", i, timestep_spikes[i]);
        
        $display("╠══════════════════════════════════════════════════╣");
        $display("║                  FEATURES                        ║");
        $display("╠══════════════════════════════════════════════════╣");
        $display("║  FTP Spike Compression                           ║");
        $display("║  Silent Neuron Filtering (≤1 spike)              ║");
        $display("║  Fast Prefix-Sum (1-cycle)                       ║");
        $display("║  Laggy Prefix-Sum                                ║");
        $display("║  Pseudo Accumulator                              ║");
        $display("║  Correction Accumulators                         ║");
        $display("║  FIFO-based Match Buffering                      ║");
        $display("║  Parallel LIF (FTP dataflow)                     ║");
        $display("║  Realistic FiberCache (4 patterns)               ║");
        $display("║  Window Manager (T-based boundaries)             ║");
        $display("║  Multi-Neuron Support (%0d neurons)                ║", NUM_NEURONS);
        $display("║  Output Router (neuron + timestep)               ║");
        $display("╚══════════════════════════════════════════════════╝\n");
        
        if (total_spikes > NUM_NEURONS * 2)
            $display(" PASS: %0d spikes across %0d neurons", total_spikes, NUM_NEURONS);
        else
            $display("  WARNING: Only %0d spikes", total_spikes);
        
        
        $finish;
    end
    
    initial begin
        #200000;
        $display("\n TIMEOUT");
        $finish;
    end
    
endmodule

`default_nettype wire
