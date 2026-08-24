# 02203 Assignment 2 – Edge Detection (SystemVerilog)

This repository contains a **SystemVerilog implementation** of **Assignment 2** in *02203 Design of Digital Systems (Fall 2026)* at DTU.

The goal of this assignment is to design, simulate, and implement a digital system for **edge detection** in images using a custom accelerator and memory interface.

The design flow follows a **top-down, simulation-based methodology** and targets the **Xilinx Nexys 4 DDR / Nexys A7 FPGA board**.

Developer: Otto Westy Rasmussen

## Repository Structure

```bash
├── other_images
│   ├── cross.pgm
│   ├── illusion.pgm
│   ├── kaleidoscope.pgm
│   ├── pattern.pgm
│   └── systemverilog.pgm
├── README.md
├── serial_interface
│   ├── HELP.txt
│   ├── LICENSE.txt
│   ├── README.md
│   ├── requirements.txt
│   ├── Serial interface.exe
│   └── serial_interface.py
├── task2
│   ├── acc2.sv
│   ├── clock.sv
│   ├── memory2.sv
│   ├── pic1.pgm
│   └── test2.sv
└── task3
    ├── clock_divider.sv
    ├── controller.sv
    ├── debounce.sv
    ├── memory3.sv
    ├── Nexys4DDR_edge.xdc
    ├── top.sv
    └── uart.sv
```

## Simulation and Tools

- **FPGA Synthesis and Testing:**  
  - Tool: [Xilinx Vivado](https://www.xilinx.com/products/design-tools/vivado.html)  
  - Target board: Nexys 4 DDR or Nexys A7  
  - Use `Nexys4DDR_edge.xdc` for FPGA pin constraints   

## Notes
- This repo provides a **SystemVerilog** version of the assignment (original was in VHDL).  
