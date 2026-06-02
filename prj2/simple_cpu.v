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

`define SHIFTOP_SLL  2'b00
`define SHIFTOP_SRL  2'b10
`define SHIFTOP_SRA  2'b11 

module simple_cpu(
	input             clk,
	input             rst,

	output reg [31:0]     PC,
	input  [31:0]     Instruction,

	output [31:0]     Address,
	output            MemWrite,
	output [31:0]     Write_data,
	output [ 3:0]     Write_strb,

	input  [31:0]     Read_data,
	output            MemRead
);

	// THESE THREE SIGNALS ARE USED IN OUR TESTBENCH
	// PLEASE DO NOT MODIFY SIGNAL NAMES
	// AND PLEASE USE THEM TO CONNECT PORTS
	// OF YOUR INSTANTIATION OF THE REGISTER FILE MODULE
	wire			RF_wen;
	wire [4:0]		RF_waddr;
	wire [31:0]		RF_wdata;

	// TODO: PLEASE ADD YOUR CODE BELOW
	
	wire [4 :0] RF_raddr1, RF_raddr2;
        wire [31:0] RF_rdata1, RF_rdata2;
        wire [31:0] extend, lui_extend, load_result, SHIFT_result;
        wire        ALUSrc, RegDst;

	//Instruction Decode
	wire [5:0]  opcode 	= Instruction[31:26];
	wire [4:0]  rs 		= Instruction[25:21];
	wire [4:0]  rt 		= Instruction[20:16];
	wire [4:0]  rd 		= Instruction[15:11];
	wire [4:0]  shamt 	= Instruction[10:6];
	wire [5:0]  func 	= Instruction[5:0];
	wire [4:0]  base 	= Instruction[25:21];	
	wire [4:0]  REG 	= Instruction[20:16];	
	wire [15:0] imm 	= Instruction[15:0];
	wire [25:0] Instr_index = Instruction[25:0];



	wire [3:0] type = 	{4{opcode == `SPECIAL && func[5] == 1'b1}} & `R_Alu |
				{4{opcode == `SPECIAL && func[5:3] == 3'b000}} & `R_Shift |
				{4{opcode == `SPECIAL && {func[5:3], func[1]} == 4'b0010}} & `R_Jump |
				{4{opcode == `SPECIAL && {func[5:3], func[1]} == 4'b0011}} & `R_Move |
				{4{opcode == 6'b000001}} & `REGIMM |
				{4{opcode[5:1] == 5'b00001}} & `JType |
				{4{opcode[5:2] == 4'b0001}} & `I_Branch |
				{4{opcode[5:3] == 3'b001 && opcode != 6'b001111}} & `I_Alu |
				{4{opcode == 6'b001111}} & `lui |
				{4{opcode[5:3] == 3'b100}} & `I_Load |
				{4{opcode[5:3] == 3'b101}} & `I_Store;

	//ALU control
	wire [2:0] ALU_op = 	{{3{type == `R_Alu && func[3:2] == 2'b00}} & {func[1], 2'b10}}|//addu,subu
			    	{{3{type == `R_Alu && func[3:2] == 2'b01}} & {func[1], 1'b0, func[0]}}|//and,or,xor,nor
			    	{{3{type == `R_Alu && func[3:2] == 2'b10}} & {~func[0], 2'b11}}|//slt,sltu
			    	{{3{type == `I_Alu && opcode[2:0] == 3'b001}} & {opcode[1], 2'b10}}|//addiu
			    	{{3{type == `I_Alu && opcode[2] == 1'b1}} & {opcode[1], 1'b0, opcode[0]}}|//andi,ori,xori
			    	{{3{type == `I_Alu && opcode[2:1] == 2'b01}} & {~opcode[0], 2'b11}}|//slti,sltiu
			    	{{3{type == `R_Move}} & `ALUop_SUB}|//movz,movn
			    	{{3{type == `REGIMM}} & `ALUop_SLT}|//bltz,bgez
			    	{{3{type == `I_Branch && opcode[1] == 1'b0}} & `ALUop_SUB}|//beq，bne
				{{3{type == `I_Branch && opcode[1] == 1'b1}} & `ALUop_SUB}|//blez,bgtz
				{{3{type == `I_Load || type == `I_Store}} & `ALUop_ADD};//lw,sw

	wire [31:00] A_aftmux =	(type == `R_Move)? RF_rdata2: RF_rdata1;
	wire [31:00] B_aftmux =	{{32{ALUSrc}}&extend}|
				{{32{type ==`R_Alu || type == `I_Branch}} & RF_rdata2}|
				{{32{type == `R_Move || type == `REGIMM}} & 32'b0};

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

	//imm extended control
	wire [31:0] sign_extend 	= {{16{imm[15]}}, imm};
	wire [31:0] zero_extend 	= {16'b0, imm};
	wire [31:0] offset_two_extend 	= {{14{imm[15]}}, imm, 2'b0};
	assign lui_extend 		= {imm, 16'b0};
	assign extend			= (((type == `I_Alu)&&(ALU_op!={opcode[1], 1'b0, opcode[0]}))||(type == `I_Load)||(type == `I_Store))?sign_extend:zero_extend;

	//load control
	assign 	Address 	= 	{ALU_result[31:2],2'b00};
	wire [1:0]  Addr_low 	= 	ALU_result[1:0];
	wire [7:0]  byte_read	= 	(Addr_low == 2'b00)?Read_data[7:0]:
				  	(Addr_low == 2'b01)?Read_data[15:8]:
				  	(Addr_low == 2'b10)?Read_data[23:16]:
				  		            Read_data[31:24];
	wire [15:0] half_read	= 	(Addr_low[1])?Read_data[31:16]:
						      Read_data[15:0];
	wire [31:0] lwl_read	= 	(Addr_low == 2'b00)?{Read_data[7:0],RF_rdata2[23:0]}:
				  	(Addr_low == 2'b01)?{Read_data[15:0],RF_rdata2[15:0]}:
				  	(Addr_low == 2'b10)?{Read_data[23:0],RF_rdata2[7:0]}:
				  		      {Read_data[31:0]};
	wire [31:0] lwr_read	= 	(Addr_low == 2'b00)?Read_data[31:0]:
				  	(Addr_low == 2'b01)?{RF_rdata2[31:24],Read_data[31:8]}:
				  	(Addr_low == 2'b10)?{RF_rdata2[31:16],Read_data[31:16]}:
				  		     	    {RF_rdata2[31:8],Read_data[31:24]};
	assign      load_result = 	(opcode == 6'b100000)?{{24{byte_read[7]}}, byte_read}://lb
    					(opcode == 6'b100100)?{24'b0, byte_read}://lbu
    					(opcode == 6'b100001)?{{16{half_read[15]}}, half_read}://lh
   					(opcode == 6'b100101)?{16'b0, half_read}://lhu
    					(opcode == 6'b100011)?Read_data://lw
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
	wire [4:0] shiftbit 	 = {{5{type == `R_Shift && func[5:2] == 4'b0000 }} & shamt} |
				   {{5{type == `R_Shift && func[5:2] == 4'b0001}} & RF_rdata1[4:0]}; 
	wire [1:0] SHIFT_control = func[1:0];
	shifter shifter_module(RF_rdata2, shiftbit, SHIFT_control, SHIFT_result);

	
	//move control
	wire Mov_true = (type == `R_Move)&((func[0]==1'b0 & Zero)|(func[0]==1'b1 & ~Zero));

	//reg_file control
	assign RF_wdata = 	(type == `R_Alu || type == `I_Alu)? ALU_result:
				(type == `R_Shift)? SHIFT_result:
				(opcode == 6'b000011 || (type == `R_Jump && func == 6'b001001))? PC + 8:
				(type == `I_Load)? load_result:
				(type == `R_Move)? RF_rdata1:lui_extend;
	assign RF_waddr 	= (opcode == 6'b000011)? 31:((RegDst)? rd:rt);
	assign RF_raddr1 	= rs;
	assign RF_raddr2 	= (type == `REGIMM)? 5'b0:rt;
	assign RF_wen = ( (type == `R_Alu)||(type == `R_Shift)||((type == `R_Jump)&&func[0])||((type == `JType) && opcode[0])||(type == `I_Alu)||(type == `I_Load)||(type == `lui)||Mov_true);
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
	wire MemtoReg	= 	(type == `I_Load);
	wire Branch	=	((type == `REGIMM)||(type == `I_Branch));
	assign MemWrite = 	(type == `I_Store);
	assign MemRead	=	(type == `I_Load);
	assign ALUSrc	= 	((type == `I_Alu)||(type == `I_Load)||(type == `I_Store));
	assign RegDst 	= 	((type == `R_Alu)||(type == `R_Shift)||(type == `R_Jump)||(type == `R_Move));

	//branch control
	wire isbranch = ((type ==  `I_Branch) & (opcode[1:0] == 2'b00) & Zero)|
			((type ==  `I_Branch) & (opcode[1:0] == 2'b01) & ~Zero)|
			((type ==  `I_Branch) & (opcode[1:0] == 2'b10) & (ALU_result[31]|Zero))|
			((type ==  `I_Branch) & (opcode[1:0] == 2'b11) & (~ALU_result[31]&~Zero))|
			((type == `REGIMM) & (REG[0] == 0) & ALU_result[0])|
			((type == `REGIMM) & (REG[0] == 1) & ~ALU_result[0]);
	

	//Instruction Fetch
	wire [31:0] PC_next 	= PC + 4;
	wire [31:0] branch_PC 	= PC_next + offset_two_extend;
	wire [31:0] jumpaddr	= (type == `R_Jump)?RF_rdata1:
				  (type == `JType)?{PC_next[31:28],Instr_index,2'b00}:32'b0;
	always @(posedge clk) begin
		if (rst) begin
			PC <= 32'b0;
		end
		else begin
			PC <= (type == `R_Jump || type == `JType) ? jumpaddr:((Branch & isbranch)?branch_PC:PC_next);
		end
	end 

	
	
endmodule
