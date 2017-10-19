// Author: Florian Zaruba, ETH Zurich
// Date: 15/04/2017
// Description: Top level testbench module. Instantiates the top level DUT, configures
//              the virtual interfaces and starts the test passed by +UVM_TEST+
//
// Copyright (C) 2017 ETH Zurich, University of Bologna
// All rights reserved.
//
// This code is under development and not yet released to the public.
// Until it is released, the code is under the copyright of ETH Zurich and
// the University of Bologna, and may contain confidential and/or unpublished
// work. Any reuse/redistribution is strictly forbidden without written
// permission from ETH Zurich.
//
// Bug fixes and contributions will eventually be released under the
// SolderPad open hardware license in the context of the PULP platform
// (http://www.pulp-platform.org), under the copyright of ETH Zurich and the
// University of Bologna.
//

import ariane_pkg::*;
import uvm_pkg::*;
import core_lib_pkg::*;

`timescale 1ns / 1ps

`define DRAM_BASE 64'h80000000

`include "uvm_macros.svh"

module core_tb;
    import "DPI-C" function chandle read_elf(string fn);
    import "DPI-C" function longint unsigned get_section_address(string symb);
    import "DPI-C" function longint unsigned get_section_size(string symb);
    import "DPI-C" function longint unsigned get_symbol_address(string symb);

    static uvm_cmdline_processor uvcl = uvm_cmdline_processor::get_inst();

    localparam int unsigned CLOCK_PERIOD = 20ns;

    logic clk_i;
    logic rst_ni;
    logic [63:0] time_i;

    logic display_instr;

    longint unsigned cycles;
    longint unsigned max_cycles;

    debug_if debug_if();
    core_if core_if (clk_i);
    dcache_if dcache_if (clk_i);

    logic [63:0] instr_if_address;
    logic        instr_if_data_req;
    logic        instr_if_data_gnt;
    logic        instr_if_data_rvalid;
    logic [63:0] instr_if_data_rdata;

    logic [63:0] data_if_data_address_i;
    logic [63:0] data_if_data_wdata_i;
    logic        data_if_data_req_i;
    logic        data_if_data_we_i;
    logic [7:0]  data_if_data_be_i;
    logic        data_if_data_gnt_o;
    logic        data_if_data_rvalid_o;
    logic [63:0] data_if_data_rdata_o;

    core_mem core_mem_i (
        .clk_i                   ( clk_i                        ),
        .rst_ni                  ( rst_ni                       ),
        .instr_if_address_i      ( instr_if_address             ),
        .instr_if_data_req_i     ( instr_if_data_req            ),
        .instr_if_data_gnt_o     ( instr_if_data_gnt            ),
        .instr_if_data_rvalid_o  ( instr_if_data_rvalid         ),
        .instr_if_data_rdata_o   ( instr_if_data_rdata          ),

        .data_if_address_i       ( data_if_data_address_i       ),
        .data_if_data_wdata_i    ( data_if_data_wdata_i         ),
        .data_if_data_req_i      ( data_if_data_req_i           ),
        .data_if_data_we_i       ( data_if_data_we_i            ),
        .data_if_data_be_i       ( data_if_data_be_i            ),
        .data_if_data_gnt_o      ( data_if_data_gnt_o           ),
        .data_if_data_rvalid_o   ( data_if_data_rvalid_o        ),
        .data_if_data_rdata_o    ( data_if_data_rdata_o         )
    );

    logic flush_dcache;

    AXI_BUS #(
        .AXI_ADDR_WIDTH ( 64 ),
        .AXI_DATA_WIDTH ( 64 ),
        .AXI_ID_WIDTH   ( 10 ),
        .AXI_USER_WIDTH ( 1  )
    ) data_if();

    AXI_BUS #(
        .AXI_ADDR_WIDTH ( 64 ),
        .AXI_DATA_WIDTH ( 64 ),
        .AXI_ID_WIDTH   ( 10 ),
        .AXI_USER_WIDTH ( 1  )
    ) bypass_if();

    axi2per #(
        .PER_ADDR_WIDTH(64),
        .PER_DATA_WIDTH(64),
        .PER_ID_WIDTH  (10),
        .AXI_ADDR_WIDTH(64),
        .AXI_DATA_WIDTH(64),
        .AXI_USER_WIDTH(1),
        .AXI_ID_WIDTH  (10),
        .BUFFER_DEPTH  (2)
    ) i_axi2per (
        .clk_i                 ( clk_i                   ),
        .rst_ni                ( rst_ni                  ),
        .test_en_i             ( 1'b0                    ),
        .axi_slave_aw_valid_i  ( bypass_if.aw_valid      ),
        .axi_slave_aw_addr_i   ( bypass_if.aw_addr       ),
        .axi_slave_aw_prot_i   ( bypass_if.aw_prot       ),
        .axi_slave_aw_region_i ( bypass_if.aw_region     ),
        .axi_slave_aw_len_i    ( bypass_if.aw_len        ),
        .axi_slave_aw_size_i   ( bypass_if.aw_size       ),
        .axi_slave_aw_burst_i  ( bypass_if.aw_burst      ),
        .axi_slave_aw_lock_i   ( bypass_if.aw_lock       ),
        .axi_slave_aw_cache_i  ( bypass_if.aw_cache      ),
        .axi_slave_aw_qos_i    ( bypass_if.aw_qos        ),
        .axi_slave_aw_id_i     ( bypass_if.aw_id         ),
        .axi_slave_aw_user_i   ( bypass_if.aw_user       ),
        .axi_slave_aw_ready_o  ( bypass_if.aw_ready      ),
        .axi_slave_ar_valid_i  ( bypass_if.ar_valid      ),
        .axi_slave_ar_addr_i   ( bypass_if.ar_addr       ),
        .axi_slave_ar_prot_i   ( bypass_if.ar_prot       ),
        .axi_slave_ar_region_i ( bypass_if.ar_region     ),
        .axi_slave_ar_len_i    ( bypass_if.ar_len        ),
        .axi_slave_ar_size_i   ( bypass_if.ar_size       ),
        .axi_slave_ar_burst_i  ( bypass_if.ar_burst      ),
        .axi_slave_ar_lock_i   ( bypass_if.ar_lock       ),
        .axi_slave_ar_cache_i  ( bypass_if.ar_cache      ),
        .axi_slave_ar_qos_i    ( bypass_if.ar_qos        ),
        .axi_slave_ar_id_i     ( bypass_if.ar_id         ),
        .axi_slave_ar_user_i   ( bypass_if.ar_user       ),
        .axi_slave_ar_ready_o  ( bypass_if.ar_ready      ),
        .axi_slave_w_valid_i   ( bypass_if.w_valid       ),
        .axi_slave_w_data_i    ( bypass_if.w_data        ),
        .axi_slave_w_strb_i    ( bypass_if.w_strb        ),
        .axi_slave_w_user_i    ( bypass_if.w_user        ),
        .axi_slave_w_last_i    ( bypass_if.w_last        ),
        .axi_slave_w_ready_o   ( bypass_if.w_ready       ),
        .axi_slave_r_valid_o   ( bypass_if.r_valid       ),
        .axi_slave_r_data_o    ( bypass_if.r_data        ),
        .axi_slave_r_resp_o    ( bypass_if.r_resp        ),
        .axi_slave_r_last_o    ( bypass_if.r_last        ),
        .axi_slave_r_id_o      ( bypass_if.r_id          ),
        .axi_slave_r_user_o    ( bypass_if.r_user        ),
        .axi_slave_r_ready_i   ( bypass_if.r_ready       ),
        .axi_slave_b_valid_o   ( bypass_if.b_valid       ),
        .axi_slave_b_resp_o    ( bypass_if.b_resp        ),
        .axi_slave_b_id_o      ( bypass_if.b_id          ),
        .axi_slave_b_user_o    ( bypass_if.b_user        ),
        .axi_slave_b_ready_i   ( bypass_if.b_ready       ),
        .per_master_req_o      ( data_if_data_req_i      ),
        .per_master_add_o      ( data_if_data_address_i  ),
        .per_master_we_no      ( data_if_data_we_i       ),
        .per_master_wdata_o    ( data_if_data_wdata_i    ),
        .per_master_be_o       ( data_if_data_be_i       ),
        .per_master_gnt_i      ( data_if_data_gnt_o      ),
        .per_master_r_valid_i  ( data_if_data_rvalid_o   ),
        .per_master_r_opc_i    ( '0                      ),
        .per_master_r_rdata_i  ( data_if_data_rdata_o    ),
        .busy_o                ( busy_o                  )
    );

    ariane dut (
        .clk_i                   ( clk_i                        ),
        .rst_ni                  ( rst_ni                       ),
        .time_i                  ( time_i                       ),
        .time_irq_i              ( 1'b0                         ),
        .test_en_i               ( core_if.test_en              ),
        .fetch_enable_i          ( core_if.fetch_enable         ),
        .core_busy_o             ( core_if.core_busy            ),
        .flush_icache_o          (                              ),
        .flush_dcache_o          ( flush_dcache                 ),
        .flush_dcache_ack_i      ( flush_dcache                 ),
        .ext_perf_counters_i     (                              ),
        .boot_addr_i             ( core_if.boot_addr            ),
        .core_id_i               ( core_if.core_id              ),
        .cluster_id_i            ( core_if.cluster_id           ),

        .instr_if_data_req_o     ( instr_if_data_req            ),
        .instr_if_address_o      ( instr_if_address             ),
        .instr_if_data_be_o      (                              ),
        .instr_if_data_gnt_i     ( instr_if_data_gnt            ),
        .instr_if_data_rvalid_i  ( instr_if_data_rvalid         ),
        .instr_if_data_rdata_i   ( instr_if_data_rdata          ),

        .data_if                 ( data_if                      ),
        .bypass_if               ( bypass_if                    ),

        .irq_i                   ( core_if.irq                  ),
        .irq_id_i                ( core_if.irq_id               ),
        .irq_ack_o               ( core_if.irq_ack              ),
        .irq_sec_i               ( core_if.irq_sec              ),
        .sec_lvl_o               ( core_if.sec_lvl              ),

        .debug_req_i             (                              ),
        .debug_gnt_o             (                              ),
        .debug_rvalid_o          (                              ),
        .debug_addr_i            (                              ),
        .debug_we_i              (                              ),
        .debug_wdata_i           (                              ),
        .debug_rdata_o           (                              ),
        .debug_halted_o          (                              ),
        .debug_halt_i            (                              ),
        .debug_resume_i          (                              )
    );

    // Clock process
    initial begin
        clk_i = 1'b0;
        rst_ni = 1'b0;
        repeat(8)
            #(CLOCK_PERIOD/2) clk_i = ~clk_i;
        rst_ni = 1'b1;
        forever begin
            #(CLOCK_PERIOD/2) clk_i = 1'b1;
            #(CLOCK_PERIOD/2) clk_i = 1'b0;

            //if (cycles > max_cycles)
            //    $fatal(1, "Simulation reached maximum cycle count of %d", max_cycles);

            cycles++;
        end
    end
    // Real Time Clock
    initial begin
        // initialize platform timer
        time_i = 64'b0;

        // increment timer with a frequency of 32.768 kHz
        forever begin
            #30.517578us;
            time_i++;
        end
    end

    task preload_memories();
        string plus_args [$];

        string file;
        string file_name;
        string base_dir;
        string test;
        // offset the temporary RAM
        logic [63:0] rmem [2**21];

        // get the file name from a command line plus arg
        void'(uvcl.get_arg_value("+BASEDIR=", base_dir));
        void'(uvcl.get_arg_value("+ASMTEST=", file_name));

        file = {base_dir, "/", file_name};

        uvm_report_info("Program Loader", $sformatf("Pre-loading memory from file: %s\n", file), UVM_LOW);
        // read elf file (DPI call)
        void'(read_elf(file));

        // get the objdump verilog file to load our memorys
        $readmemh({file, ".hex"}, rmem);
        // copy double-wordwise from verilog file
        for (int i = 0; i < 2**21; i++) begin
            core_mem_i.ram_i.mem[i] = rmem[i];
        end

    endtask : preload_memories

    program testbench (core_if core_if, dcache_if dcache_if);
        longint unsigned begin_signature_address;
        longint unsigned tohost_address;
        string max_cycle_string;
        initial begin
            preload_memories();

            uvm_config_db #(virtual core_if)::set(null, "uvm_test_top", "core_if", core_if);
            uvm_config_db #(virtual dcache_if )::set(null, "uvm_test_top", "dcache_if", dcache_if);

            // we are interested in the .tohost ELF symbol in-order to observe end of test signals
            tohost_address = get_symbol_address("tohost");
            begin_signature_address = get_symbol_address("begin_signature");
            uvm_report_info("Program Loader", $sformatf("tohost: %h begin_signature %h\n", tohost_address, begin_signature_address), UVM_LOW);
            // pass tohost address to UVM resource DB
            uvm_config_db #(longint unsigned)::set(null, "uvm_test_top.m_env.m_eoc", "tohost", tohost_address);
            uvm_config_db #(longint unsigned)::set(null, "uvm_test_top.m_env.m_eoc", "begin_signature", ((begin_signature_address -`DRAM_BASE) >> 3));
            // print the topology
            // uvm_top.enable_print_topology = 1;
            // get the maximum cycle count the simulation is allowed to run
            if (uvcl.get_arg_value("+max-cycles=", max_cycle_string) == 0) begin
                max_cycles = {64{1'b1}};
            end else begin
                max_cycles = max_cycle_string.atoi();
            end
            // Start UVM test
            run_test();
        end
    endprogram

    testbench tb(core_if, dcache_if);
endmodule
