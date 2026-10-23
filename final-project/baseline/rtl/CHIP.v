// Top module of your design, you cannot modify this module!!
module CHIP (	clk,
				rst_n,
//----------for slow_memD------------
				mem_read_D,
				mem_write_D,
				mem_addr_D,
				mem_wdata_D,
				mem_rdata_D,
				mem_ready_D,
//----------for slow_memI------------
				mem_read_I,
				mem_write_I,
				mem_addr_I,
				mem_wdata_I,
				mem_rdata_I,
				mem_ready_I,
//----------for TestBed--------------				
				DCACHE_addr, 
				DCACHE_wdata,
				DCACHE_wen   
			);
input			clk, rst_n;
//--------------------------

output			mem_read_D;
output			mem_write_D;
output	[31:4]	mem_addr_D;
output	[127:0]	mem_wdata_D;
input	[127:0]	mem_rdata_D;
input			mem_ready_D;
//--------------------------
output			mem_read_I;
output			mem_write_I;
output	[31:4]	mem_addr_I;
output	[127:0]	mem_wdata_I;
input	[127:0]	mem_rdata_I;
input			mem_ready_I;
//----------for TestBed--------------
output	[29:0]	DCACHE_addr;
output	[31:0]	DCACHE_wdata;
output			DCACHE_wen;
//--------------------------

// wire declaration
wire        ICACHE_ren;
wire        ICACHE_wen;
wire [29:0] ICACHE_addr;
wire [31:0] ICACHE_wdata;
wire        ICACHE_stall;
wire [31:0] ICACHE_rdata;

wire        DCACHE_ren;
wire        DCACHE_wen;
wire [29:0] DCACHE_addr;
wire [31:0] DCACHE_wdata;
wire        DCACHE_stall;
wire [31:0] DCACHE_rdata;

//=========================================
	// Note that the overall design of your MIPS includes:
	// 1. pipelined MIPS processor
	// 2. data cache
	// 3. instruction cache


	MIPS_Pipeline i_MIPS(
		// control interface
		.clk			(clk), 
		.rst_n			(rst_n),
//----------I cache interface-------		
		.ICACHE_ren		(ICACHE_ren),
		.ICACHE_wen		(ICACHE_wen),
		.ICACHE_addr	(ICACHE_addr),
		.ICACHE_wdata	(ICACHE_wdata),
		.ICACHE_stall	(ICACHE_stall),
		.ICACHE_rdata	(ICACHE_rdata),
//----------D cache interface-------
		.DCACHE_ren		(DCACHE_ren),
		.DCACHE_wen		(DCACHE_wen),
		.DCACHE_addr	(DCACHE_addr),
		.DCACHE_wdata	(DCACHE_wdata),
		.DCACHE_stall	(DCACHE_stall),
		.DCACHE_rdata	(DCACHE_rdata)
	);
	
	cache D_cache(
		.clk		(clk),
		.proc_reset	(~rst_n),
		.proc_read	(DCACHE_ren),
		.proc_write	(DCACHE_wen),
		.proc_addr	(DCACHE_addr),
		.proc_wdata	(DCACHE_wdata),
		.proc_stall	(DCACHE_stall),
		.proc_rdata	(DCACHE_rdata),
		.mem_read	(mem_read_D),
		.mem_write	(mem_write_D),
		.mem_addr	(mem_addr_D),
		.mem_rdata	(mem_rdata_D),
		.mem_wdata	(mem_wdata_D),
		.mem_ready	(mem_ready_D)
	);

	cache I_cache(
		.clk		(clk),
		.proc_reset	(~rst_n),
		.proc_read	(ICACHE_ren),
		.proc_write	(ICACHE_wen),
		.proc_addr	(ICACHE_addr),
		.proc_wdata	(ICACHE_wdata),
		.proc_stall	(ICACHE_stall),
		.proc_rdata	(ICACHE_rdata),
		.mem_read	(mem_read_I),
		.mem_write	(mem_write_I),
		.mem_addr	(mem_addr_I),
		.mem_rdata	(mem_rdata_I),
		.mem_wdata	(mem_wdata_I),
		.mem_ready	(mem_ready_I)
	);
endmodule

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

	parameter CACHE_NUM = 8;
	parameter CACHE_WIDTH = 155; //32*4+25(block[152:128])+1(block[154])+1(block[153])
    
//==== input/output definition ============================
    input          clk;
    // processor interface
    input          proc_reset;
    input          proc_read, proc_write;
    input   [29:0] proc_addr;
    input   [31:0] proc_wdata;
    output         proc_stall;
    output  [31:0] proc_rdata;
    // memory interface
    input  [127:0] mem_rdata;
    input          mem_ready;
    output         mem_read, mem_write;
    output  [27:0] mem_addr;
    output [127:0] mem_wdata;
    
//==== wire/reg definition ================================
    
	//cache block[154]=[154] block[153]=[153] block[152:128]=[152:128] set0=[127:96] set1=[95:64] set2=[63:32] set3=[31;0]
	reg		[CACHE_WIDTH-1:0] cache [0:CACHE_NUM-1];	
	//output
	//processor interface
	reg		[31:0] proc_rdata;
	reg			   proc_stall;
	//memory interface
	reg			   mem_read,mem_write;
	reg		[27:0] mem_addr;
	reg	   [127:0] mem_wdata;
	
	integer i;
	
	reg	   [154:0] block;

//==== combinational circuit ==============================
	
	// read/write in cache
	always@(*) begin
		//default
		block 	   = cache[proc_addr[4:2]];
		mem_read   = 0;
		mem_write  = 0;
		mem_addr   = 0;
		mem_wdata  = 0;
		proc_stall = 0;
		proc_rdata = 0;
		//read
		if (proc_read || proc_write)begin
			//if valid = 1
			if (block[154] == 1) begin
				//if tag same, get value from cache
				//read hit
				if(block[152:128] == proc_addr[29:5])begin
					if(proc_read) begin
						case(proc_addr[1:0])
							2'd0: proc_rdata = block[127:96];
							2'd1: proc_rdata = block[95:64];
							2'd2: proc_rdata = block[63:32];
							2'd3: proc_rdata = block[31:0];
						endcase
						proc_stall = 0;
					end
					//proc_write
					else begin
						case(proc_addr[1:0])
							2'd0: block[127:96] = proc_wdata;
							2'd1: block[95:64]  = proc_wdata;
							2'd2: block[63:32]  = proc_wdata;
							2'd3: block[31:0]   = proc_wdata;
						endcase
						block[153] = 1;//D=1
						proc_stall = 0;					
					end
				end
				//if tags aren't same
				else begin
					proc_stall = 1; 
					//dirty=0
					if(block[153] == 0) begin
						if(mem_ready == 0) begin
							mem_read = 1;
							mem_write = 0;
							mem_addr = proc_addr[29:2];
						end
						//ready=1
						else begin
							//stop mem
							mem_read  = 0;
							mem_write = 0;
							//write data from mem into cache
							block[127:96]	= mem_rdata[31:0];//block[127:96]
							block[95:64] 	= mem_rdata[63:32];//block[95:64]
							block[63:32] 	= mem_rdata[95:64];//block[63:32]
							block[31:0] 	= mem_rdata[127:96];//block[31:0]
							block[152:128]  = proc_addr[29:5];//block[152:128]
							//then go to read hit
						end
					end
					//dirty=1,write back
					else begin
						//write data into mem
						if(mem_ready == 0 ) begin
							mem_read  = 0;
							mem_write = 1;
							mem_addr  = {block[152:128],proc_addr[4:2]}; //the address for writing data
							mem_wdata = {block[31:0],block[63:32],block[95:64],block[127:96]};
						end
						//after finishing write back, get value from mem
						else begin
							block[153] = 0;//let dirty = 0, which means it can be write
						end
					end
				end				
			end
			//valid = 0,read miss, need to get value from memory
			else begin
				proc_stall = 1; 
				//get value from mem
				if (mem_ready == 0) begin
					mem_read  = 1;
					mem_write = 0;
					mem_addr  = proc_addr[29:2];
				end
				//write data from mem into cach,and read
				else begin
					mem_read  = 0;
					mem_write = 0;
					block[127:96]	= mem_rdata[31:0];//set0
					block[95:64] 	= mem_rdata[63:32];//set1
					block[63:32] 	= mem_rdata[95:64];//set2
					block[31:0] 	= mem_rdata[127:96];//set3
					block[152:128]  = proc_addr[29:5];//tag
					block[154]= 1;//V=1
					block[153]= 0;//D=1
				end
			end
		end
		
		// read=0 && write=0
		else begin
			mem_read   = 0;
			mem_write  = 0;
			mem_addr   = 0;
			mem_wdata  = 0;
			proc_stall = 0;
			proc_rdata = 0;
		end
	end
	
//==== sequential circuit =================================

	always@(posedge clk or posedge proc_reset) begin
		
		if(proc_reset)begin
			for (i=0;i<CACHE_NUM;i=i+1)
				cache[i] <= 155'b0;	
			
		end
		else begin
			cache[proc_addr[4:2]] <= block;
		end
	end

endmodule

// Pipelined MIPS with Hazard
module MIPS_Pipeline(
		// control interface
		clk, 
		rst_n,
//----------I cache interface-------		
		ICACHE_ren,
		ICACHE_wen,
		ICACHE_addr,
		ICACHE_wdata,
		ICACHE_stall,
		ICACHE_rdata,
//----------D cache interface-------
		DCACHE_ren,
		DCACHE_wen,
		DCACHE_addr,
		DCACHE_wdata,
		DCACHE_stall,
		DCACHE_rdata
	);

//==== in/out declaration =================================
    //-----------ICACHE-----------------------
    input			clk,rst_n;
	input			ICACHE_stall;
	input  [31:0]   ICACHE_rdata;
	output			ICACHE_ren,ICACHE_wen;
	output [29:0]	ICACHE_addr;
	output [31:0]	ICACHE_wdata;
	
	//-----------DCACHE-----------------------
	input			DCACHE_stall;
	input  [31:0]   DCACHE_rdata;
	output			DCACHE_ren,DCACHE_wen;
	output [29:0]	DCACHE_addr;
	output [31:0]	DCACHE_wdata;

//==== reg/wire declaration ===============================

	//the wire for PC
	reg  [31:0] PC_i;
	wire [31:0] PC_o;
	wire [31:0] PC_add4;
	//wire [31:0] PC_branch;
	wire		PCSrc;
	//the wire for branch type
	wire [31:0] jump_addr;
	wire [31:0] Sign_Extend;
	//the wire for control
	wire		RegDst;
	wire		Jump;
	wire		Branch;
	wire		MemRead;
	wire		MemToReg;
	wire [ 1:0]	ALUOp;
	wire		MemWrite;
	wire		ALUSrc;
	wire		RegWrite_WB; //RegWrite_ID = ID_EX_next[0]
	wire		jal_ID,jal_WB;
	wire		jr;
	wire [ 8:0]	control_out;
	//the wire for register
	wire [31:0] IR;
	wire [ 4:0] Reg_R1;
	wire [ 4:0] Reg_R2;
	wire [ 4:0] Reg_W;	
	wire [31:0] WriteData;
	wire [31:0] Reg1_out,Reg2_out;
		
	wire [31:0] ReadData1;
	wire [31:0] ReadData2; 
	wire		ALUzero;
	//the wire for hazard detection
	wire 		Bubble;
	wire		Hazard_stall;
	//the wire for ALU
	wire [ 3:0] ALUctrl;
	wire [31:0] ALUin1;
	wire [31:0] ALUin2;
	wire [31:0] ALUresult;
	
	wire [31:0] BranchAddr;
	wire [31:0] MUX_Branch_o;
	wire [31:0] MUX_Jump_o;
	
	//register
	wire		   IF_flush;
	wire    [ 63:0]IF_ID_next;
	wire    [116:0]ID_EX_next;
	wire	[ 74:0]EX_MEM_next;
	reg	 	[ 63:0]IF_ID;
	reg	 	[116:0]ID_EX;
	reg	    [ 74:0]EX_MEM;
	
	//for forward_unit
	wire 	[  1:0]ForwardA,ForwardB;
	
//==== module connection ==================================

	// FOR ICACHE
	assign ICACHE_ren   = 1;
	assign ICACHE_wen   = 0;
	assign ICACHE_wdata = 0;
	
	//-------------------------IF--------------------------------

	// for jump jr beq
	assign BranchAddr= IF_ID[31:0] + {Sign_Extend[29:0],2'b00};
	assign ALUzero	 = (ReadData1 == ReadData2) ? 1 : 0;
	assign PCSrc	 = ID_EX_next[2] && ALUzero; // ID_EX_next[2] = Branch	
	assign jump_addr = {IF_ID[31:28],IR[25:0],2'b00} ;
	always@(*)begin
		PC_i = PC_add4;
		if(jr)
			PC_i = ReadData1;
		else
		if(Jump)
			PC_i = jump_addr;
		else
		if(PCSrc)
			PC_i = BranchAddr;
		else
			PC_i = PC_add4;
	end
	
	PC PC (
	.PC_i			(PC_i),
	.PC_o			(PC_o),
	.ICACHE_stall_i	(ICACHE_stall),
	.DCACHE_stall_i	(DCACHE_stall),
	.Hazard_stall_i	(Hazard_stall),
	.clk			(clk),
	.rst_n			(rst_n)
	);	
	assign ICACHE_addr = PC_o[31:2];
	
	//adder for PC+4
	Adder Adder0 (
	.data0_i	(PC_o),
	.data1_i	(32'b100),
	.data_o		(PC_add4)
	);
	
	assign IF_ID_next[31: 0] = PC_add4;
	assign IF_ID_next[63:32] = ICACHE_rdata;
	
	//-------------------------ID--------------------------------
	assign IR	  = IF_ID[63:32];	
	assign Reg_R1 = IR[25:21];
	assign Reg_R2 = IR[20:16];	
	Register Register (
	.Reg_R1_i		(Reg_R1),
	.Reg_R2_i		(Reg_R2),
	.Reg_W_i		(Reg_W),
	.RegWrite_WB_i	(RegWrite_WB),
	.jal_ID_i		(jal_ID),
	.jal_WB_i		(jal_WB),
	.PC_add4_i		(IF_ID[31:0]),   //IF_ID[31:0] 為前一個PC+4 if 用PC_add4為在IF stage的PC+4
	.WriteData_i	(WriteData),
	.ReadData1_o	(Reg1_out),
	.ReadData2_o	(Reg2_out),
	.clk			(clk),
	.rst_n			(rst_n)
	);

	MUX4_32b MUX_ForwardA(
	.data0_i(Reg1_out),
	.data1_i(WriteData),
	.data2_i(ALUresult),
	.sel_i	(ForwardA),
	.data_o	(ReadData1)
	);

	MUX4_32b MUX_ForwardB(
	.data0_i(Reg2_out),
	.data1_i(WriteData),
	.data2_i(ALUresult),
	.sel_i	(ForwardB),
	.data_o	(ReadData2)
	);	
	
	assign	IF_flush = Jump || jal_ID || jr || PCSrc;
	Control Control (
	.opcode_i	(IR[31:26]),
	.func_i		(IR[5:0]),
	.RegDst_o	(control_out[5]),
	.Jump_o		(Jump), 
	.Branch_o	(control_out[2]),
	.MemRead_o	(control_out[3]),
	.MemToReg_o	(control_out[1]),
	.ALUOp_o	(control_out[7:6]),
	.MemWrite_o	(control_out[4]),
	.ALUSrc_o	(control_out[8]),
	.RegWrite_o	(control_out[0]),
	.jal_o		(jal_ID),  
	.jr_o		(jr)    
	);
	
	MUX2_9b Bubble0 (
	.data0_i(control_out[8:0]),
	.data1_i(9'b0),
	.sel_i	(Bubble),
	.data_o	(ID_EX_next[8:0])	
	);
	
	//hazard detect to add bubble
	Hazard_detection Hazard_detection(
	.ID_EX_MemRead_i(ID_EX[3]),
	.ID_EX_Rt_i		(ID_EX[115:111]), 
	.IF_ID_Rs_i		(IR[25:21]),
	.IF_ID_Rt_i		(IR[20:16]),
	.Bubble_o		(Bubble),
	.Hazard_stall_o	(Hazard_stall)
	);
	
	
	Sign_Extend Sign_Extend0 (
	.data_i(IR[15:0]),
	.data_o(Sign_Extend)
	);
	assign ID_EX_next[104: 73] = Sign_Extend ;
	
	assign ID_EX_next[ 40:  9] = ReadData1;
	assign ID_EX_next[ 72: 41] = ReadData2;
	assign ID_EX_next[110:105] = IR[31:26]; //opcode
	assign ID_EX_next[115:111] = IR[20:16]; //Rt
	assign ID_EX_next[116]	   = jal_ID;
	
	//-------------------------EX--------------------------------
	
	forward_unit forward_unit( 
	.EX_MEM_Rd_i		(Reg_W), 
	.ID_EX_Rd_i			(EX_MEM_next[73:69]),
	.IF_ID_Rs_i			(IR[25:21]),
	.IF_ID_Rt_i			(IR[20:16]),
	.EX_MEM_RegWrite_i	(EX_MEM[0]), 
	.ID_EX_RegWrite_i	(ID_EX[0]),
	.ForwardA_o			(ForwardA),
	.ForwardB_o			(ForwardB)
	);
	
	assign ALUSrc = ID_EX[8];
	MUX2_32b MUX_ALUSrc (
	.data0_i(ID_EX[72:41]),
	.data1_i(ID_EX[104:73]),
	.sel_i	(ALUSrc),
	.data_o	(ALUin2)
	);
	
	
	assign RegDst = ID_EX[5];
	MUX2_5b MUX_RegDST (
	.data0_i(ID_EX[115:111]),
	.data1_i(ID_EX[ 88: 84]),
	.sel_i	(RegDst),
	.data_o	(EX_MEM_next[73:69])
	);


	assign ALUOp = ID_EX[7:6];
	ALU_Control ALU_Control (
	.opcode_i	(ID_EX[110:105]),
	.func_i		(ID_EX[78:73]),
	.ALUOp_i	(ALUOp),
	.ALUctrl_o	(ALUctrl)
	);

	assign	ALUin1 = ID_EX[40:9]; 
	ALU ALU (
	.ALUin1_i	(ALUin1),
	.ALUin2_i	(ALUin2),
	.ALUctrl_i	(ALUctrl),
	.shamt_i	(ID_EX[83:79]),
	.ALUresult_o(ALUresult)
	);	
	assign EX_MEM_next[36: 5] = ALUresult;
	assign EX_MEM_next[ 4: 0] = ID_EX[ 4: 0];
	assign EX_MEM_next[68:37] = ID_EX[72:41];
	assign EX_MEM_next[74]    = ID_EX[116];
	
	//-------------------------MEM--------------------------------
	assign DCACHE_ren		  = EX_MEM[3];
	assign DCACHE_wen		  = EX_MEM[4];
	assign DCACHE_addr 		  = EX_MEM[36: 7];
	assign DCACHE_wdata 	  = EX_MEM[68:37];
	
	assign RegWrite_WB		  = EX_MEM[0];
	assign Reg_W 	  		  = EX_MEM[73:69];
	assign jal_WB			  = EX_MEM[74];
	
	assign MemToReg = EX_MEM[1];
	MUX2_32b MUX_MemToReg (
	.data0_i(EX_MEM[36:5]),
	.data1_i(DCACHE_rdata),
	.sel_i	(MemToReg),
	.data_o	(WriteData)
	);	
	

	// -------------------------pipeline-----------------------------------
	// for IF_ID
	always@(posedge clk or negedge rst_n) begin
		if (~rst_n ) begin
			IF_ID  <= 0;
		end		
		else 
		if (ICACHE_stall || DCACHE_stall || Hazard_stall ) begin
			IF_ID  <= IF_ID;
		end

		else
		if	(!(ICACHE_stall || DCACHE_stall || Hazard_stall ) && IF_flush == 1)	begin
			IF_ID  <= 0;
		end
		
		else begin
			IF_ID  <= IF_ID_next;
		end
	end
	// for ID_EX EX_MEM MEM_WB 
	always@(posedge clk or negedge rst_n) begin
		if (~rst_n) begin
			ID_EX  <= 0;
			EX_MEM <= 0;
		end		
		else 
		if (ICACHE_stall || DCACHE_stall) begin
			ID_EX  <= ID_EX;
			EX_MEM <= EX_MEM;
		end	
		
		else begin
			ID_EX  <= ID_EX_next;
			EX_MEM <= EX_MEM_next;
		end
	end

endmodule

// Control
module Control (
	opcode_i,
	func_i,	
	RegDst_o,
	Jump_o,
	Branch_o,
	MemRead_o,
	MemToReg_o,
	ALUOp_o,
	MemWrite_o,
	ALUSrc_o,
	RegWrite_o,
	jal_o,
	jr_o
);

	input  [5:0] opcode_i;
	input  [5:0] func_i;
	output 	     RegDst_o;
	output 		 Jump_o;
	output		 Branch_o;
	output		 MemRead_o;
	output		 MemToReg_o;
	output [1:0] ALUOp_o;
	output		 MemWrite_o;
	output 		 ALUSrc_o;
	output 		 RegWrite_o;
	output		 jal_o;
	output		 jr_o;
	
	wire r,lw,sw,beq,jump,jal,jr,imm; //immediate
	
	parameter addi = 6'b001000;
	parameter andi = 6'b101100;
	parameter ori  = 6'b001101;
	parameter xori = 6'b001110;
	parameter slti = 6'b001010;
	
	assign r    = (  opcode_i == 6'b000000 ) ? 1'b1 : 1'b0 ;
	assign lw   = (  opcode_i == 6'b100011 ) ? 1'b1 : 1'b0 ;
	assign sw   = (  opcode_i == 6'b101011 ) ? 1'b1 : 1'b0 ;
	assign beq  = (  opcode_i == 6'b000100 ) ? 1'b1 : 1'b0 ;
	assign jump = (  opcode_i == 6'b000010 ) ? 1'b1 : 1'b0 ;
	assign jal  = (  opcode_i == 6'b000011 ) ? 1'b1 : 1'b0 ;
	assign jr   = ( (opcode_i == 6'b000000) && (func_i == 6'b001000) ) ? 1'b1 : 1'b0 ;
	assign imm  = ( (opcode_i == addi)||(opcode_i == andi)||(opcode_i == ori)||(opcode_i == xori)||(opcode_i == slti) )?1'b1:1'b0;
	
	
	assign RegDst_o   = r ;
	assign Jump_o 	  = jump || jal ;
	assign Branch_o   = beq ;
    assign MemRead_o  = lw ;
	assign MemToReg_o = lw ;
	assign ALUOp_o	  = { ( r || imm ) , ( beq || imm ) } ; //beq can be ignored since ALUzero is calculted in ID
	assign MemWrite_o = sw ;
	assign ALUSrc_o   = lw || sw || imm ;
	assign RegWrite_o = r || lw || jal || imm ;
	assign jal_o 	  = jal ;
	assign jr_o	      = jr ;	

endmodule

// Register
module Register (
	Reg_R1_i,
	Reg_R2_i,
	Reg_W_i,
	RegWrite_WB_i,
	jal_ID_i,
	jal_WB_i,
	PC_add4_i,
	WriteData_i,
	ReadData1_o,
	ReadData2_o,
	clk,
	rst_n
);

	input		  clk; // this clk is for writing data into reg
	input 	      rst_n;
	input		  RegWrite_WB_i,jal_ID_i,jal_WB_i;
	input  [ 4:0] Reg_R1_i;
	input  [ 4:0] Reg_R2_i;
	input  [ 4:0] Reg_W_i;
	input  [31:0] PC_add4_i,WriteData_i;
	output [31:0] ReadData1_o;
	output [31:0] ReadData2_o;
	
	reg [31:0] register [0:31] ; //32個(後面) 有32bits(前面) registers
	integer i ; // use for 'for' loop
	
	assign ReadData1_o = register[Reg_R1_i] ;
	assign ReadData2_o = register[Reg_R2_i] ;
	
	//Writing data 
	always @(posedge clk or negedge rst_n) begin
	
		if (~rst_n) begin
			for ( i = 0 ; i < 32 ; i = i + 1) begin
				register[i] <= 0 ;
			end	
		end 
		
		else begin
			if (RegWrite_WB_i && jal_WB_i != 1) begin 
				register[Reg_W_i] <= WriteData_i ;
			end
			
			if (jal_ID_i) begin
				register[31] <= PC_add4_i ;
			end
		end
	end	

endmodule

//Program Counter
module PC (
	PC_i,
	PC_o,
	ICACHE_stall_i,
	DCACHE_stall_i,
	Hazard_stall_i,
	clk,
	rst_n
);

	input		  	  clk;
	input			  rst_n;
	input			  ICACHE_stall_i,DCACHE_stall_i,Hazard_stall_i;
	input  	   [31:0] PC_i;
	output reg [31:0] PC_o;
	
	always @ (posedge clk or negedge rst_n) begin
		if(~rst_n)
			PC_o <= 0;
		else
		if(ICACHE_stall_i || DCACHE_stall_i || Hazard_stall_i)
			PC_o <= PC_o;
		else
			PC_o <= PC_i;
	end
	
endmodule

// ALU
module ALU (
	ALUin1_i,
	ALUin2_i,
	ALUctrl_i,
	shamt_i,
	ALUresult_o
);
	input signed [31:0] ALUin1_i;
	input signed [31:0] ALUin2_i;
	input  		 [ 3:0] ALUctrl_i;
	input  		 [ 4:0] shamt_i;
	
	output reg signed [31:0] ALUresult_o;
	
	parameter AND = 4'b0000;
	parameter OR  = 4'b0001;
	parameter ADD = 4'b0010;
	parameter SUB = 4'b0011;
	parameter SLT = 4'b0100;
	parameter NOR = 4'b0101;
	parameter XOR = 4'b0110;
	parameter SLL = 4'b0111;
	parameter SRA = 4'b1000;
	parameter SRL = 4'b1001;
		
	always @(*) begin
		case(ALUctrl_i)
			AND : ALUresult_o = ALUin1_i & ALUin2_i ;
			OR  : ALUresult_o = ALUin1_i | ALUin2_i ; 
			ADD : ALUresult_o = ALUin1_i + ALUin2_i ; 
			SUB : ALUresult_o = ALUin1_i - ALUin2_i ; 
			SLT : ALUresult_o = (ALUin1_i < ALUin2_i) ? 1 : 0 ;
			NOR : ALUresult_o = ~(ALUin1_i | ALUin2_i) ; 
			XOR : ALUresult_o = ALUin1_i ^ ALUin2_i ; 
			SLL : ALUresult_o = ALUin1_i <<  shamt_i; 
			SRA : ALUresult_o = ALUin1_i >>> shamt_i; 
			SRL : ALUresult_o = ALUin1_i >>  shamt_i; 			
			default : ALUresult_o = 0;
		endcase
	end 
endmodule

//ALU Control for ALU
module ALU_Control (
	opcode_i,
	func_i,
	ALUOp_i,
	ALUctrl_o
);

	input 	    [5:0] opcode_i;
	input 		[5:0] func_i;
	input  		[1:0] ALUOp_i;	
	output reg  [3:0] ALUctrl_o;
	
	parameter AND = 4'b0000;
	parameter OR  = 4'b0001;
	parameter ADD = 4'b0010;
	parameter SUB = 4'b0011;
	parameter SLT = 4'b0100;
	parameter NOR = 4'b0101;
	parameter XOR = 4'b0110;
	parameter SLL = 4'b0111;
	parameter SRA = 4'b1000;
	parameter SRL = 4'b1001;
	
	always@(*) begin
		case(ALUOp_i)
		//lw sw
		2'b00: 	ALUctrl_o = ADD;
		
		//beq
		2'b01: 	ALUctrl_o = SUB;
		
		//add sub and or slt xor nor sll sra srl
		2'b10: begin
			case(func_i)
			6'b100000: ALUctrl_o = ADD;
			6'b100010: ALUctrl_o = SUB;
			6'b100100: ALUctrl_o = AND;
			6'b100101: ALUctrl_o = OR;
			6'b101010: ALUctrl_o = SLT;
			6'b100110: ALUctrl_o = XOR;
			6'b100111: ALUctrl_o = NOR;
			6'b000000: ALUctrl_o = SLL;
			6'b000011: ALUctrl_o = SRA;
			6'b000010: ALUctrl_o = SRL;
			default:   ALUctrl_o = 0;	
			endcase
		end
		//addi andi ori xori slti
		2'b11:
			case(opcode_i)
			6'b001000: ALUctrl_o = ADD;
			6'b101100: ALUctrl_o = AND;
			6'b001101: ALUctrl_o = OR;
			6'b001110: ALUctrl_o = XOR;
			6'b001010: ALUctrl_o = SLT;
			default:   ALUctrl_o = 0;
			endcase
		endcase
	end

endmodule

// Adder
module Adder (
	data0_i,
	data1_i,
	data_o
);

	input  [31:0] data0_i;
	input  [31:0] data1_i;
	output [31:0] data_o;
	
	assign data_o = data0_i + data1_i ;
	
endmodule

// extend 16-bits to 32-bits
module Sign_Extend (
	data_i,
	data_o
);

	input  [15:0] data_i;
	output [31:0] data_o;
	
	assign data_o = { {16{data_i[15]}} , data_i } ;
	
endmodule

// 2-to-1 MUX for  whose input is 5-bits
module MUX2_5b (
	data0_i,
	data1_i,
	sel_i,
	data_o
);

	input  [4:0] data0_i;
	input  [4:0] data1_i;
	input		 sel_i;	
	output [4:0] data_o;
	
	assign data_o = sel_i ? data1_i : data0_i;
	
endmodule

// 2-to-1 MUX for Branch, Jump, Control, MemToReg whose input is 32-bits
module MUX2_32b (
	data0_i,
	data1_i,
	sel_i,
	data_o
);

	input  [31:0] data0_i;
	input  [31:0] data1_i;
	input	      sel_i;	
	output [31:0] data_o;
	
	assign data_o = sel_i ? data1_i : data0_i;
	
endmodule

module	MUX2_9b (
	data0_i,
	data1_i,
	sel_i,
	data_o
);

	input  [8:0] data0_i;
	input  [8:0] data1_i;
	input	     sel_i;	
	output [8:0] data_o;
	
	assign data_o = sel_i ? data1_i : data0_i;	
	
endmodule

module	MUX4_32b (
	data0_i,
	data1_i,
	data2_i,
	sel_i,
	data_o
);

	input		[31:0] data0_i,data1_i,data2_i;
	input		[ 1:0] sel_i;
	output	reg [31:0] data_o;
	
	always@(*) begin
		case(sel_i)
		2'b00: 	 data_o = data0_i;
		2'b01: 	 data_o = data1_i;
		2'b10: 	 data_o = data2_i;
		default: data_o = data0_i;
		endcase
	end
	
endmodule


module Hazard_detection (
	ID_EX_MemRead_i,
	ID_EX_Rt_i,
	IF_ID_Rs_i,
	IF_ID_Rt_i,
	Bubble_o,
	Hazard_stall_o
);

	input 		ID_EX_MemRead_i;
	input [4:0]	ID_EX_Rt_i,IF_ID_Rs_i,IF_ID_Rt_i;
	
	output reg Hazard_stall_o,Bubble_o;
	
	always@(*) begin	
		if(ID_EX_MemRead_i == 1 && ( ID_EX_Rt_i == IF_ID_Rs_i || ID_EX_Rt_i == IF_ID_Rt_i )) begin
			Hazard_stall_o = 1;
			Bubble_o	   = 1;
		end
		else begin
			Hazard_stall_o = 0;
			Bubble_o	   = 0;
		end
	end

endmodule

module forward_unit ( 
	EX_MEM_Rd_i, 
	ID_EX_Rd_i,
	IF_ID_Rs_i,
	IF_ID_Rt_i,
	EX_MEM_RegWrite_i, 
	ID_EX_RegWrite_i,
	ForwardA_o,
	ForwardB_o
);

    input       [4:0] EX_MEM_Rd_i, ID_EX_Rd_i; // address of pipeline register
	input       [4:0] IF_ID_Rs_i,IF_ID_Rt_i; // for add beq
	input             EX_MEM_RegWrite_i,ID_EX_RegWrite_i; // signal of write register
	output reg	[1:0] ForwardA_o,ForwardB_o; //selection signal of mux for readdata1 readdata2

	//for ForwardA
	always@(*) begin
	
		if (EX_MEM_RegWrite_i == 1 && EX_MEM_Rd_i != 0 && EX_MEM_Rd_i == IF_ID_Rs_i && 
			!(ID_EX_RegWrite_i == 1 && ID_EX_Rd_i != 0 && ID_EX_Rd_i == IF_ID_Rs_i))
			ForwardA_o = 2'b01;
			
		else
		if (ID_EX_RegWrite_i == 1 && ID_EX_Rd_i != 0 && ID_EX_Rd_i == IF_ID_Rs_i)
			ForwardA_o = 2'b10;
			
		else
			ForwardA_o = 2'b00;
	end
	
	//for ForwardB
	always@(*) begin
	
		if (EX_MEM_RegWrite_i == 1 && EX_MEM_Rd_i != 0 && EX_MEM_Rd_i == IF_ID_Rt_i && 
			!(ID_EX_RegWrite_i == 1 && ID_EX_Rd_i != 0 && ID_EX_Rd_i == IF_ID_Rt_i))
			ForwardB_o = 2'b01;
			
		else
		if (ID_EX_RegWrite_i == 1 && ID_EX_Rd_i != 0 && ID_EX_Rd_i == IF_ID_Rt_i)
			ForwardB_o = 2'b10;
			
		else
			ForwardB_o = 2'b00;
	end	
	
endmodule