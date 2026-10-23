# Pipelined MIPS with Branch Prediction and L1/L2 Caches

Coursework by Bo-Wen Chen with teammates (NTU EE 4039 Computer Architecture, 2017).
Bo-Wen Chen owned the L1/L2 cache design and evaluation.

> This repository is archived coursework, published for reference. It is not maintained,
> and it is not meant to be copied into a current course submission.

The final project is a five-stage pipelined MIPS processor in synthesizable Verilog. It has
three branch predictors and a configurable two-level cache hierarchy, which were evaluated
with RTL simulation and Synopsys Design Compiler synthesis. The homework that led up to it
(ALU, register file, MIPS assembly, a single-cycle MIPS, and a C++ cache simulator) is in
`homework/`.

## Repository layout

```
final-project/
  baseline/rtl/CHIP.v              5-stage pipelined MIPS + L1 I/D caches (top module CHIP)
  baseline/syn/                    gate-level netlist and SDF for the baseline
  branch-prediction/rtl/           CHIP_1bit.v, CHIP_2bit.v, CHIP_PHT2.v (two-level adaptive)
  branch-prediction/syn/           netlists and SDFs for the three predictor variants
  cache/rtl/
    CHIP.v                         pipeline with hit/miss counters exposed for the cache study
    L1cache.v                      L1 cache: 16/32 words, direct-mapped / 2-way / 4-way
    L2_ICache.v, L2_DCache.v       L2 caches: 32-512 words, direct-mapped up to 8-way
    Final_tb.v                     testbench used for the cache sweeps
homework/
  hw1/   8-bit ALU (RTL and behavioral), register file, simple calculator, with testbenches
  hw2/   bubble sort and quicksort in MIPS assembly (SPIM/MARS style console I/O)
  hw3/   single-cycle MIPS (SingleCycle_MIPS.v) and its synthesized netlist/SDF
  hw4/   C++ L1 cache simulator (direct-mapped, 2-way, 4-way, fully associative; LRU, write-back)
```

## Pipeline design

The baseline (`final-project/baseline/rtl/CHIP.v`) is a classic IF / ID / EX / MEM / WB
pipeline with IF/ID, ID/EX, EX/MEM and MEM/WB registers. It supports R-type arithmetic and
logic, `lw`, `sw`, `beq`, `j`, `jal`, `jr` and `jalr`.

- **Forwarding.** Branches are resolved in ID, so a single forwarding unit forwards the newest
  EX or MEM result back into ID. EX takes priority over MEM when both match. Operands are
  already current when they reach EX, so the ALU needs no second forwarding path.
- **Load-use stall.** The hazard detection unit checks `ID_EX_MemRead` against the rs/rt of the
  instruction in ID. On a match it stalls PC and IF/ID and inserts one bubble.
- **Flush.** Jumps and taken branches are resolved in ID, and the wrong-path instruction in
  IF/ID is flushed (one cycle).
- **`jal`/`jr`.** `jal` writes PC+4 into `$31` the cycle after it is decoded rather than at WB,
  so a `jr $31` right behind it reads the correct return address. A `jal_WB` guard stops the
  same instruction from writing `$31` a second time when it reaches WB.

## Branch predictors

The predictor sits in IF and chooses between the branch target and PC+4. A comparator in ID
checks the real outcome. On a misprediction it redirects the PC and flushes IF/ID. In these
variants the jump multiplexers also move to IF, which saves one cycle on `j`/`jal`. `jr` still
waits for `$31` in ID.

| File | Predictor |
|---|---|
| `CHIP_1bit.v`  | 1-bit last-outcome predictor |
| `CHIP_2bit.v`  | 2-bit saturating counter (strongly/weakly taken/not-taken) |
| `CHIP_PHT2.v`  | two-level adaptive predictor: 2-bit global history register selecting one of four 2-bit counters |

## Cache design

All caches use 4-word (128-bit) blocks, write-back with dirty bits, and LRU replacement in
the set-associative versions. Size and associativity are picked at compile time with
`+define+` macros:

| Level | Sizes | Associativity | Macros |
|---|---|---|---|
| L1 (I and D) | 16 words (`L1SIZE_4`) or 32 words (`L1SIZE_8`) | direct-mapped (default), 2-way (`L1_2way`); 4-way (`L1_4way`) is also coded for the 32-word size | e.g. `+define+L1SIZE_8+L1_2way` |
| L2 D-cache | 64 / 128 / 256 words (`L2SIZE_64`/`_128`/`_256`; 32 and 512 also coded) | `DIRECTMAPD`, `L2_D_2way`, `L2_D_4way`, `L2_D_8way` | e.g. `+define+L2_D_2way+L2SIZE_64` |
| L2 I-cache | same sizes | `DIRECTMAPI`, `L2_I_2way`, `L2_I_4way`, `L2_I_8way` | e.g. `+define+DIRECTMAPI` |

`L2Ddisabled` / `L2Idisabled` / `L2disabled` remove an L2 level for the "L1 only" comparison.
`cache/rtl/CHIP.v` exposes hit and miss counters, and `Final_tb.v` reports miss rates from them.

## Results

All numbers come from the original project report (course test benches, Synopsys Design Compiler).

**Baseline synthesis.** The baseline pipelined MIPS with its L1 caches synthesized to
**281,113 um^2 at a 3.37 ns cycle**, which was the tightest constraint that still met timing.
Area dropped as the clock target tightened down to about 5 ns, then rose again as the tool
traded area for speed. Area x time still improved overall:

| Set cycle (ns) | Area (um^2) | Cycle length (ns) | Total sim time (ns) |
|---|---|---|---|
| 10  | 255,804 | 9.5  | 19,983 |
| 8   | 252,277 | 6.9  | 14,824 |
| 5   | 244,624 | 5.1  | 10,937 |
| 4   | 279,376 | 4.3  | 9,540  |
| 3.3 | 281,113 | 3.37 | 7,576  |

**Branch prediction.** On the course test benches, branch prediction cut execution cycles by
about 9-10%:

| Predictor | `I_mem_hasHazard` cycles | `I_mem_BrPred` cycles | Area at 3.5 ns (um^2) |
|---|---|---|---|
| none   | 2144.5 | 155.5 | - |
| 1-bit  | 1954.5 | 141.5 | 285,400 |
| 2-bit  | 1939.5 | 138.5 | 285,433 |
| two-level (PHT2) | 1942.5 | 138.5 | 286,086 |

The 2-bit predictor matched the two-level predictor on these benches with less area. PHT2
needs a one-cycle bubble between back-to-back branches while its history updates, so on
these benches it never pulled ahead. The 2-bit predictor was chosen as the best trade-off.

**Caches.** The benchmark generates a Fibonacci series and then bubble-sorts it, with the input
size `nb` swept from 10 to 70.

- A 2-way L1 beat direct-mapped at 32 words, especially for the I-cache. At 16 words, 2-way
  had a *higher* I-cache miss rate than direct-mapped: with half as many sets, the cache no
  longer held whole function blocks of the 76-instruction program.
- An L2 I-cache helped for small inputs (nb < 50). Its benefit faded with a 32-word L1, which
  already covers about half of the program.
- An L2 D-cache only helped once it held the whole working set (256 words). A 64-word L2 D-cache
  was *slower* than having no L2 D-cache. The workload streams through its data, so a small
  L2 adds a lookup cycle on every miss without getting reuse.
- Associativity in the L2 D-cache made little difference, though 2-way was best in almost
  every case. Associativity helped the L2 I-cache because the code jumps between blocks.
- The L1:L2 size ratio mattered much less than the absolute L2 size.
- The two L1 caches together take about as much area as the pipeline itself, so the cache
  design matters as much as the core.

## Simulating

The top module is `CHIP`. It connects to an external `slow_memory` model for instruction and
data memory. The course supplied that memory model, the `TestBed_*.v` checkers and the
`I_mem_*` / `D_mem` program images, and they are **not included here**. You need your own
equivalents to run a full program. With those in place, the original flow used Cadence
NC-Verilog. For example, to run the cache study with a 32-word 2-way L1, a 2-way 64-word L2
D-cache and a direct-mapped L2 I-cache:

```sh
cd final-project/cache/rtl
ncverilog Final_tb.v CHIP.v L1cache.v L2_DCache.v L2_ICache.v slow_memory.v \
  +define+L2Cache+L1SIZE_8+L1_2way+L2_D_2way+DIRECTMAPI+L2SIZE_64 +access+r
```

Gate-level simulation uses the netlist and SDF in `syn/` with `+define+SDF` (and the standard
cell library models). Synopsys VCS accepts the same files and `+define+` options.

With Icarus Verilog 11, the baseline, all three predictor variants and every L1/L2 combination
used in the report (L1 16/32 words with direct-mapped or 2-way; L2 D and I direct-mapped to
8-way at 64/128/256 words) elaborate without errors. Without the course memory model and
program images this is an elaboration check only, not a functional run:

```sh
iverilog -s CHIP -o /dev/null final-project/baseline/rtl/CHIP.v
iverilog -s CHIP -o /dev/null final-project/branch-prediction/rtl/CHIP_2bit.v
iverilog -DL1SIZE_8 -DL1_2way -DL2_D_2way -DDIRECTMAPI -DL2SIZE_128 -s CHIP -o /dev/null \
  final-project/cache/rtl/CHIP.v final-project/cache/rtl/L1cache.v \
  final-project/cache/rtl/L2_DCache.v final-project/cache/rtl/L2_ICache.v
```

The HW1 testbenches are self-checking and pass under Icarus. Run them from a writable
directory, because they dump VCD files:

```sh
cd homework/hw1
iverilog -o alu alu-behavioral/alu.v alu-behavioral/alu_tb.v && vvp alu
iverilog -o rf register-file/register_file.v register-file/register_file_tb.v && vvp rf
iverilog -o calc simple-calculator/simple_calculator.v simple-calculator/simple_calculator_tb.v && vvp calc
```

`homework/hw4/L1cache.cpp` is the student-written part of a course-provided simulator
framework. The `L1cache.h` / `Mem.h` headers and the driver are not included.
