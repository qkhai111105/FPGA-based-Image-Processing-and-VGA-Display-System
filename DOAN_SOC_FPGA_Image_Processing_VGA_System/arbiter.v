module arbiter (
    input wire clk,
    input wire rst_n,

    // -------------------------------------------------------------------------
    // 1. GIAO DIỆN VỚI UART (Chỉ cần RX vì mục tiêu là nhận ảnh từ PC)
    // -------------------------------------------------------------------------
    input  wire [7:0] uart_rx_data,
    input  wire       uart_rx_done,

    // -------------------------------------------------------------------------
    // 2. GIAO DIỆN VỚI MÀN HÌNH VGA
    // -------------------------------------------------------------------------
    output reg  [15:0] vga_data_o,
    output reg         vga_wr_en_o,
    input  wire        vga_full_i,

    // -------------------------------------------------------------------------
    // 3. GIAO DIỆN VỚI SRAM CONTROLLER
    // -------------------------------------------------------------------------
    output reg  [17:0] sram_addr_o,
    output reg         sram_read_o,
    output reg         sram_write_o,
    output reg  [15:0] sram_data_o,
    input  wire [15:0] sram_data_i,
    output wire [1:0]  sram_byte_en_o,
	 
	 
    // -------------------------------------------------------------------------
    // 4. GIAO DIỆN VỚI EDGE DETECTION
    // -------------------------------------------------------------------------
	 
	 output reg 			edge_pixel_valid_o,
	 output reg	[15:0]	edge_rgb565_o,
	 input wire [15:0]	edge_rgb565_i,
	 output reg 			edge_fifo_rdreq_o,
	 input wire 			edge_fifo_full_i,
	 input wire 			edge_fifo_empty_i,
	 input wire 			edge_fifo_almost_full_i,
	 
	 // -------------------------------------------------------------------------
    // 5. AVALON-MM SLAVE INTERFACE
    // -------------------------------------------------------------------------
		
	 input wire [2:0] 	avs_address_i,
	 input wire 			avs_read_i,
	 input wire 			avs_write_i,
	 input wire [31:0] 	avs_writedata_i,
	 output reg [31:0] 	avs_readdata_o,
	 output reg 			avs_readdatavalid_o,
	 output wire 			avs_irq_o
);

    // Độ phân giải ảnh 320x240 = 76800 pixels
    localparam MAX_ADDR = 18'd76799;

    // Luôn cho phép ghi cả 2 byte (16-bit) vào SRAM
    assign sram_byte_en_o = 2'b11;

    // =========================================================================
    // MAIN ARBITER FSM STATES
    // =========================================================================
    localparam ST_IDLE       				= 4'd0;
    localparam ST_UART_WR    				= 4'd1;
    localparam ST_VGA_RD_REQ 				= 4'd2;
    localparam ST_VGA_RD_WAIT 			= 4'd3;
    localparam ST_VGA_RD_ACK 				= 4'd4;
	 localparam ST_EDGE_RD_REQ				= 4'd5;
	 localparam ST_EDGE_RD_WAIT 			= 4'd6;
	 localparam ST_EDGE_RD_ACK 			= 4'd7;
	 localparam ST_EDGE_FLUSH				= 4'd8;
	 localparam ST_EDGE_DRAIN				= 4'd9;
	 localparam ST_EDGE_WR_REQ				= 4'd10;
	 localparam ST_EDGE_WR_SEQ 			= 4'd11;
	 localparam ST_EDGE_WAIT_CMD_CLEAR 	= 4'd12;
	 localparam EDGE_PIPELINE_FLUSH_CYCLES = 4'd8;

    reg [3:0] state;

    // =========================================================================
    // KHỐI 1: QUẢN LÝ GHÉP BYTE TỪ UART
    // =========================================================================
    reg        byte_toggle;      // 0: Chờ byte thấp, 1: Chờ byte cao
    reg [15:0] pixel_reg;        // Thanh ghi chứa pixel hoàn chỉnh
    reg        uart_req;         // Cờ báo hiệu đã có đủ 1 pixel 16-bit cần ghi vào SRAM

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_toggle <= 1'b0;
            pixel_reg   <= 16'h0000;
            uart_req    <= 1'b0;
        end else begin
            // Mặc định hạ cờ req sau 1 chu kỳ để tránh ghi liên tục
            if (state == ST_UART_WR) begin
                uart_req <= 1'b0; 
            end

            if (uart_rx_done) begin
                if (byte_toggle == 1'b0) begin
                    // Nhận byte đầu tiên (Ví dụ: Byte thấp)
                    pixel_reg[7:0] <= uart_rx_data;
                    byte_toggle    <= 1'b1;
                end else begin
                    // Nhận byte thứ hai (Ví dụ: Byte cao)
                    pixel_reg[15:8] <= uart_rx_data;
                    byte_toggle     <= 1'b0;
                    uart_req        <= 1'b1; // Đã đủ 2 byte -> Bật cờ yêu cầu Arbiter cấp quyền SRAM
                end
            end
        end
    end

    // =========================================================================
    // KHỐI 2: REGISTERS, POINTERS AND FLGAS
    // =========================================================================
    reg [17:0] uart_addr_ptr; // Con trỏ địa chỉ dùng để GHI dữ liệu từ UART (0)
    reg [17:0] vga_addr_ptr;  // Con trỏ địa chỉ dùng để ĐỌC dữ liệu cho VGA (1)
	 reg [17:0] edge_detect_write_addr_ptr; // con tro dia chi ghi xu ly anh  (2)
	 reg [17:0] edge_detect_read_addr_ptr; // con tro dia chi doc xu ly anh   (3)
	 // offset
	 reg [17:0] edge_detect_read_offset;
	 reg [17:0] edge_detect_write_offset;
	 reg [17:0] vga_offset;
	 reg [17:0] uart_offset;
	 
	 reg [1:0] interrupt_status_reg;				 // (4)
	 reg perform_edge_detect; // fsm1
	 reg uart_wrapped;
	 reg edge_detect_done;
	 reg edge_input_done;
	 reg [3:0] edge_flush_count;
	 
	 localparam IRQ_UART_WRAPPED_IDX = 0;
	 localparam IRQ_EDGE_DETECT_DONE_IDX = 1;
	 
	 assign avs_irq_o = (interrupt_status_reg != 2'b00)?1'b1:1'b0;
	
    // =========================================================================
    // KHỐI 3: FSM1 - XU LY AVALON REQUEST
    // =========================================================================
	localparam 	UART_ADDR_PTR 					= 3'd0, 
					VGA_ADDR_PTR 					= 3'd1, 
					EDGE_DETECT_WRITE_ADDR_PTR = 3'd2, 
					EDGE_DETECT_READ_ADDR_PTR 	= 3'd3, 
					INTERRUPT_STATUS_REGISTER	= 3'd4, 
					PERFORM_EDGE_DETECTION_CMD = 3'd5;
					
					
	localparam ST_AVS_IDLE = 2'b00;
	localparam ST_AVS_READ = 2'b01;
	localparam ST_AVS_WRITE = 2'b11;
	
	reg [1:0] avs_state;
	
	always @(posedge clk or negedge rst_n) begin 
		if (rst_n == 1'b0) begin
			uart_addr_ptr <= 18'd0;
         vga_addr_ptr  <= 18'd0;
			edge_detect_write_addr_ptr <= 18'd0;
			edge_detect_read_addr_ptr <= 18'd0;
			interrupt_status_reg <= 2'b00;
			perform_edge_detect <= 1'b0;
			avs_state <= ST_AVS_IDLE;
			avs_readdata_o <= 32'd0;
			avs_readdatavalid_o <= 1'b0;
		end else begin 
			case (avs_state) 
			
				ST_AVS_IDLE: begin 
					avs_readdatavalid_o <= 0;
					if (avs_read_i == 1'b1) avs_state <= ST_AVS_READ;
					else if (avs_write_i == 1'b1) avs_state <= ST_AVS_WRITE;
					else avs_state <= ST_AVS_IDLE;
					
					// set interrupt flags when specific events occurs
					if (uart_wrapped == 1'b1) begin // uart 
						interrupt_status_reg[IRQ_UART_WRAPPED_IDX] <= 1'b1;
					end
					
					if (edge_detect_done == 1'b1) begin // image processing
						perform_edge_detect <= 1'b0;
						interrupt_status_reg[IRQ_EDGE_DETECT_DONE_IDX] <= 1'b1;
					end
				end
				
				ST_AVS_READ: begin
					// perform read operation
					case (avs_address_i)
						UART_ADDR_PTR: begin 
							avs_readdata_o <= {{14{1'b0}}, {uart_addr_ptr}};
							avs_readdatavalid_o <= 1'b1;
						end
						
						VGA_ADDR_PTR: begin 
							avs_readdata_o <= {{14{1'b0}}, {vga_addr_ptr}};
							avs_readdatavalid_o <= 1'b1;
						end
						
						EDGE_DETECT_WRITE_ADDR_PTR: begin
							avs_readdata_o <= {{14{1'b0}}, {edge_detect_write_addr_ptr}};
							avs_readdatavalid_o <= 1'b1;
						end
						
						EDGE_DETECT_READ_ADDR_PTR: begin 
							avs_readdata_o <= {{14{1'b0}}, {edge_detect_read_addr_ptr}};
							avs_readdatavalid_o <= 1'b1;
						end
						
						INTERRUPT_STATUS_REGISTER: begin
							avs_readdata_o <= {{30{1'b0}}, {interrupt_status_reg}};
							avs_readdatavalid_o <= 1'b1;
						end
						default: begin 
							avs_readdata_o <= 32'd0;
							avs_readdatavalid_o <= 1'b1;
						end
					endcase
					// back to idle state 
					avs_state <= ST_AVS_IDLE;
				end
				
				ST_AVS_WRITE: begin 
					// perform write operation
					case (avs_address_i)
						UART_ADDR_PTR: begin 
							uart_addr_ptr <= avs_writedata_i[17:0];
						end
						
						VGA_ADDR_PTR: begin 
							vga_addr_ptr <= avs_writedata_i[17:0];
						end
						
						EDGE_DETECT_WRITE_ADDR_PTR: begin
							edge_detect_write_addr_ptr <= avs_writedata_i[17:0];
						end
						
						EDGE_DETECT_READ_ADDR_PTR: begin
							edge_detect_read_addr_ptr <= avs_writedata_i[17:0];
						end
						
						PERFORM_EDGE_DETECTION_CMD: begin 
							perform_edge_detect <= 1'b1;
						end
						
						INTERRUPT_STATUS_REGISTER: begin
							interrupt_status_reg <= avs_writedata_i[1:0];
						end
						
						default: begin 
							// do nothing
						end
					endcase
					
					// back to idle state
					avs_state <= ST_AVS_IDLE;
				end
				
				default: avs_state <= ST_AVS_IDLE;
			endcase
		end
	end
	
	 
	 
    // =========================================================================
    // KHỐI 4: FSM2 - MÁY TRẠNG THÁI PHÂN XỬ (ARBITER)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (rst_n == 1'b0) begin
            state         <= ST_IDLE;
				uart_offset <= 18'd0;
				vga_offset <= 18'd0;
				edge_detect_write_offset <= 18'd0;
				edge_detect_read_offset <= 18'd0;
				uart_wrapped <= 1'b0;
				edge_detect_done <= 1'b0;
				edge_input_done <= 1'b0;
				edge_flush_count <= 4'd0;
            sram_addr_o   <= 18'd0;
            sram_read_o   <= 1'b0;
            sram_write_o  <= 1'b0;
            sram_data_o   <= 16'h0000;
            vga_data_o    <= 16'h0000;
            vga_wr_en_o   <= 1'b0;
            edge_pixel_valid_o <= 1'b0;
            edge_rgb565_o <= 16'h0000;
            edge_fifo_rdreq_o <= 1'b0;
        end else begin
            // Xóa các tín hiệu xung 1 chu kỳ
            sram_read_o  <= 1'b0;
            sram_write_o <= 1'b0;
            vga_wr_en_o  <= 1'b0;
            edge_pixel_valid_o <= 1'b0;
            edge_fifo_rdreq_o <= 1'b0;
				
				
            case (state)
                ST_IDLE: begin
							// reset flags but still ensuring fsm1 acknowledge these flags
							if (avs_state == ST_AVS_IDLE) begin // the flags is sampled by fsm1 in idle state
								uart_wrapped <= 1'b0;
								edge_detect_done <= 1'b0;
							end

							if (avs_state == ST_AVS_WRITE) begin
								case (avs_address_i)
									UART_ADDR_PTR: uart_offset <= 18'd0;
									VGA_ADDR_PTR: vga_offset <= 18'd0;
									EDGE_DETECT_WRITE_ADDR_PTR: edge_detect_write_offset <= 18'd0;
									EDGE_DETECT_READ_ADDR_PTR: edge_detect_read_offset <= 18'd0;
									PERFORM_EDGE_DETECTION_CMD: begin
										edge_detect_read_offset <= 18'd0;
										edge_detect_write_offset <= 18'd0;
										edge_input_done <= 1'b0;
										edge_flush_count <= 4'd0;
									end
									default: begin
									end
								endcase
							end

							// uart
                    if (uart_req) begin
                        state <= ST_UART_WR;
                    end
						  // edge
						  else if (perform_edge_detect == 1'b1) begin
								state <= ST_EDGE_RD_REQ;
						  end
                     // vga
                    else if (!vga_full_i) begin
                        state <= ST_VGA_RD_REQ;
                    end else begin
								state <= ST_IDLE;
						  end
                end

                ST_UART_WR: begin
                    // Thực hiện chu kỳ GHI vào SRAM (Chỉ mất 1 chu kỳ)
                    sram_addr_o  <= uart_addr_ptr + uart_offset;
                    sram_data_o  <= pixel_reg;
                    sram_write_o <= 1'b1;

                    // Tăng con trỏ địa chỉ UART (Reset về 0 nếu kịch khung hình)
                    if (uart_offset == MAX_ADDR) begin
									uart_offset <= 18'd0;
									uart_wrapped <= 1'b1;
								end
                    else
                        uart_offset <= uart_offset + 1'b1;

                    state <= ST_IDLE; // Xong việc -> Trả quyền quyết định về IDLE
                end

                ST_VGA_RD_REQ: begin
                    // read sram
                    sram_addr_o <= vga_addr_ptr + vga_offset;
                    sram_read_o <= 1'b1;
                    
                    // wait for SRAM data to be captured by sram_controller
                    state <= ST_VGA_RD_WAIT;
                end

                ST_VGA_RD_WAIT: begin
                    state <= ST_VGA_RD_ACK;
                end

                ST_VGA_RD_ACK: begin
                    // write sram data to vga fifo
                    vga_data_o  <= sram_data_i;
                    vga_wr_en_o <= 1'b1;

                    // increase vga ptr offset
                    if (vga_offset == MAX_ADDR)
                        vga_offset <= 18'd0;
                    else
                        vga_offset <= vga_offset + 1'b1;

                    state <= ST_IDLE; // turn back to idle state
                end
					 
					 ST_EDGE_RD_REQ: begin
							sram_addr_o <= edge_detect_read_addr_ptr + edge_detect_read_offset;
							sram_read_o <= 1'b1;
							sram_write_o <= 1'b0;
							
							state <= ST_EDGE_RD_WAIT;
					 end

					 ST_EDGE_RD_WAIT: begin
							state <= ST_EDGE_RD_ACK;
					 end
					 
					 ST_EDGE_RD_ACK: begin
							edge_rgb565_o <= sram_data_i;
							edge_pixel_valid_o <= 1'b1;
							
							// increase ptr offset
							if (edge_detect_read_offset == MAX_ADDR) begin
									edge_flush_count <= 4'd0;
									state <= ST_EDGE_FLUSH;
								end
							else if (edge_fifo_almost_full_i == 1'b1) begin 
									edge_detect_read_offset <= edge_detect_read_offset + 1'b1;
									state <= ST_EDGE_WR_REQ; // write back to sram when edge core's fifo is full
							end
							else begin
								edge_detect_read_offset <= edge_detect_read_offset + 1'b1;
								state <= ST_EDGE_RD_REQ;
							end
					 end

					 ST_EDGE_FLUSH: begin
							if (edge_flush_count == EDGE_PIPELINE_FLUSH_CYCLES) begin
								edge_input_done <= 1'b1;
								state <= ST_EDGE_DRAIN;
							end
							else begin
								edge_flush_count <= edge_flush_count + 1'b1;
								state <= ST_EDGE_FLUSH;
							end
					 end

					 ST_EDGE_DRAIN: begin
							if (edge_fifo_empty_i == 1'b0) begin
								state <= ST_EDGE_WR_REQ;
							end
							else begin
								state <= ST_EDGE_DRAIN;
							end
					 end
					 
					 ST_EDGE_WR_REQ: begin // write back to sram when edge core's fifo is full
							if (edge_fifo_empty_i == 1'b0) begin
								sram_addr_o <= edge_detect_write_addr_ptr + edge_detect_write_offset;
								sram_write_o <= 1'b1;
								sram_read_o <= 1'b0;
								sram_data_o <= edge_rgb565_i;
								edge_fifo_rdreq_o <= 1'b1;
							end

							if (edge_detect_write_offset == MAX_ADDR) begin
								edge_detect_write_offset <= 18'd0;
								edge_detect_done <= 1'b1;
								state <= ST_EDGE_WAIT_CMD_CLEAR;
							end
							else begin
								edge_detect_write_offset <= edge_detect_write_offset + 1'b1;
								state <= ST_EDGE_WR_SEQ;
							end
					 end
					 
					 ST_EDGE_WR_SEQ: begin 
							if (edge_fifo_empty_i == 1'b1) begin
								if (edge_input_done == 1'b1)
									state <= ST_EDGE_DRAIN;
								else
									state <= ST_EDGE_RD_REQ;
							end	
							else begin
								state <= ST_EDGE_WR_REQ;
							end
					 end
					 
					 ST_EDGE_WAIT_CMD_CLEAR: begin
							if (perform_edge_detect == 1'b0) begin
								state <= ST_IDLE;
							end
							else state <= ST_EDGE_WAIT_CMD_CLEAR;
					 end

            endcase
        end
    end

endmodule
