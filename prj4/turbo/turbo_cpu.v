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
`define R_Alu    4'b0000
`define R_Shift  4'b0001
`define R_Jump   4'b0010
`define R_Move   4'b0011
`define REGIMM   4'b0100
`define JType    4'b0101
`define I_Branch 4'b0110
`define I_Alu    4'b0111
`define lui      4'b1000
`define I_Load   4'b1001
`define I_Store  4'b1010

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
    wire        RF_wen;     
    wire [4:0]  RF_waddr;   
    wire [31:0] RF_wdata;   
    wire [4:0]  RF_raddr1;  
    wire [4:0]  RF_raddr2;  
    wire [31:0] RF_rdata1;  
    wire [31:0] RF_rdata2;  

// pipeline handshake control
    reg if_valid;
    reg id_valid;
    reg ex_valid;
    reg mem_valid;
    reg wb_valid;

    reg [1:0] id_state;
    reg [1:0] ex_state;
    reg [2:0] mem_state;
    reg [1:0] wb_state;

    localparam ST_EMPTY = 2'b00;
    localparam ST_DONE  = 2'b01;

    localparam MEM_EMPTY = 3'b000;
    localparam MEM_REQ   = 3'b001;
    localparam MEM_WAIT  = 3'b010;
    localparam MEM_DONE  = 3'b011;

    wire if_allowin;
    wire id_allowin;
    wire ex_allowin;
    wire mem_allowin;
    wire wb_allowin;

    wire if_readygo;
    wire id_readygo;
    wire ex_readygo;
    wire mem_readygo;
    wire wb_readygo;

    wire if_to_id_valid;
    wire id_to_ex_valid;
    wire ex_to_mem_valid;
    wire mem_to_wb_valid;

    assign if_to_id_valid  = if_valid;
    assign id_to_ex_valid  = id_valid && id_readygo;
    assign ex_to_mem_valid = ex_valid && ex_readygo;
    assign mem_to_wb_valid = mem_valid && mem_readygo;

    assign if_allowin  = 1'b0;
    assign id_allowin  = (id_state  == ST_EMPTY);
    assign ex_allowin  = (ex_state  == ST_EMPTY);
    assign mem_allowin = (mem_state == MEM_EMPTY);
    assign wb_allowin  = (wb_state  == ST_EMPTY);

    assign if_readygo = 1'b1;
    assign ex_readygo = (ex_state == ST_DONE);
    assign wb_readygo = (wb_state == ST_DONE);
    assign mem_readygo =(mem_state == MEM_DONE);

// pipeline register
    reg [31:0] if_pc;

    reg [31:0] id_pc;
    reg [31:0] id_inst;

    reg [31:0] ex_pc;
    reg [31:0] ex_inst;
    reg [31:0] ex_rdata1;
    reg [31:0] ex_rdata2;
    reg [31:0] ex_extend;
    reg [31:0] ex_lui_extend;
    reg [31:0] ex_offset_two_extend;
    reg [4:0]  ex_rs;
    reg [4:0]  ex_rt;
    reg [4:0]  ex_rd;
    reg [4:0]  ex_shamt;
    reg [5:0]  ex_opcode;
    reg [5:0]  ex_func;
    reg [4:0]  ex_reg;
    reg [25:0] ex_instr_index;
    reg [3:0]  ex_mode;
    reg [2:0]  ex_alu_op;
    reg        ex_alusrc;
    reg        ex_branch;
    reg        ex_memread;
    reg        ex_memwrite;
    reg        ex_rf_wen;
    reg [4:0]  ex_rf_waddr;

    reg [31:0] mem_pc;
    reg [31:0] mem_inst;
    reg [31:0] mem_alu_result;
    reg [31:0] mem_result;
    reg [31:0] mem_store_data;
    reg [5:0]  mem_opcode;
    reg        mem_memread;
    reg        mem_memwrite;
    reg        mem_rf_wen;
    reg [4:0]  mem_rf_waddr;

    reg [31:0] wb_pc;
    reg [31:0] wb_inst;
    reg [31:0] wb_result;
    reg        wb_rf_wen;
    reg [4:0]  wb_rf_waddr;

// IF control
    reg [31:0] if_inst;
    reg [31:0] if_req_pc;
    reg [2:0]  if_state;

    localparam IF_REQ         = 3'b001;
    localparam IF_WAIT        = 3'b010;
    localparam IF_DONE        = 3'b011;
    localparam IF_BRANCH_WAIT = 3'b100;
    localparam IF_MEM_WAIT    = 3'b101;

    wire ex_redirect;
    wire [31:0] ex_redirect_pc;
    wire id_holds_redirect_target = id_valid && (id_pc == ex_redirect_pc);
    wire if_req_fire  = Inst_Req_Valid && Inst_Req_Ready;
    wire if_resp_fire = Inst_Ready && Inst_Valid;

    wire [5:0] if_opcode = if_inst[31:26];
    wire [5:0] if_func   = if_inst[5:0];

    wire if_is_control =
        (if_opcode == `SPECIAL && {if_func[5:3], if_func[1]} == 4'b0010) ||
        (if_opcode == 6'b000001) ||
        (if_opcode[5:1] == 5'b00001) ||
        (if_opcode[5:2] == 4'b0001);

    wire if_is_mem = (if_opcode[5:3] == 3'b100) || (if_opcode[5:3] == 3'b101);

    wire ex_control_done =
        ex_valid && ex_readygo && mem_allowin && (ex_pc == if_pc) &&
        (ex_branch || (ex_mode == `R_Jump) || (ex_mode == `JType));

    wire if_mem_done =
        mem_valid && (mem_pc == if_pc) && (mem_state == MEM_DONE);

    assign Inst_Req_Valid = !rst && (if_state == IF_REQ) && !ex_redirect;
    assign Inst_Ready     = rst || (if_state == IF_WAIT) || ex_redirect;
    

    always @(posedge clk) begin
        if (rst) begin
            if_state  <= IF_REQ;
            if_valid  <= 1'b0;
            PC        <= 32'b0;
            if_pc     <= 32'b0;
            if_inst   <= 32'b0;
            if_req_pc <= 32'b0;
        end else if (ex_redirect) begin
            if_state <= IF_REQ;
            if_valid <= 1'b0;
            PC       <= ex_redirect_pc;
        end else begin
            case (if_state)
                IF_REQ: begin
                    if_valid <= 1'b0;
                    if (if_req_fire) begin
                        if_state <= IF_WAIT;
                        if_req_pc <= PC;
                    end
                end

                IF_WAIT: begin
                    if (if_resp_fire) begin
                        if_state <= IF_DONE;
                        if_valid <= 1'b1;
                        if_pc    <= if_req_pc;
                        if_inst  <= Instruction;
                    end
                end

                IF_DONE: begin
                    if (id_allowin) begin
                        if_valid <= 1'b0;
                        if (if_is_control) begin
                            if_state <= IF_BRANCH_WAIT;
                        end else if (if_is_mem) begin
                            if_state <= IF_MEM_WAIT;
                        end else begin
                            if_state <= IF_REQ;
                            PC       <= if_pc + 32'd4;
                        end
                    end
                end

                IF_BRANCH_WAIT: begin
                    if_valid <= 1'b0;
                    if (ex_control_done) begin
                        if_state <= IF_REQ;
                        PC       <= if_pc + 32'd4;
                    end
                end

                IF_MEM_WAIT: begin
                    if_valid <= 1'b0;
                    if (if_mem_done) begin
                        if_state <= IF_REQ;
                        PC       <= if_pc + 32'd4;
                    end
                end

                default: begin
                    if_state <= IF_REQ;
                    if_valid <= 1'b0;
                end
            endcase
        end
    end

// IF/ID register
    always @(posedge clk) begin
        if (rst) begin
            id_state <= ST_EMPTY;
            id_valid <= 1'b0;
            id_pc    <= 32'b0;
            id_inst  <= 32'b0;
        end else if (ex_redirect && !id_holds_redirect_target) begin
            id_state <= ST_EMPTY;
            id_valid <= 1'b0;
            id_pc    <= 32'b0;
            id_inst  <= 32'b0;
        end else begin
            case (id_state)
                ST_EMPTY: begin
                    id_valid <= 1'b0;
                    if (if_to_id_valid) begin
                        id_state <= ST_DONE;
                        id_valid <= 1'b1;
                        id_pc    <= if_pc;
                        id_inst  <= if_inst;
                    end
                end

                ST_DONE: begin
                    if (id_to_ex_valid && ex_allowin) begin
                        id_state <= ST_EMPTY;
                        id_valid <= 1'b0;
                    end
                end

                default: begin
                    id_state <= ST_EMPTY;
                    id_valid <= 1'b0;
                end
            endcase
        end
    end

// ID field decode
    wire        id_is_nop      = (id_inst == 32'b0);
    wire [5:0]  id_opcode      = id_inst[31:26];
    wire [4:0]  id_rs          = id_inst[25:21];
    wire [4:0]  id_rt          = id_inst[20:16];
    wire [4:0]  id_rd          = id_inst[15:11];
    wire [4:0]  id_shamt       = id_inst[10:6];
    wire [5:0]  id_func        = id_inst[5:0];
    wire [4:0]  id_reg         = id_inst[20:16]; 
    wire [15:0] id_imm         = id_inst[15:0];
    wire [25:0] id_instr_index = id_inst[25:0];

// instruction type control
    wire [3:0] id_mode =
        ({4{id_opcode == `SPECIAL && id_func[5] == 1'b1}} & `R_Alu) |
        ({4{id_opcode == `SPECIAL && id_func[5:3] == 3'b000}} & `R_Shift) |
        ({4{id_opcode == `SPECIAL && {id_func[5:3], id_func[1]} == 4'b0010}} & `R_Jump) |
        ({4{id_opcode == `SPECIAL && {id_func[5:3], id_func[1]} == 4'b0011}} & `R_Move) |
        ({4{id_opcode == 6'b000001}} & `REGIMM) |
        ({4{id_opcode[5:1] == 5'b00001}} & `JType) |
        ({4{id_opcode[5:2] == 4'b0001}} & `I_Branch) |
        ({4{id_opcode[5:3] == 3'b001 && id_opcode != 6'b001111}} & `I_Alu) |
        ({4{id_opcode == 6'b001111}} & `lui) |
        ({4{id_opcode[5:3] == 3'b100}} & `I_Load) |
        ({4{id_opcode[5:3] == 3'b101}} & `I_Store);

// ALUop control
    wire [2:0] id_alu_op =  ({3{id_mode == `R_Alu && id_func[3:2] == 2'b00}} & {id_func[1], 2'b10}) |
                            ({3{id_mode == `R_Alu && id_func[3:2] == 2'b01}} & {id_func[1], 1'b0, id_func[0]}) |
                            ({3{id_mode == `R_Alu && id_func[3:2] == 2'b10}} & {~id_func[0], 2'b11}) | 
                            ({3{id_mode == `I_Alu && id_opcode[2:0] == 3'b001}} & {id_opcode[1], 2'b10}) | 
                            ({3{id_mode == `I_Alu && id_opcode[2] == 1'b1}} & {id_opcode[1], 1'b0, id_opcode[0]}) |
                            ({3{id_mode == `I_Alu && id_opcode[2:1] == 2'b01}} & {~id_opcode[0], 2'b11}) |// slti/sltiu
                            ({3{id_mode == `R_Move}} & `ALUop_SUB) |// movz/movn
                            ({3{id_mode == `REGIMM}} & `ALUop_SLT) |// bltz/bgez
                            ({3{id_mode == `I_Branch && id_opcode[1] == 1'b0}} & `ALUop_SUB) |// beq/bne
                            ({3{id_mode == `I_Branch && id_opcode[1] == 1'b1}} & `ALUop_SUB) | // blez/bgtz
                            ({3{id_mode == `I_Load || id_mode == `I_Store}} & `ALUop_ADD);// load/store：base+offset

// immediate and simple control
    wire [31:0] id_sign_extend       = {{16{id_imm[15]}}, id_imm};
    wire [31:0] id_zero_extend       = {16'b0, id_imm};
    wire [31:0] id_lui_extend        = {id_imm, 16'b0};
    wire [31:0] id_offset_two_extend = {{14{id_imm[15]}}, id_imm, 2'b0};

    wire id_alusrc = (id_mode == `I_Alu) || (id_mode == `I_Load) || (id_mode == `I_Store);

    wire id_regdst = (id_mode == `R_Alu) || (id_mode == `R_Shift) ||
                     (id_mode == `R_Jump) || (id_mode == `R_Move);

    wire id_branch = (id_mode == `REGIMM) || (id_mode == `I_Branch);

    wire id_memread  = (id_mode == `I_Load);
    wire id_memwrite = (id_mode == `I_Store);

    wire [31:0] id_extend =
        (((id_mode == `I_Alu) && (id_alu_op != {id_opcode[1], 1'b0, id_opcode[0]})) ||
         (id_mode == `I_Load) ||
         (id_mode == `I_Store)) ? id_sign_extend : id_zero_extend;

// register file read control
    assign RF_raddr1 = id_rs;
    assign RF_raddr2 = (id_mode == `REGIMM) ? 5'b0 : id_rt;

    wire [31:0] id_rdata1 =
        (wb_valid && wb_rf_wen && wb_rf_waddr != 5'b0 && wb_rf_waddr == id_rs) ?
        wb_result : RF_rdata1;

    wire [31:0] id_rdata2 =
        (wb_valid && wb_rf_wen && wb_rf_waddr != 5'b0 && wb_rf_waddr == id_rt) ?
        wb_result : RF_rdata2;

    wire id_mov_true =
        (id_mode == `R_Move) &&
        (((id_func[0] == 1'b0) && (id_rdata2 == 32'b0)) ||
         ((id_func[0] == 1'b1) && (id_rdata2 != 32'b0)));

    wire id_rf_wen =
        !id_is_nop &&
        ((id_mode == `R_Alu) ||
         (id_mode == `R_Shift) ||
         ((id_mode == `R_Jump) && id_func[0]) ||       // jalr指令
         ((id_mode == `JType) && id_opcode[0]) ||      // jal指令
         (id_mode == `I_Alu) ||
         (id_mode == `I_Load) ||
         (id_mode == `lui) ||
         id_mov_true);

    wire [4:0] id_rf_waddr =
        (id_opcode == 6'b000011) ? 5'd31 :
        (id_regdst ? id_rd : id_rt);

// load-use stall control
    wire id_rs_used =
        (id_mode == `R_Alu) ||
        (id_mode == `R_Move) ||
        (id_mode == `REGIMM) ||
        (id_mode == `I_Branch) ||
        (id_mode == `I_Alu) ||
        (id_mode == `I_Load) ||
        (id_mode == `I_Store) ||
        (id_mode == `R_Jump) ||
        (id_mode == `R_Shift && id_func[5:2] == 4'b0001);

    wire id_rt_used =
        (id_mode == `R_Alu) ||
        (id_mode == `R_Shift) ||
        (id_mode == `R_Move) ||
        (id_mode == `I_Branch) ||
        (id_mode == `I_Store) ||
        (id_mode == `I_Load && (id_opcode == 6'b100010 || id_opcode == 6'b100110));

    wire id_wait_ex_load =
        ex_valid && ex_memread && ex_rf_wen && (ex_rf_waddr != 5'b0) &&
        ((id_rs_used && id_rs == ex_rf_waddr) ||
         (id_rt_used && id_rt == ex_rf_waddr));

    wire id_wait_mem_load =
        mem_valid && mem_memread && mem_rf_wen && (mem_rf_waddr != 5'b0) &&
        ((id_rs_used && id_rs == mem_rf_waddr) ||
         (id_rt_used && id_rt == mem_rf_waddr));

    assign id_readygo = !(id_wait_ex_load || id_wait_mem_load);

// ID/EX register
    always @(posedge clk) begin
        if (rst) begin
            ex_state <= ST_EMPTY;
            ex_valid <= 1'b0;
            ex_pc <= 32'b0;
            ex_inst <= 32'b0;
            ex_rdata1 <= 32'b0;
            ex_rdata2 <= 32'b0;
            ex_extend <= 32'b0;
            ex_lui_extend <= 32'b0;
            ex_offset_two_extend <= 32'b0;
            ex_rs <= 5'b0;
            ex_rt <= 5'b0;
            ex_rd <= 5'b0;
            ex_shamt <= 5'b0;
            ex_opcode <= 6'b0;
            ex_func <= 6'b0;
            ex_reg <= 5'b0;
            ex_instr_index <= 26'b0;
            ex_mode <= 4'b0;
            ex_alu_op <= 3'b0;
            ex_alusrc <= 1'b0;
            ex_branch <= 1'b0;
            ex_memread <= 1'b0;
            ex_memwrite <= 1'b0;
            ex_rf_wen <= 1'b0;
            ex_rf_waddr <= 5'b0;
        end else begin
            case (ex_state)
                ST_EMPTY: begin
                    ex_valid <= 1'b0;
                    if (id_to_ex_valid) begin
                        ex_state             <= ST_DONE;
                        ex_valid             <= 1'b1;
                        ex_pc                <= id_pc;
                        ex_inst              <= id_inst;
                        ex_rdata1            <= id_rdata1;
                        ex_rdata2            <= id_rdata2;
                        ex_extend            <= id_extend;
                        ex_lui_extend        <= id_lui_extend;
                        ex_offset_two_extend <= id_offset_two_extend;
                        ex_rs                <= id_rs;
                        ex_rt                <= id_rt;
                        ex_rd                <= id_rd;
                        ex_shamt             <= id_shamt;
                        ex_opcode            <= id_opcode;
                        ex_func              <= id_func;
                        ex_reg               <= id_reg;
                        ex_instr_index       <= id_instr_index;
                        ex_mode              <= id_mode;
                        ex_alu_op            <= id_alu_op;
                        ex_alusrc            <= id_alusrc;
                        ex_branch            <= id_branch;
                        ex_memread           <= id_memread;
                        ex_memwrite          <= id_memwrite;
                        ex_rf_wen            <= id_rf_wen;
                        ex_rf_waddr          <= id_rf_waddr;
                    end
                end

                ST_DONE: begin
                    if (ex_to_mem_valid && mem_allowin) begin
                        ex_state <= ST_EMPTY;
                        ex_valid <= 1'b0;
                    end
                end

                default: begin
                    ex_state <= ST_EMPTY;
                    ex_valid <= 1'b0;
                end
            endcase
        end
    end

// EX forwarding and operand control
    wire [31:0] ex_forward_rdata1 =
        (mem_valid && mem_rf_wen && !mem_memread &&
         mem_rf_waddr != 5'b0 && mem_rf_waddr == ex_rs) ? mem_result :
        (wb_valid && wb_rf_wen && wb_rf_waddr != 5'b0 && wb_rf_waddr == ex_rs) ? wb_result :
                                                                                ex_rdata1;

    wire [31:0] ex_forward_rdata2 =
        (mem_valid && mem_rf_wen && !mem_memread &&
         mem_rf_waddr != 5'b0 && mem_rf_waddr == ex_rt) ? mem_result :
        (wb_valid && wb_rf_wen &&wb_rf_waddr != 5'b0 && wb_rf_waddr == ex_rt) ? wb_result :
                                                                                ex_rdata2;

    wire [31:0] ex_alu_src1 =
        (ex_mode == `R_Move) ? ex_forward_rdata2 : ex_forward_rdata1;

    wire [31:0] ex_alu_src2 =
        ex_alusrc ? ex_extend :
        ((ex_mode == `R_Alu || ex_mode == `I_Branch) ? ex_forward_rdata2 : 32'b0);

    wire [31:0] ex_alu_result;
    wire        ex_zero;

    alu alu_module(
        .A(ex_alu_src1),
        .B(ex_alu_src2),
        .ALUop(ex_alu_op),
        .Overflow(),
        .CarryOut(),
        .Zero(ex_zero),
        .Result(ex_alu_result)
    );

    wire [4:0] ex_shiftbit =
        ({5{ex_mode == `R_Shift && ex_func[5:2] == 4'b0000}} & ex_shamt) |
        ({5{ex_mode == `R_Shift && ex_func[5:2] == 4'b0001}} & ex_forward_rdata1[4:0]);

    wire [31:0] ex_shift_result;

    shifter shifter_module(
        .A(ex_forward_rdata2),
        .B(ex_shiftbit),
        .Shiftop(ex_func[1:0]),
        .Result(ex_shift_result)
    );

// branch and jump control
    wire ex_branch_taken =
        // beq
        ((ex_mode == `I_Branch) && (ex_opcode[1:0] == 2'b00) && ex_zero) |
        // bne
        ((ex_mode == `I_Branch) && (ex_opcode[1:0] == 2'b01) && !ex_zero) |
        ((ex_mode == `I_Branch) && (ex_opcode[1:0] == 2'b10) && (ex_alu_result[31] | ex_zero)) |
        ((ex_mode == `I_Branch) && (ex_opcode[1:0] == 2'b11) && (~ex_alu_result[31] & ~ex_zero)) |
        // bltz
        ((ex_mode == `REGIMM) && (ex_reg[0] == 1'b0) && ex_alu_result[0]) |
        // bgez
        ((ex_mode == `REGIMM) && (ex_reg[0] == 1'b1) && ~ex_alu_result[0]);

    wire [31:0] ex_pc_next       = ex_pc + 32'd4;
    wire [31:0] ex_branch_target = ex_pc_next + ex_offset_two_extend;
    wire [31:0] ex_jump_target   =
        (ex_mode == `R_Jump) ? ex_forward_rdata1 :
        (ex_mode == `JType)  ? {ex_pc_next[31:28], ex_instr_index, 2'b00} :
                               32'b0;

    assign ex_redirect =
        ex_valid &&
        ex_readygo &&
        mem_allowin &&
        (((ex_branch) && ex_branch_taken) ||
         (ex_mode == `R_Jump) ||
         (ex_mode == `JType));

    assign ex_redirect_pc =
        ((ex_branch) && ex_branch_taken) ? ex_branch_target : ex_jump_target;

// EX result control
    wire [31:0] ex_result =
        (ex_mode == `R_Alu || ex_mode == `I_Alu) ? ex_alu_result :
        (ex_mode == `R_Shift)                    ? ex_shift_result :
        (ex_opcode == 6'b000011 ||
        (ex_mode == `R_Jump && ex_func == 6'b001001)) ? ex_pc_next + 32'd4 :
        (ex_mode == `R_Move)                     ? ex_forward_rdata1 :
        (ex_mode == `lui)                        ? ex_lui_extend :
                                                    ex_alu_result;

// EX/MEM register
    wire mem_req_fire;

    always @(posedge clk) begin
        if (rst) begin
            mem_state <= MEM_EMPTY;
            mem_valid <= 1'b0;
            mem_pc <= 32'b0;
            mem_inst <= 32'b0;
            mem_alu_result <= 32'b0;
            mem_result <= 32'b0;
            mem_store_data <= 32'b0;
            mem_opcode <= 6'b0;
            mem_memread <= 1'b0;
            mem_memwrite <= 1'b0;
            mem_rf_wen <= 1'b0;
            mem_rf_waddr <= 5'b0;
        end else begin
            case (mem_state)
                MEM_EMPTY: begin
                    mem_valid <= 1'b0;
                    if (ex_to_mem_valid) begin
                        mem_valid      <= 1'b1;
                        mem_pc         <= ex_pc;
                        mem_inst       <= ex_inst;
                        mem_alu_result <= ex_alu_result;
                        mem_result     <= ex_result;
                        mem_store_data <= ex_forward_rdata2;
                        mem_opcode     <= ex_opcode;
                        mem_memread    <= ex_memread;
                        mem_memwrite   <= ex_memwrite;
                        mem_rf_wen     <= ex_rf_wen;
                        mem_rf_waddr   <= ex_rf_waddr;
                        mem_state      <= (ex_memread || ex_memwrite) ? MEM_REQ : MEM_DONE;
                    end
                end

                MEM_REQ: begin
                    if (mem_req_fire) begin
                        mem_state <= mem_memread ? MEM_WAIT : MEM_DONE;
                    end
                end

                MEM_WAIT: begin
                    if (Read_data_Valid) begin
                        mem_result    <= mem_result_from_bus;
                        mem_state     <= MEM_DONE;
                    end
                end

                MEM_DONE: begin
                    if (wb_allowin) begin
                        mem_state <= MEM_EMPTY;
                        mem_valid <= 1'b0;
                    end
                end

                default: begin
                    mem_state <= MEM_EMPTY;
                    mem_valid <= 1'b0;
                end
            endcase
        end
    end

// memory request control
    wire [1:0] mem_addr_low = mem_alu_result[1:0];
    wire       mem_is_load  = mem_valid && mem_memread;
    wire       mem_is_store = mem_valid && mem_memwrite;
    assign     mem_req_fire = (MemRead || MemWrite) && Mem_Req_Ready;

    wire mem_bus_active = MemRead || MemWrite || (mem_state == MEM_WAIT);

    assign Address = mem_bus_active ? {mem_alu_result[31:2], 2'b00} : 32'b0;

    assign MemRead  = !rst && (mem_state == MEM_REQ) && mem_is_load;
    assign MemWrite = !rst && (mem_state == MEM_REQ) && mem_is_store;

    assign Read_data_Ready = rst || (mem_state == MEM_WAIT);


// load data control
    wire [7:0] mem_byte_read_from_bus =
        (mem_addr_low == 2'b00) ? Read_data[7:0]   :
        (mem_addr_low == 2'b01) ? Read_data[15:8]  :
        (mem_addr_low == 2'b10) ? Read_data[23:16] :
                                  Read_data[31:24];

    wire [15:0] mem_half_read_from_bus =
        mem_addr_low[1] ? Read_data[31:16] : Read_data[15:0];

    wire [31:0] mem_lwl_read_from_bus =
        (mem_addr_low == 2'b00) ? {Read_data[7:0],   mem_store_data[23:0]} :
        (mem_addr_low == 2'b01) ? {Read_data[15:0],  mem_store_data[15:0]} :
        (mem_addr_low == 2'b10) ? {Read_data[23:0],  mem_store_data[7:0]}  :
                                  Read_data;

    wire [31:0] mem_lwr_read_from_bus =
        (mem_addr_low == 2'b00) ? Read_data :
        (mem_addr_low == 2'b01) ? {mem_store_data[31:24], Read_data[31:8]}  :
        (mem_addr_low == 2'b10) ? {mem_store_data[31:16], Read_data[31:16]} :
                                  {mem_store_data[31:8],  Read_data[31:24]};

    wire [31:0] mem_result_from_bus =
        (mem_opcode == 6'b100000) ? {{24{mem_byte_read_from_bus[7]}}, mem_byte_read_from_bus} :
        (mem_opcode == 6'b100100) ? {24'b0, mem_byte_read_from_bus} :
        (mem_opcode == 6'b100001) ? {{16{mem_half_read_from_bus[15]}}, mem_half_read_from_bus} :
        (mem_opcode == 6'b100101) ? {16'b0, mem_half_read_from_bus} :
        (mem_opcode == 6'b100011) ? Read_data :
        (mem_opcode == 6'b100010) ? mem_lwl_read_from_bus :
        (mem_opcode == 6'b100110) ? mem_lwr_read_from_bus :
                                    32'b0;

// store data control
    wire [3:0] store_strb =
        (mem_opcode == 6'b101011) ? 4'b1111 : // sw指令
        (mem_opcode == 6'b101001) ? ((mem_addr_low == 2'b00) ? 4'b0011 : 4'b1100) : // sh指令
        (mem_opcode == 6'b101000) ? ((mem_addr_low == 2'b00) ? 4'b0001 : // sb指令
                                     (mem_addr_low == 2'b01) ? 4'b0010 :
                                     (mem_addr_low == 2'b10) ? 4'b0100 :
                                                               4'b1000) :
        (mem_opcode == 6'b101010) ? ((mem_addr_low == 2'b11) ? 4'b1111 : // swl指令
                                     (mem_addr_low == 2'b10) ? 4'b0111 :
                                     (mem_addr_low == 2'b01) ? 4'b0011 :
                                                               4'b0001) :
        (mem_opcode == 6'b101110) ? ((mem_addr_low == 2'b11) ? 4'b1000 : // swr指令
                                     (mem_addr_low == 2'b10) ? 4'b1100 :
                                     (mem_addr_low == 2'b01) ? 4'b1110 :
                                                               4'b1111) :
                                                               4'b0000;

    wire [31:0] store_data =
        (mem_opcode == 6'b101011) ? mem_store_data : // sw指令
        (mem_opcode == 6'b101001) ? ((mem_addr_low == 2'b00) ? {16'b0, mem_store_data[15:0]} :
                                                               {mem_store_data[15:0], 16'b0}) : // sh指令
        (mem_opcode == 6'b101000) ? ((mem_addr_low == 2'b00) ? {24'b0, mem_store_data[7:0]} :
                                     (mem_addr_low == 2'b01) ? {16'b0, mem_store_data[7:0], 8'b0} :
                                     (mem_addr_low == 2'b10) ? {8'b0,  mem_store_data[7:0], 16'b0} :
                                                               {mem_store_data[7:0], 24'b0}) : // sb指令
        (mem_opcode == 6'b101010) ? ((mem_addr_low == 2'b11) ? mem_store_data :
                                     (mem_addr_low == 2'b10) ? {8'b0,  mem_store_data[31:8]} :
                                     (mem_addr_low == 2'b01) ? {16'b0, mem_store_data[31:16]} :
                                                               {24'b0, mem_store_data[31:24]}) : // swl指令
        (mem_opcode == 6'b101110) ? ((mem_addr_low == 2'b11) ? {mem_store_data[7:0], 24'b0} :
                                     (mem_addr_low == 2'b10) ? {mem_store_data[15:0], 16'b0} :
                                     (mem_addr_low == 2'b01) ? {mem_store_data[23:0], 8'b0} :
                                                               mem_store_data) : // swr指令
                                                               32'b0;

    assign Write_strb = MemWrite ? store_strb : 4'b0000;
    assign Write_data = MemWrite ? store_data : 32'b0;

    wire [31:0] mem_to_wb_result = mem_result;

// MEM/WB register
    always @(posedge clk) begin
        if (rst) begin
            wb_state    <= ST_EMPTY;
            wb_valid    <= 1'b0;
            wb_pc       <= 32'b0;
            wb_inst     <= 32'b0;
            wb_result   <= 32'b0;
            wb_rf_wen   <= 1'b0;
            wb_rf_waddr <= 5'b0;
        end else begin
            case (wb_state)
                ST_EMPTY: begin
                    wb_valid <= 1'b0;
                    if (mem_to_wb_valid) begin
                        wb_state    <= ST_DONE;
                        wb_valid    <= 1'b1;
                        wb_pc       <= mem_pc;
                        wb_inst     <= mem_inst;
                        wb_result   <= mem_to_wb_result;
                        wb_rf_wen   <= mem_rf_wen;
                        wb_rf_waddr <= mem_rf_waddr;
                    end
                end

                ST_DONE: begin
                    wb_state <= ST_EMPTY;
                    wb_valid <= 1'b0;
                end

                default: begin
                    wb_state <= ST_EMPTY;
                    wb_valid <= 1'b0;
                end
            endcase
        end
    end

// WB control
    assign RF_wen   = wb_valid && wb_rf_wen;
    assign RF_waddr = RF_wen ? wb_rf_waddr : 5'b0;
    assign RF_wdata = RF_wen ? wb_result : 32'b0;

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

    assign inst_retire = wb_valid ? {RF_wen, RF_waddr, RF_wdata, wb_pc} : 70'b0;

// performance counter
    reg [31:0] cycle_cnt;
    always @(posedge clk) begin
        if (rst) begin
            cycle_cnt <= 32'd0;
        end else begin
            cycle_cnt <= cycle_cnt + 32'd1;
        end
    end
    assign cpu_perf_cnt_0 = cycle_cnt;

    reg [31:0] inst_retired_cnt;
    wire retire_valid = wb_valid;
    always @(posedge clk) begin
        if (rst) begin
            inst_retired_cnt <= 32'd0;
        end else if (retire_valid) begin
            inst_retired_cnt <= inst_retired_cnt + 32'd1;
        end
    end
    assign cpu_perf_cnt_1 = inst_retired_cnt;

    assign cpu_perf_cnt_2  = 32'b0;
    assign cpu_perf_cnt_3  = 32'b0;
    assign cpu_perf_cnt_4  = 32'b0;
    assign cpu_perf_cnt_5  = 32'b0;
    assign cpu_perf_cnt_6  = 32'b0;
    assign cpu_perf_cnt_7  = 32'b0;
    assign cpu_perf_cnt_8  = 32'b0;
    assign cpu_perf_cnt_9  = 32'b0;
    assign cpu_perf_cnt_10 = 32'b0;
    assign cpu_perf_cnt_11 = 32'b0;
    assign cpu_perf_cnt_12 = 32'b0;
    assign cpu_perf_cnt_13 = 32'b0;
    assign cpu_perf_cnt_14 = 32'b0;
    assign cpu_perf_cnt_15 = 32'b0;

endmodule

