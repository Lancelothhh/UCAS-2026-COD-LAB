`timescale 10ns / 1ns

`define ALUop_AND  3'b000
`define ALUop_OR   3'b001
`define ALUop_ADD  3'b010
`define ALUop_SUB  3'b110
`define ALUop_SLT  3'b111
`define ALUop_XOR  3'b100
`define ALUop_NOR  3'b101
`define ALUop_SLTU 3'b011

`define SPECIAL  6'b000000
`define R_Alu 	 4'b0000
`define R_Shift  4'b0001
`define R_Jump 	 4'b0010
`define R_Move 	 4'b0011
`define REGIMM 	 4'b0100
`define JType 	 4'b0101
`define I_Branch 4'b0110
`define I_Alu 	 4'b0111
`define lui 	 4'b1000
`define I_Load 	 4'b1001
`define I_Store  4'b1010
`define Mul      4'b1011 

`define SHIFTOP_SLL  2'b00
`define SHIFTOP_SRL  2'b10
`define SHIFTOP_SRA  2'b11 


module custom_cpu(
	input         clk,
	input         rst,

	//Instruction request channel
	output reg [31:0] PC,
	output        Inst_Req_Valid,
	input         Inst_Req_Ready,

	//Instruction response channel
	input  [31:0] Instruction,
	input         Inst_Valid,
	output        Inst_Ready,

	//Memory request channel
	output [31:0] Address,
	output        MemWrite,
	output [31:0] Write_data,
	output [ 3:0] Write_strb,
	output        MemRead,
	input         Mem_Req_Ready,

	//Memory data response channel
	input  [31:0] Read_data,
	input         Read_data_Valid,
	output        Read_data_Ready,

	input         intr,

	output [31:0] cpu_perf_cnt_0,
	output [31:0] cpu_perf_cnt_1,
	output [31:0] cpu_perf_cnt_2,
	output [31:0] cpu_perf_cnt_3,
	output [31:0] cpu_perf_cnt_4,
	output [31:0] cpu_perf_cnt_5,
	output [31:0] cpu_perf_cnt_6,
	output [31:0] cpu_perf_cnt_7,
	output [31:0] cpu_perf_cnt_8,
	output [31:0] cpu_perf_cnt_9,
	output [31:0] cpu_perf_cnt_10,
	output [31:0] cpu_perf_cnt_11,
	output [31:0] cpu_perf_cnt_12,
	output [31:0] cpu_perf_cnt_13,
	output [31:0] cpu_perf_cnt_14,
	output [31:0] cpu_perf_cnt_15,

	output [69:0] inst_retire
);

/* The following signal is leveraged for behavioral simulation, 
* which is delivered to testbench.
*
* STUDENTS MUST CONTROL LOGICAL BEHAVIORS of THIS SIGNAL.
*
* inst_retired (70-bit): detailed information of the retired instruction,
* mainly including (in order) 
* { 
*   reg_file write-back enable  (69:69,  1-bit),
*   reg_file write-back address (68:64,  5-bit), 
*   reg_file write-back data    (63:32, 32-bit),  
*   retired PC                  (31: 0, 32-bit)
* }
*
*/

// TODO: Please add your custom CPU code here
	wire			RF_wen;
	wire [4:0]		RF_waddr;
	wire [31:0]		RF_wdata;
  	wire [4 :0] RF_raddr1, RF_raddr2;
  	wire [31:0] RF_rdata1, RF_rdata2;
        wire [31:0] extend, lui_extend, load_result, SHIFT_result;
        wire        ALUSrc, RegDst;
	reg  [31:0] PC_cur;

	assign inst_retire = {RF_wen, RF_waddr, RF_wdata, PC_cur};

	//Instruction Decode
	wire [5:0]  opcode 	= valid_Instruction[31:26];
	wire [4:0]  rs 		= valid_Instruction[25:21];
	wire [4:0]  rt 		= valid_Instruction[20:16];
	wire [4:0]  rd 		= valid_Instruction[15:11];
	wire [4:0]  shamt 	= valid_Instruction[10:6];
	wire [5:0]  func 	= valid_Instruction[5:0];
	wire [4:0]  base 	= valid_Instruction[25:21];	
	wire [4:0]  REG 	= valid_Instruction[20:16];	
	wire [15:0] imm 	= valid_Instruction[15:0];
	wire [25:0] Instr_index = valid_Instruction[25:0];

	wire [3:0] mode = 	{4{opcode == `SPECIAL && func[5] == 1'b1}} & `R_Alu |
				{4{opcode == `SPECIAL && func[5:3] == 3'b000}} & `R_Shift |
				{4{opcode == `SPECIAL && {func[5:3], func[1]} == 4'b0010}} & `R_Jump |
				{4{opcode == `SPECIAL && {func[5:3], func[1]} == 4'b0011}} & `R_Move |
				{4{opcode == 6'b000001}} & `REGIMM |
				{4{opcode[5:1] == 5'b00001}} & `JType |
				{4{opcode[5:2] == 4'b0001}} & `I_Branch |
				{4{opcode[5:3] == 3'b001 && opcode != 6'b001111}} & `I_Alu |
				{4{opcode == 6'b001111}} & `lui |
				{4{opcode == 6'b011100 && shamt == 5'b00000 && func == 6'b000010}} & `Mul |
				{4{opcode[5:3] == 3'b100}} & `I_Load |
				{4{opcode[5:3] == 3'b101}} & `I_Store;

	//ALU control
	wire [2:0] ALU_op = 	{{3{mode == `R_Alu && func[3:2] == 2'b00}} & {func[1], 2'b10}}|//addu,subu
			    	{{3{mode == `R_Alu && func[3:2] == 2'b01}} & {func[1], 1'b0, func[0]}}|//and,or,xor,nor
			    	{{3{mode == `R_Alu && func[3:2] == 2'b10}} & {~func[0], 2'b11}}|//slt,sltu
			    	{{3{mode == `I_Alu && opcode[2:0] == 3'b001}} & {opcode[1], 2'b10}}|//addiu
			    	{{3{mode == `I_Alu && opcode[2] == 1'b1}} & {opcode[1], 1'b0, opcode[0]}}|//andi,ori,xori
			    	{{3{mode == `I_Alu && opcode[2:1] == 2'b01}} & {~opcode[0], 2'b11}}|//slti,sltiu
			    	{{3{mode == `R_Move}} & `ALUop_SUB}|//movz,movn
			    	{{3{mode == `REGIMM}} & `ALUop_SLT}|//bltz,bgez
			    	{{3{mode == `I_Branch && opcode[1] == 1'b0}} & `ALUop_SUB}|//beq，bne
				{{3{mode == `I_Branch && opcode[1] == 1'b1}} & `ALUop_SUB}|//blez,bgtz
				{{3{mode == `I_Load || mode == `I_Store}} & `ALUop_ADD};//lw,sw

	wire [31:00] A_aftmux =	(mode == `R_Move)? RF_rdata2: RF_rdata1;
	wire [31:00] B_aftmux =	{{32{ALUSrc}}&extend}|
				{{32{mode ==`R_Alu || mode == `I_Branch}} & RF_rdata2}|
				{{32{mode == `R_Move || mode == `REGIMM}} & 32'b0};

	wire [31:0] ALU_result;
	wire Zero;
	alu alu_module(
		.A(A_aftmux),
		.B(B_aftmux),
		.ALUop(ALU_op),
		.Result(ALU_result),
		.Overflow(),
		.CarryOut(),
		.Zero(Zero)
	);

	// mul control
	wire [63:0] MUL_result_full = RF_rdata1 * RF_rdata2;
	wire [31:0] MUL_result      = MUL_result_full[31:0];

	//imm extended control
	wire [31:0] sign_extend 	= {{16{imm[15]}}, imm};
	wire [31:0] zero_extend 	= {16'b0, imm};
	wire [31:0] offset_two_extend 	= {{14{imm[15]}}, imm, 2'b0};
	assign lui_extend 		= {imm, 16'b0};
	assign extend			= (((mode == `I_Alu)&&(ALU_op!={opcode[1], 1'b0, opcode[0]}))||
					(mode == `I_Load)||
					(mode == `I_Store))?sign_extend:zero_extend;

	//load control
	assign 	Address 	= 	{ALU_result[31:2],2'b00};
	wire [1:0]  Addr_low 	= 	ALU_result[1:0];
	wire [7:0]  byte_read	= 	(Addr_low == 2'b00)?valid_Read_data[7:0]:
				  	(Addr_low == 2'b01)?valid_Read_data[15:8]:
				  	(Addr_low == 2'b10)?valid_Read_data[23:16]:
				  		            valid_Read_data[31:24];
	wire [15:0] half_read	= 	(Addr_low[1])?valid_Read_data[31:16]:
						      valid_Read_data[15:0];
	wire [31:0] lwl_read	= 	(Addr_low == 2'b00)?{valid_Read_data[7:0],RF_rdata2[23:0]}:
				  	(Addr_low == 2'b01)?{valid_Read_data[15:0],RF_rdata2[15:0]}:
				  	(Addr_low == 2'b10)?{valid_Read_data[23:0],RF_rdata2[7:0]}:
				  		      {valid_Read_data[31:0]};
	wire [31:0] lwr_read	= 	(Addr_low == 2'b00)?valid_Read_data[31:0]:
				  	(Addr_low == 2'b01)?{RF_rdata2[31:24],valid_Read_data[31:8]}:
				  	(Addr_low == 2'b10)?{RF_rdata2[31:16],valid_Read_data[31:16]}:
				  		     	    {RF_rdata2[31:8],valid_Read_data[31:24]};
	assign      load_result = 	(opcode == 6'b100000)?{{24{byte_read[7]}}, byte_read}://lb
    					(opcode == 6'b100100)?{24'b0, byte_read}://lbu
    					(opcode == 6'b100001)?{{16{half_read[15]}}, half_read}://lh
   					(opcode == 6'b100101)?{16'b0, half_read}://lhu
    					(opcode == 6'b100011)?valid_Read_data://lw
    					(opcode == 6'b100010)?lwl_read://lwl
    					(opcode == 6'b100110)?lwr_read://lwr
    							      32'b0; 
	
	//store control
	assign Write_strb 	= 	(opcode == 6'b101011)?4'b1111: //sw
					(opcode == 6'b101001)?((Addr_low == 2'b00)?4'b0011:4'b1100): //sh
					(opcode == 6'b101000)? ((Addr_low == 2'b00)?4'b0001:
							        (Addr_low == 2'b01)?4'b0010:
							        (Addr_low == 2'b10)?4'b0100:
							                            4'b1000)://sb
					(opcode == 6'b101010)? ((Addr_low == 2'b11)?4'b1111:
                            					(Addr_low == 2'b10)?4'b0111:
                            					(Addr_low == 2'b01)?4'b0011: 
                                               		 			    4'b0001)://swl
					(opcode == 6'b101110)? ((Addr_low == 2'b11)?4'b1000: 
                            					(Addr_low == 2'b10)?4'b1100: 
                            					(Addr_low == 2'b01)?4'b1110: 
                                                				    4'b1111)://swr
										    4'b0000;
	assign Write_data 	=     	(opcode == 6'b101011)? RF_rdata2://sw
                        		(opcode == 6'b101001)? ((Addr_low == 2'b00)?{16'b0,RF_rdata2[15:0]}: 
                                                                {RF_rdata2[15:0],16'b0})://sh
                        		(opcode == 6'b101000)? ((Addr_low == 2'b00)?{24'b0,RF_rdata2[7:0]}:
                                                		(Addr_low == 2'b01)?{16'b0,RF_rdata2[7:0],8'b0}:
                                                		(Addr_low == 2'b10)?{8'b0,RF_rdata2[7:0],16'b0}:
                                                                {RF_rdata2[7:0], 24'b0})://sb
                        		(opcode == 6'b101010)? ((Addr_low == 2'b11)?RF_rdata2[31:0] :
                            					(Addr_low == 2'b10)?{8'b0,  RF_rdata2[31:8]}:
                            					(Addr_low == 2'b01)?{16'b0, RF_rdata2[31:16]}:
                                                 				    {24'b0, RF_rdata2[31:24]})://swl
                        		(opcode == 6'b101110)? ((Addr_low == 2'b11)?{RF_rdata2[7:0], 24'b0}:
                            					(Addr_low == 2'b10)?{RF_rdata2[15:0], 16'b0}:
                            					(Addr_low == 2'b01)?{RF_rdata2[23:0], 8'b0} :
                                                 				     RF_rdata2[31:0]):// swr
                        					32'b0;

	//shifter control
	wire [4:0] shiftbit 	 = {{5{mode == `R_Shift && func[5:2] == 4'b0000 }} & shamt} |
				   {{5{mode == `R_Shift && func[5:2] == 4'b0001}} & RF_rdata1[4:0]}; 
	wire [1:0] SHIFT_control = func[1:0];
	shifter shifter_module(RF_rdata2, shiftbit, SHIFT_control, SHIFT_result);

	
	//move control
	wire Mov_true = (mode == `R_Move)&((func[0]==1'b0 & Zero)|(func[0]==1'b1 & ~Zero));

	//reg_file control
	assign RF_wdata = 	(mode == `R_Alu || mode == `I_Alu)? ALU_result:
				(mode == `Mul)? MUL_result:
				(mode == `R_Shift)? SHIFT_result:
				(opcode == 6'b000011 || (mode == `R_Jump && func == 6'b001001))? PC_cur + 8:
				(mode == `I_Load)? load_result:
				(mode == `R_Move)? RF_rdata1:lui_extend;
	assign RF_waddr 	= (opcode == 6'b000011)? 31:((RegDst)? rd:rt);
	assign RF_raddr1 	= rs;
	assign RF_raddr2 	= (mode == `REGIMM)? 5'b0:rt;
	assign RF_wen = 	(current_state == WB) &&((mode == `R_Alu)||
							(mode == `R_Shift)||
							((mode == `R_Jump)&&func[0])||
							((mode == `JType) && opcode[0])||
							(mode == `I_Alu)||
							(mode == `I_Load)||
							(mode == `lui)||
							(mode == `Mul)||
							Mov_true);
	reg_file reg_file_module(
		.clk(clk),
		.waddr(RF_waddr),
		.raddr1(RF_raddr1),
		.raddr2(RF_raddr2),
		.wen(RF_wen),
		.wdata(RF_wdata),
		.rdata1(RF_rdata1),
		.rdata2(RF_rdata2)
		);

	//cpu control
	wire MemtoReg	= 	(mode == `I_Load);
	wire Branch	=	((mode == `REGIMM)||(mode == `I_Branch));
	assign ALUSrc	= 	((mode == `I_Alu)||(mode == `I_Load)||(mode == `I_Store));
	assign RegDst 	= 	((mode == `R_Alu)||(mode == `R_Shift)||(mode == `R_Jump)||(mode == `R_Move)||(mode == `Mul));

	//branch control
	wire isbranch = ((mode ==  `I_Branch) & (opcode[1:0] == 2'b00) & Zero)|
			((mode ==  `I_Branch) & (opcode[1:0] == 2'b01) & ~Zero)|
			((mode ==  `I_Branch) & (opcode[1:0] == 2'b10) & (ALU_result[31]|Zero))|
			((mode ==  `I_Branch) & (opcode[1:0] == 2'b11) & (~ALU_result[31]&~Zero))|
			((mode == `REGIMM) & (REG[0] == 0) & ALU_result[0])|
			((mode == `REGIMM) & (REG[0] == 1) & ~ALU_result[0]);




	//Sequential circuit control
  	reg 	[8:0]	current_state;
  	reg	[8:0]	next_state;
  	reg 	[31:0] 	valid_Instruction;
  	reg 	[31:0] 	valid_Read_data;

	localparam 	INIT 	= 9'b000000001;
	localparam 	IF   	= 9'b000000010;
	localparam	IW 	= 9'b000000100;
	localparam	ID	= 9'b000001000;
	localparam	EX 	= 9'b000010000;
	localparam	ST 	= 9'b000100000;
	localparam	WB	= 9'b001000000;
	localparam	LD 	= 9'b010000000;
	localparam	RDW	= 9'b100000000;

	//part 1
	always @ (posedge clk)
	begin
		if(rst) 
			current_state <= INIT;
		else
			current_state <= next_state;
	end

	//part 2

	always @ (*)
	begin
		case(current_state)
		INIT:begin
			next_state = IF;
		end

		IF:begin
			if(Inst_Req_Ready)
			next_state = IW;
			else
			next_state = IF;
		end

		IW:begin
			if(Inst_Valid)
			next_state = ID;
			else
			next_state = IW;
		end

		ID:begin
			if(valid_Instruction == 32'b0)
			next_state = IF;
			else
			next_state = EX;	
		end

		EX:begin
			if(mode == `I_Load)
			next_state = LD;
			else if(mode == `I_Store)
			next_state = ST;
			else if((mode == `REGIMM)||(mode == `I_Branch)||(opcode == 6'b000010))
			next_state = IF;
			else
			next_state = WB;
		end

		LD:begin
			if(Mem_Req_Ready)
			next_state = RDW;
			else
			next_state = LD;
		end

		RDW:begin
			if(Read_data_Valid) 
			next_state = WB; 
			else 
			next_state = RDW;
		end

		ST:begin
			if(Mem_Req_Ready) 
			next_state = IF; 
			else 
			next_state = ST;
		end

		WB:begin
			next_state = IF;
		end

		default:next_state = INIT;

		endcase
	end

	//part 3
	assign Inst_Req_Valid 	= (current_state == IF);
	assign Inst_Ready 		= (current_state == IW)||(current_state == INIT);
	assign Read_data_Ready 		= (current_state == RDW)||(current_state == INIT);
	assign MemRead         	= (current_state == LD);
	assign MemWrite        	= current_state == ST;

	always @(posedge clk) 
		begin
			valid_Instruction <= (Inst_Ready && Inst_Valid)? Instruction: valid_Instruction;
		end
	always @(posedge clk) 
		begin
			valid_Read_data <= (Read_data_Ready && Read_data_Valid)? Read_data: valid_Read_data;
		end


	//Instruction Fetch
	wire [31:0] PC_next 	= PC + 4;
	wire [31:0] branch_PC 	= PC_next + offset_two_extend;
	wire [31:0] jumpaddr	= (mode == `R_Jump)?RF_rdata1:
				  (mode == `JType)?{PC_next[31:28],Instr_index,2'b00}:32'b0;
	
	always @ (posedge clk) 
	begin
		if(rst)
		PC <= 32'b0;
		else if(current_state == EX)
		PC <= (mode == `R_Jump || mode == `JType) ? jumpaddr:((Branch & isbranch)?branch_PC:PC_next);
		else if((valid_Instruction == 32'b0)&&(current_state == ID))
		PC <= PC_next;
		else
		PC <= PC;
	end

	always @ (posedge clk)
	begin
		if(current_state == IF)
		PC_cur <= PC;
		else
		PC_cur <= PC_cur;
	end

	// performance counter
	// The number of cycle
	reg [31:0] cycle_cnt;
	always @(posedge clk) 
	begin
		if(rst) cycle_cnt <= 32'd0;
		else cycle_cnt <= cycle_cnt + 32'd1;
	end
	assign cpu_perf_cnt_0 = cycle_cnt;

	// The number of instructions retired
	reg [31:0] inst_retired_cnt;
	always @(posedge clk) 
	begin
    		if(rst)
        	inst_retired_cnt <= 32'b0;
    		else 
		begin
			if ((current_state == WB) || 
            		(current_state == ST && Mem_Req_Ready) || 
            		(current_state == EX && ((mode == `REGIMM) || (mode == `I_Branch) || (opcode == 6'b000010))))
            		inst_retired_cnt <= inst_retired_cnt + 1'b1;
		end
	end
	assign cpu_perf_cnt_1 = inst_retired_cnt;


  

endmodule
