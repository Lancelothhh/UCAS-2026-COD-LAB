# UCAS 2026 COD Lab

This repository contains lab code for the UCAS 2026 Computer Organization and Design course.

## Contents

- `prj0/`: 8-bit adder implementation.
- `prj1/`: register file and ALU modules.
- `prj2/`: simple CPU and shifter implementation.
- `prj3/`: custom CPU hardware and supporting software utilities.

## Project Structure

```text
.
├── prj0/
│   └── adder.v
├── prj1/
│   ├── alu.v
│   └── reg_file.v
├── prj2/
│   ├── shifter.v
│   └── simple_cpu.v
└── prj3/
    ├── hardware/
    │   └── custom_cpu.v
    └── software/
        ├── perf_cnt.h
        ├── pert_cnt.c
        └── print.c
```

## Notes

The Verilog files implement the hardware modules required by each lab project. The software files in `prj3/software` provide lightweight printing and performance counter helpers for the custom CPU project.
