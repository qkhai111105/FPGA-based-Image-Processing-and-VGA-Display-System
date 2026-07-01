module dm9000a_controller (
    // =========================================================================
    // 1. INTERFACE PHÍA ARBITER / HỆ THỐNG NỘI BỘ (Chạy ở clk_50)
    // =========================================================================
    input wire        clk_50,        // Xung nhịp hệ thống 50MHz
    input wire        clk_25,        // Xung nhịp cấp cho chip Ethernet 25MHz
    input wire        rst_n,         // Reset hệ thống tích cực mức thấp
    input wire [15:0] data_i,        // Dữ liệu cấu hình ghi xuống DM9000A từ Host
    output wire [15:0] data_o,       // Dữ liệu đọc từ DM9000A trả về Host / Luồng Pixel ảnh
    input wire [7:0]  addr,          // Địa chỉ thanh ghi muốn truy cập (0x00 - 0xFF)
    input wire        write,         // Lệnh ghi từ Host (Xung tích cực mức cao)
    input wire        read,          // Lệnh đọc từ Host (Xung tích cực mức cao)
    output reg        rx_data_valid, // Cờ báo dữ liệu Pixel ảnh thô hợp lệ (Tích cực 1 chu kỳ clk_50)
    
    // =========================================================================
    // 2. INTERFACE KẾT NỐI VẬT LÝ VỚI CHIP DM9000A TRÊN KIT DE2
    // =========================================================================
    inout  wire [15:0] enet_data,     // Bus dữ liệu 16-bit song hướng
    output wire        enet_clk,      // Cấp nguồn clock 25MHz cho chip DM9000A
    output reg         enet_cmd,      // 0: Khối lệnh/Index, 1: Khối dữ liệu/Data
    output reg         enet_cs_n,     // Chip Select (Tích cực mức thấp)
    input  wire        enet_int,      // Tín hiệu ngắt báo có gói tin mới từ DM9000A
    output reg         enet_rd_n,     // Read Enable (Tích cực mức thấp)
    output reg         enet_wr_n,     // Write Enable (Tích cực mức thấp)
    output wire        enet_rst_n     // Hardware Reset cho chip DM9000A
);

    // -------------------------------------------------------------------------
    // CẤU HÌNH ĐƯỜNG DÂY CỨNG TRỰC TIẾP (HARDWIRED ASSIGNMENTS)
    // -------------------------------------------------------------------------
    assign enet_clk   = clk_25; // Đưa thẳng xung 25MHz ra chân phần cứng nuôi chip
    assign enet_rst_n = rst_n;  // Đồng bộ chân reset vật lý với nút hệ thống

    // Định nghĩa loại EtherType tự quy ước cho gói tin chứa dữ liệu ảnh thuần (Raw Ethernet)
    // Mã chuẩn quốc tế dành cho thí nghiệm là 0x88B5. Do kiến trúc bus 16-bit Little-Endian 
    // của DM9000A, giá trị này sẽ được đảo byte khi đọc ra thành 16'hB588.
    localparam [15:0] RAW_ETHER_TYPE = 16'hB588; 

    // -------------------------------------------------------------------------
    // GIAO TIẾP VỚI KHỐI ĐIỀU KHIỂN ĐỊNH THỜI CẤP THẤP (LOW-LEVEL BUS CONTROLLER)
    // -------------------------------------------------------------------------
    reg         start_op;
    reg         op_cmd;
    reg         op_write;
    reg  [15:0] op_data_in;
    reg [15:0] op_data_out;
    reg        op_done;

    reg  [2:0]  low_state;
    reg  [3:0]  low_timer;
    reg  [15:0] tri_data;
    reg         tri_en;

    // Điều khiển Bus trạng thái ba (Tri-state Buffer) cho chân ENET_DATA
    assign enet_data = (tri_en) ? tri_data : 16'hZZZZ;

    localparam L_IDLE  = 3'd0,
               L_SETUP = 3'd1,
               L_ACT   = 3'd2,
               L_HOLD  = 3'd3,
               L_DONE  = 3'd4;

    // FSM CẤP THẤP: Tạo xung điều khiển chính xác, kéo dài chu kỳ ghi/đọc để thỏa mãn định thời >22ns
    always @(posedge clk_50 or negedge rst_n) begin
        if (!rst_n) begin
            low_state   <= L_IDLE;
            low_timer   <= 0;
            enet_cs_n   <= 1'b1;
            enet_wr_n   <= 1'b1;
            enet_rd_n   <= 1'b1;
            enet_cmd    <= 1'b0;
            tri_en      <= 1'b0;
            tri_data    <= 16'h0000;
            op_done     <= 1'b0;
            op_data_out <= 16'h0000;
        end else begin
            op_done <= 1'b0;
            case (low_state)
                L_IDLE: begin
                    if (start_op) begin
                        enet_cmd <= op_cmd;
                        if (op_write) begin
                            tri_data <= op_data_in;
                            tri_en   <= 1'b1;
                        end else begin
                            tri_en   <= 1'b0;
                        end
                        low_state <= L_SETUP;
                    end
                end
                L_SETUP: begin
                    // 1 chu kỳ clk_50 (20ns) để ổn định chân enet_cmd trước khi hạ CS_N
                    low_state <= L_ACT;
                    low_timer <= 0;
                end
                L_ACT: begin
                    enet_cs_n <= 1'b0;
                    if (op_write) enet_wr_n <= 1'b0;
                    else          enet_rd_n <= 1'b0;

                    // Giữ tích cực trong 3 chu kỳ clk_50 (tương đương 60ns), dư sức đáp ứng chuẩn phần cứng
                    if (low_timer == 4'd2) begin
                        low_state <= L_HOLD;
                    end else begin
                        low_timer <= low_timer + 1'b1;
                    end
                end
                L_HOLD: begin
                    if (!op_write) begin
                        op_data_out <= enet_data; // Chốt dữ liệu từ DM9000A vào thanh ghi nội bộ
                    end
                    enet_wr_n <= 1'b1;
                    enet_rd_n <= 1'b1;
                    low_state <= L_DONE;
                end
                L_DONE: begin
                    enet_cs_n <= 1'b1;
                    tri_en    <= 1'b0;
                    op_done   <= 1'b1; // Phát xung báo hoàn tất chu kỳ bus
                    low_state <= L_IDLE;
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // MÁY TRẠNG THÁI CHÍNH (MAIN COMMAND SEQUENCER FSM)
    // -------------------------------------------------------------------------
    reg [3:0]  main_state;
    reg [3:0]  rx_step;
    reg [15:0] data_o_reg;

    // Bộ đệm bắt yêu cầu từ Host (Arbiter) tránh mất xung
    reg        host_req_write;
    reg        host_req_read;
    reg [7:0]  host_addr;
    reg [15:0] host_data_i;
    reg        is_host_op;

    // Các thanh ghi quản lý thông tin gói tin mạng nhận được
    reg [15:0] rx_packet_len;
    reg [15:0] rx_word_cnt;
    reg [15:0] total_words_to_read;
    reg        is_raw_image;

    assign data_o = data_o_reg;

    // Các trạng thái của Main FSM
    localparam MS_IDLE       = 4'd0,
               MS_WRITE_IDX  = 4'd1,
               MS_WAIT_IDX   = 4'd2,
               MS_RW_DATA    = 4'd3,
               MS_WAIT_DATA  = 4'd4,
               MS_RX_LOOP    = 4'd5,
               MS_RX_LWAIT   = 4'd6;

    // Các bước nhỏ phục vụ tiến trình tự động nhận gói tin (RX Process)
    localparam RXS_IDLE      = 4'd0,
               RXS_READ_ISR  = 4'd1,
               RXS_CLEAR_ISR = 4'd2,
               RXS_CHECK_RDY = 4'd3,
               RXS_READ_HDR1 = 4'd4,
               RXS_READ_HDR2 = 4'd5,
               RXS_READ_BODY = 4'd6;

    always @(posedge clk_50 or negedge rst_n) begin
        if (!rst_n) begin
            main_state        <= MS_IDLE;
            rx_step           <= RXS_IDLE;
            start_op          <= 1'b0;
            op_cmd            <= 1'b0;
            op_write          <= 1'b0;
            op_data_in        <= 16'h0000;
            rx_data_valid     <= 1'b0;
            data_o_reg        <= 16'h0000;
            host_req_write    <= 1'b0;
            host_req_read     <= 1'b0;
            host_addr         <= 8'h00;
            host_data_i       <= 16'h0000;
            is_host_op        <= 1'b0;
            rx_packet_len     <= 16'h0000;
            rx_word_cnt       <= 16'h0000;
            total_words_to_read <= 16'h0000;
            is_raw_image      <= 1'b0;
        end else begin
            // Mặc định giải phóng xung valid cho từng chu kỳ
            rx_data_valid <= 1'b0;

            // Cơ chế bắt cạnh tích cực của các lệnh từ Host (Arbiter)
            if (write) begin
                host_req_write <= 1'b1;
                host_addr      <= addr;
                host_data_i    <= data_i;
            end
            if (read) begin
                host_req_read  <= 1'b1;
                host_addr      <= addr;
            end

            case (main_state)
                // -------------------------------------------------------------
                MS_IDLE: begin
                    if (host_req_write || host_req_read) begin
                        // Ưu tiên xử lý lệnh do Host gửi xuống (Cấu hình ban đầu)
                        is_host_op <= 1'b1;
                        main_state <= MS_WRITE_IDX;
                    end else if (enet_int == 1'b1) begin
                        // Tự động chuyển sang chế độ đọc gói dữ liệu khi có tín hiệu ngắt phần cứng
                        is_host_op <= 1'b0;
                        rx_step    <= RXS_READ_ISR;
                        main_state <= MS_WRITE_IDX;
                    end
                end

                // -------------------------------------------------------------
                MS_WRITE_IDX: begin
                    // BƯỚC 1: Chỉ định địa chỉ thanh ghi (Ghi Index với chân CMD = 0)
                    start_op   <= 1'b1;
                    op_cmd     <= 1'b0; // Chọn thanh ghi Index
                    op_write   <= 1'b1; // Luôn là chu kỳ ghi địa chỉ
                    
                    if (is_host_op) begin
                        op_data_in <= {8'h00, host_addr};
                    end else begin
                        // Chọn thanh ghi tự động tùy thuộc vào bước xử lý mạng
                        case (rx_step)
                            RXS_READ_ISR, RXS_CLEAR_ISR : op_data_in <= 16'h00FE; // Thanh ghi ISR
                            RXS_CHECK_RDY               : op_data_in <= 16'h00FC; // Thanh ghi MRCMDX
                            default                     : op_data_in <= 16'h0044; // Thanh ghi đọc bộ nhớ MRCMD
                        endcase
                    end
                    main_state <= MS_WAIT_IDX;
                end

                // -------------------------------------------------------------
                MS_WAIT_IDX: begin
                    start_op <= 1'b0;
                    if (op_done) begin
                        main_state <= MS_RW_DATA;
                    end
                end

                // -------------------------------------------------------------
                MS_RW_DATA: begin
                    // BƯỚC 2: Thực hiện Đọc/Ghi dữ liệu thật sự vào thanh ghi đã chọn (CMD = 1)
                    start_op <= 1'b1;
                    op_cmd   <= 1'b1; // Khối dữ liệu
                    
                    if (is_host_op) begin
                        op_write   <= host_req_write;
                        op_data_in <= host_data_i;
                    end else begin
                        // Phục vụ chuỗi máy trạng thái đọc mạng
                        op_write   <= (rx_step == RXS_CLEAR_ISR) ? 1'b1 : 1'b0;
                        op_data_in <= (rx_step == RXS_CLEAR_ISR) ? 16'h0001 : 16'h0000; // Ghi 1 để xóa cờ ngắt RX
                    end
                    main_state <= MS_WAIT_DATA;
                end

                // -------------------------------------------------------------
                MS_WAIT_DATA: begin
                    start_op <= 1'b0;
                    if (op_done) begin
                        if (is_host_op) begin
                            // Trả kết quả về cho mạch Host nếu là tác vụ đọc
                            if (host_req_read) data_o_reg <= op_data_out;
                            // Xóa cờ yêu cầu cũ, hoàn tất 1 vòng tác vụ Host
                            host_req_write <= 1'b0;
                            host_req_read  <= 1'b0;
                            main_state     <= MS_IDLE;
                        end else begin
                            // Xử lý dữ liệu mạng vừa thu được từ bộ nhớ đệm
                            case (rx_step)
                                RXS_READ_ISR: begin
                                    if (op_data_out[0] == 1'b1) begin // Kiểm tra cờ PR (Packet Received)
                                        rx_step    <= RXS_CLEAR_ISR;
                                        main_state <= MS_WRITE_IDX;
                                    end else begin
                                        main_state <= MS_IDLE; // Ngắt không phải do nhận gói, bỏ qua
                                    end
                                end
                                RXS_CLEAR_ISR: begin
                                    rx_step    <= RXS_CHECK_RDY;
                                    main_state <= MS_WRITE_IDX;
                                end
                                RXS_CHECK_RDY: begin
                                    if (op_data_out[0] == 1'b1 || op_data_out[7:0] == 8'h01) begin // Có gói tin hợp lệ sẵn sàng trong SRAM
                                        rx_step    <= RXS_READ_HDR1;
                                        main_state <= MS_WRITE_IDX;
                                    end else begin
                                        main_state <= MS_IDLE; // Sai mã trạng thái bộ đệm
                                    end
                                end
                                RXS_READ_HDR1: begin
                                    // Đọc xong 2 byte đầu chứa: [Status, Khối kiểm tra] -> Bỏ qua
                                    rx_step    <= RXS_READ_HDR2;
                                    main_state <= MS_WRITE_IDX;
                                end
                                RXS_READ_HDR2: begin
                                    // Đọc xong byte 3,4 chứa độ dài thực tế của gói tin mạng (Tính bằng Byte)
                                    rx_packet_len       <= op_data_out;
                                    rx_word_cnt         <= 16'h0000;
                                    is_raw_image        <= 1'b0;
                                    // Tính số từ nhớ 16-bit cần quét: 2 từ nhớ Header hệ thống + số từ Payload
                                    total_words_to_read <= 16'd2 + ((op_data_out + 16'h0001) >> 1);
                                    
                                    rx_step    <= RXS_READ_BODY;
                                    main_state <= MS_RX_LOOP;
                                end
                                default: main_state <= MS_IDLE;
                            endcase
                        end
                    end
                end

                // -------------------------------------------------------------
                MS_RX_LOOP: begin
                    // Đọc liên tiếp vùng nhớ gói tin bằng lệnh MRCMD. DM9000A sẽ tự động tăng 
                    // con trỏ bộ nhớ nội bộ, chúng ta không cần ghi lại Index địa chỉ nữa.
                    if (rx_word_cnt < total_words_to_read) begin
                        start_op   <= 1'b1;
                        op_cmd     <= 1'b1; // Tiếp tục đọc khối dữ liệu
                        op_write   <= 1'b0; // Chế độ đọc
                        main_state <= MS_RX_LWAIT;
                    end else begin
                        main_state <= MS_IDLE; // Đọc xong trọn vẹn gói tin -> Quay về trạng thái chờ
                    end
                end

                // -------------------------------------------------------------
                MS_RX_LWAIT: begin
                    start_op <= 1'b0;
                    if (op_done) begin
                        // GIẢI MÃ BÓC TÁCH CẤU TRÚC KHUNG KHÔNG CẦN TẦNG MẠNG
                        // Word 0,1,2: MAC Đích | Word 3,4,5: MAC Nguồn
                        
                        if (rx_word_cnt == 16'd6) begin
                            // Word thứ 6 chứa trường thông tin loại giao thức mạng (EtherType)
                            if (op_data_out == RAW_ETHER_TYPE) begin
                                is_raw_image <= 1'b1; // Xác nhận đây chính xác là gói tin chứa ảnh thô tự quy ước
                            end
                        end else if (rx_word_cnt >= 16'd7) begin
                            // Từ Word thứ 7 trở đi chính là dữ liệu Pixel ảnh thô nguyên bản (Payload)
                            if (is_raw_image) begin
                                rx_data_valid <= 1'b1;        // Kích hoạt cờ báo dữ liệu hợp lệ cho Arbiter cất vào SRAM
                                data_o_reg    <= op_data_out; // Đưa pixel ảnh 16-bit ra bus dữ liệu
                            end
                        end

                        rx_word_cnt <= rx_word_cnt + 1'b1;
                        main_state  <= MS_RX_LOOP; // Tiếp tục vòng lặp lấy từ nhớ tiếp theo
                    end
                end

                default: main_state <= MS_IDLE;
            endcase
        end
    end

endmodule