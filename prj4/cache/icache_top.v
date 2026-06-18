`timescale 10ns / 1ns

`define CACHE_SET	8
`define CACHE_WAY	4
`define TAG_LEN		24
`define LINE_LEN	256

module icache_top (
	input	      clk,
	input	      rst,
	
	//CPU interface
	/** CPU instruction fetch request to Cache: valid signal */
	input         from_cpu_inst_req_valid,
	/** CPU instruction fetch request to Cache: address (4 byte alignment) */
	input  [31:0] from_cpu_inst_req_addr,
	/** Acknowledgement from Cache: ready to receive CPU instruction fetch request */
	output        to_cpu_inst_req_ready,
	
	/** Cache responses to CPU: valid signal */
	output        to_cpu_cache_rsp_valid,
	/** Cache responses to CPU: 32-bit Instruction value */
	output [31:0] to_cpu_cache_rsp_data,
	/** Acknowledgement from CPU: Ready to receive Instruction */
	input	      from_cpu_cache_rsp_ready,

	//Memory interface (32 byte aligned address)
	/** Cache sending memory read request: valid signal */
	output        to_mem_rd_req_valid,
	/** Cache sending memory read request: address (32 byte alignment) */
	output [31:0] to_mem_rd_req_addr,
	/** Acknowledgement from memory: ready to receive memory read request */
	input         from_mem_rd_req_ready,

	/** Memory return read data: valid signal of one data beat */
	input         from_mem_rd_rsp_valid,
	/** Memory return read data: 32-bit one data beat */
	input  [31:0] from_mem_rd_rsp_data,
	/** Memory return read data: if current data beat is the last in this burst data transmission */
	input         from_mem_rd_rsp_last,
	/** Acknowledgement from cache: ready to receive current data beat */
	output        to_mem_rd_rsp_ready
);

//TODO: Please add your I-Cache code here
    localparam S_WAIT     = 3'd0;
    localparam S_TAG_RD   = 3'd1;
    localparam S_CACHE_RD = 3'd2;
    localparam S_RESP     = 3'd3;
    localparam S_EVICT    = 3'd4;
    localparam S_MEM_RD   = 3'd5;
    localparam S_RECV     = 3'd6;
    localparam S_REFILL   = 3'd7;

    reg [2:0] state;

    reg [31:0] req_addr;
    reg [31:0] rsp_data;

    wire [`TAG_LEN - 1:0] req_tag = req_addr[31:8];
    wire [ 2:0] req_index = req_addr[7:5];
    wire [ 2:0] req_word  = req_addr[4:2];
    wire [31:0] req_line_addr = {req_addr[31:5], 5'b0};

    reg [`CACHE_SET - 1:0] valid_way0;
    reg [`CACHE_SET - 1:0] valid_way1;
    reg [`CACHE_SET - 1:0] valid_way2;
    reg [`CACHE_SET - 1:0] valid_way3;

    reg [1:0] replace_way [`CACHE_SET - 1:0];
    reg [1:0] victim_way;

    wire [`TAG_LEN - 1:0] tag_way0;
    wire [`TAG_LEN - 1:0] tag_way1;
    wire [`TAG_LEN - 1:0] tag_way2;
    wire [`TAG_LEN - 1:0] tag_way3;

    wire [`LINE_LEN - 1:0] data_way0;
    wire [`LINE_LEN - 1:0] data_way1;
    wire [`LINE_LEN - 1:0] data_way2;
    wire [`LINE_LEN - 1:0] data_way3;

    reg         tag_wen0;
    reg         tag_wen1;
    reg         tag_wen2;
    reg         tag_wen3;

    reg         data_wen0;
    reg         data_wen1;
    reg         data_wen2;
    reg         data_wen3;

    reg  [2:0]   array_waddr;
    reg  [`TAG_LEN - 1:0]  tag_wdata;
    reg  [`LINE_LEN - 1:0] data_wdata;

    tag_array tag_array_way0 (
        .clk   (clk),
        .waddr (array_waddr),
        .raddr (req_index),
        .wen   (tag_wen0),
        .wdata (tag_wdata),
        .rdata (tag_way0)
    );

    tag_array tag_array_way1 (
        .clk   (clk),
        .waddr (array_waddr),
        .raddr (req_index),
        .wen   (tag_wen1),
        .wdata (tag_wdata),
        .rdata (tag_way1)
    );

    tag_array tag_array_way2 (
        .clk   (clk),
        .waddr (array_waddr),
        .raddr (req_index),
        .wen   (tag_wen2),
        .wdata (tag_wdata),
        .rdata (tag_way2)
    );

    tag_array tag_array_way3 (
        .clk   (clk),
        .waddr (array_waddr),
        .raddr (req_index),
        .wen   (tag_wen3),
        .wdata (tag_wdata),
        .rdata (tag_way3)
    );

    data_array data_array_way0 (
        .clk   (clk),
        .waddr (array_waddr),
        .raddr (req_index),
        .wen   (data_wen0),
        .wdata (data_wdata),
        .rdata (data_way0)
    );

    data_array data_array_way1 (
        .clk   (clk),
        .waddr (array_waddr),
        .raddr (req_index),
        .wen   (data_wen1),
        .wdata (data_wdata),
        .rdata (data_way1)
    );

    data_array data_array_way2 (
        .clk   (clk),
        .waddr (array_waddr),
        .raddr (req_index),
        .wen   (data_wen2),
        .wdata (data_wdata),
        .rdata (data_way2)
    );

    data_array data_array_way3 (
        .clk   (clk),
        .waddr (array_waddr),
        .raddr (req_index),
        .wen   (data_wen3),
        .wdata (data_wdata),
        .rdata (data_way3)
    );

    wire hit_way0 = valid_way0[req_index] && (tag_way0 == req_tag);
    wire hit_way1 = valid_way1[req_index] && (tag_way1 == req_tag);
    wire hit_way2 = valid_way2[req_index] && (tag_way2 == req_tag);
    wire hit_way3 = valid_way3[req_index] && (tag_way3 == req_tag);

    wire cache_hit = hit_way0 || hit_way1 || hit_way2 || hit_way3;

    wire [`LINE_LEN - 1:0] hit_line =   hit_way0 ? data_way0 :
                                        hit_way1 ? data_way1 :
                                        hit_way2 ? data_way2 :
                                                   data_way3;

    wire has_invalid =  !valid_way0[req_index] ||
                        !valid_way1[req_index] ||
                        !valid_way2[req_index] ||
                        !valid_way3[req_index];

    wire [1:0] first_invalid_way =  !valid_way0[req_index] ? 2'd0 :
                                    !valid_way1[req_index] ? 2'd1 :
                                    !valid_way2[req_index] ? 2'd2 :
                                                            2'd3;

    reg [`LINE_LEN - 1:0] refill_line;
    reg [2:0]   recv_cnt;

    //control sign for state
    assign to_cpu_inst_req_ready    = rst || (state == S_WAIT);
    assign to_cpu_cache_rsp_valid   = !rst && (state == S_RESP);
    assign to_cpu_cache_rsp_data    = rsp_data;

    assign to_mem_rd_req_valid      = !rst && (state == S_MEM_RD);
    assign to_mem_rd_req_addr       = req_line_addr;
    assign to_mem_rd_rsp_ready      = rst || (state == S_RECV);

    function [31:0] select_word;
        input [`LINE_LEN - 1:0] line;
        input [2:0] word_index;
        begin
            case (word_index)
                3'd0: select_word = line[ 31:  0];
                3'd1: select_word = line[ 63: 32];
                3'd2: select_word = line[ 95: 64];
                3'd3: select_word = line[127: 96];
                3'd4: select_word = line[159:128];
                3'd5: select_word = line[191:160];
                3'd6: select_word = line[223:192];
                3'd7: select_word = line[255:224];
                default: select_word = 32'b0;
            endcase
        end
    endfunction

    integer i;

    always @(*) begin
        tag_wen0    = 1'b0;
        tag_wen1    = 1'b0;
        tag_wen2    = 1'b0;
        tag_wen3    = 1'b0;

        data_wen0   = 1'b0;
        data_wen1   = 1'b0;
        data_wen2   = 1'b0;
        data_wen3   = 1'b0;

        array_waddr = req_index;
        tag_wdata   = req_tag;
        data_wdata  = refill_line;

        if (state == S_REFILL) begin
            case (victim_way)
                2'd0: begin
                    tag_wen0  = 1'b1;
                    data_wen0 = 1'b1;
                end
                2'd1: begin
                    tag_wen1  = 1'b1;
                    data_wen1 = 1'b1;
                end
                2'd2: begin
                    tag_wen2  = 1'b1;
                    data_wen2 = 1'b1;
                end
                2'd3: begin
                    tag_wen3  = 1'b1;
                    data_wen3 = 1'b1;
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state       <= S_WAIT;
            req_addr    <= 32'b0;
            rsp_data    <= 32'b0;
            refill_line <= {`LINE_LEN{1'b0}};
            recv_cnt    <= 3'b0;
            victim_way  <= 2'b0;

            valid_way0  <= {`CACHE_SET{1'b0}};
            valid_way1  <= {`CACHE_SET{1'b0}};
            valid_way2  <= {`CACHE_SET{1'b0}};
            valid_way3  <= {`CACHE_SET{1'b0}};

            for (i = 0; i < `CACHE_SET; i = i + 1) begin
                replace_way[i] <= 2'b0;
            end
        end else begin
            case (state)
                S_WAIT: begin
                    if (from_cpu_inst_req_valid) begin
                        req_addr <= from_cpu_inst_req_addr;
                        state    <= S_TAG_RD;
                    end
                end

                S_TAG_RD: begin
                    if (cache_hit) begin
                        state <= S_CACHE_RD;
                    end else begin
                        state <= S_EVICT;
                    end
                end

                S_CACHE_RD: begin
                    rsp_data <= select_word(hit_line, req_word);
                    state    <= S_RESP;
                end

                S_RESP: begin
                    if (from_cpu_cache_rsp_ready) begin
                        state <= S_WAIT;
                    end
                end

                S_EVICT: begin
                    victim_way <= (has_invalid ? first_invalid_way : replace_way[req_index]);

                    case (has_invalid ? first_invalid_way : replace_way[req_index])
                        2'd0: valid_way0[req_index] <= 1'b0;
                        2'd1: valid_way1[req_index] <= 1'b0;
                        2'd2: valid_way2[req_index] <= 1'b0;
                        2'd3: valid_way3[req_index] <= 1'b0;
                    endcase

                    state <= S_MEM_RD;
                end

                S_MEM_RD: begin
                    if (from_mem_rd_req_ready) begin
                        recv_cnt    <= 3'b0;
                        refill_line <= {`LINE_LEN{1'b0}};
                        state       <= S_RECV;
                    end
                end

                S_RECV: begin
                    if (from_mem_rd_rsp_valid) begin
                        case (recv_cnt)
                            3'd0: refill_line[ 31:  0] <= from_mem_rd_rsp_data;
                            3'd1: refill_line[ 63: 32] <= from_mem_rd_rsp_data;
                            3'd2: refill_line[ 95: 64] <= from_mem_rd_rsp_data;
                            3'd3: refill_line[127: 96] <= from_mem_rd_rsp_data;
                            3'd4: refill_line[159:128] <= from_mem_rd_rsp_data;
                            3'd5: refill_line[191:160] <= from_mem_rd_rsp_data;
                            3'd6: refill_line[223:192] <= from_mem_rd_rsp_data;
                            3'd7: refill_line[255:224] <= from_mem_rd_rsp_data;
                        endcase

                        if (from_mem_rd_rsp_last) begin
                            state <= S_REFILL;
                        end else begin
                            recv_cnt <= recv_cnt + 3'd1;
                        end
                    end
                end

                S_REFILL: begin
                    case (victim_way)
                        2'd0: valid_way0[req_index] <= 1'b1;
                        2'd1: valid_way1[req_index] <= 1'b1;
                        2'd2: valid_way2[req_index] <= 1'b1;
                        2'd3: valid_way3[req_index] <= 1'b1;
                    endcase

                    replace_way[req_index] <= victim_way + 2'd1;
                    rsp_data <= select_word(refill_line, req_word);
                    state    <= S_RESP;
                end

                default: begin
                    state <= S_WAIT;
                end
            endcase
        end
    end




endmodule

