`ifdef DIRECTMAPI
module L2Icache(
    clk,
    reset,
    i_l1_read,
    i_l1_write,
    i_l1_addr,
    i_l1_wdata,
    o_l1_ready,
    o_l1_rdata,
    o_m_read,
    o_m_write,
    o_m_addr,
    i_m_rdata,
    o_m_wdata,
    i_m_ready,
    cnt_r,
    cnt_w,
    cnt_hit_r,
    cnt_hit_w,
    cnt_wb_r,
    cnt_wb_w
);
    function integer clogb2;
        input [31:0] value;
        integer     i;
        begin
            clogb2 = 0;
            for(i = 0; 2**i < value; i = i + 1)
                clogb2 = i + 1;
        end
    endfunction
//==== parameter definition ===============================
    parameter      WORD_WIDTH = 128;
    parameter      WORD_NUM = 1;
    `ifdef L2SIZE_32
    parameter      CACHE_SIZE = 32;
    `elsif L2SIZE_64
    parameter      CACHE_SIZE = 64;
    `elsif L2SIZE_128
    parameter      CACHE_SIZE = 128;
    `elsif L2SIZE_256
    parameter      CACHE_SIZE = 256;
    `else
    parameter      CACHE_SIZE = 256;
    `endif
    parameter      BLOCK_NUM = CACHE_SIZE/4;
    parameter      ENTRY_LEN = clogb2(BLOCK_NUM);
//==== input/output definition ============================
    input          clk;
    // processor interface
    input                       reset;
    input                       i_l1_read, i_l1_write;
    input   [27:0]              i_l1_addr;
    input   [WORD_WIDTH-1:0]    i_l1_wdata;
    output                      o_l1_ready;
    output  [WORD_WIDTH-1:0]    o_l1_rdata;
    // memory interface
    input  [WORD_WIDTH-1:0] i_m_rdata;
    input                   i_m_ready;
    output                  o_m_read, o_m_write;
    output [27:0]           o_m_addr;
    output [WORD_WIDTH-1:0] o_m_wdata;


    output [31:0]        cnt_r;
    output [31:0]        cnt_w;
    output [31:0]        cnt_hit_r;
    output [31:0]        cnt_hit_w;
    output [31:0]        cnt_wb_r;
    output [31:0]        cnt_wb_w;
//==== wire/reg definition ================================
    //==== memory related register ====//
    reg                             o_l1_ready;
    reg     [WORD_WIDTH-1:0]        o_l1_rdata;
    reg                             o_m_read, o_m_write;
    reg     [27:0]                  o_m_addr;
    //==== cache related register ====//  _next: buffer for next clk posedge
    reg                         hit;
    reg     [BLOCK_NUM-1:0]     valid_bits;
    reg                         valid_bits_next;
    reg     [BLOCK_NUM-1:0]     dirty_bits; 
    reg                         dirty_bits_next;
    reg     [27-ENTRY_LEN:0]    tag_field[BLOCK_NUM-1:0]; 
    reg     [27-ENTRY_LEN:0]    tag_field_next;
    reg     [WORD_WIDTH-1:0]    Cache_data[BLOCK_NUM-1:0];      
    reg     [WORD_WIDTH-1:0]    Cache_data_next;  
    //==== wires ====//
    wire                        valid_bit, dirty_bit;
    wire    [ENTRY_LEN-1:0]     index;
    wire    [27-ENTRY_LEN:0]    tag, current_tag;

    integer        i;
//==== combinational circuit ==============================
    assign index            = i_l1_addr[ENTRY_LEN-1:0];   // 8 block in cache unit
    assign tag              = i_l1_addr[27:ENTRY_LEN];    // remain bits in address

    assign o_m_wdata        = Cache_data[index];
//==== sequential circuit =================================
always@( posedge clk or posedge reset ) begin
    if ( reset ) begin
        for (i=0; i<BLOCK_NUM-1; i=i+1) begin
            {tag_field[i],Cache_data[i]} <= 0;
        end
        o_l1_ready <= 0;
        o_l1_rdata <= 0;
        valid_bits <= 0;
        dirty_bits <= 0;
    end
    else begin
        // $display("o_m_addr: ", o_m_addr, "i_l1_addr: ", i_l1_addr[29:2]);
        // $display("i_m_ready: ", i_m_ready, " hit:", hit);
        o_l1_ready <= (i_l1_read|i_l1_write)?(hit)? 1'b1 : 1'b0 : 1'b0;
        o_l1_rdata <= Cache_data[index];
        Cache_data[index] <= Cache_data_next;
        valid_bits[index] <= valid_bits_next;
        dirty_bits[index] <= dirty_bits_next;
        tag_field[index] <= tag_field_next;
        /*
        $display("-----------------------------");
        $display(" hit: ", hit);
        $display(" i_l1_addr: ", i_l1_addr);
        $display(" o_m_read: ", o_m_read);
        $display(" i_m_rdata: ", i_m_rdata[127:96],i_m_rdata[95:64],i_m_rdata[63:32],i_m_rdata[31:0]);
        $display(" o_l1_rdata: ", o_l1_rdata[127:96],o_l1_rdata[95:64],o_l1_rdata[63:32],o_l1_rdata[31:0]);
        $display("-----------------------------");
        */
    end
end

always@( * ) begin
    // default value
    {valid_bits_next,dirty_bits_next,tag_field_next} = 
    {valid_bits[index],dirty_bits[index],tag_field[index]};
    Cache_data_next = Cache_data[index];
    o_m_addr = 0;
    o_m_read = 1'b0;
    o_m_write = 1'b0;
    hit = (valid_bits[index] & (tag_field[index] == tag));
    if ( ~hit & (i_l1_read^i_l1_write) ) begin
        // If dirty, write back 
        if ( dirty_bits[index] & valid_bits[index] ) begin
            // Wait for data from memory 
            if ( ~i_m_ready ) begin
                o_m_addr = {tag_field[index],index};
                // o_m_read = 0;
                o_m_write = 1'b1;
            end
            else begin
                dirty_bits_next = 1'b0;
            end
        end
        // Not dirty, read from memory 
        else begin
            if ( ~i_m_ready )begin
                o_m_addr = i_l1_addr;
                o_m_read = 1'b1;
                // o_m_write = 0;
            end
            // Data from memory is ready, write data into cache 
            else begin
                // o_m_addr = 0;
                // o_m_read = 0;
                // o_m_write = 0;
                Cache_data_next = i_m_rdata;
                tag_field_next = tag;
                valid_bits_next = 1'b1;
                dirty_bits_next = 1'b0;
            end
        end
    end
    else if ( hit & i_l1_write & ~i_l1_read) begin
        dirty_bits_next = 1'b1;
        Cache_data_next = i_l1_wdata;
    end
end
endmodule


`elsif L2_I_2way
module L2Icache(clk,                                             // clk
               reset,                                           // proc_reset
               i_l1_read,                                       // proc_read
               i_l1_write,                                      // proc_write
               i_l1_addr,           // 28 bits (block address)  // proc_addr
               i_l1_wdata,          // 128 bits (4 words)       // proc_wdata
               o_l1_ready,                                      // proc_ready
               o_l1_rdata,          // 128 bits (4 words)       // proc_rdata                   

               o_m_read,                                        // mem_read
               o_m_write,                                       // mem_write
               o_m_addr,            // 28 bits (block address)  // mem_addr
               i_m_rdata,           // 128 bits (4 words)       // mem_rdata    
               o_m_wdata,           // 128 bits (4 words)       // mem_wdata              
               i_m_ready,                                       // mem_ready

               // some counters to record the usage of r/w operation
               cnt_r,
               cnt_w,
               cnt_hit_r,
               cnt_hit_w,
               cnt_wb_r,
               cnt_wb_w);

    function integer clogb2;
    input [31:0] value;
    integer     i;
    begin
        clogb2 = 0;
        for(i = 0; 2**i < value; i = i + 1)
            clogb2 = i + 1;
    end
    endfunction
    //...................................................................//
    parameter way_num       = 2;
    parameter way_len       = clogb2(way_num);
    
    parameter block_num     = 1;
    parameter block_offset  = clogb2(block_num);
    
    parameter word_len      = 32;
    parameter word_num_in_block = 4;                // number of words in one block
    parameter block_len     = word_num_in_block*word_len;
    
    // address total 28 bits
    // |remain bits for tag|log(cache_entry) bits for index/entry|
    parameter l1_addr_len   = 28;
    parameter mem_addr_len  = l1_addr_len - block_offset;
    //...................................................................//
    `ifdef L2SIZE_32
    parameter cache_size    = 32;
    `elsif L2SIZE_64
    parameter cache_size    = 64;                  // number of words contained in cache
    `elsif L2SIZE_128
    parameter cache_size    = 128;
    `elsif L2SIZE_256
    parameter cache_size    = 256;
    `else
    parameter cache_size    = 256;
    `endif
    parameter cache_entry   = cache_size/(word_num_in_block*way_num);           
    parameter entry_len     = clogb2(cache_entry);  // cache entry: number of index

    integer   i;

    input wire                      clk, reset;
    input wire  [l1_addr_len-1:0]   i_l1_addr;
    input wire  [block_len-1:0]     i_l1_wdata;
    input wire                      i_l1_read, i_l1_write;
    output reg                      o_l1_ready;
    reg                             o_l1_ready_next;
    output wire [block_len-1:0]     o_l1_rdata;

    // @param o_l1_rdata_ways: Read data from each way inferred by cache entry 
    wire        [block_len-1:0]     o_l1_rdata_ways[way_num-1:0];

    output reg  [mem_addr_len-1:0]  o_m_addr;
    output wire [block_len-1:0]     o_m_wdata;
    output reg                      o_m_read, o_m_write;
    input wire  [block_len-1:0]     i_m_rdata;
    input wire                      i_m_ready;

    `ifdef SET_COUNTER
    output reg [31:0]   cnt_r;
    output reg [31:0]   cnt_w;
    output reg [31:0]   cnt_hit_r;
    output reg [31:0]   cnt_hit_w;
    output reg [31:0]   cnt_wb_r;
    output reg [31:0]   cnt_wb_w;
    `else 
    output wire [31:0]  cnt_r;
    output wire [31:0]  cnt_w;
    output wire [31:0]  cnt_hit_r;
    output wire [31:0]  cnt_hit_w;
    output wire [31:0]  cnt_wb_r;
    output wire [31:0]  cnt_wb_w;
    `endif

    // wires about the information of current data //
    wire [way_num-1:0]                  hit;        // At any time, there may be many bits turn on for hit 
    wire [way_num-1:0]                  modify;     // Whether the data needed to be written back
    wire [way_num-1:0]                  miss;       // Whether r/w miss occur, but no need to write back (dirty bit is 0)
    wire [way_num-1:0]                  valid;      // Valid bit for cache entry in each way
    wire [way_len-1:0]                  hit_way;    // determine which way is hit
    // wires about the read write operation //
    wire [block_len-1:0]                readdata[way_num-1:0];  // readdata (not blocked, directly read from reg)
    wire [block_len-1:0]                writedata;              // writedata, change current data in cache
    wire [way_num-1:0]                  write;
    wire [block_num-1:0]                block_en;               // not used in this file, determine which block is to be written 
    
    wire [l1_addr_len-1:0]              wb_addr[way_num-1:0];   // address to write back for each way (choose 1 from ways)
    wire                                r_cm_data;      // read out the priority list from register
    
    // registers about next state signal or data
    reg  [1:0]                          state;          // finite state machine
    reg  [1:0]                          state_next;     // store the next state to go
    reg                                 w_cm_data;      // store the new priority list for next clock (LRU unit)
    reg                                 w_cm;           // write signal for LRU register/unit
    reg  [way_num-1:0]                  write_set_next, write_set;
    reg  [way_num-1:0]                  fetch_write_next, fetch_write;  // determine which way to write back data from memory
    // registers for buffer
    reg  [l1_addr_len-1:0]              l1_addr_buf;    // buffer for input signal
    reg                                 write_buf, read_buf;
    reg  [block_num*block_len-1:0]      writedata_buf;  
        

    localparam IDLE = 0;
    localparam COMP = 1;
    localparam FETCH = 2;
    localparam WB = 3;

    /* the interface of simple ram */
    /* simple_ram(clk, reset, writeaddr, write, wdata, readaddr, rdata) */
    L2simple_ram #(.width(1), .widthad(entry_len)) lru_field 
                (clk, reset, l1_addr_buf[entry_len-1:0], w_cm, w_cm_data, l1_addr_buf[entry_len-1:0], r_cm_data);
    /* instances of set */
    generate
        genvar k;
        for (k=0; k<way_num; k=k+1)  begin : cache_set
            L2cache_set #(.entry_len(entry_len),
                        .block_offset(block_offset),
                        .block_len(block_len),
                        .l1_addr_len(l1_addr_len)) cache_set
                       (.clk(clk),
                        .rst(reset),
                        .entry(l1_addr_buf[entry_len-1:0]),
                        .o_tag(l1_addr_buf[l1_addr_len-1:entry_len]),
                        .writedata(writedata),              // data needed to be written (block_len)
                        .write(write[k]),                   // write enable signal
                        .block_en(block_en),                // each block change or not
                        .readdata(readdata[k]),             // data needed to be read (block_len)
                        .wb_addr(wb_addr[k]),               // indicate which block is needed to write back
                                                            // width: l1_addr_len
                        .hit(hit[k]),
                        .modify(modify[k]),                 // modify
                        .miss(miss[k]),                     // miss
                        .valid(valid[k]),                   // valid
                        .read_miss(read_buf));              // read_miss
        end
    endgenerate
    // the priority of read data from memory is higher than read data from l1 cache
    // first fetch data from memory then modify the data by i_l1_wdata
    assign writedata = (|fetch_write) ? i_m_rdata : i_l1_wdata;           // 128bit
    
    // i_m_ready: means the data from memory is what we requested and valid, we can write back
    // write_set_next[i] = 1 means write operation is required for ith way
    // write_set_next determine the signal source for write operation
    generate
        genvar t;
        for (t=0; t<way_num; t=t+1) begin : write_signal
            assign write[t] = (fetch_write[t]) ? i_m_ready : write_set[t];
            assign o_l1_rdata_ways[t] = readdata[t];
        end
    endgenerate
    
    assign addr = (o_l1_ready) ? i_l1_addr[l1_addr_len-1:0] : l1_addr_buf[l1_addr_len-1:0]; 
    // assign addr = l1_addr_buf;
    
    /*** warning: if more way we need to modify hit_way ***/
    assign block_en = 1'b1;
    /*
    assign block_en = (|fetch_write_next) ? 4'b1111 : 
                      (l1_addr_buf[block_offset-1:0] == 2'b00) ? 4'b0001 :
                      (l1_addr_buf[block_offset-1:0] == 2'b01) ? 4'b0010 :
                      (l1_addr_buf[block_offset-1:0] == 2'b10) ? 4'b0100 : 4'b1000;
    */
    assign hit_way = (hit[0]) ? 1'b0 : 1'b1;

    /*** warning: if more way we need to modify 
    wire [block_offset-1:0] b_offset;
    assign b_offset = l1_addr_buf[block_offset-1:0];
    for (i=0; i<way_num; i=i+1) begin
        assign o_l1_rdata_ways[i] = (b_offset == 2'b00) ? readdata[i][block_len-1:0] :
                                    (b_offset == 2'b01) ? readdata[i][block_len*2-1:block_len] :
                                    (b_offset == 2'b10) ? readdata[i][block_len*3-1:block_len*2] : 
                                                          readdata[i][block_len*4-1:block_len*3];
    end
    ***/

    /* output port for l2cache module */
    assign o_l1_rdata = (hit[0]) ? o_l1_rdata_ways[0] : 
                        (hit[1]) ? o_l1_rdata_ways[1] : 0;
    assign o_m_wdata  = (fetch_write[0]) ? readdata[0] : 
                        (fetch_write[1]) ? readdata[1] : 0;
    
    /* w_cm_data determination */
    wire [way_len*way_num-1:0] w_cm_data_source;
    assign w_cm_data_source =  ~hit_way;
    
    always @( * ) begin
        `ifdef SET_COUNTER
        if (reset) begin
            {cnt_r, cnt_w} = 0;
            {cnt_hit_r, cnt_hit_w} = 0;
            {cnt_wb_r, cnt_wb_w} = 0;
        end
        else begin
            {cnt_r, cnt_w} = {cnt_r, cnt_w};
            {cnt_hit_r, cnt_hit_w} = {cnt_hit_r, cnt_hit_w};
            {cnt_wb_r, cnt_wb_w} = {cnt_wb_r, cnt_wb_w};
        end
        `endif
        o_l1_ready_next = 1'b0;
        o_m_read = 1'b0;
        o_m_write = 1'b0;
        o_m_addr = 0;
        w_cm = 1'b0;
        w_cm_data = 0;
        write_set_next = 0;
        fetch_write_next = 0;
        state_next = IDLE;
        case(state)
            /* IDLE(redundant): nothing done, waiting for read/write instructions */
            IDLE:
                begin
                    if ( read_buf^write_buf ) begin
                        state_next = COMP;
                        // write_set_next = 0;
                        // fetch_write_next = 0;
                    end
                    else begin
                        state_next = IDLE;
                        // write_set_next = 0;
                        // fetch_write_next = 0;
                    end

                end
            /* COMPARE_TAG: check whether hit or not */
            COMP:
                begin
                    `ifdef SET_COUNTER
                    if ( read_buf )
                        cnt_r = cnt_r + 1;
                    else if ( write_buf )
                        cnt_w = cnt_w + 1;
                    `endif                  
                    /*** warning: if more way we need to modify ***/
                     // LRU register need to update, set w_cm to true
                    w_cm = 1'b1;
                    w_cm_data = w_cm_data_source;
                    
                    if (~(read_buf | write_buf)) begin
                        state_next = COMP;
                        w_cm = 1'b0;
                    end
                    else if ( (|hit) & write_buf ) begin
                        `ifdef SET_COUNTER
                        cnt_hit_w = cnt_hit_w + 1;
                        `endif
                        // write signal for ith way set to 1 if hit occur
                        if (o_l1_ready)
                            o_l1_ready_next = 1'b0;
                        else
                            o_l1_ready_next = 1'b1;
                        write_set_next = hit;
                        state_next = COMP;
                        // w_cm = 1;        
                    end
                    else if ( (|hit) & read_buf ) begin
                        `ifdef SET_COUNTER
                        cnt_hit_r <= cnt_hit_r + 1;
                        `endif
                        if (o_l1_ready)
                            o_l1_ready_next = 1'b0;
                        else
                            o_l1_ready_next = 1'b1; 
                        state_next = COMP;
                        // w_cm = 1;            
                    end
                    // if there is any block not valid, first write data to that block
                    // if all blocks are valid, fetch block that is less recent accessed
                    else if(!(&valid) | miss[r_cm_data]) begin
                        state_next = FETCH;
                        /*** warning: if more way we need to modify the number of if***/
                        if(!valid[0]) begin
                            fetch_write_next = 2'b01;
                            w_cm_data = 1'b1;
                            // w_cm = 1;
                        end 
                        else if(!valid[1]) begin
                            fetch_write_next = 2'b10;
                            w_cm_data = 1'b0;
                            // w_cm = 1;
                        end 
                        /*** warning: if more way we need to modify the number of bit ***/
                        else if(miss[r_cm_data]) begin
                            if(r_cm_data == 1'b0) begin
                                fetch_write_next = 2'b01;
                                w_cm_data = 1'b1;
                            end
                            else if(r_cm_data == 1'b1) begin
                                fetch_write_next = 2'b10;
                                w_cm_data = 1'b0;
                                // w_cm = 1;
                            end
                        end
                        o_m_addr = l1_addr_buf;
                        o_m_read = 1'b1;
                    end
                    else if (modify[r_cm_data]) begin
                        `ifdef SET_COUNTER
                        if(read_buf) cnt_wb_r = cnt_wb_r + 1;
                        else if(write_buf) cnt_wb_w = cnt_wb_w + 1;
                        `endif
                        state_next = WB;
                        /*** warning: if more way we need to modify the number of bit ***/
                        if(r_cm_data == 1'b0) begin
                            fetch_write_next = 2'b01;
                            w_cm_data = 1'b1;
                        end
                        else if(r_cm_data == 1'b1) begin
                            fetch_write_next = 2'b10;
                            w_cm_data = 1'b0;
                        end
                        // w_cm = 1;
                        o_m_addr = (fetch_write_next[0]) ? wb_addr[0] : wb_addr[1] ;
                        o_m_write = 1'b1;
                    end
                    else begin
                        state_next = IDLE;
                    end
                end
            FETCH:
                begin
                    if ( i_m_ready ) begin
                        if( write_buf ) begin
                            state_next = COMP;
                            write_set_next = fetch_write;
                        end 
                        else if( read_buf ) begin
                            state_next = COMP;
                            // fetch_write_next = fetch_write;
                        end
                    end
                    else begin
                        state_next = FETCH;
                        fetch_write_next = fetch_write;
                        o_m_addr = l1_addr_buf;
                        o_m_read = 1'b1;
                    end
                end
            WB:
                begin
                    if ( i_m_ready ) begin
                        state_next = FETCH;
                        // o_m_write = 1'b0;
                        o_m_read = 1'b1;
                        o_m_addr = l1_addr_buf;
                        fetch_write_next = fetch_write;
                    end
                    else begin
                        state_next = WB;
                        // w_cm = 0;
                        /*** warning:  ***/
                        o_m_addr =  (fetch_write[0]) ? wb_addr[0] : wb_addr[1];
                        o_m_write = 1'b1;
                        fetch_write_next = fetch_write;
                    end     
                end
            default:
                state_next = IDLE;
        endcase
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fetch_write <= 0;
            write_set <= 0;
        end
        else begin
            fetch_write <= fetch_write_next;
            write_set <= write_set_next;
            if (i_l1_addr != l1_addr_buf) begin
                // TO find the begin of an operation
                // $display(" NEW operation......");
            end
        end
    end
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            o_l1_ready <= 0;
            l1_addr_buf <= 0;
            writedata_buf <= 0;
            {write_buf, read_buf} <= 0;     
            state <= IDLE;
        end
        else begin
            if (|hit)
                o_l1_ready <= o_l1_ready_next;
            else
                o_l1_ready <= 0;
            read_buf <= i_l1_read;
            write_buf <= i_l1_write;
            writedata_buf <= {block_num{i_l1_wdata}};
            
            
            if (state == COMP & (write_buf|read_buf)) begin
                l1_addr_buf <= l1_addr_buf;
            end
            else begin
                l1_addr_buf <= i_l1_addr;
            end
            state <= state_next;
            /*
            $display(".............................");
            $display(" state: %d", state);
            $display(" state_next: %d", state_next);
            //$display(" i_l1_read: ", i_l1_read, read_buf);
            $display(" mem_ready: %d", i_m_ready);
            $display(" hit: %b", hit);
            $display(" valid: %b", valid);
            
            $display(" write_set_next: %b, fetch_write_next %b, write %b", write_set_next, fetch_write_next, write);
            $display(" addr: ", addr, i_l1_addr, o_m_addr);
            $display(" l1_addr_buf: ", l1_addr_buf);
            $display(readdata[0][31:0],readdata[0][63:32],readdata[0][95:64],readdata[0][127:96]); 
            $display(readdata[1][31:0],readdata[1][63:32],readdata[1][95:64],readdata[1][127:96]);
            $display(" i_m_rdata: ", i_m_rdata[31:0], i_m_rdata[63:32], i_m_rdata[95:64], i_m_rdata[127:96]);
            $display(" i_l1_wdata: ", i_l1_wdata[31:0], i_l1_wdata[63:32], i_l1_wdata[95:64], i_l1_wdata[127:96]);
            $display(" writedata: ", writedata[31:0], writedata[63:32], writedata[95:64], writedata[127:96]);
            $display(".............................");
            */
        end
    end

endmodule
`elsif L2_I_4way
// Cache Memory (4way 4words)               //
// i_   means input port                    //
// o_   means output port                   //
// _l1_ means data exchange with processor  //
// _m_  means data exchange with memory     //
// Replacement policy is LRU (8bit)         //
module L2Icache(clk,                                             // clk
               reset,                                           // proc_reset
               i_l1_read,                                       // proc_read
               i_l1_write,                                      // proc_write
               i_l1_addr,           // 28 bits (block address)  // proc_addr
               i_l1_wdata,          // 128 bits (4 words)       // proc_wdata
               o_l1_ready,                                      // proc_ready
               o_l1_rdata,          // 128 bits (4 words)       // proc_rdata                   

               o_m_read,                                        // mem_read
               o_m_write,                                       // mem_write
               o_m_addr,            // 28 bits (block address)  // mem_addr
               i_m_rdata,           // 128 bits (4 words)       // mem_rdata    
               o_m_wdata,           // 128 bits (4 words)       // mem_wdata              
               i_m_ready,                                       // mem_ready

               // some counters to record the usage of r/w operation
               cnt_r,
               cnt_w,
               cnt_hit_r,
               cnt_hit_w,
               cnt_wb_r,
               cnt_wb_w);

    function integer clogb2;
    input [31:0] value;
    integer     i;
    begin
        clogb2 = 0;
        for(i = 0; 2**i < value; i = i + 1)
            clogb2 = i + 1;
    end
    endfunction
    //...................................................................//
    parameter way_num       = 4;
    parameter way_len       = clogb2(way_num);
    
    parameter block_num     = 1;
    parameter block_offset  = clogb2(block_num);
    
    parameter word_len      = 32;
    parameter word_num_in_block = 4;                // number of words in one block
    parameter block_len     = word_num_in_block*word_len;
    
    // address total 28 bits
    // |remain bits for tag|log(cache_entry) bits for index/entry|
    parameter l1_addr_len   = 28;
    parameter mem_addr_len  = l1_addr_len - block_offset;
    //...................................................................//
    `ifdef L2SIZE_32
    parameter cache_size    = 32;
    `elsif L2SIZE_64
    parameter cache_size    = 64;                  // number of words contained in cache
    `elsif L2SIZE_128
    parameter cache_size    = 128;
    `elsif L2SIZE_256
    parameter cache_size    = 256;
    `else
    parameter cache_size    = 256;
    `endif
    parameter cache_entry   = cache_size/(word_num_in_block*way_num);           
    parameter entry_len     = clogb2(cache_entry);  // cache entry: number of index

    integer   i;

    input wire                      clk, reset;
    input wire  [l1_addr_len-1:0]   i_l1_addr;
    input wire  [block_len-1:0]     i_l1_wdata;
    input wire                      i_l1_read, i_l1_write;
    output reg                      o_l1_ready;
    reg                             o_l1_ready_next;
    output wire [block_len-1:0]     o_l1_rdata;

    // @param o_l1_rdata_ways: Read data from each way inferred by cache entry 
    wire        [block_len-1:0]     o_l1_rdata_ways[way_num-1:0];

    output reg  [mem_addr_len-1:0]  o_m_addr;
    output wire [block_len-1:0]     o_m_wdata;
    output reg                      o_m_read, o_m_write;
    input wire  [block_len-1:0]     i_m_rdata;
    input wire                      i_m_ready;

    `ifdef SET_COUNTER
    output reg [31:0]   cnt_r;
    output reg [31:0]   cnt_w;
    output reg [31:0]   cnt_hit_r;
    output reg [31:0]   cnt_hit_w;
    output reg [31:0]   cnt_wb_r;
    output reg [31:0]   cnt_wb_w;
    `else 
    output wire [31:0]  cnt_r;
    output wire [31:0]  cnt_w;
    output wire [31:0]  cnt_hit_r;
    output wire [31:0]  cnt_hit_w;
    output wire [31:0]  cnt_wb_r;
    output wire [31:0]  cnt_wb_w;
    `endif

    // wires about the information of current data //
    wire [way_num-1:0]                  hit;        // At any time, there may be many bits turn on for hit 
    wire [way_num-1:0]                  modify;     // Whether the data needed to be written back
    wire [way_num-1:0]                  miss;       // Whether r/w miss occur, but no need to write back (dirty bit is 0)
    wire [way_num-1:0]                  valid;      // Valid bit for cache entry in each way
    wire [way_len-1:0]                  hit_way;    // determine which way is hit
    // wires about the read write operation //
    wire [block_len-1:0]                readdata[way_num-1:0];  // readdata (not blocked, directly read from reg)
    wire [block_len-1:0]                writedata;              // writedata, change current data in cache
    wire [way_num-1:0]                  write;
    wire [block_num-1:0]                block_en;               // not used in this file, determine which block is to be written 
    
    wire [l1_addr_len-1:0]              wb_addr[way_num-1:0];   // address to write back for each way (choose 1 from ways)
    wire [way_len*way_num-1:0]          r_cm_data;      // read out the priority list from register
    
    // registers about next state signal or data
    reg  [1:0]                          state;          // finite state machine
    reg  [1:0]                          state_next;     // store the next state to go
    reg  [way_len*way_num-1:0]          w_cm_data;      // store the new priority list for next clock (LRU unit)
    reg                                 w_cm;           // write signal for LRU register/unit
    reg  [way_num-1:0]                  write_set_next, write_set;
    reg  [way_num-1:0]                  fetch_write_next, fetch_write;  // determine which way to write back data from memory
    // registers for buffer
    reg  [l1_addr_len-1:0]              l1_addr_buf, addr_next, addr_buf;   // buffer for input signal
    reg                                 write_buf, read_buf;
    reg  [block_num*block_len-1:0]      writedata_buf;  
        

    localparam IDLE = 0;
    localparam COMP = 1;
    localparam FETCH = 2;
    localparam WB = 3;

    /* the interface of simple ram */
    /* simple_ram(clk, reset, writeaddr, write, wdata, readaddr, rdata) */
    L2simple_ram #(.width(way_len*way_num), .widthad(entry_len)) lru_field 
                (clk, reset, l1_addr_buf[entry_len-1:0], w_cm, w_cm_data, l1_addr_buf[entry_len-1:0], r_cm_data);
    /* instances of set */
    generate
        genvar k;
        for (k=0; k<way_num; k=k+1)  begin : cache_set
            L2cache_set #(.entry_len(entry_len),
                        .block_offset(block_offset),
                        .block_len(block_len),
                        .l1_addr_len(l1_addr_len)) cache_set
                       (.clk(clk),
                        .rst(reset),
                        .entry(l1_addr_buf[entry_len-1:0]),
                        .o_tag(l1_addr_buf[l1_addr_len-1:entry_len]),
                        .writedata(writedata),              // data needed to be written (block_len)
                        .write(write[k]),                   // write enable signal
                        .block_en(block_en),                // each block change or not
                        .readdata(readdata[k]),             // data needed to be read (block_len)
                        .wb_addr(wb_addr[k]),               // indicate which block is needed to write back
                                                            // width: l1_addr_len
                        .hit(hit[k]),
                        .modify(modify[k]),                 // modify
                        .miss(miss[k]),                     // miss
                        .valid(valid[k]),                   // valid
                        .read_miss(read_buf));              // read_miss
        end
    endgenerate
    // the priority of read data from memory is higher than read data from l1 cache
    // first fetch data from memory then modify the data by i_l1_wdata
    assign writedata = (|fetch_write) ? i_m_rdata : i_l1_wdata;           // 128bit
    
    // i_m_ready: means the data from memory is what we requested and valid, we can write back
    // write_set_next[i] = 1 means write operation is required for ith way
    // write_set_next determine the signal source for write operation
    generate
        genvar t;
        for (t=0; t<way_num; t=t+1) begin : write_signal
            assign write[t] = (fetch_write[t]) ? i_m_ready : write_set[t];
            assign o_l1_rdata_ways[t] = readdata[t];
        end
    endgenerate
    
    assign addr = (o_l1_ready) ? i_l1_addr[l1_addr_len-1:0] : l1_addr_buf[l1_addr_len-1:0]; 
    // assign addr = l1_addr_buf;
    
    /*** warning: if more way we need to modify hit_way ***/
    assign block_en = 1'b1;
    /*
    assign block_en = (|fetch_write_next) ? 4'b1111 : 
                      (l1_addr_buf[block_offset-1:0] == 2'b00) ? 4'b0001 :
                      (l1_addr_buf[block_offset-1:0] == 2'b01) ? 4'b0010 :
                      (l1_addr_buf[block_offset-1:0] == 2'b10) ? 4'b0100 : 4'b1000;
    */
    assign hit_way = (hit[0]) ? 2'b0 : (hit[1]) ? 2'b01 : (hit[2]) ? 2'b10 : 2'b11;

    /*** warning: if more way we need to modify 
    wire [block_offset-1:0] b_offset;
    assign b_offset = l1_addr_buf[block_offset-1:0];
    for (i=0; i<way_num; i=i+1) begin
        assign o_l1_rdata_ways[i] = (b_offset == 2'b00) ? readdata[i][block_len-1:0] :
                                    (b_offset == 2'b01) ? readdata[i][block_len*2-1:block_len] :
                                    (b_offset == 2'b10) ? readdata[i][block_len*3-1:block_len*2] : 
                                                          readdata[i][block_len*4-1:block_len*3];
    end
    ***/

    /* output port for l2cache module */
    assign o_l1_rdata = (hit[0]) ? o_l1_rdata_ways[0] : 
                        (hit[1]) ? o_l1_rdata_ways[1] : 
                        (hit[2]) ? o_l1_rdata_ways[2] : 
                        (hit[3]) ? o_l1_rdata_ways[3] : 0;
    assign o_m_wdata  = (fetch_write[0]) ? readdata[0] : 
                        (fetch_write[1]) ? readdata[1] : 
                        (fetch_write[2]) ? readdata[2] : 
                        (fetch_write[3]) ? readdata[3] : 1;
    
    /* w_cm_data determination */
    wire [way_len*way_num-1:0] w_cm_data_source[way_num-1:0];
    assign w_cm_data_source[0] = (r_cm_data[1:0] == hit_way) ? {r_cm_data[1:0], r_cm_data[7:2]} :
                                 (r_cm_data[3:2] == hit_way) ? {r_cm_data[3:2], r_cm_data[7:4], r_cm_data[1:0]} :
                                 (r_cm_data[5:4] == hit_way) ? {r_cm_data[5:4], r_cm_data[7:6], r_cm_data[3:0]} : r_cm_data;
    assign w_cm_data_source[1] = (r_cm_data[1:0] == 2'b01) ? {r_cm_data[1:0], r_cm_data[7:2]} :
                                 (r_cm_data[3:2] == 2'b01) ? {r_cm_data[3:2], r_cm_data[7:4], r_cm_data[1:0]} :
                                 (r_cm_data[5:4] == 2'b01) ? {r_cm_data[5:4], r_cm_data[7:6], r_cm_data[3:0]} : r_cm_data;
    assign w_cm_data_source[2] = (r_cm_data[1:0] == 2'b10) ? {r_cm_data[1:0], r_cm_data[7:2]} :
                                 (r_cm_data[3:2] == 2'b10) ? {r_cm_data[3:2], r_cm_data[7:4], r_cm_data[1:0]} :
                                 (r_cm_data[5:4] == 2'b10) ? {r_cm_data[5:4], r_cm_data[7:6], r_cm_data[3:0]} : r_cm_data;
    assign w_cm_data_source[3] = (r_cm_data[1:0] == 2'b11) ? {r_cm_data[1:0], r_cm_data[7:2]} :
                                 (r_cm_data[3:2] == 2'b11) ? {r_cm_data[3:2], r_cm_data[7:4], r_cm_data[1:0]} :
                                 (r_cm_data[5:4] == 2'b11) ? {r_cm_data[5:4], r_cm_data[7:6], r_cm_data[3:0]} : r_cm_data;

    
    
    always @( * ) begin
        `ifdef SET_COUNTER
        if (reset) begin
            {cnt_r, cnt_w} = 0;
            {cnt_hit_r, cnt_hit_w} = 0;
            {cnt_wb_r, cnt_wb_w} = 0;
        end
        else begin
            {cnt_r, cnt_w} = {cnt_r, cnt_w};
            {cnt_hit_r, cnt_hit_w} = {cnt_hit_r, cnt_hit_w};
            {cnt_wb_r, cnt_wb_w} = {cnt_wb_r, cnt_wb_w};
        end
        `endif
        o_l1_ready_next = 1'b0;
        o_m_read = 1'b0;
        o_m_write = 1'b0;
        o_m_addr = 0;
        w_cm = 1'b0;
        w_cm_data = 0;
        write_set_next = 0;
        fetch_write_next = 0;
        addr_next = 0;
        state_next = IDLE;
        case(state)
            /* IDLE(redundant): nothing done, waiting for read/write instructions */
            IDLE:
                begin
                    if ( read_buf^write_buf ) begin
                        state_next = COMP;
                        addr_next = i_l1_addr;
                        // write_set_next = 0;
                        // fetch_write_next = 0;
                    end
                    else begin
                        state_next = IDLE;
                        // write_set_next = 0;
                        // fetch_write_next = 0;
                    end

                end
            /* COMPARE_TAG: check whether hit or not */
            COMP:
                begin
                    `ifdef SET_COUNTER
                    if ( read_buf )
                        cnt_r = cnt_r + 1;
                    else if ( write_buf )
                        cnt_w = cnt_w + 1;
                    `endif                  
                    /*** warning: if more way we need to modify ***/
                     // LRU register need to update, set w_cm to true
                    w_cm = 1'b1;
                    w_cm_data = w_cm_data_source[0];
                    
                    if (~(read_buf | write_buf)) begin
                        state_next = COMP;
                        addr_next = i_l1_addr;
                        w_cm = 1'b0;
                    end
                    else if ( (|hit) & write_buf ) begin
                        `ifdef SET_COUNTER
                        cnt_hit_w = cnt_hit_w + 1;
                        `endif
                        // write signal for ith way set to 1 if hit occur
                        if (o_l1_ready)
                            o_l1_ready_next = 1'b0;
                        else
                            o_l1_ready_next = 1'b1;
                        write_set_next = hit;
                        state_next = COMP;
                        addr_next = i_l1_addr;
                        // w_cm = 1;        
                    end
                    else if ( (|hit) & read_buf ) begin
                        `ifdef SET_COUNTER
                        cnt_hit_r <= cnt_hit_r + 1;
                        `endif
                        if (o_l1_ready)
                            o_l1_ready_next = 1'b0;
                        else
                            o_l1_ready_next = 1'b1; 
                        state_next = COMP;
                        addr_next = i_l1_addr;
                        // w_cm = 1;            
                    end
                    // if there is any block not valid, first write data to that block
                    // if all blocks are valid, fetch block that is less recent accessed
                    else if(!(&valid) | miss[r_cm_data[1:0]]) begin
                        state_next = FETCH;
                        addr_next = i_l1_addr;
                        /*** warning: if more way we need to modify the number of if***/
                        if(!valid[0]) begin
                            fetch_write_next = 4'b0001;
                            w_cm_data = 8'b00111001;
                            // w_cm = 1;
                        end 
                        else if(!valid[1]) begin
                            fetch_write_next = 4'b0010;
                            w_cm_data = 8'b01001110;
                            // w_cm = 1;
                        end 
                        else if(!valid[2]) begin
                            fetch_write_next = 4'b0100;
                            w_cm_data = w_cm_data_source[2];
                            // w_cm = 1;
                        end 
                        else if(!valid[3]) begin
                            fetch_write_next = 4'b1000;
                            w_cm_data = w_cm_data_source[3];
                            // w_cm = 1;
                        end
                        /*** warning: if more way we need to modify the number of bit ***/
                        else if(miss[r_cm_data[1:0]]) begin
                            if(r_cm_data[1:0] == 2'b00) fetch_write_next = 4'b0001;
                            else if(r_cm_data[1:0] == 2'b01) fetch_write_next = 4'b0010;
                            else if(r_cm_data[1:0] == 2'b10) fetch_write_next = 4'b0100;
                            else if(r_cm_data[1:0] == 2'b11) fetch_write_next = 4'b1000;
                            w_cm_data = {r_cm_data[1:0], r_cm_data[7:2]};
                            // w_cm = 1;
                        end
                        o_m_addr = l1_addr_buf;
                        o_m_read = 1'b1;
                    end
                    else if (modify[r_cm_data[1:0]]) begin
                        `ifdef SET_COUNTER
                        if(read_buf) cnt_wb_r = cnt_wb_r + 1;
                        else if(write_buf) cnt_wb_w = cnt_wb_w + 1;
                        `endif
                        state_next = WB;
                        addr_next = i_l1_addr;
                        /*** warning: if more way we need to modify the number of bit ***/
                        if(r_cm_data[1:0] == 2'b00) fetch_write_next = 4'b0001;
                        else if(r_cm_data[1:0] == 2'b01) fetch_write_next = 4'b0010;
                        else if(r_cm_data[1:0] == 2'b10) fetch_write_next = 4'b0100;
                        else if(r_cm_data[1:0] == 2'b11) fetch_write_next = 4'b1000;
                        w_cm_data = {r_cm_data[1:0], r_cm_data[7:2]};
                        // w_cm = 1;
                        o_m_addr =  (fetch_write_next[0]) ? wb_addr[0] :
                                    (fetch_write_next[1]) ? wb_addr[1] :
                                    (fetch_write_next[2]) ? wb_addr[2] : wb_addr[3];
                        o_m_write = 1'b1;
                    end
                    else begin
                        state_next = IDLE;
                    end
                end
            FETCH:
                begin
                    if ( i_m_ready ) begin
                        if( write_buf ) begin
                            state_next = COMP;
                            addr_next = addr_buf;
                            write_set_next = fetch_write;
                        end 
                        else if( read_buf ) begin
                            state_next = COMP;
                            addr_next = addr_buf;
                            // fetch_write_next = fetch_write;
                        end
                    end
                    else begin
                        state_next = FETCH;
                        addr_next = addr_buf;
                        fetch_write_next = fetch_write;
                        o_m_addr = l1_addr_buf;
                        o_m_read = 1'b1;
                    end
                end
            WB:
                begin
                    if ( i_m_ready ) begin
                        state_next = FETCH;
                        // o_m_write = 1'b0;
                        o_m_read = 1'b1;
                        o_m_addr = l1_addr_buf;
                        // o_m_addr = addr_buf;
                        fetch_write_next = fetch_write;
                    end
                    else begin
                        state_next = WB;
                        // w_cm = 0;
                        /*** warning:  ***/
                        o_m_addr =  (fetch_write[0]) ? wb_addr[0] :
                                    (fetch_write[1]) ? wb_addr[1] :
                                    (fetch_write[2]) ? wb_addr[2] : wb_addr[3];
                        o_m_write = 1'b1;
                        fetch_write_next = fetch_write;
                    end     
                end
            default:
                state_next = IDLE;
        endcase
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fetch_write <= 0;
            write_set <= 0;
        end
        else begin
            fetch_write <= fetch_write_next;
            write_set <= write_set_next;
            if (i_l1_addr != l1_addr_buf) begin
                // TO find the begin of an operation
                // $display(" NEW operation......");
            end
        end
    end
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            o_l1_ready <= 0;
            l1_addr_buf <= 0;
            writedata_buf <= 0;
            {write_buf, read_buf} <= 0;     
            addr_buf <= 0;
            state <= IDLE;
        end
        else begin
            if (|hit)
                o_l1_ready <= o_l1_ready_next;
            else
                o_l1_ready <= 0;
            read_buf <= i_l1_read;
            write_buf <= i_l1_write;
            writedata_buf <= {block_num{i_l1_wdata}};
            
            
            if (state == COMP & (write_buf|read_buf)) begin
                l1_addr_buf <= l1_addr_buf;
                addr_buf <= addr_buf;
            end
            else begin
                l1_addr_buf <= i_l1_addr;
                addr_buf <= addr_next;
            end
            state <= state_next;
            /*
            $display(".............................");
            $display(" state: %d", state);
            $display(" state_next: %d", state_next);
            //$display(" i_l1_read: ", i_l1_read, read_buf);
            $display(" mem_ready: %d", i_m_ready);
            $display(" hit: %b", hit);
            $display(" valid: %b", valid);
            
            $display(" write_set_next: %b, fetch_write_next %b, write %b", write_set_next, fetch_write_next, write);
            $display(" addr: ", addr, i_l1_addr, o_m_addr);
            $display(" l1_addr_buf: ", l1_addr_buf);
            $display(readdata[0][31:0],readdata[0][63:32],readdata[0][95:64],readdata[0][127:96]); 
            $display(readdata[1][31:0],readdata[1][63:32],readdata[1][95:64],readdata[1][127:96]);
            $display(readdata[2][31:0],readdata[2][63:32],readdata[2][95:64],readdata[2][127:96]); 
            $display(readdata[3][31:0],readdata[3][63:32],readdata[3][95:64],readdata[3][127:96]);
            $display(" i_m_rdata: ", i_m_rdata[31:0], i_m_rdata[63:32], i_m_rdata[95:64], i_m_rdata[127:96]);
            $display(" i_l1_wdata: ", i_l1_wdata[31:0], i_l1_wdata[63:32], i_l1_wdata[95:64], i_l1_wdata[127:96]);
            $display(" writedata: ", writedata[31:0], writedata[63:32], writedata[95:64], writedata[127:96]);
            $display(".............................");
            */
        end
    end

endmodule
`elsif L2_I_8way
module L2Icache(clk,                                             // clk
               reset,                                           // proc_reset
               i_l1_read,                                       // proc_read
               i_l1_write,                                      // proc_write
               i_l1_addr,           // 28 bits (block address)  // proc_addr
               i_l1_wdata,          // 128 bits (4 words)       // proc_wdata
               o_l1_ready,                                      // proc_ready
               o_l1_rdata,          // 128 bits (4 words)       // proc_rdata                   

               o_m_read,                                        // mem_read
               o_m_write,                                       // mem_write
               o_m_addr,            // 28 bits (block address)  // mem_addr
               i_m_rdata,           // 128 bits (4 words)       // mem_rdata    
               o_m_wdata,           // 128 bits (4 words)       // mem_wdata              
               i_m_ready,                                       // mem_ready

               // some counters to record the usage of r/w operation
               cnt_r,
               cnt_w,
               cnt_hit_r,
               cnt_hit_w,
               cnt_wb_r,
               cnt_wb_w);

    function integer clogb2;
    input [31:0] value;
    integer     i;
    begin
        clogb2 = 0;
        for(i = 0; 2**i < value; i = i + 1)
            clogb2 = i + 1;
    end
    endfunction
    //...................................................................//
    parameter way_num       = 8;
    parameter way_len       = clogb2(way_num);
    
    parameter block_num     = 1;
    parameter block_offset  = clogb2(block_num);
    
    parameter word_len      = 32;
    parameter word_num_in_block = 4;                // number of words in one block
    parameter block_len     = word_num_in_block*word_len;
    
    // address total 28 bits
    // |remain bits for tag|log(cache_entry) bits for index/entry|
    parameter l1_addr_len   = 28;
    parameter mem_addr_len  = l1_addr_len - block_offset;
    //...................................................................//
    `ifdef L2SIZE_32
    parameter cache_size    = 32;
    `elsif L2SIZE_64
    parameter cache_size    = 64;                  // number of words contained in cache
    `elsif L2SIZE_128
    parameter cache_size    = 128;
    `elsif L2SIZE_256
    parameter cache_size    = 256;
    `else
    parameter cache_size    = 256;
    `endif
    parameter cache_entry   = cache_size/(word_num_in_block*way_num);           
    parameter entry_len     = clogb2(cache_entry);  // cache entry: number of index

    integer   i;

    input wire                      clk, reset;
    input wire  [l1_addr_len-1:0]   i_l1_addr;
    input wire  [block_len-1:0]     i_l1_wdata;
    input wire                      i_l1_read, i_l1_write;
    output reg                      o_l1_ready;
    reg                             o_l1_ready_next;
    output wire [block_len-1:0]     o_l1_rdata;

    // @param o_l1_rdata_ways: Read data from each way inferred by cache entry 
    wire        [block_len-1:0]     o_l1_rdata_ways[way_num-1:0];

    output reg  [mem_addr_len-1:0]  o_m_addr;
    output wire [block_len-1:0]     o_m_wdata;
    output reg                      o_m_read, o_m_write;
    input wire  [block_len-1:0]     i_m_rdata;
    input wire                      i_m_ready;

    `ifdef SET_COUNTER
    output reg [31:0]   cnt_r;
    output reg [31:0]   cnt_w;
    output reg [31:0]   cnt_hit_r;
    output reg [31:0]   cnt_hit_w;
    output reg [31:0]   cnt_wb_r;
    output reg [31:0]   cnt_wb_w;
    `else 
    output wire [31:0]  cnt_r;
    output wire [31:0]  cnt_w;
    output wire [31:0]  cnt_hit_r;
    output wire [31:0]  cnt_hit_w;
    output wire [31:0]  cnt_wb_r;
    output wire [31:0]  cnt_wb_w;
    `endif

    // wires about the information of current data //
    wire [way_num-1:0]                  hit;        // At any time, there may be many bits turn on for hit 
    wire [way_num-1:0]                  modify;     // Whether the data needed to be written back
    wire [way_num-1:0]                  miss;       // Whether r/w miss occur, but no need to write back (dirty bit is 0)
    wire [way_num-1:0]                  valid;      // Valid bit for cache entry in each way
    wire [way_len-1:0]                  hit_way;    // determine which way is hit
    wire [way_len-1:0]                  invalid_way;
    // wires about the read write operation //
    wire [block_len-1:0]                readdata[way_num-1:0];  // readdata (not blocked, directly read from reg)
    wire [block_len-1:0]                writedata;              // writedata, change current data in cache
    wire [way_num-1:0]                  write;
    wire [block_num-1:0]                block_en;               // not used in this file, determine which block is to be written 
    wire [l1_addr_len-1:0]              addr;
    wire [l1_addr_len-1:0]              wb_addr[way_num-1:0];   // address to write back for each way (choose 1 from ways)
    wire [way_len*way_num-1:0]          r_cm_data;      // read out the priority list from register
    
    // registers about next state signal or data
    reg  [1:0]                          state;          // finite state machine
    reg  [1:0]                          state_next;     // store the next state to go
    reg  [way_len*way_num-1:0]          w_cm_data;      // store the new priority list for next clock (LRU unit)
    reg                                 w_cm;           // write signal for LRU register/unit
    reg  [way_num-1:0]                  write_set_next, write_set;
    reg  [way_num-1:0]                  fetch_write_next, fetch_write;  // determine which way to write back data from memory
    // registers for buffer
    reg  [l1_addr_len-1:0]              l1_addr_buf;    // buffer for input signal
    reg                                 write_buf, read_buf;
    reg  [block_num*block_len-1:0]      writedata_buf;  
        

    localparam IDLE = 0;
    localparam COMP = 1;
    localparam FETCH = 2;
    localparam WB = 3;

    /* the interface of simple ram */
    /* simple_ram(clk, reset, writeaddr, write, wdata, readaddr, rdata) */
    L2simple_ram #(.width(way_len*way_num), .widthad(entry_len)) lru_field 
                (clk, reset, l1_addr_buf[entry_len-1:0], w_cm, w_cm_data, l1_addr_buf[entry_len-1:0], r_cm_data);
    /* instances of set */
    generate
        genvar k;
        for (k=0; k<way_num; k=k+1)  begin : cache_set
            L2cache_set #(.entry_len(entry_len),
                        .block_offset(block_offset),
                        .block_len(block_len),
                        .l1_addr_len(l1_addr_len)) cache_set
                       (.clk(clk),
                        .rst(reset),
                        .entry(l1_addr_buf[entry_len-1:0]),
                        .o_tag(l1_addr_buf[l1_addr_len-1:entry_len]),
                        .writedata(writedata),              // data needed to be written (block_len)
                        .write(write[k]),                   // write enable signal
                        .block_en(block_en),                // each block change or not
                        .readdata(readdata[k]),             // data needed to be read (block_len)
                        .wb_addr(wb_addr[k]),               // indicate which block is needed to write back
                                                            // width: l1_addr_len
                        .hit(hit[k]),
                        .modify(modify[k]),                 // modify
                        .miss(miss[k]),                     // miss
                        .valid(valid[k]),                   // valid
                        .read_miss(read_buf));              // read_miss
        end
    endgenerate
    // the priority of read data from memory is higher than read data from l1 cache
    // first fetch data from memory then modify the data by i_l1_wdata
    assign writedata = (|fetch_write) ? i_m_rdata : i_l1_wdata;           // 128bit
    
    // i_m_ready: means the data from memory is what we requested and valid, we can write back
    // write_set_next[i] = 1 means write operation is required for ith way
    // write_set_next determine the signal source for write operation
    generate
        genvar t;
        for (t=0; t<way_num; t=t+1) begin : write_signal
            assign write[t] = (fetch_write[t]) ? i_m_ready : write_set[t];
            assign o_l1_rdata_ways[t] = readdata[t];
        end
    endgenerate
    
    assign addr = (o_l1_ready) ? i_l1_addr[l1_addr_len-1:0] : l1_addr_buf[l1_addr_len-1:0]; 
    // assign addr = l1_addr_buf;
    
    /*** warning: if more way we need to modify hit_way ***/
    assign block_en = 1'b1;
    /*
    assign block_en = (|fetch_write_next) ? 4'b1111 : 
                      (l1_addr_buf[block_offset-1:0] == 2'b00) ? 4'b0001 :
                      (l1_addr_buf[block_offset-1:0] == 2'b01) ? 4'b0010 :
                      (l1_addr_buf[block_offset-1:0] == 2'b10) ? 4'b0100 : 4'b1000;
    */
    /*** warning: if more way we need to modify 
    wire [block_offset-1:0] b_offset;
    assign b_offset = l1_addr_buf[block_offset-1:0];
    for (i=0; i<way_num; i=i+1) begin
        assign o_l1_rdata_ways[i] = (b_offset == 2'b00) ? readdata[i][block_len-1:0] :
                                    (b_offset == 2'b01) ? readdata[i][block_len*2-1:block_len] :
                                    (b_offset == 2'b10) ? readdata[i][block_len*3-1:block_len*2] : 
                                                          readdata[i][block_len*4-1:block_len*3];
    end
    ***/
    assign hit_way =    (hit[0]) ? 3'b000 : (hit[1]) ? 3'b001 : 
                        (hit[2]) ? 3'b010 : (hit[3]) ? 3'b011 :
                        (hit[4]) ? 3'b100 : (hit[5]) ? 3'b101 :
                        (hit[6]) ? 3'b110 : 3'b111;
    assign invalid_way = (!valid[0]) ? 3'b000 : (!valid[1]) ? 3'b001 : 
                         (!valid[2]) ? 3'b010 : (!valid[3]) ? 3'b011 :
                         (!valid[4]) ? 3'b100 : (!valid[5]) ? 3'b101 :
                         (!valid[6]) ? 3'b110 : 3'b111;
    /* output port for l2cache module */
    assign o_l1_rdata = (hit[0]) ? o_l1_rdata_ways[0] : 
                        (hit[1]) ? o_l1_rdata_ways[1] : 
                        (hit[2]) ? o_l1_rdata_ways[2] : 
                        (hit[3]) ? o_l1_rdata_ways[3] :
                        (hit[4]) ? o_l1_rdata_ways[4] :
                        (hit[5]) ? o_l1_rdata_ways[5] :
                        (hit[6]) ? o_l1_rdata_ways[6] : 
                        (hit[7]) ? o_l1_rdata_ways[7] : 0;
    assign o_m_wdata  = (fetch_write[0]) ? readdata[0] : 
                        (fetch_write[1]) ? readdata[1] : 
                        (fetch_write[2]) ? readdata[2] : 
                        (fetch_write[3]) ? readdata[3] : 
                        (fetch_write[4]) ? readdata[4] : 
                        (fetch_write[5]) ? readdata[5] : 
                        (fetch_write[6]) ? readdata[6] : 
                        (fetch_write[7]) ? readdata[7] : 0;
    
    /* w_cm_data determination */
    wire [way_len*way_num-1:0] w_cm_data_source[way_num-1:0];
    assign w_cm_data_source[0] = (r_cm_data[ 2: 0] == hit_way) ? {r_cm_data[ 2: 0], r_cm_data[23: 3]} :
                                 (r_cm_data[ 5: 3] == hit_way) ? {r_cm_data[ 5: 3], r_cm_data[23: 6], r_cm_data[ 2:0]} :
                                 (r_cm_data[ 8: 6] == hit_way) ? {r_cm_data[ 8: 6], r_cm_data[23: 9], r_cm_data[ 5:0]} : 
                                 (r_cm_data[11: 9] == hit_way) ? {r_cm_data[11: 9], r_cm_data[23:12], r_cm_data[ 8:0]} :
                                 (r_cm_data[14:12] == hit_way) ? {r_cm_data[14:12], r_cm_data[23:15], r_cm_data[11:0]} :
                                 (r_cm_data[17:15] == hit_way) ? {r_cm_data[17:15], r_cm_data[23:18], r_cm_data[14:0]} :
                                 (r_cm_data[20:18] == hit_way) ? {r_cm_data[20:18], r_cm_data[23:21], r_cm_data[17:0]} : r_cm_data;
    generate
        genvar s;
        for(s=1; s<way_num; s=s+1) begin: w_cm_source
                assign w_cm_data_source[s] = (r_cm_data[ 2: 0] == s) ? {r_cm_data[ 2: 0], r_cm_data[23: 3]} :
                                             (r_cm_data[ 5: 3] == s) ? {r_cm_data[ 5: 3], r_cm_data[23: 6], r_cm_data[ 2:0]} :
                                             (r_cm_data[ 8: 6] == s) ? {r_cm_data[ 8: 6], r_cm_data[23: 9], r_cm_data[ 5:0]} : 
                                             (r_cm_data[11: 9] == s) ? {r_cm_data[11: 9], r_cm_data[23:12], r_cm_data[ 8:0]} :
                                             (r_cm_data[14:12] == s) ? {r_cm_data[14:12], r_cm_data[23:15], r_cm_data[11:0]} :
                                             (r_cm_data[17:15] == s) ? {r_cm_data[17:15], r_cm_data[23:18], r_cm_data[14:0]} :
                                             (r_cm_data[20:18] == s) ? {r_cm_data[20:18], r_cm_data[23:21], r_cm_data[17:0]} : r_cm_data;
        end
    endgenerate

    
    always @( * ) begin
        `ifdef SET_COUNTER
        if (reset) begin
            {cnt_r, cnt_w} = 0;
            {cnt_hit_r, cnt_hit_w} = 0;
            {cnt_wb_r, cnt_wb_w} = 0;
        end
        else begin
            {cnt_r, cnt_w} = {cnt_r, cnt_w};
            {cnt_hit_r, cnt_hit_w} = {cnt_hit_r, cnt_hit_w};
            {cnt_wb_r, cnt_wb_w} = {cnt_wb_r, cnt_wb_w};
        end
        `endif
        o_l1_ready_next = 1'b0;
        o_m_read = 1'b0;
        o_m_write = 1'b0;
        o_m_addr = 0;
        w_cm = 1'b0;
        w_cm_data = 0;
        write_set_next = 0;
        fetch_write_next = 0;
        state_next = IDLE;
        case(state)
            /* IDLE(redundant): nothing done, waiting for read/write instructions */
            IDLE:
                begin
                    if ( read_buf^write_buf ) begin
                        state_next = COMP;
                        // write_set_next = 0;
                        // fetch_write_next = 0;
                    end
                    else begin
                        state_next = IDLE;
                        // write_set_next = 0;
                        // fetch_write_next = 0;
                    end

                end
            /* COMPARE_TAG: check whether hit or not */
            COMP:
                begin
                    `ifdef SET_COUNTER
                    if ( read_buf )
                        cnt_r = cnt_r + 1;
                    else if ( write_buf )
                        cnt_w = cnt_w + 1;
                    `endif                  
                    /*** warning: if more way we need to modify ***/
                     // LRU register need to update, set w_cm to true
                    w_cm = 1'b1;
                    w_cm_data = w_cm_data_source[0];
                    
                    if (~(read_buf | write_buf)) begin
                        state_next = COMP;
                        w_cm = 1'b0;
                    end
                    else if ( (|hit) & write_buf ) begin
                        `ifdef SET_COUNTER
                        cnt_hit_w = cnt_hit_w + 1;
                        `endif
                        // write signal for ith way set to 1 if hit occur
                        if (o_l1_ready)
                            o_l1_ready_next = 1'b0;
                        else
                            o_l1_ready_next = 1'b1;
                        write_set_next = hit;
                        state_next = COMP;
                        // w_cm = 1;        
                    end
                    else if ( (|hit) & read_buf ) begin
                        `ifdef SET_COUNTER
                        cnt_hit_r <= cnt_hit_r + 1;
                        `endif
                        if (o_l1_ready)
                            o_l1_ready_next = 1'b0;
                        else
                            o_l1_ready_next = 1'b1; 
                        state_next = COMP;
                        // w_cm = 1;            
                    end
                    // if there is any block not valid, first write data to that block
                    // if all blocks are valid, fetch block that is less recent accessed
                    else if(!(&valid)) begin
                        state_next = FETCH;
                        // w_cm = 1;
                        o_m_addr = l1_addr_buf;
                        o_m_read = 1'b1;
                        /*** warning: if more way we need to modify the number of if***/
                        case(invalid_way)
                            0: begin fetch_write_next = 8'b00000001; w_cm_data = 24'b000111110101100011010001; end
                            1: begin fetch_write_next = 8'b00000010; w_cm_data = w_cm_data_source[1]; end
                            2: begin fetch_write_next = 8'b00000100; w_cm_data = w_cm_data_source[2]; end
                            3: begin fetch_write_next = 8'b00001000; w_cm_data = w_cm_data_source[3]; end
                            4: begin fetch_write_next = 8'b00010000; w_cm_data = w_cm_data_source[4]; end
                            5: begin fetch_write_next = 8'b00100000; w_cm_data = w_cm_data_source[5]; end
                            6: begin fetch_write_next = 8'b01000000; w_cm_data = w_cm_data_source[6]; end
                            7: begin fetch_write_next = 8'b10000000; w_cm_data = w_cm_data_source[7]; end
                        endcase
                    end
                    /*** warning: if more way we need to modify the number of bit ***/
                    else if(miss[r_cm_data[way_len-1:0]]) begin    
                        state_next = FETCH;
                        // w_cm = 1;
                        o_m_addr = l1_addr_buf;
                        o_m_read = 1'b1;
                        case(r_cm_data[way_len-1:0])
                            0: fetch_write_next = 8'b00000001;
                            1: fetch_write_next = 8'b00000010;
                            2: fetch_write_next = 8'b00000100;
                            3: fetch_write_next = 8'b00001000;
                            4: fetch_write_next = 8'b00010000;
                            5: fetch_write_next = 8'b00100000;
                            6: fetch_write_next = 8'b01000000;
                            7: fetch_write_next = 8'b10000000;
                        endcase
                        w_cm_data = {r_cm_data[way_len-1:0], r_cm_data[way_num*way_len-1:way_len]};
                    end
                    else if (modify[r_cm_data[way_len-1:0]]) begin
                        `ifdef SET_COUNTER
                        if(read_buf) cnt_wb_r = cnt_wb_r + 1;
                        else if(write_buf) cnt_wb_w = cnt_wb_w + 1;
                        `endif
                        state_next = WB;
                        // w_cm = 1;
                        o_m_addr =  (fetch_write_next[0]) ? wb_addr[0] :
                                    (fetch_write_next[1]) ? wb_addr[1] :
                                    (fetch_write_next[2]) ? wb_addr[2] :
                                    (fetch_write_next[3]) ? wb_addr[3] :
                                    (fetch_write_next[4]) ? wb_addr[4] :
                                    (fetch_write_next[5]) ? wb_addr[5] :
                                    (fetch_write_next[6]) ? wb_addr[6] : wb_addr[7];
                        o_m_write = 1'b1;
                        /*** warning: if more way we need to modify the number of bit ***/
                        case(r_cm_data[way_len-1:0])
                            0: fetch_write_next = 8'b00000001;
                            1: fetch_write_next = 8'b00000010;
                            2: fetch_write_next = 8'b00000100;
                            3: fetch_write_next = 8'b00001000;
                            4: fetch_write_next = 8'b00010000;
                            5: fetch_write_next = 8'b00100000;
                            6: fetch_write_next = 8'b01000000;
                            7: fetch_write_next = 8'b10000000;
                        endcase
                        w_cm_data = {r_cm_data[way_len-1:0], r_cm_data[way_num*way_len-1:way_len]};
                    end
                    else begin
                        state_next = IDLE;
                    end
                end
            FETCH:
                begin
                    if ( i_m_ready ) begin
                        if( write_buf ) begin
                            state_next = COMP;
                            write_set_next = fetch_write;
                        end 
                        else if( read_buf ) begin
                            state_next = COMP;
                            // fetch_write_next = fetch_write;
                        end
                    end
                    else begin
                        state_next = FETCH;
                        fetch_write_next = fetch_write;
                        o_m_addr = l1_addr_buf;
                        o_m_read = 1'b1;
                    end
                end
            WB:
                begin
                    if ( i_m_ready ) begin
                        state_next = FETCH;
                        // o_m_write = 1'b0;
                        o_m_read = 1'b1;
                        o_m_addr = l1_addr_buf;
                        fetch_write_next = fetch_write;
                    end
                    else begin
                        state_next = WB;
                        // w_cm = 0;
                        /*** warning:  ***/
                        o_m_addr =  (fetch_write[0]) ? wb_addr[0] :
                                    (fetch_write[1]) ? wb_addr[1] :
                                    (fetch_write[2]) ? wb_addr[2] :
                                    (fetch_write[3]) ? wb_addr[3] :
                                    (fetch_write[4]) ? wb_addr[4] :
                                    (fetch_write[5]) ? wb_addr[5] :
                                    (fetch_write[6]) ? wb_addr[6] : wb_addr[7];
                        o_m_write = 1'b1;
                        fetch_write_next = fetch_write;
                    end     
                end
            default:
                state_next = IDLE;
        endcase
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fetch_write <= 0;
            write_set <= 0;
        end
        else begin
            fetch_write <= fetch_write_next;
            write_set <= write_set_next;
            if (i_l1_addr != l1_addr_buf) begin
                // TO find the begin of an operation
                // $display(" NEW operation......");
            end
        end
    end
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            o_l1_ready <= 0;
            l1_addr_buf <= 0;
            writedata_buf <= 0;
            {write_buf, read_buf} <= 0;     
            state <= IDLE;
        end
        else begin
            if (|hit)
                o_l1_ready <= o_l1_ready_next;
            else
                o_l1_ready <= 0;
            read_buf <= i_l1_read;
            write_buf <= i_l1_write;
            writedata_buf <= {block_num{i_l1_wdata}};
            
            
            if (~(state == COMP & (write_buf|read_buf))) begin
                l1_addr_buf <= i_l1_addr;
            end
            state <= state_next;
            /*
            $display(".............................");
            $display(" state: %d", state);
            $display(" state_next: %d", state_next);
            //$display(" i_l1_read: ", i_l1_read, read_buf);
            $display(" mem_ready: %d", i_m_ready);
            $display(" o_l1_ready: ", o_l1_ready, o_l1_ready_next);
            $display(" hit: %b", hit);
            $display(" valid: %b", valid);
            
            $display(" write_set_next: %b, fetch_write_next %b, write %b", write_set_next, fetch_write_next, write);
            $display(" addr: ", addr, i_l1_addr, o_m_addr);
            $display(" l1_addr_buf: ", l1_addr_buf);
            $display(readdata[0][31:0],readdata[0][63:32],readdata[0][95:64],readdata[0][127:96]); 
            $display(readdata[1][31:0],readdata[1][63:32],readdata[1][95:64],readdata[1][127:96]);
            $display(readdata[2][31:0],readdata[2][63:32],readdata[2][95:64],readdata[2][127:96]); 
            $display(readdata[3][31:0],readdata[3][63:32],readdata[3][95:64],readdata[3][127:96]);
            $display(readdata[4][31:0],readdata[4][63:32],readdata[4][95:64],readdata[4][127:96]);
            $display(readdata[5][31:0],readdata[5][63:32],readdata[5][95:64],readdata[5][127:96]);
            $display(readdata[6][31:0],readdata[6][63:32],readdata[6][95:64],readdata[6][127:96]);
            $display(readdata[7][31:0],readdata[7][63:32],readdata[7][95:64],readdata[7][127:96]);
            $display(" i_m_rdata: ", i_m_rdata[31:0], i_m_rdata[63:32], i_m_rdata[95:64], i_m_rdata[127:96]);
            $display(" i_l1_wdata: ", i_l1_wdata[31:0], i_l1_wdata[63:32], i_l1_wdata[95:64], i_l1_wdata[127:96]);
            $display(" writedata: ", writedata[31:0], writedata[63:32], writedata[95:64], writedata[127:96]);
            $display(".............................");
            */ 
        end
    end
endmodule
`endif

module L2cache_set( clk,
                    rst,
                    entry,
                    o_tag,
                    writedata,
                    write,
                    block_en,

                    readdata,
                    wb_addr,
                    hit,
                    modify,
                    miss,
                    valid,
                    read_miss);

    parameter entry_len     = 4;
    parameter block_offset  = 0;
    parameter block_len     = 128;
    // address total 28 bits
    // |remain bits for tag|log(cache_entry) bits for index/entry|
    parameter l1_addr_len   = 28;
                
    input wire                                  clk, rst;
    input wire [entry_len-1:0]                  entry;
    /*** warning: the length of o_tag need to change ***/
    input wire [l1_addr_len-entry_len-1:0]      o_tag;
    input wire [block_len-1:0]                  writedata;
    input wire                                  write;
    /*** warning: the length of block_en need to change ***/
    input wire                                  block_en;
    input wire                                  read_miss;

    output wire [block_len-1:0]                 readdata;
    output wire [l1_addr_len-1:0]               wb_addr;
    output wire                                 hit, modify, miss, valid;

    wire [l1_addr_len-entry_len-1:0]            i_tag;
    wire                                        dirty;
    wire [l1_addr_len-entry_len+1:0]            write_tag_data;

    assign hit = valid & (o_tag == i_tag);

    assign modify = valid & (o_tag != i_tag) & dirty;
    assign miss = !valid | ((o_tag != i_tag) & !dirty);

    assign wb_addr = {i_tag, entry};
    assign write_tag_data = (read_miss) ? {1'b0, 1'b1, o_tag} : ( modify | miss ) ? {1'b1, 1'b1, o_tag} : {1'b1, 1'b1, i_tag};
    L2simple_ram #(.width(block_len), .widthad(entry_len)) ram11(clk, rst, entry, write & block_en, writedata, entry, readdata);
    L2simple_ram #(.width(l1_addr_len-entry_len+2), .widthad(entry_len)) ram_tag(clk, rst, entry, write, write_tag_data, entry, {dirty, valid, i_tag});

endmodule

module L2simple_ram
  #(parameter width     = 1,
    parameter widthad   = 1)
   (input                   clk,
    input                   rst,
    input [widthad-1:0]     wraddress,
    input                   wren,
    input [width-1:0]       data,
    input [widthad-1:0]     rdaddress,
    output wire [width-1:0] q);

    reg   [width-1:0] mem [(2**widthad)-1:0];
    integer           i;
    assign q = mem[rdaddress];
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i=0; i<(2**widthad); i=i+1) begin
                mem[i] <= 0;
            end
        end
        else if(wren) begin
            mem[wraddress] <= data;
        end
    end
endmodule
