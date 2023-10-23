/*
 *  Copyright 2023 CEA*
 *  *Commissariat a l'Energie Atomique et aux Energies Alternatives (CEA)
 *
 *  SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 *
 *  Licensed under the Solderpad Hardware License v 2.1 (the “License”); you
 *  may not use this file except in compliance with the License, or, at your
 *  option, the Apache License version 2.0. You may obtain a copy of the
 *  License at
 *
 *  https://solderpad.org/licenses/SHL-2.1/
 *
 *  Unless required by applicable law or agreed to in writing, any work
 *  distributed under the License is distributed on an “AS IS” BASIS, WITHOUT
 *  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
 *  License for the specific language governing permissions and limitations
 *  under the License.
 */
/*
 *  Authors       : Riccardo Alidori, Cesar Fuguet
 *  Creation Date : June, 2021
 *  Description   : Linear Hardware Memory Prefetcher wrapper.
 *  History       :
 */
module hwpf_stride_wrapper
import hwpf_stride_pkg::*;
import hpdcache_pkg::*;
//  Parameters
//  {{{
#(
    parameter NUM_HW_PREFETCH = 4,
    parameter NUM_SNOOP_PORTS = 1
)
//  }}}

//  Ports
//  {{{
(
    input  logic                                       clk_i,
    input  logic                                       rst_ni,

    //  CSR
    //  {{{
    input  logic                  [NUM_HW_PREFETCH-1:0] hwpf_stride_base_set_i,
    input  hwpf_stride_base_t     [NUM_HW_PREFETCH-1:0] hwpf_stride_base_i,
    output hwpf_stride_base_t     [NUM_HW_PREFETCH-1:0] hwpf_stride_base_o,

    input  logic                  [NUM_HW_PREFETCH-1:0] hwpf_stride_param_set_i,
    input  hwpf_stride_param_t    [NUM_HW_PREFETCH-1:0] hwpf_stride_param_i,
    output hwpf_stride_param_t    [NUM_HW_PREFETCH-1:0] hwpf_stride_param_o,

    input  logic                  [NUM_HW_PREFETCH-1:0] hwpf_stride_throttle_set_i,
    input  hwpf_stride_throttle_t [NUM_HW_PREFETCH-1:0] hwpf_stride_throttle_i,
    output hwpf_stride_throttle_t [NUM_HW_PREFETCH-1:0] hwpf_stride_throttle_o,

    output hwpf_stride_status_t                         hwpf_stride_status_o,
    //  }}}

    // Snooping
    //  {{{
    input  logic               [NUM_SNOOP_PORTS-1:0]   snoop_valid_i,
    input  hpdcache_req_addr_t [NUM_SNOOP_PORTS-1:0]   snoop_addr_i,
    //  }}}

    //  DCache interface
    //  {{{
    input  hpdcache_req_sid_t                          dcache_req_sid_i,
    output logic                                       dcache_req_valid_o,
    input  logic                                       dcache_req_ready_i,
    output hpdcache_req_t                              dcache_req_o,
    input  logic                                       dcache_rsp_valid_i,
    input  hpdcache_rsp_t                              dcache_rsp_i
    //  }}}
);
//  }}}

    //  Internal signals
    //  {{{
    logic            [NUM_HW_PREFETCH-1:0] hwpf_stride_enable;
    logic            [NUM_HW_PREFETCH-1:0] hwpf_stride_free;
    logic            [NUM_HW_PREFETCH-1:0] hwpf_stride_status_busy;
    logic            [3:0]                 hwpf_stride_status_free_idx;

    hpdcache_nline_t [NUM_HW_PREFETCH-1:0] snoop_addr;
    logic            [NUM_HW_PREFETCH-1:0] snoop_match;

    logic            [NUM_HW_PREFETCH-1:0] hwpf_stride_req_valid;
    logic            [NUM_HW_PREFETCH-1:0] hwpf_stride_req_ready;
    hpdcache_req_t   [NUM_HW_PREFETCH-1:0] hwpf_stride_req;
    logic            [NUM_HW_PREFETCH-1:0] hwpf_stride_arb_in_req_valid;
    logic            [NUM_HW_PREFETCH-1:0] hwpf_stride_arb_in_req_ready;
    hpdcache_req_t   [NUM_HW_PREFETCH-1:0] hwpf_stride_arb_in_req;
    logic            [NUM_HW_PREFETCH-1:0] hwpf_stride_arb_in_rsp_valid;
    hpdcache_rsp_t   [NUM_HW_PREFETCH-1:0] hwpf_stride_arb_in_rsp;
    //  }}}



    // forood: signals used to provide engines with data
    // these registers are later drived in an always statement and are
    // filled with data of prefetching instructions
    //{{{

    logic                  [NUM_HW_PREFETCH-1:0] hwpf_stride_base_set_p;
    hwpf_stride_base_t     [NUM_HW_PREFETCH-1:0] hwpf_stride_base_p;
    
    logic                  [NUM_HW_PREFETCH-1:0] hwpf_stride_param_set_p;
    hwpf_stride_param_t    [NUM_HW_PREFETCH-1:0] hwpf_stride_param_p;
    
    logic                  [NUM_HW_PREFETCH-1:0] hwpf_stride_throttle_set_p;
    hwpf_stride_throttle_t [NUM_HW_PREFETCH-1:0] hwpf_stride_throttle_p;
    
    //}}}



    // forood: signals used to send detection logic data to engine driver registers
    //{{{

    logic                  [NUM_HW_PREFETCH-1:0] hwpf_stride_base_set_internal;
    hwpf_stride_base_t     [NUM_HW_PREFETCH-1:0] hwpf_stride_base_internal;
    
    logic                  [NUM_HW_PREFETCH-1:0] hwpf_stride_param_set_internal;
    hwpf_stride_param_t    [NUM_HW_PREFETCH-1:0] hwpf_stride_param_internal;
    
    logic                  [NUM_HW_PREFETCH-1:0] hwpf_stride_throttle_set_internal;
    hwpf_stride_throttle_t [NUM_HW_PREFETCH-1:0] hwpf_stride_throttle_internal;
    
    //}}}



    //  Assertions
    //  {{{
    //  pragma translate_off
    initial
    begin
        max_hwpf_stride_assert: assert (NUM_HW_PREFETCH <= 16) else
                $error("hwpf_stride: maximum number of HW prefetchers is 16");
    end



    

    //  pragma translate_on
    //  }}}

    //  Compute the status information
    //  {{{
    always_comb begin: hwpf_stride_priority_encoder
        hwpf_stride_status_free_idx = '0;
        for (int unsigned i = 0; i < NUM_HW_PREFETCH; i++) begin
            if (hwpf_stride_free[i]) begin
                hwpf_stride_status_free_idx = i;
                break;
            end
        end
    end

    assign  hwpf_stride_free = ~(hwpf_stride_enable | hwpf_stride_status_busy);

    assign  hwpf_stride_status_o[63:32] = {{32-NUM_HW_PREFETCH{1'b0}}, hwpf_stride_status_busy}, // Busy flags
            hwpf_stride_status_o[31]    = |hwpf_stride_free,                                     // Global free flag
            hwpf_stride_status_o[30:16] = {11'b0, hwpf_stride_status_free_idx},                  // Free Index
            hwpf_stride_status_o[15:0]  = {{16-NUM_HW_PREFETCH{1'b0}}, hwpf_stride_enable};      // Enable flags
    //  }}}




    //forood : the new prefetcher stride detection logic
    //  {{{
        //the prefetching date table. this table has LRU replacing policy and always all
        //entries are ordered from 0 to PREFETCHER_TABLE_SIZE - 1, it applies to all entries 
        //regardless of them being valid or not.
        prefethcing_table_entry_t [`PREFETCHER_TABLE_SIZE - 1:0]    prefetcher_lookUp_table;
        //this entry is what snooping mechanism detects and enqueus.
        prefethcing_engine_entry_t                                  snooping_entry;
        




        //this logic is used to reset the table
        always @(negedge rst_ni) begin
            // forood : reset the valid bits of the table for all entries
            if (!rst_ni) begin
                for (int i = 0; i < `PREFETCHER_TABLE_SIZE - 1 ; i++ ) begin
                    prefetcher_lookUp_table[i].valid = '0;
                    prefetcher_lookUp_table[i].LRU_state = i;
                end

                hwpf_stride_base_set_p = '0;
                hwpf_stride_base_p = '0;
                hwpf_stride_param_set_p = '0;
                hwpf_stride_param_p = '0;
                hwpf_stride_throttle_set_p = '0;
                hwpf_stride_throttle_p = '0;
                
                
            end
        end

        always @(posedge clk_i)
            begin
                //forood : first check if there is any match for the data on ports

                for (int j = 0; j < NUM_SNOOP_PORTS; j++) begin
                    automatic int matched_index = -1;
                    // many 0 addresses are seen on prts when there is no request hence 0 addresses are not processed.
                    if (snoop_addr_i[j][48:10] != '0) begin
                            // looping over all entries in table to find a matched tag, 
                            // if the match is found then this entry is set to 0 in LRU table 
                            // and all entries with less priority than it's initial state are incremented
                            for (int i = 0; i < `PREFETCHER_TABLE_SIZE - 1 ; i++ ) begin
                                if(prefetcher_lookUp_table[i].valid && prefetcher_lookUp_table[i].tag == snoop_addr_i[j][48:10]) begin
                                    matched_index = i;
                                    for (int k = 0; k < `PREFETCHER_TABLE_SIZE - 1 ; k++) begin
                                        if (prefetcher_lookUp_table[k].LRU_state < prefetcher_lookUp_table[i].LRU_state) begin
                                            prefetcher_lookUp_table[k].LRU_state++;
                                        end
                                    end
                                    prefetcher_lookUp_table[i].LRU_state = '0;
                                    break;
                                end 
                            end

                            // forood: if there is no match we must create a new entry
                            // first check if there is an invalid entry, then fill it with data and update all other 
                            //entries LRU state
                            if(matched_index == -1) begin
                                automatic int invalid_index = -1;
                                for (int i=0; i<`PREFETCHER_TABLE_SIZE - 1; ++i) begin
                                    if(~prefetcher_lookUp_table[i].valid)begin
                                        prefetcher_lookUp_table[i].LRU_state = '0;
                                        prefetcher_lookUp_table[i].valid = '1;
                                        prefetcher_lookUp_table[i].tag = snoop_addr_i[j][48:10];
                                        prefetcher_lookUp_table[i].training_mode = INITIAL;
                                        prefetcher_lookUp_table[i].index = snoop_addr_i[j][9:4];
                                        prefetcher_lookUp_table[i].stride = '0;

                                        invalid_index = prefetcher_lookUp_table[i].LRU_state;
                                        
                                        for (int k = 0; k < `PREFETCHER_TABLE_SIZE - 1 ; k++) begin
                                            if (prefetcher_lookUp_table[k].LRU_state < prefetcher_lookUp_table[i].LRU_state) begin
                                                prefetcher_lookUp_table[k].LRU_state++;
                                            end
                                        end
                                        prefetcher_lookUp_table[i].LRU_state = '0;

                                        break;
                                    end
                                end
                                
                                //forood : now that all indexes are valid, we will evict the LRU entry
                                //with state = PREFETCHER_TABLE_SIZE (the latest)
                                if(invalid_index == -1) begin
                                    for (int i=0; i<`PREFETCHER_TABLE_SIZE - 1; ++i) begin
                                        // next line may need to be re-written in some other kind of syntax
                                        if(prefetcher_lookUp_table[i].LRU_state == 7'd`PREFETCHER_TABLE_SIZE - 6'd1) begin
                                            prefetcher_lookUp_table[i].LRU_state = '0;
                                            prefetcher_lookUp_table[i].valid = '1;
                                            prefetcher_lookUp_table[i].tag = snoop_addr_i[j][48:10];
                                            prefetcher_lookUp_table[i].training_mode = INITIAL;
                                            prefetcher_lookUp_table[i].index = snoop_addr_i[j][9:4];
                                            prefetcher_lookUp_table[i].stride = '0;
                                            $display("no invalid index was found for %h so entry %0d was evicted as it was LRU index is %h",snoop_addr_i[j][48:10],i, , snoop_addr_i[j][9:4]);
                                        end
                                        else 
                                            prefetcher_lookUp_table[i].LRU_state++;
                                    end
                                end

                            end
                            //this is where the fun begins, in this case we've got a match and we have to start
                            //detecting the stride, make sure it's OK and start prefetching.

                            else begin
                                // forood: whenever the address exactly matches the previous index
                                // we ignore the addr and don't change anything.
                                // theses cases are repeated address accesses the we must ignore
                                if(prefetcher_lookUp_table[matched_index].index != snoop_addr_i[j][9:4]) begin

                                    case (prefetcher_lookUp_table[matched_index].training_mode)
                                        INITIAL: begin
                                        
                                            prefetcher_lookUp_table[matched_index].stride = snoop_addr_i[j][9:4] - prefetcher_lookUp_table[matched_index].index;
                                            prefetcher_lookUp_table[matched_index].index = snoop_addr_i[j][9:4];
                                            prefetcher_lookUp_table[matched_index].training_mode = STRIDE_DETECTION;
                                            //$display("INITIAL addr %h with stride %h and index %h", prefetcher_lookUp_table[matched_index].index, prefetcher_lookUp_table[matched_index].stride, snoop_addr_i[j][9:4]);
                                            
                                        end 

                                        STRIDE_DETECTION: begin
                                            if (prefetcher_lookUp_table[matched_index].stride + prefetcher_lookUp_table[matched_index].index == snoop_addr_i[j][9:4]) begin
                                                prefetcher_lookUp_table[matched_index].index = snoop_addr_i[j][9:4];
                                                prefetcher_lookUp_table[matched_index].training_mode = HIT1;
                                                //$display("at STRD addr %h with stride %h and index %h", prefetcher_lookUp_table[matched_index].index, prefetcher_lookUp_table[matched_index].stride, snoop_addr_i[j][9:4]);
                                            
                                            end
                                            else begin
                                                //$display("at STRD addr %h with stride %h FAILED BACK TO INITIAL and index %h the gussed result was %h", prefetcher_lookUp_table[matched_index].index, prefetcher_lookUp_table[matched_index].stride, snoop_addr_i[j][9:4], prefetcher_lookUp_table[matched_index].stride + prefetcher_lookUp_table[matched_index].index);
                                                prefetcher_lookUp_table[matched_index].stride = snoop_addr_i[j][9:4] - prefetcher_lookUp_table[matched_index].index;
                                                prefetcher_lookUp_table[matched_index].index = snoop_addr_i[j][9:4];
                                                prefetcher_lookUp_table[matched_index].training_mode = INITIAL;
                                                
                                            end
                                        end
                                        HIT1: begin
                                            if (prefetcher_lookUp_table[matched_index].stride + prefetcher_lookUp_table[matched_index].index == snoop_addr_i[j][9:4]) begin
                                                prefetcher_lookUp_table[matched_index].index = snoop_addr_i[j][9:4];
                                                prefetcher_lookUp_table[matched_index].training_mode = HIT2;
                                                //$display("at HIT1 addr %h with stride %h and index %h", prefetcher_lookUp_table[matched_index].index, prefetcher_lookUp_table[matched_index].stride, snoop_addr_i[j][9:4]);
                                            
                                            end
                                            else begin
                                                prefetcher_lookUp_table[matched_index].stride = snoop_addr_i[j][9:4] - prefetcher_lookUp_table[matched_index].index;
                                                prefetcher_lookUp_table[matched_index].index = snoop_addr_i[j][9:4];
                                                prefetcher_lookUp_table[matched_index].training_mode = INITIAL;
                                                //$display("at HIT1 addr %h with stride %h FAILED BACK TO INITIAL and index %h", prefetcher_lookUp_table[matched_index].index, prefetcher_lookUp_table[matched_index].stride, snoop_addr_i[j][9:4]);

                                            end
                                        end
                                        HIT2: begin
                                            if (prefetcher_lookUp_table[matched_index].stride + prefetcher_lookUp_table[matched_index].index == snoop_addr_i[j][9:4]) begin
                                                prefetcher_lookUp_table[matched_index].index = snoop_addr_i[j][9:4];
                                                prefetcher_lookUp_table[matched_index].training_mode = HIT3;
                                                //$display("at HIT2 addr %h with stride %h and index %h", prefetcher_lookUp_table[matched_index].index, prefetcher_lookUp_table[matched_index].stride, snoop_addr_i[j][9:4]);
                                            
                                            end
                                            else begin
                                                prefetcher_lookUp_table[matched_index].stride = snoop_addr_i[j][9:4] - prefetcher_lookUp_table[matched_index].index;
                                                prefetcher_lookUp_table[matched_index].index = snoop_addr_i[j][9:4];
                                                prefetcher_lookUp_table[matched_index].training_mode = INITIAL;
                                                //$display("at HIT2 addr %h with stride %h FAILED BACK TO INITIAL and index %h", prefetcher_lookUp_table[matched_index].index, prefetcher_lookUp_table[matched_index].stride, snoop_addr_i[j][9:4]);

                                            end
                                        end
                                        HIT3: begin
                                            if (prefetcher_lookUp_table[matched_index].stride + prefetcher_lookUp_table[matched_index].index == snoop_addr_i[j][9:4]) begin
                                                prefetcher_lookUp_table[matched_index].index = snoop_addr_i[j][9:4];
                                                prefetcher_lookUp_table[matched_index].training_mode = PREFETCHING;
                                            end
                                            else begin
                                                prefetcher_lookUp_table[matched_index].stride = snoop_addr_i[j][9:4] - prefetcher_lookUp_table[matched_index].index;
                                                prefetcher_lookUp_table[matched_index].index = snoop_addr_i[j][9:4];
                                                prefetcher_lookUp_table[matched_index].training_mode = INITIAL;
                                                //$display("at HIT3 addr %h with stride %h FAILED BACK TO INITIAL and index %h", prefetcher_lookUp_table[matched_index].index, prefetcher_lookUp_table[matched_index].stride, snoop_addr_i[j][9:4]);

                                            end
                                        end
                                        PREFETCHING: begin
                                            

                                                    //once the prefetcher has completly detected a stride it enqueues a request
                                                    //indside the queue and reset this entry to the initial state
                                                    //this is where all parameters are passed to the prefetching engines 
                                                    //if you want to dinamically change prefetcher behaviour for every request
                                                    //this is your chance
                                                    hwpf_stride_base_internal[0].base_cline = snoop_addr_i[j][48:4] + prefetcher_lookUp_table[matched_index].stride ;
                                                    hwpf_stride_base_internal[0].cycle = '0;
                                                    hwpf_stride_base_internal[0].rearm = '0;
                                                    hwpf_stride_base_internal[0].enable = '1;

                                                    hwpf_stride_param_internal[0].nblocks = 4'd8;
                                                    hwpf_stride_param_internal[0].nlines = '0;
                                                    hwpf_stride_param_internal[0].stride = prefetcher_lookUp_table[matched_index].stride;
                                                    
                                                    hwpf_stride_throttle_internal[0].ninflight = 8'd128;
                                                    hwpf_stride_throttle_internal[0].nwait = 16'd100; 

                                                    hwpf_stride_throttle_set_internal = '1;
                                                    hwpf_stride_param_set_internal = '1;
                                                    hwpf_stride_base_set_internal = '1;
                                                    
                                                    

                                                    snooping_entry.base = hwpf_stride_base_internal;
                                                    snooping_entry.throttle = hwpf_stride_throttle_internal;
                                                    snooping_entry.param = hwpf_stride_param_internal;
                                                    enqueue(snooping_entry);
                                                    $display("a request targeting addr %h is enqueud",hwpf_stride_base_internal[0].base_cline);

                                            
                                            prefetcher_lookUp_table[matched_index].training_mode = INITIAL;
                                            prefetcher_lookUp_table[matched_index].valid = '0;
                                        end
                                    endcase

                                end

                            end
                    end
                end

                
                

                
            end


            //forood: this Code implements a quque used for prefetching requests, it lands between
            //snooping mechanism and prefetching engines

    
    parameter                                             QUEUE_SIZE = 16;
    prefethcing_engine_entry_t      [QUEUE_SIZE - 1 : 0]  prefetching_queue;
    int head = 0;
    int tail = 0;
    int count = 0;

    // Function to check if the queue is empty
    function automatic bit is_empty;
        is_empty = (count == 0);
    endfunction

    // Function to check if the queue is full
    function automatic bit is_full;
        is_full = (count == QUEUE_SIZE);
    endfunction

    // Function to add data to the queue
    function automatic void enqueue(prefethcing_engine_entry_t entry);
        if (!is_full()) begin
            prefetching_queue[tail] = entry;
            tail = (tail + 1) % QUEUE_SIZE;
            count++;
        end else begin
            $display("Queue is full. Cannot enqueue data: %h", entry);
        end
    endfunction

    // Function to remove data from the queue
    function automatic prefethcing_engine_entry_t dequeue;
        prefethcing_engine_entry_t entry;
        entry = '0;
        if (!is_empty()) begin
            entry = prefetching_queue[head];
            head = (head + 1) % QUEUE_SIZE;
            count--;
        end else begin
            entry = '0;
        end
        return entry;
    endfunction





       // end

    //  }}}



        //this logic is used to initiate the prefetcher engines
        //every clock cycle the queue of requests is checked and any
        //outsanding request is dequeued and dispatched.
           always @(posedge clk_i) begin
            
            for (int i = 0 ; i < NUM_HW_PREFETCH ; i++) begin
                if(~hwpf_stride_status_busy[i]) begin
                    prefethcing_engine_entry_t entry = dequeue();
                    if(entry != '0) begin
                        // these registers provide request data
                        hwpf_stride_base_p[i] <= entry.base;
                        hwpf_stride_param_p[i] <= entry.param;
                        hwpf_stride_throttle_p[i] <= entry.throttle;

                        // these registers set the above info
                        // in engines registers
                        hwpf_stride_base_set_p[i] <= '1; 
                        hwpf_stride_param_set_p[i] <= '1;
                        hwpf_stride_throttle_set_p[i] <= '1;


                        // considering the engine architecture
                        // by setting this bit to 1, the prefetching requests
                        // are initiated inside engines
                        snoop_match[i] <= '1;
                        $display("the prefetching will be initiated starting from addr %h in prefetcher %d", /*prefetcher_lookUp_table[matched_index].indexsnoop_addr_i[j][48:4]*/entry.base.base_cline, i);
                        
                    end                                
                end
                else begin    
                    // making sure no register inside engine is overridden mid flight
                    snoop_match[i] <= '0;
                    hwpf_stride_base_set_p[i] <= '0; 
                    hwpf_stride_param_set_p[i] <= '0;
                    hwpf_stride_throttle_set_p[i] <= '0;
                end    
            end

            
        end









    //  Hardware prefetcher engines
    //  {{{
    generate
        for (genvar i = 0; i < NUM_HW_PREFETCH; i++) begin
            assign hwpf_stride_enable[i] = hwpf_stride_base_o[i].enable;



            //old snooping mechanism

            //  Compute snoop match signals
            //  {{{
            // always_comb
            // begin : snoop_comb
            //     snoop_match[i] = 1'b0;
            //     for (int j = 0; j < NUM_SNOOP_PORTS; j++) begin
            //         automatic hpdcache_nline_t [NUM_SNOOP_PORTS-1:0] snoop_nline;
            //         snoop_nline = snoop_addr_i[j][HPDCACHE_OFFSET_WIDTH +: HPDCACHE_NLINE_WIDTH];
            //         snoop_match[i] |= (snoop_valid_i[j] && (snoop_nline == snoop_addr[i]));
            //         //$display("requested address on port %0d is %0d\n", HPDCACHE_OFFSET_WIDTH, HPDCACHE_NLINE_WIDTH);
            //     end
            // end
            //  }}}



            hwpf_stride #(
                .CACHE_LINE_BYTES   ( HPDCACHE_CL_WIDTH/8 )
            ) hwpf_stride_i (
                .clk_i,
                .rst_ni,

                .csr_base_set_i     ( hwpf_stride_base_set_p[i] ),
                .csr_base_i         ( hwpf_stride_base_p[i] ),
                .csr_param_set_i    ( hwpf_stride_param_set_p[i] ),
                .csr_param_i        ( hwpf_stride_param_p[i] ),
                .csr_throttle_set_i ( hwpf_stride_throttle_set_p[i] ),
                .csr_throttle_i     ( hwpf_stride_throttle_p[i] ),

                .csr_base_o         ( hwpf_stride_base_o[i] ),
                .csr_param_o        ( hwpf_stride_param_o[i] ),
                .csr_throttle_o     ( hwpf_stride_throttle_o[i] ),

                .busy_o             ( hwpf_stride_status_busy[i] ),

                .snoop_addr_o       ( snoop_addr[i] ),
                .snoop_match_i      ( snoop_match[i] ),

                .dcache_req_valid_o ( hwpf_stride_req_valid[i] ),
                .dcache_req_ready_i ( hwpf_stride_req_ready[i] ),
                .dcache_req_o       ( hwpf_stride_req[i] ),
                .dcache_rsp_valid_i ( hwpf_stride_arb_in_rsp_valid[i]  ),
                .dcache_rsp_i       ( hwpf_stride_arb_in_rsp[i] )
            );

            assign hwpf_stride_req_ready[i]              = hwpf_stride_arb_in_req_ready[i],
                   hwpf_stride_arb_in_req_valid[i]       = hwpf_stride_req_valid[i],
                   hwpf_stride_arb_in_req[i].addr        = hwpf_stride_req[i].addr,
                   hwpf_stride_arb_in_req[i].wdata       = hwpf_stride_req[i].wdata,
                   hwpf_stride_arb_in_req[i].op          = hwpf_stride_req[i].op,
                   hwpf_stride_arb_in_req[i].be          = hwpf_stride_req[i].be,
                   hwpf_stride_arb_in_req[i].size        = hwpf_stride_req[i].size,
                   hwpf_stride_arb_in_req[i].uncacheable = hwpf_stride_req[i].uncacheable,
                   hwpf_stride_arb_in_req[i].sid         = dcache_req_sid_i,
                   hwpf_stride_arb_in_req[i].tid         = hpdcache_req_tid_t'(i),
                   hwpf_stride_arb_in_req[i].need_rsp    = hwpf_stride_req[i].need_rsp;
        end
    endgenerate
    //  }}}

    //  Hardware prefetcher arbiter betweem engines
    //  {{{
    hwpf_stride_arb #(
        .NUM_HW_PREFETCH          ( NUM_HW_PREFETCH )
    ) hwpf_stride_arb_i (
        .clk_i,
        .rst_ni,

        // DCache input interface
        .hwpf_stride_req_valid_i  ( hwpf_stride_arb_in_req_valid ),
        .hwpf_stride_req_ready_o  ( hwpf_stride_arb_in_req_ready ),
        .hwpf_stride_req_i        ( hwpf_stride_arb_in_req ),
        .hwpf_stride_rsp_valid_o  ( hwpf_stride_arb_in_rsp_valid ),
        .hwpf_stride_rsp_o        ( hwpf_stride_arb_in_rsp ),

        // DCache output interface
        .dcache_req_valid_o,
        .dcache_req_ready_i,
        .dcache_req_o,
        .dcache_rsp_valid_i,
        .dcache_rsp_i
    );
    //  }}}

endmodule
