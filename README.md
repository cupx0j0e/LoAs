# LoAs: Low-latency Inference Accelerator for Dual-Sparse SNNs

> **RTL implementation** of the LoAS architecture from the MICRO 2024 paper:  
> *"LoAS: Fully Temporal-Parallel Dataflow for Dual-Sparse Spiking Neural Networks"*  
> Ruokai Yin, Youngeun Kim, Di Wu, Priyadarshini Panda | [arXiv:2407.14073](https://arxiv.org/abs/2407.14073)

---

## Table of Contents

1. [What is LoAS?](#what-is-loas)
2. [The Problem](#the-problem)
3. [Key Innovations](#key-innovations)
4. [System Architecture](#system-architecture)
5. [Dataflow](#dataflow)
6. [Spike Compression](#spike-compression)
7. [Inner-Join Circuit](#inner-join-circuit)
8. [SNN Layer Execution Flow](#snn-layer-execution-flow)
9. [Repository Structure](#repository-structure)
10. [Results](#results)
11. [Citation](#citation)

---

## What is LoAS?

**LoAS** (Low-latency inference Accelerator for dual-Sparse SNNs) is a hardware accelerator designed to efficiently run **dual-sparse Spiking Neural Networks (SNNs)**, networks where *both* the input spikes (binary activations) and the synaptic weights are sparse.

Its core contribution is the **Fully Temporal-Parallel (FTP) dataflow**, which parallelizes all timestep computations simultaneously, eliminating the sequential overhead that cripples conventional ANN sparse accelerators when applied to SNNs.

---

## The Problem

SNNs process data across multiple **timesteps**, a property that does not exist in regular ANNs. When you take an existing ANN dual-sparse accelerator (designed for spMspM: sparse-matrix x sparse-matrix multiplication) and naively run an SNN on it, you get:

```
ANN spMspM loop:
  for each row in A:
    for each row in B:
      inner-join + accumulate

SNN spMspM loop (naive):
  for each TIMESTEP:          ← extra loop added
    for each row in A[t]:
      for each row in B:
        inner-join + accumulate
```

This extra timestep loop causes two compounding problems:

| Problem | Cause | Effect |
|---|---|---|
| **Extra latency** | Timesteps processed sequentially | T× longer execution time |
| **Extra memory traffic** | Different spike tensors per timestep must be re-fetched | Repeated off-chip/on-chip data movement |
| **Dataflow complexity** | Timestep loop creates dependency across iterations | Harder to pipeline, larger design space |
| **Format mismatch** | CSR uses multi-bit coordinates for non-zeros, wasteful for 1-bit spikes | Poor compression efficiency |

---

## Key Innovations

LoAS introduces three tightly coupled innovations to solve the above:

```
┌──────────────────────────────────────────────────────┐
│                  LoAS Core Innovations                │
│                                                      │
│  1. FTP Dataflow       → Parallelize all timesteps   │
│  2. FTP Spike Compress → Efficient 1-bit compression │
│  3. FTP Inner-Join     → Low-cost coordinate match   │
└──────────────────────────────────────────────────────┘
```

### 1. Fully Temporal-Parallel (FTP) Dataflow
All `T` timesteps are processed **in parallel** rather than sequentially. Spikes across all timesteps for the same neuron are packed together and processed by a single **Temporal-Parallel Processing Element (TPPE)**, eliminating the inter-timestep data dependency and the associated latency penalty.

### 2. FTP-Friendly Spike Compression
Instead of CSR (which uses multi-bit coordinates per non-zero), spikes from all `T` timesteps are **packed together** into a compact bit-vector indexed by neuron coordinate. This ensures:
- Only one set of coordinates is stored per neuron (amortized across timesteps)
- Memory access for all timesteps is **contiguous**, enabling efficient cache line utilization

### 3. FTP-Friendly Inner-Join Circuit
The inner-join is the hardware mechanism that matches non-zero coordinates between the sparse spike matrix and sparse weight matrix. Conventional designs require expensive **prefix-sum circuits** to resolve coordinate intersections. LoAS proposes a modified inner-join that uses a **"laggy" prefix-sum**, accepting a minor and bounded throughput tradeoff in exchange for cutting prefix-sum area to just **8.3% of total area** and **11.4% of total power**, with nearly zero throughput penalty.

---

## System Architecture

```
                        ┌──────────────────────────────────────────┐
                        │             HBM (128 GB/s)               │
                        │  Sparse Spikes A  │  Sparse Weights B    │
                        └──────────┬────────┴──────────────────────┘
                                   │
                        ┌──────────▼────────────────────────────────┐
                        │           Global SRAM Cache               │
                        │  (dominates area + power in design)       │
                        └──────────┬────────────────────────────────┘
                                   │  broadcast row fiber of B
                     ┌─────────────▼──────────────────────────┐
                     │         LoAS Processing Array           │
                     │                                         │
                     │  ┌────────┐ ┌────────┐ ┌────────┐      │
                     │  │ TPPE 0 │ │ TPPE 1 │ │ TPPE N │ ...  │
                     │  └────────┘ └────────┘ └────────┘      │
                     │     │           │           │           │
                     │  ┌──▼───────────▼───────────▼────────┐ │
                     │  │     FTP Inner-Join Units           │ │
                     │  │  (laggy prefix-sum per TPPE)       │ │
                     │  └────────────────────────────────────┘ │
                     └───────────────┬─────────────────────────┘
                                     │
                        ┌────────────▼──────────────┐
                        │      LIF Neuron Units      │
                        │  (accumulate + fire + V_m) │
                        └────────────────────────────┘
```

**TPPEs (Temporal-Parallel Processing Elements)** are the core compute units. Each TPPE:
- Receives one compressed spike fiber (covering all `T` timesteps at once)
- Performs inner-join with the corresponding weight fiber
- Outputs partial sums for all `T` timesteps in parallel

A single **compressed row fiber of weight matrix B** is fetched once and **broadcast** to all TPPEs, maximizing data reuse.

---

## Dataflow

### FTP vs. Sequential Timestep Processing

```
Sequential (ANN spMspM adapted):               FTP (LoAS):

  t=0 ──► [TPPE] ──► accum                      ┌─────────────────────┐
  t=1 ──► [TPPE] ──► accum      vs.             │  t=0 ─┐             │
  t=2 ──► [TPPE] ──► accum                      │  t=1 ─┼─► [TPPE] ──►│ accum (all T)
  ...                                            │  t=2 ─┤             │
                                                 │  ... ─┘             │
  Latency = T × single_t_latency                └─────────────────────┘
  Mem traffic = T × per_timestep_fetch
                                                 Latency ≈ single_t_latency
                                                 Mem traffic = 1× fetch (amortized)
```

### Full Inference Loop (FTP Dataflow)

```
┌─────────────────────────────────────────────────────────────┐
│  For each SNN layer:                                        │
│                                                             │
│  1. LOAD  ─── Fetch compressed spike fiber A[m, :, 0..T]   │
│               from HBM into global SRAM                    │
│                                                             │
│  2. FETCH ─── Load one row fiber of B[:, n] (broadcast)    │
│                                                             │
│  3. INNER-JOIN ── Match non-zero coordinates               │
│                   across A and B using FTP inner-join       │
│                                                             │
│  4. ACCUMULATE ── Sum products into partial output O[m,n,t] │
│                   for all T simultaneously per TPPE         │
│                                                             │
│  5. LIF   ─── Pass O through Leaky-Integrate-and-Fire      │
│               neurons to generate output spikes for t+1     │
│                                                             │
│  6. REPEAT ── Tile across all M rows and N columns          │
└─────────────────────────────────────────────────────────────┘
```

---

## Spike Compression

The FTP-friendly spike compression format stores the binary spikes across all timesteps as a **packed bit-vector** indexed by neuron coordinate, rather than one coordinate entry per non-zero spike per timestep (as CSR would require).

```
CSR per timestep (conventional):         FTP Spike Compression:

  t=0: [(coord=2, val=1),                  Neuron 2: [1, 0, 1, 1]  ← T=4 bits
         (coord=5, val=1), ...]             Neuron 5: [1, 1, 0, 0]
  t=1: [(coord=2, val=1),                  Neuron 7: [0, 0, 0, 1]
         (coord=7, val=1), ...]
  ...                                     One coordinate entry per neuron,
                                          regardless of T.
  Cost: T × num_nonzeros × coord_bits     Contiguous memory layout → efficient
                                          cache line access across all timesteps.
```

This saves significant storage and ensures that fetching all timesteps' spike data for a neuron requires a **single contiguous memory read**.

---

## Inner-Join Circuit

The inner-join finds matching non-zero coordinates between a spike fiber and a weight fiber to identify which multiply-accumulate operations are needed.

```
  Spike fiber A:   coord = [2,  5,  9, 14]
  Weight fiber B:  coord = [1,  5,  9, 13, 14]

  Inner-join →     match = [5, 9, 14]   ← only these pairs produce non-zero output
```

Traditional inner-join circuits use a **prefix-sum tree** to resolve coordinate positions in parallel, which is expensive in both area and power. LoAS replaces this with a **"laggy" prefix-sum**: a simplified variant that accepts a small, bounded stall cycle rather than fully resolving all positions simultaneously. The result:

```
  Conventional inner-join:      LoAS FTP inner-join:

  Full prefix-sum tree          Laggy (simplified) prefix-sum
  High area overhead     vs.    8.3% of total chip area
  High power overhead           11.4% of total chip power
  High throughput               Nearly identical throughput
```

---

## SNN Layer Execution Flow

```
                  ┌────────────────────────────────────────┐
                  │             Input Layer t               │
                  │  A ∈ {0,1}^(M × K × T)  (binary spikes)│
                  └─────────────────┬──────────────────────┘
                                    │
                         ┌──────────▼──────────┐
                         │   FTP Compression   │
                         │  Pack spikes across │
                         │  T timesteps per    │
                         │  neuron coordinate  │
                         └──────────┬──────────┘
                                    │
              ┌─────────────────────▼──────────────────────┐
              │             spMspM (FTP dataflow)           │
              │                                            │
              │  For each TPPE in parallel:                │
              │    inner-join(A[m,:,0..T], B[:,n])         │
              │    → partial sums O[m,n,0..T]              │
              └─────────────────────┬──────────────────────┘
                                    │
                         ┌──────────▼──────────┐
                         │   LIF Neuron Model  │
                         │                     │
                         │  V_m[t+1] = decay × │
                         │  V_m[t] + O[m,n,t]  │
                         │  Fire if V_m > θ    │
                         └──────────┬──────────┘
                                    │
                  ┌─────────────────▼──────────────────────┐
                  │           Output Spikes                 │
                  │  A_next ∈ {0,1}^(M × N × T)            │
                  └────────────────────────────────────────┘
                              (fed into next layer)
```

---

## Repository Structure

```
LoAs/
├── rtl/                  # Verilog RTL source files
│   └── ...               # Hardware implementation of LoAS components
│                         # (TPPEs, inner-join units, compression logic)
└── README.md
```

The RTL implements the key components of the LoAS architecture. The original paper validates synthesis at **800 MHz in 32 nm technology**, connected to a **128 GB/s HBM** off-chip memory subsystem.

---

## Results

LoAS achieves significant improvements over prior dual-sparse SNN accelerators (SparTen-SNN, GoSPA-SNN, Gamma-SNN):

| Metric | vs. SparTen-SNN | vs. GoSPA-SNN | vs. Gamma-SNN |
|---|---|---|---|
| **Speedup** | up to **8.51×** | significant | up to **3.25×** |
| **Energy Reduction** | up to **3.68×** | significant | significant |

### Why LoAS wins

```
  FTP Dataflow       → eliminates sequential timestep latency penalty
  Spike Compression  → reduces off-chip memory traffic
  FTP Inner-Join     → low-cost coordinate matching with near-zero throughput loss
```

### Comparison with prior SNN accelerators

| Accelerator | Spike Sparsity | Weight Sparsity | Temporal Parallelism | Neuron Model |
|---|---|---|---|---|
| SpinalFlow | ✅ | ❌ | Spatial only | LIF |
| PTB | ✅ | ❌ | Spatial + partial-T | LIF |
| Stellar | ✅ | ❌ | Spatial + fully-T | FS |
| **LoAS (ours)** | **✅** | **✅** | **Spatial + fully-T** | **LIF** |

LoAS is the **first** accelerator to support both spike *and* weight sparsity with full temporal parallelism for LIF neurons.

---

## Citation

Paper: [arXiv:2407.14073](https://arxiv.org/abs/2407.14073) | Original codebase (PyTorch + artifact eval): [RuokaiYin/LoAS](https://github.com/RuokaiYin/LoAS)
