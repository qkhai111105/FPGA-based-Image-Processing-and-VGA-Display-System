module vga (
    input wire clk_i,                // Xung nhịp hệ thống (50MHz, chung với Arbiter/SRAM)
    input wire rst_n_i,              // Reset hệ thống
	 
    // -------------------------------------------------------------------------
    // 1. GIAO DIỆN KẾT NỐI TRỰC TIẾP VỚI ARBITER (Thay thế Avalon-ST)
    // -------------------------------------------------------------------------
    input  wire [15:0] vga_data_i,   // Dữ liệu pixel (RGB565) từ Arbiter cấp vào
    input  wire        vga_wr_en_i,  // Arbiter ra lệnh GHI dữ liệu vào FIFO (Tích cực mức cao)
    output wire        vga_full_o,   // Khối VGA báo cho Arbiter biết FIFO sắp đầy (1 = Bận, ngừng ghi)

    // -------------------------------------------------------------------------
    // 2. CÁC CHÂN NGOẠI VI ĐI RA MÀN HÌNH VGA
    // -------------------------------------------------------------------------
    input  wire        vga_clk_25,   // Xung nhịp hiển thị màn hình (25MHz)
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_BLANK,
    output wire [9:0]  VGA_R,
    output wire [9:0]  VGA_G,
    output wire [9:0]  VGA_B,
    output wire        VGA_CLK
);

    wire [15:0] fifo_data_out;
    wire [15:0] fifo_data_out0;
    wire [15:0] fifo_data_out1;
    
    wire fifo_rdreq0;
    wire fifo_rdreq1;
    reg  fifo_wrreq;
    
    wire fifo_rdempty0;
    wire fifo_rdempty1;
    wire fifo_wrfull;
    wire fifo_wrfull0;
    wire fifo_wrfull1;
    
    wire [9:0] fifo_wrusedw;
    wire [9:0] fifo_wrusedw0;
    wire [9:0] fifo_wrusedw1;

    // Khối phát tín hiệu VGA Sync giữ nguyên
    vga_sync_gen u_vga_sync_gen(
        .clk(vga_clk_25), 
        .reset_n(rst_n_i), 
        .hsync(VGA_HS), 
        .vsync(VGA_VS), 
        .blank_n(VGA_BLANK)
    );

    // FIFO 0 (Lưu dòng chẵn)
    vga_fifo u_vga_fifo0(
        .aclr(!rst_n_i), 
        .data(vga_data_i),            // Nhận dữ liệu pixel từ Arbiter
        .rdclk(vga_clk_25),
        .rdreq(fifo_rdreq0),
        .wrclk(clk_i),
        .wrreq(fifo_wrreq),           
        .q(fifo_data_out0),
        .rdempty(fifo_rdempty0), 
        .wrfull(fifo_wrfull0),
        .wrusedw(fifo_wrusedw0)
    );

    // FIFO 1 (Lưu dòng lẻ)
    vga_fifo u_vga_fifo1(
        .aclr(!rst_n_i), 
        .data(vga_data_i),            // Nhận dữ liệu pixel từ Arbiter
        .rdclk(vga_clk_25),
        .rdreq(fifo_rdreq1),
        .wrclk(clk_i),
        .wrreq(fifo_wrreq),           
        .q(fifo_data_out1),
        .rdempty(fifo_rdempty1), 
        .wrfull(fifo_wrfull1),
        .wrusedw(fifo_wrusedw1)
    );

    vga_color_map u_vga_color_map(
        .pixel(fifo_data_out),
        .VGA_R(VGA_R),
        .VGA_G(VGA_G),
        .VGA_B(VGA_B)
    );

    assign VGA_CLK = vga_clk_25;
	 
    // Ghép logic trạng thái từ 2 FIFO
    assign fifo_wrusedw = (fifo_wrusedw0 > fifo_wrusedw1) ? fifo_wrusedw0 : fifo_wrusedw1;
    assign fifo_wrfull = (fifo_wrfull0 || fifo_wrfull1);

    // --- XỬ LÝ GIAO TIẾP VỚI ARBITER (FLOW CONTROL) ---
    parameter FIFO_ALMOST_FULL = 10'd800; 
    
    // Cờ báo vga_full_o gửi cho Arbiter: Nếu FIFO đạt ngưỡng 800 từ (chứa được >1 dòng quét) 
    // hoặc bị Full cứng, thì báo hiệu đầy để Arbiter ưu tiên làm việc khác (như nhận UART).
    assign vga_full_o = (fifo_wrusedw >= FIFO_ALMOST_FULL) || fifo_wrfull;
    
    // Thực hiện lệnh ghi khi Arbiter yêu cầu và FIFO phải chưa đầy
    always @(*) begin
        fifo_wrreq = vga_wr_en_i && !fifo_wrfull;
    end

    // --- XỬ LÝ ĐỌC FIFO (HIỂN THỊ & NHÂN ĐÔI KÍCH THƯỚC 320x240 -> 640x480) ---
    reg h_toggle;       // Cờ nhân đôi chiều ngang
    reg v_toggle;       // Cờ nhân đôi chiều dọc (để chọn FIFO)
    reg prev_blank;     // Bộ nhớ trạng thái cũ của VGA_BLANK để dò cạnh xuống

    always @(posedge vga_clk_25 or negedge rst_n_i) begin
        if (!rst_n_i) begin
            h_toggle <= 1'b0;
            v_toggle <= 1'b0;
            prev_blank <= 1'b0;
        end else begin
            prev_blank <= VGA_BLANK;

            // XỬ LÝ NHÂN ĐÔI CHIỀU NGANG
            if (VGA_BLANK) begin
                h_toggle <= ~h_toggle;
            end else begin
                h_toggle <= 1'b0; 
            end

            // XỬ LÝ NHÂN ĐÔI CHIỀU DỌC
            if (prev_blank == 1'b1 && VGA_BLANK == 1'b0) begin
                v_toggle <= ~v_toggle; // Đảo cờ để dòng sau đọc FIFO khác
            end

            // Đồng bộ khung hình ở đầu màn hình
            if (VGA_VS == 1'b0) begin
                v_toggle <= 1'b0;
            end
        end
    end

    assign fifo_rdreq0 = VGA_BLANK & ~fifo_rdempty0 & ~v_toggle & ~h_toggle;
    assign fifo_rdreq1 = VGA_BLANK & ~fifo_rdempty1 & v_toggle  & ~h_toggle;
	 
    // Ghép kênh dữ liệu xuất ra màn hình
    assign fifo_data_out = (v_toggle == 1'b0) ? fifo_data_out0 : fifo_data_out1;

endmodule
