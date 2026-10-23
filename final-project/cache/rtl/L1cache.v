`ifdef L1_2way
module cache(
    clk,
    proc_reset,
    proc_read,
    proc_write,
    proc_addr,
    proc_wdata,
    proc_stall,
    proc_rdata,
    mem_read,
    mem_write,
    mem_addr,
    mem_rdata,
    mem_wdata,
    mem_ready
);
//==== utility function ===================================
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
    parameter      WORD_WIDTH = 32;
    parameter      WORD_NUM = 4;
    parameter      BLOCK_WIDTH = WORD_NUM*WORD_WIDTH;
    `ifdef L1SIZE_4
    parameter      BLOCK_NUM = 4;
    `elsif L1SIZE_8
    parameter      BLOCK_NUM = 8;
    `else
    parameter      BLOCK_NUM = 8;
    `endif
    parameter      WAY_NUM = 2;
    parameter      WAY_WIDTH = clogb2(WAY_NUM);
    parameter      ENTRY_NUM = BLOCK_NUM/WAY_NUM;
    parameter      ENTRY_WIDTH = clogb2(ENTRY_NUM);

    parameter      ADDR_WIDTH = 30;
    parameter      M_ADDR_WIDTH = 28;
    
    parameter      TAG_WIDTH = M_ADDR_WIDTH - ENTRY_WIDTH;
//==== input/output definition ============================
    input          clk;
    // processor interface
    input                           proc_reset;
    input                           proc_read, proc_write;
    input       [ADDR_WIDTH-1:0]    proc_addr;
    input       [WORD_WIDTH-1:0]    proc_wdata;
    output wire                     proc_stall;
    output wire [WORD_WIDTH-1:0]    proc_rdata;
    // memory interface
    input       [BLOCK_WIDTH-1:0]   mem_rdata;
    input                           mem_ready;
    output                          mem_read, mem_write;
    output      [M_ADDR_WIDTH-1:0]  mem_addr;
    output wire [BLOCK_WIDTH-1:0]   mem_wdata;
//==== wire/reg definition ================================
    //==== memory related register ====//
    reg                             mem_read, mem_write;
    reg         [M_ADDR_WIDTH-1:0]  mem_addr;
    //==== cache related register ====//  _next: buffer for next clk posedge
    reg                             way;
    reg     [WAY_NUM-1:0]           hit;
    // reg  [WAY_WIDTH-1:0]         fetch_num;
    reg     [WAY_NUM-1:0]           fetch_write;
    reg     [WAY_NUM-1:0]           valid_bits[ENTRY_NUM-1:0];
    reg     [WAY_NUM-1:0]           valid_bits_next;
    reg     [WAY_NUM-1:0]           dirty_bits[ENTRY_NUM-1:0]; 
    reg     [WAY_NUM-1:0]           dirty_bits_next;
    reg                             lru_field[ENTRY_NUM-1:0];
    reg                             lru_field_next;   
    reg     [TAG_WIDTH-1:0]         tag_field[ENTRY_NUM-1:0][WAY_NUM-1:0]; 
    reg     [TAG_WIDTH-1:0]         tag_field_next[WAY_NUM-1:0];
    reg     [BLOCK_WIDTH-1:0]       Cache_data[ENTRY_NUM-1:0][WAY_NUM-1:0];      
    reg     [BLOCK_WIDTH-1:0]       Cache_data_next[WAY_NUM-1:0];
    //==== wires ====//
    wire                            hit_num, fetch_num;
    wire    [WAY_NUM-1:0]           valid_bit, dirty_bit;
    wire                            current_lru;

    wire    [1:0]                   word_offset;
    wire    [ENTRY_WIDTH-1:0]       index;
    wire    [TAG_WIDTH-1:0]         tag, current_tag;
    wire    [BLOCK_WIDTH-1:0]       rdata_way;
    wire    [BLOCK_WIDTH-1:0]       rdata_ways[WAY_NUM-1:0];

    integer        i,j;
//==== combinational circuit ==============================
    assign valid_bit        = valid_bits[index];
    assign dirty_bit        = dirty_bits[index];
    assign current_lru      = lru_field[index];
    // assign current_tag      = tag_field[index];
    assign  hit_num = (hit[0]) ? 1'b0 : 1'b1;
    assign  fetch_num = lru_field[index];

    assign word_offset      = proc_addr[1:0];                           // 4 words in 1 block
    assign index            = proc_addr[ENTRY_WIDTH+1:2];               // 8 block in cache unit
    assign tag              = proc_addr[ADDR_WIDTH-1:ENTRY_WIDTH+2];    // remain bits in address

    assign proc_stall       = (proc_read | proc_write)?(|hit)? 1'b0 : 1'b1 : 1'b0;
    generate
        genvar k;
        for (k=0; k<WAY_NUM; k=k+1) begin: mutiple_way
            assign rdata_ways[k] = Cache_data[index][k];
        end   
    endgenerate

    assign rdata_way    =   (hit[0]) ? rdata_ways[0] : 
                            (hit[1]) ? rdata_ways[1] : 0;   
    assign proc_rdata   =   (word_offset == 2'b00) ? rdata_way[WORD_WIDTH-1:0] :
                            (word_offset == 2'b01) ? rdata_way[WORD_WIDTH*2-1:WORD_WIDTH] :
                            (word_offset == 2'b10) ? rdata_way[WORD_WIDTH*3-1:WORD_WIDTH*2] :
                            (word_offset == 2'b11) ? rdata_way[WORD_WIDTH*4-1:WORD_WIDTH*3] : 0;
    
    assign mem_wdata    =   (fetch_write[0]) ? rdata_ways[0] : 
                            (fetch_write[1]) ? rdata_ways[1] : 0;
//==== sequential circuit =================================
always@( posedge clk or posedge proc_reset ) begin
    if ( proc_reset ) begin
        for (i=0; i<ENTRY_NUM; i=i+1) begin
            for (j=0; j<WAY_NUM; j=j+1) begin
                Cache_data[i][j] <= 0;
                tag_field[i][j] <= 0;
            end
            valid_bits[i] <= 0;
            dirty_bits[i] <= 0;
            lru_field[i] <= 0;
        end
    end
    else begin
        for (i=0; i<WAY_NUM; i=i+1) begin
            Cache_data[index][i] <= Cache_data_next[i];
            tag_field[index][i] <= tag_field_next[i];
        end
        valid_bits[index] <= valid_bits_next;
        dirty_bits[index] <= dirty_bits_next;
        lru_field[index] <= lru_field_next;       
        /*
        $display("proc_stall: ", proc_stall);
        $display("Cache_data0: ",Cache_data[index][0][31:0],
                                 Cache_data[index][0][63:32],
                                 Cache_data[index][0][95:64],
                                 Cache_data[index][0][127:96]);
        $display("Cache_data1: ",Cache_data[index][1][31:0],
                                 Cache_data[index][1][63:32],
                                 Cache_data[index][1][95:64],
                                 Cache_data[index][1][127:96]);
        $display("mem_addr: ", mem_addr, "proc_addr: ", proc_addr[ADDR_WIDTH-1:2]);
        $display("mem_ready: ", mem_ready, " hit:", hit);
        */
    end
end

always@( * ) begin
    // default value
    for (i=0; i<WAY_NUM; i=i+1) begin    
        tag_field_next[i] = tag_field[index][i];
        Cache_data_next[i] = Cache_data[index][i];
    end
    valid_bits_next = valid_bit;
    dirty_bits_next = dirty_bit;
    lru_field_next = current_lru;

    mem_addr = 0;
    mem_read = 1'b0;
    mem_write = 1'b0;
    for (i=0; i<WAY_NUM; i=i+1) begin
        hit[i] = (valid_bit[i] & (tag_field[index][i] == tag));
    end
    fetch_write = (|hit) ? 2'b00 : (lru_field[index]) ? 2'b10 : 2'b01;

    if ( ~(|hit) & (proc_read^proc_write) ) begin
        // If dirty, write back 
        if ( |fetch_write & dirty_bit[fetch_num] & valid_bit[fetch_num] ) begin
            // Wait for data from memory 
            if ( ~mem_ready ) begin
                mem_addr = {tag_field_next[fetch_num],index};
                // mem_read = 0;
                mem_write = 1'b1;
            end
            else begin
                dirty_bits_next[fetch_num] = 1'b0;
            end
        end
        // Not dirty, read from memory 
        else begin
            if ( ~mem_ready )begin
                mem_addr = proc_addr[ADDR_WIDTH-1:2];
                mem_read = 1'b1;
                // mem_write = 0;
            end
            // Data from memory is ready, write data into cache 
            else begin
                // mem_addr = 0;
                // mem_read = 0;
                // mem_write = 0;
                Cache_data_next[fetch_num] = mem_rdata;
                tag_field_next[fetch_num] = tag;
                valid_bits_next[fetch_num] = 1'b1;
                dirty_bits_next[fetch_num] = 1'b0;
            end
        end
    end
    else if ( |hit & proc_write & ~proc_read) begin
        dirty_bits_next[hit_num] = 1'b1; 
        lru_field_next = hit[0] ? 1'b1 : 1'b0;
        case( word_offset )
            2'b00: Cache_data_next[hit_num][31:0] = proc_wdata;
            2'b01: Cache_data_next[hit_num][63:32] = proc_wdata;
            2'b10: Cache_data_next[hit_num][95:64] = proc_wdata;
            2'b11: Cache_data_next[hit_num][127:96] = proc_wdata;
        endcase
    end
    else if ( |hit & proc_read & ~proc_write) begin
       lru_field_next = hit[0] ? 1'b1 : 1'b0;     
    end
end
endmodule

`elsif L1_4way
module cache(
    clk,
    proc_reset,
    proc_read,
    proc_write,
    proc_addr,
    proc_wdata,
    proc_stall,
    proc_rdata,
    mem_read,
    mem_write,
    mem_addr,
    mem_rdata,
    mem_wdata,
    mem_ready
);
//==== utility function ===================================
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
    parameter      WORD_WIDTH = 32;
    parameter      WORD_NUM = 4;
    parameter      BLOCK_WIDTH = WORD_NUM*WORD_WIDTH;
    `ifdef L1SIZE_4
    parameter      BLOCK_NUM = 4;
    `elsif L1SIZE_8
    parameter      BLOCK_NUM = 8;
    `else
    parameter      BLOCK_NUM = 8;
    `endif
    parameter      WAY_NUM = 4;
    parameter      WAY_WIDTH = clogb2(WAY_NUM);
    parameter      ENTRY_NUM = BLOCK_NUM/WAY_NUM;
    parameter      ENTRY_WIDTH = clogb2(ENTRY_NUM);

    parameter      ADDR_WIDTH = 30;
    parameter      M_ADDR_WIDTH = 28;
    
    parameter      TAG_WIDTH = M_ADDR_WIDTH - ENTRY_WIDTH;
//==== input/output definition ============================
    input          clk;
    // processor interface
    input                           proc_reset;
    input                           proc_read, proc_write;
    input       [ADDR_WIDTH-1:0]    proc_addr;
    input       [WORD_WIDTH-1:0]    proc_wdata;
    output wire                     proc_stall;
    output wire [WORD_WIDTH-1:0]    proc_rdata;
    // memory interface
    input       [BLOCK_WIDTH-1:0]   mem_rdata;
    input                           mem_ready;
    output                          mem_read, mem_write;
    output      [M_ADDR_WIDTH-1:0]  mem_addr;
    output wire [BLOCK_WIDTH-1:0]   mem_wdata;
//==== wire/reg definition ================================
    //==== memory related register ====//
    reg                             mem_read, mem_write;
    reg         [M_ADDR_WIDTH-1:0]  mem_addr;
    //==== cache related register ====//  _next: buffer for next clk posedge
    reg                             way;
    reg     [WAY_NUM-1:0]           hit;
    reg     [WAY_NUM-1:0]           fetch_write;
    reg     [WAY_NUM-1:0]           valid_bits[ENTRY_NUM-1:0];
    reg     [WAY_NUM-1:0]           valid_bits_next;
    reg     [WAY_NUM-1:0]           dirty_bits[ENTRY_NUM-1:0]; 
    reg     [WAY_NUM-1:0]           dirty_bits_next;
    reg                             lru_field[ENTRY_NUM-1:0];
    reg                             lru_field_next;   
    reg     [TAG_WIDTH-1:0]         tag_field[ENTRY_NUM-1:0][WAY_NUM-1:0]; 
    reg     [TAG_WIDTH-1:0]         tag_field_next[WAY_NUM-1:0];
    reg     [BLOCK_WIDTH-1:0]       Cache_data[ENTRY_NUM-1:0][WAY_NUM-1:0];      
    reg     [BLOCK_WIDTH-1:0]       Cache_data_next[WAY_NUM-1:0];
    //==== wires ====//
    wire    [WAY_WIDTH-1:0]         hit_num, fetch_num;
    wire    [WAY_NUM-1:0]           valid_bit, dirty_bit;
    wire                            current_lru;

    wire    [1:0]                   word_offset;
    wire    [ENTRY_WIDTH-1:0]       index;
    wire    [TAG_WIDTH-1:0]         tag, current_tag;
    wire    [BLOCK_WIDTH-1:0]       rdata_way;
    wire    [BLOCK_WIDTH-1:0]       rdata_ways[WAY_NUM-1:0];

    integer        i,j;
//==== combinational circuit ==============================
    assign valid_bit        = valid_bits[index];
    assign dirty_bit        = dirty_bits[index];
    assign current_lru      = lru_field[index];
    // assign current_tag      = tag_field[index];
    assign  hit_num = (hit[0]) ? 1'b0 : 1'b1;
    assign  fetch_num = lru_field[index];

    assign word_offset      = proc_addr[1:0];                           // 4 words in 1 block
    assign index            = proc_addr[ENTRY_WIDTH+1:2];               // 8 block in cache unit
    assign tag              = proc_addr[ADDR_WIDTH-1:ENTRY_WIDTH+2];    // remain bits in address

    assign proc_stall       = (proc_read | proc_write)?(|hit)? 1'b0 : 1'b1 : 1'b0;
    generate
        genvar k;
        for (k=0; k<WAY_NUM; k=k+1) begin: mutiple_way
            assign rdata_ways[k] = Cache_data[index][k];
        end   
    endgenerate

    assign rdata_way    =   (hit[0]) ? rdata_ways[0] : 
                            (hit[1]) ? rdata_ways[1] : 0;   
    assign proc_rdata   =   (word_offset == 2'b00) ? rdata_way[WORD_WIDTH-1:0] :
                            (word_offset == 2'b01) ? rdata_way[WORD_WIDTH*2-1:WORD_WIDTH] :
                            (word_offset == 2'b10) ? rdata_way[WORD_WIDTH*3-1:WORD_WIDTH*2] :
                            (word_offset == 2'b11) ? rdata_way[WORD_WIDTH*4-1:WORD_WIDTH*3] : 0;
    
    assign mem_wdata    =   (fetch_write[0]) ? rdata_ways[0] : 
                            (fetch_write[1]) ? rdata_ways[1] : 0;
//==== sequential circuit =================================
always@( posedge clk or posedge proc_reset ) begin
    if ( proc_reset ) begin
        for (i=0; i<ENTRY_NUM; i=i+1) begin
            for (j=0; j<WAY_NUM; j=j+1) begin
                Cache_data[i][j] <= 0;
                tag_field[i][j] <= 0;
            end
            valid_bits[i] <= 0;
            dirty_bits[i] <= 0;
            lru_field[i] <= 0;
        end
    end
    else begin
        for (i=0; i<WAY_NUM; i=i+1) begin
            Cache_data[index][i] <= Cache_data_next[i];
            tag_field[index][i] <= tag_field_next[i];
        end
        valid_bits[index] <= valid_bits_next;
        dirty_bits[index] <= dirty_bits_next;
        lru_field[index] <= lru_field_next;       
        /*
        $display("proc_stall: ", proc_stall);
        $display("Cache_data0: ",Cache_data[index][0][31:0],
                                 Cache_data[index][0][63:32],
                                 Cache_data[index][0][95:64],
                                 Cache_data[index][0][127:96]);
        $display("Cache_data1: ",Cache_data[index][1][31:0],
                                 Cache_data[index][1][63:32],
                                 Cache_data[index][1][95:64],
                                 Cache_data[index][1][127:96]);
        $display("mem_addr: ", mem_addr, "proc_addr: ", proc_addr[ADDR_WIDTH-1:2]);
        $display("mem_ready: ", mem_ready, " hit:", hit);
        */
    end
end

always@( * ) begin
    // default value
    for (i=0; i<WAY_NUM; i=i+1) begin    
        tag_field_next[i] = tag_field[index][i];
        Cache_data_next[i] = Cache_data[index][i];
    end
    valid_bits_next = valid_bit;
    dirty_bits_next = dirty_bit;
    lru_field_next = current_lru;

    mem_addr = 0;
    mem_read = 1'b0;
    mem_write = 1'b0;
    for (i=0; i<WAY_NUM; i=i+1) begin
        hit[i] = (valid_bit[i] & (tag_field[index][i] == tag));
    end
    fetch_write = (|hit) ? 2'b00 : (lru_field[index]) ? 2'b10 : 2'b01;

    if ( ~(|hit) & (proc_read^proc_write) ) begin
        // If dirty, write back 
        if ( |fetch_write & dirty_bit[fetch_num] & valid_bit[fetch_num] ) begin
            // Wait for data from memory 
            if ( ~mem_ready ) begin
                mem_addr = {tag_field_next[fetch_num],index};
                // mem_read = 0;
                mem_write = 1'b1;
            end
            else begin
                dirty_bits_next[fetch_num] = 1'b0;
            end
        end
        // Not dirty, read from memory 
        else begin
            if ( ~mem_ready )begin
                mem_addr = proc_addr[ADDR_WIDTH-1:2];
                mem_read = 1'b1;
                // mem_write = 0;
            end
            // Data from memory is ready, write data into cache 
            else begin
                // mem_addr = 0;
                // mem_read = 0;
                // mem_write = 0;
                Cache_data_next[fetch_num] = mem_rdata;
                tag_field_next[fetch_num] = tag;
                valid_bits_next[fetch_num] = 1'b1;
                dirty_bits_next[fetch_num] = 1'b0;
            end
        end
    end
    else if ( |hit & proc_write & ~proc_read) begin
        dirty_bits_next[hit_num] = 1'b1; 
        lru_field_next = hit_num;
        case( word_offset )
            2'b00: Cache_data_next[hit_num][31:0] = proc_wdata;
            2'b01: Cache_data_next[hit_num][63:32] = proc_wdata;
            2'b10: Cache_data_next[hit_num][95:64] = proc_wdata;
            2'b11: Cache_data_next[hit_num][127:96] = proc_wdata;
        endcase
    end
    else if ( |hit & proc_read & ~proc_write) begin
       lru_field_next = hit[0] ? 1'b1 : 1'b0;     
    end
end
endmodule

`else
module cache(
    clk,
    proc_reset,
    proc_read,
    proc_write,
    proc_addr,
    proc_wdata,
    proc_stall,
    proc_rdata,
    mem_read,
    mem_write,
    mem_addr,
    mem_rdata,
    mem_wdata,
    mem_ready
);
//==== parameter definition ===============================
    parameter      WORD_WIDTH = 32;
    parameter      WORD_NUM = 4;
    parameter      BLOCK_WIDTH = WORD_NUM*WORD_WIDTH;
    `ifdef L1SIZE_4
    parameter      BLOCK_NUM = 4;
    parameter      ENTRY_WIDTH = 2;
    `elsif L1SIZE_8
    parameter      BLOCK_NUM = 8;
    parameter      ENTRY_WIDTH = 3;
    `else
    parameter      BLOCK_NUM = 8;
    parameter      ENTRY_WIDTH = 3;
    `endif
    parameter      ADDR_WIDTH = 30;
    parameter      M_ADDR_WIDTH = 28;
    parameter      TAG_WIDTH = M_ADDR_WIDTH - ENTRY_WIDTH;
//==== input/output definition ============================
    input          clk;
    // processor interface
    input                           proc_reset;
    input                           proc_read, proc_write;
    input       [ADDR_WIDTH-1:0]    proc_addr;
    input       [WORD_WIDTH-1:0]    proc_wdata;
    output wire                     proc_stall;
    output wire [WORD_WIDTH-1:0]    proc_rdata;
    // memory interface
    input       [BLOCK_WIDTH-1:0]   mem_rdata;
    input                           mem_ready;
    output                          mem_read, mem_write;
    output      [M_ADDR_WIDTH-1:0]  mem_addr;
    output wire [BLOCK_WIDTH-1:0]   mem_wdata;
//==== wire/reg definition ================================
    //==== memory related register ====//
    reg                             mem_read, mem_write;
    reg         [M_ADDR_WIDTH-1:0]  mem_addr;
    //==== cache related register ====//  _next: buffer for next clk posedge
    reg                         hit;
    reg     [BLOCK_NUM-1:0]     valid_bits;
    reg                         valid_bits_next;
    reg     [BLOCK_NUM-1:0]     dirty_bits; 
    reg                         dirty_bits_next;
    reg     [TAG_WIDTH-1:0]     tag_field[BLOCK_NUM-1:0]; 
    reg     [TAG_WIDTH-1:0]     tag_field_next;
    reg     [WORD_WIDTH-1:0]    Cache_data[BLOCK_NUM-1:0][WORD_NUM-1:0];      
    reg     [WORD_WIDTH-1:0]    Cache_data_next[WORD_NUM-1:0];        // origin setting: [154]: valid bit, [153]: dirty bit, [152:128]: tag, [127:0]: data
    //==== wires ====//
    wire                        valid_bit, dirty_bit;
    wire    [1:0]               word_offset;
    wire    [ENTRY_WIDTH-1:0]   index;
    wire    [TAG_WIDTH-1:0]     tag, current_tag;

    integer        i;
//==== combinational circuit ==============================
    assign valid_bit        = valid_bits[index];
    assign dirty_bit        = dirty_bits[index];
    assign current_tag      = tag_field[index];
    assign word_offset      = proc_addr[1:0];                           // 4 words in 1 block
    assign index            = proc_addr[ENTRY_WIDTH+1:2];               // 8 block in cache unit
    assign tag              = proc_addr[ADDR_WIDTH-1:ENTRY_WIDTH+2];    // remain bits in address

    assign proc_stall       = (proc_read|proc_write)?(hit)? 1'b0 : 1'b1 : 1'b0;
    assign proc_rdata       = Cache_data[index][word_offset];
    assign mem_wdata        = {Cache_data[index][3],Cache_data[index][2],Cache_data[index][1],Cache_data[index][0]};
//==== sequential circuit =================================
always@( posedge clk or posedge proc_reset ) begin
    if ( proc_reset ) begin
        for (i=0; i<BLOCK_NUM-1; i=i+1) begin
            {tag_field[i],Cache_data[i][3],Cache_data[i][2],Cache_data[i][1],Cache_data[i][0]} <= 0;
        end
        valid_bits <= 0;
        dirty_bits <= 0;
    end
    else begin
        {Cache_data[index][3],Cache_data[index][2],Cache_data[index][1],Cache_data[index][0]} <=
        {Cache_data_next[3],Cache_data_next[2],Cache_data_next[1],Cache_data_next[0]};
        valid_bits[index] <= valid_bits_next;
        dirty_bits[index] <= dirty_bits_next;
        tag_field[index] <= tag_field_next;
        /*
        $display("proc_stall: ", proc_stall);
        $display("mem_addr: ", mem_addr, "proc_addr: ", proc_addr[ADDR_WIDTH-1:2]);
        $display("mem_ready: ", mem_ready, " hit:", hit);
        */
    end
end

always@( * ) begin
    // default value
    {valid_bits_next,dirty_bits_next,tag_field_next} = {valid_bits[index],dirty_bits[index],tag_field[index]};
    {Cache_data_next[3],Cache_data_next[2],Cache_data_next[1],Cache_data_next[0]} = 
    {Cache_data[index][3],Cache_data[index][2],Cache_data[index][1],Cache_data[index][0]};
    mem_addr = 0;
    mem_read = 1'b0;
    mem_write = 1'b0;
    hit = (valid_bit & (current_tag == tag));
    if ( ~hit & (proc_read^proc_write) ) begin
        // If dirty, write back 
        if ( dirty_bit & valid_bit ) begin
            // Wait for data from memory 
            if ( ~mem_ready ) begin
                mem_addr = {current_tag,index};
                // mem_read = 0;
                mem_write = 1'b1;
            end
            else begin
                dirty_bits_next = 1'b0;
            end
        end
        // Not dirty, read from memory 
        else begin
            if ( ~mem_ready )begin
                mem_addr = proc_addr[ADDR_WIDTH-1:2];
                mem_read = 1'b1;
                // mem_write = 0;
            end
            // Data from memory is ready, write data into cache 
            else begin
                // mem_addr = 0;
                // mem_read = 0;
                // mem_write = 0;
                {Cache_data_next[3],Cache_data_next[2],Cache_data_next[1],Cache_data_next[0]} = mem_rdata;
                tag_field_next = tag;
                valid_bits_next = 1'b1;
                dirty_bits_next = 1'b0;
            end
        end
    end
    else if ( hit & proc_write & ~proc_read) begin
        dirty_bits_next = 1'b1;
        case( word_offset )
            2'b00: Cache_data_next[0] = proc_wdata;
            2'b01: Cache_data_next[1] = proc_wdata;
            2'b10: Cache_data_next[2] = proc_wdata;
            2'b11: Cache_data_next[3] = proc_wdata;
        endcase
    end
end
endmodule
`endif
