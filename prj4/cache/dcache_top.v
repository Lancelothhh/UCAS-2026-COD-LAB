`timescale 10ns / 1ns

`define CACHE_SET	8
`define CACHE_WAY	4
`define TAG_LEN		24
`define LINE_LEN	256

module dcache_top (
	input	      clk,
	input	      rst,
  
	//CPU interface
	/** CPU memory/IO access request to Cache: valid signal */
	input         from_cpu_mem_req_valid,
	/** CPU memory/IO access request to Cache: 0 for read; 1 for write (when req_valid is high) */
	input         from_cpu_mem_req,
	/** CPU memory/IO access request to Cache: address (4 byte alignment) */
	input  [31:0] from_cpu_mem_req_addr,
	/** CPU memory/IO access request to Cache: 32-bit write data */
	input  [31:0] from_cpu_mem_req_wdata,
	/** CPU memory/IO access request to Cache: 4-bit write strobe */
	input  [ 3:0] from_cpu_mem_req_wstrb,
	/** Acknowledgement from Cache: ready to receive CPU memory access request */
	output        to_cpu_mem_req_ready,
		
	/** Cache responses to CPU: valid signal */
	output        to_cpu_cache_rsp_valid,
	/** Cache responses to CPU: 32-bit read data */
	output [31:0] to_cpu_cache_rsp_data,
	/** Acknowledgement from CPU: Ready to receive read data */
	input         from_cpu_cache_rsp_ready,
		
	//Memory/IO read interface
	/** Cache sending memory/IO read request: valid signal */
	output        to_mem_rd_req_valid,
	/** Cache sending memory read request: address
	  * 4 byte alignment for I/O read 
	  * 32 byte alignment for cache read miss */
	output [31:0] to_mem_rd_req_addr,
        /** Cache sending memory read request: burst length
	  * 0 for I/O read (read only one data beat)
	  * 7 for cache read miss (read eight data beats) */
	output [ 7:0] to_mem_rd_req_len,
        /** Acknowledgement from memory: ready to receive memory read request */
	input	      from_mem_rd_req_ready,

	/** Memory return read data: valid signal of one data beat */
	input	      from_mem_rd_rsp_valid,
	/** Memory return read data: 32-bit one data beat */
	input  [31:0] from_mem_rd_rsp_data,
	/** Memory return read data: if current data beat is the last in this burst data transmission */
	input	      from_mem_rd_rsp_last,
	/** Acknowledgement from cache: ready to receive current data beat */
	output        to_mem_rd_rsp_ready,

	//Memory/IO write interface
	/** Cache sending memory/IO write request: valid signal */
	output        to_mem_wr_req_valid,
	/** Cache sending memory write request: address
	  * 4 byte alignment for I/O write 
	  * 4 byte alignment for cache write miss
          * 32 byte alignment for cache write-back */
	output [31:0] to_mem_wr_req_addr,
        /** Cache sending memory write request: burst length
          * 0 for I/O write (write only one data beat)
          * 0 for cache write miss (write only one data beat)
          * 7 for cache write-back (write eight data beats) */
	output [ 7:0] to_mem_wr_req_len,
        /** Acknowledgement from memory: ready to receive memory write request */
	input         from_mem_wr_req_ready,

	/** Cache sending memory/IO write data: valid signal for current data beat */
	output        to_mem_wr_data_valid,
	/** Cache sending memory/IO write data: current data beat */
	output [31:0] to_mem_wr_data,
	/** Cache sending memory/IO write data: write strobe
	  * 4'b1111 for cache write-back 
	  * other values for I/O write and cache write miss according to the original CPU request*/ 
	output [ 3:0] to_mem_wr_data_strb,
	/** Cache sending memory/IO write data: if current data beat is the last in this burst data transmission */
	output        to_mem_wr_data_last,
	/** Acknowledgement from memory/IO: ready to receive current data beat */
	input	      from_mem_wr_data_ready
);

    // Blocking, write-back, write-allocate D-Cache.
    localparam S_WAIT           = 4'd0;
    localparam S_TAG_RD         = 4'd1;
    localparam S_CACHE_RD       = 4'd2;
    localparam S_RESP           = 4'd3;
    localparam S_EVICT          = 4'd4;
    localparam S_WRITEBACK_REQ  = 4'd5;
    localparam S_WRITEBACK_DATA = 4'd6;
    localparam S_MEM_RD         = 4'd7;
    localparam S_RECV           = 4'd8;
    localparam S_REFILL         = 4'd9;
    localparam S_BYPASS_RD_REQ  = 4'd10;
    localparam S_BYPASS_RD_RECV = 4'd11;
    localparam S_BYPASS_WR_REQ  = 4'd12;
    localparam S_BYPASS_WR_DATA = 4'd13;

    reg [3:0] state;

    reg        req_write;
    reg [31:0] req_addr;
    reg [31:0] req_wdata;
    reg [ 3:0] req_wstrb;
    reg [31:0] rsp_data;

    wire [`TAG_LEN - 1:0] req_tag = req_addr[31:8];
    wire [2:0] req_index = req_addr[7:5];
    wire [2:0] req_word  = req_addr[4:2];
    wire [31:0] req_word_addr = {req_addr[31:2], 2'b0};
    wire [31:0] req_line_addr = {req_addr[31:5], 5'b0};

    reg [`CACHE_SET - 1:0] valid_way0;
    reg [`CACHE_SET - 1:0] valid_way1;
    reg [`CACHE_SET - 1:0] valid_way2;
    reg [`CACHE_SET - 1:0] valid_way3;

    reg [`CACHE_SET - 1:0] dirty_way0;
    reg [`CACHE_SET - 1:0] dirty_way1;
    reg [`CACHE_SET - 1:0] dirty_way2;
    reg [`CACHE_SET - 1:0] dirty_way3;

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

    reg tag_wen0;
    reg tag_wen1;
    reg tag_wen2;
    reg tag_wen3;

    reg data_wen0;
    reg data_wen1;
    reg data_wen2;
    reg data_wen3;

    reg [2:0] array_waddr;
    reg [`TAG_LEN - 1:0] tag_wdata;
    reg [`LINE_LEN - 1:0] data_wdata;

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

    wire [1:0] hit_way = hit_way0 ? 2'd0 :
                         hit_way1 ? 2'd1 :
                         hit_way2 ? 2'd2 :
                                    2'd3;

    wire [`LINE_LEN - 1:0] hit_line = hit_way0 ? data_way0 :
                                      hit_way1 ? data_way1 :
                                      hit_way2 ? data_way2 :
                                                 data_way3;

    wire has_invalid = !valid_way0[req_index] ||
                       !valid_way1[req_index] ||
                       !valid_way2[req_index] ||
                       !valid_way3[req_index];

    wire [1:0] first_invalid_way = !valid_way0[req_index] ? 2'd0 :
                                   !valid_way1[req_index] ? 2'd1 :
                                   !valid_way2[req_index] ? 2'd2 :
                                                            2'd3;

    wire [1:0] chosen_victim_way = has_invalid ? first_invalid_way : replace_way[req_index];

    wire chosen_victim_valid = (chosen_victim_way == 2'd0) ? valid_way0[req_index] :
                               (chosen_victim_way == 2'd1) ? valid_way1[req_index] :
                               (chosen_victim_way == 2'd2) ? valid_way2[req_index] :
                                                              valid_way3[req_index];

    wire chosen_victim_dirty = (chosen_victim_way == 2'd0) ? dirty_way0[req_index] :
                               (chosen_victim_way == 2'd1) ? dirty_way1[req_index] :
                               (chosen_victim_way == 2'd2) ? dirty_way2[req_index] :
                                                              dirty_way3[req_index];

    wire [`TAG_LEN - 1:0] chosen_victim_tag =
        (chosen_victim_way == 2'd0) ? tag_way0 :
        (chosen_victim_way == 2'd1) ? tag_way1 :
        (chosen_victim_way == 2'd2) ? tag_way2 :
                                      tag_way3;

    wire [`LINE_LEN - 1:0] chosen_victim_line =
        (chosen_victim_way == 2'd0) ? data_way0 :
        (chosen_victim_way == 2'd1) ? data_way1 :
        (chosen_victim_way == 2'd2) ? data_way2 :
                                      data_way3;

    reg [31:0] wb_addr;
    reg [`LINE_LEN - 1:0] wb_line;
    reg [2:0] wb_cnt;

    reg [`LINE_LEN - 1:0] refill_line;
    reg [2:0] recv_cnt;

    assign to_cpu_mem_req_ready    = rst || (state == S_WAIT);
    assign to_cpu_cache_rsp_valid  = !rst && (state == S_RESP);
    assign to_cpu_cache_rsp_data   = rsp_data;

    assign to_mem_rd_req_valid     = !rst && ((state == S_MEM_RD) || (state == S_BYPASS_RD_REQ));
    assign to_mem_rd_req_addr      = (state == S_BYPASS_RD_REQ) ? req_word_addr : req_line_addr;
    assign to_mem_rd_req_len       = (state == S_BYPASS_RD_REQ) ? 8'd0 : 8'd7;
    assign to_mem_rd_rsp_ready     = rst || (state == S_RECV) || (state == S_BYPASS_RD_RECV);

    assign to_mem_wr_req_valid     = !rst && ((state == S_WRITEBACK_REQ) || (state == S_BYPASS_WR_REQ));
    assign to_mem_wr_req_addr      = (state == S_BYPASS_WR_REQ) ? req_word_addr : wb_addr;
    assign to_mem_wr_req_len       = (state == S_BYPASS_WR_REQ) ? 8'd0 : 8'd7;

    assign to_mem_wr_data_valid    = !rst && ((state == S_WRITEBACK_DATA) || (state == S_BYPASS_WR_DATA));
    assign to_mem_wr_data          = (state == S_BYPASS_WR_DATA) ? req_wdata : select_word(wb_line, wb_cnt);
    assign to_mem_wr_data_strb     = (state == S_BYPASS_WR_DATA) ? req_wstrb : 4'b1111;
    assign to_mem_wr_data_last     = (state == S_BYPASS_WR_DATA) || (wb_cnt == 3'd7);

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

    function [31:0] merge_word;
        input [31:0] old_word;
        input [31:0] new_word;
        input [3:0]  wstrb;
        begin
            merge_word[ 7: 0] = wstrb[0] ? new_word[ 7: 0] : old_word[ 7: 0];
            merge_word[15: 8] = wstrb[1] ? new_word[15: 8] : old_word[15: 8];
            merge_word[23:16] = wstrb[2] ? new_word[23:16] : old_word[23:16];
            merge_word[31:24] = wstrb[3] ? new_word[31:24] : old_word[31:24];
        end
    endfunction

    function [`LINE_LEN - 1:0] write_line;
        input [`LINE_LEN - 1:0] line;
        input [2:0] word_index;
        input [31:0] wdata;
        input [3:0]  wstrb;
        reg [`LINE_LEN - 1:0] next_line;
        begin
            next_line = line;
            case (word_index)
                3'd0: next_line[ 31:  0] = merge_word(line[ 31:  0], wdata, wstrb);
                3'd1: next_line[ 63: 32] = merge_word(line[ 63: 32], wdata, wstrb);
                3'd2: next_line[ 95: 64] = merge_word(line[ 95: 64], wdata, wstrb);
                3'd3: next_line[127: 96] = merge_word(line[127: 96], wdata, wstrb);
                3'd4: next_line[159:128] = merge_word(line[159:128], wdata, wstrb);
                3'd5: next_line[191:160] = merge_word(line[191:160], wdata, wstrb);
                3'd6: next_line[223:192] = merge_word(line[223:192], wdata, wstrb);
                3'd7: next_line[255:224] = merge_word(line[255:224], wdata, wstrb);
            endcase
            write_line = next_line;
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

        if (state == S_CACHE_RD && req_write && cache_hit) begin
            data_wdata = write_line(hit_line, req_word, req_wdata, req_wstrb);
            case (hit_way)
                2'd0: data_wen0 = 1'b1;
                2'd1: data_wen1 = 1'b1;
                2'd2: data_wen2 = 1'b1;
                2'd3: data_wen3 = 1'b1;
            endcase
        end else if (state == S_REFILL) begin
            data_wdata = req_write ? write_line(refill_line, req_word, req_wdata, req_wstrb) : refill_line;
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
            req_write   <= 1'b0;
            req_addr    <= 32'b0;
            req_wdata   <= 32'b0;
            req_wstrb   <= 4'b0;
            rsp_data    <= 32'b0;
            victim_way  <= 2'b0;
            wb_addr     <= 32'b0;
            wb_line     <= {`LINE_LEN{1'b0}};
            wb_cnt      <= 3'b0;
            refill_line <= {`LINE_LEN{1'b0}};
            recv_cnt    <= 3'b0;

            valid_way0  <= {`CACHE_SET{1'b0}};
            valid_way1  <= {`CACHE_SET{1'b0}};
            valid_way2  <= {`CACHE_SET{1'b0}};
            valid_way3  <= {`CACHE_SET{1'b0}};
            dirty_way0  <= {`CACHE_SET{1'b0}};
            dirty_way1  <= {`CACHE_SET{1'b0}};
            dirty_way2  <= {`CACHE_SET{1'b0}};
            dirty_way3  <= {`CACHE_SET{1'b0}};

            for (i = 0; i < `CACHE_SET; i = i + 1) begin
                replace_way[i] <= 2'b0;
            end
        end else begin
            case (state)
                S_WAIT: begin
                    if (from_cpu_mem_req_valid) begin
                        req_write <= from_cpu_mem_req;
                        req_addr  <= from_cpu_mem_req_addr;
                        req_wdata <= from_cpu_mem_req_wdata;
                        req_wstrb <= from_cpu_mem_req_wstrb;

                        if ((from_cpu_mem_req_addr[31:5] == 27'b0) || (from_cpu_mem_req_addr[31:30] != 2'b00)) begin
                            state <= from_cpu_mem_req ? S_BYPASS_WR_REQ : S_BYPASS_RD_REQ;
                        end else begin
                            state <= S_TAG_RD;
                        end
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
                    if (req_write) begin
                        case (hit_way)
                            2'd0: dirty_way0[req_index] <= 1'b1;
                            2'd1: dirty_way1[req_index] <= 1'b1;
                            2'd2: dirty_way2[req_index] <= 1'b1;
                            2'd3: dirty_way3[req_index] <= 1'b1;
                        endcase
                        state <= S_WAIT;
                    end else begin
                        rsp_data <= select_word(hit_line, req_word);
                        state    <= S_RESP;
                    end
                end

                S_RESP: begin
                    if (from_cpu_cache_rsp_ready) begin
                        state <= S_WAIT;
                    end
                end

                S_EVICT: begin
                    victim_way <= chosen_victim_way;
                    wb_addr    <= {chosen_victim_tag, req_index, 5'b0};
                    wb_line    <= chosen_victim_line;

                    case (chosen_victim_way)
                        2'd0: begin
                            valid_way0[req_index] <= 1'b0;
                            dirty_way0[req_index] <= 1'b0;
                        end
                        2'd1: begin
                            valid_way1[req_index] <= 1'b0;
                            dirty_way1[req_index] <= 1'b0;
                        end
                        2'd2: begin
                            valid_way2[req_index] <= 1'b0;
                            dirty_way2[req_index] <= 1'b0;
                        end
                        2'd3: begin
                            valid_way3[req_index] <= 1'b0;
                            dirty_way3[req_index] <= 1'b0;
                        end
                    endcase

                    if (chosen_victim_valid && chosen_victim_dirty) begin
                        state <= S_WRITEBACK_REQ;
                    end else begin
                        state <= S_MEM_RD;
                    end
                end

                S_WRITEBACK_REQ: begin
                    if (from_mem_wr_req_ready) begin
                        wb_cnt <= 3'b0;
                        state  <= S_WRITEBACK_DATA;
                    end
                end

                S_WRITEBACK_DATA: begin
                    if (from_mem_wr_data_ready) begin
                        if (wb_cnt == 3'd7) begin
                            state <= S_MEM_RD;
                        end else begin
                            wb_cnt <= wb_cnt + 3'd1;
                        end
                    end
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
                        2'd0: begin
                            valid_way0[req_index] <= 1'b1;
                            dirty_way0[req_index] <= req_write;
                        end
                        2'd1: begin
                            valid_way1[req_index] <= 1'b1;
                            dirty_way1[req_index] <= req_write;
                        end
                        2'd2: begin
                            valid_way2[req_index] <= 1'b1;
                            dirty_way2[req_index] <= req_write;
                        end
                        2'd3: begin
                            valid_way3[req_index] <= 1'b1;
                            dirty_way3[req_index] <= req_write;
                        end
                    endcase

                    replace_way[req_index] <= victim_way + 2'd1;

                    if (req_write) begin
                        state <= S_WAIT;
                    end else begin
                        rsp_data <= select_word(refill_line, req_word);
                        state    <= S_RESP;
                    end
                end

                S_BYPASS_RD_REQ: begin
                    if (from_mem_rd_req_ready) begin
                        state <= S_BYPASS_RD_RECV;
                    end
                end

                S_BYPASS_RD_RECV: begin
                    if (from_mem_rd_rsp_valid) begin
                        rsp_data <= from_mem_rd_rsp_data;
                        state    <= S_RESP;
                    end
                end

                S_BYPASS_WR_REQ: begin
                    if (from_mem_wr_req_ready) begin
                        state <= S_BYPASS_WR_DATA;
                    end
                end

                S_BYPASS_WR_DATA: begin
                    if (from_mem_wr_data_ready) begin
                        state <= S_WAIT;
                    end
                end

                default: begin
                    state <= S_WAIT;
                end
            endcase
        end
    end

endmodule

