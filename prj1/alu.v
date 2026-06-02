`timescale 10 ns / 1 ns

`define DATA_WIDTH 32
`define ALUop_AND  3'b000
`define ALUop_OR   3'b001
`define ALUop_ADD  3'b010
`define ALUop_SUB  3'b110
`define ALUop_SLT  3'b111
`define ALUop_XOR  3'b100
`define ALUop_NOR  3'b101
`define ALUop_SLTU 3'b011


module alu(
	input  [`DATA_WIDTH - 1:0]  A,
	input  [`DATA_WIDTH - 1:0]  B,
	input  [              2:0]  ALUop,
	output                      Overflow,
	output                      CarryOut,
	output                      Zero,
	output [`DATA_WIDTH - 1:0]  Result
);
	// TODO: Please add your logic design here
	wire   [`DATA_WIDTH - 1:0]  out_and;
	wire   [`DATA_WIDTH - 1:0]  out_or;
	wire   [`DATA_WIDTH - 1:0]  out_add;
	wire   [`DATA_WIDTH - 1:0]  out_xor;
	wire   [`DATA_WIDTH - 1:0]  out_nor;
	wire   out_slt;
	wire   out_sltu;
        wire   cin;
	wire   co;
	wire   [`DATA_WIDTH - 1:0]B_mux = ((ALUop == `ALUop_SUB)||(ALUop == `ALUop_SLT)||ALUop == `ALUop_SLTU) ? ~B : B;
	assign cin 			= (ALUop == `ALUop_SUB) || (ALUop == `ALUop_SLT) || (ALUop == `ALUop_SLTU);
	assign out_and 			= A&B;
	assign out_or  			= A|B;
	assign out_xor			= A^B;
	assign out_nor			= ~(A|B);
	assign {co,out_add} 		= A+B_mux+{32'b0,cin};


	assign out_slt  = 	(A[31] == 1 && B[31] == 0) ? 1 : 
			    	(A[31] == 0 && B[31] == 1) ? 0 :
    				(out_add[31] == 1) ? 1 : 0;
	assign out_sltu =	~co;
	assign Overflow = 	(ALUop == `ALUop_ADD) ? ((A[31] == B[31]) && (out_add[31] != A[31])) :
                          	(ALUop == `ALUop_SUB) ? ((A[31] != B[31]) && (out_add[31] != A[31])) : 1'b0;
	assign CarryOut = 	(ALUop == `ALUop_ADD) ? co:
			  	(ALUop == `ALUop_SUB) ? ~co:1'b0;
	assign Zero 	= 	(Result == 32'b0);


	assign Result   = 	({`DATA_WIDTH{ALUop == `ALUop_AND }}			& out_and)|
				({`DATA_WIDTH{ALUop == `ALUop_OR  }}			& out_or )|
				({`DATA_WIDTH{ALUop == `ALUop_XOR }}			& out_xor)|
				({`DATA_WIDTH{ALUop == `ALUop_NOR }}			& out_nor)|
				({`DATA_WIDTH{ALUop == `ALUop_ADD||ALUop == `ALUop_SUB}}& out_add)|
				({`DATA_WIDTH{ALUop == `ALUop_SLT }}&   (out_slt ? 32'b1 : 32'b0))|
				({`DATA_WIDTH{ALUop == `ALUop_SLTU}}& 	(out_sltu? 32'b1 : 32'b0));

	


endmodule
