module sram_controller (
    // -------------------------------------------------------------------------
    // 1. GIAO DIỆN KẾT NỐI TRỰC TIẾP VỚI ARBITER TỰ CHẾ
    // -------------------------------------------------------------------------
    input  wire        clk,             // Xung nhịp hệ thống (50MHz)
    input  wire        rst_n,           // Reset hệ thống tích cực mức thấp
    input  wire [17:0] sram_addr_i,     // Địa chỉ 18-bit từ Arbiter (Quản lý 256K từ nhớ)
    input  wire        sram_read_i,     // Lệnh ĐỌC từ Arbiter (Tích cực mức cao)
    input  wire        sram_write_i,    // Lệnh GHI từ Arbiter (Tích cực mức cao)
    input  wire [15:0] sram_data_i,     // Dữ liệu từ Arbiter muốn GHI vào SRAM (ví dụ: Pixel từ UART)
    output reg  [15:0] sram_data_o,     // Dữ liệu ĐỌC từ SRAM xuất ra cho Arbiter (ví dụ: cấp cho VGA)
    input  wire [1:0]  sram_byte_en_i,  // Mặt nạ chọn Byte ([0]: Byte thấp, [1]: Byte cao)

    // -------------------------------------------------------------------------
    // 2. GIAO DIỆN VẬT LÝ NỐI RA CHÂN CHIP SRAM TRÊN BOARD DE2
    // -------------------------------------------------------------------------
    output wire [17:0] SRAM_ADDR,       // Chân [17:0] SRAM_ADDR
    inout  wire [15:0] SRAM_DQ,         // Chân [15:0] SRAM_DQ (Bus song hướng)
    output wire        SRAM_CE_N,       // Chip Enable (Tích cực mức thấp)
    output wire        SRAM_OE_N,       // Output Enable (Tích cực mức thấp)
    output wire        SRAM_WE_N,       // Write Enable (Tích cực mức thấp)
    output wire        SRAM_UB_N,       // Upper Byte Enable (Quản lý DQ[15:8])
    output wire        SRAM_LB_N        // Lower Byte Enable (Quản lý DQ[7:0])
);

    // Điều khiển trạng thái mở/khóa Bus dữ liệu song hướng (Tri-state Bus) [cite: 44]
    // Nếu Arbiter ra lệnh GHI -> Đẩy dữ liệu sram_data_i ra chip SRAM [cite: 44, 45]
    // Nếu KHÔNG ghi -> Thả nổi bus (Hi-Z) để chip SRAM có thể lái đường truyền lúc ĐỌC [cite: 44, 45]
    assign SRAM_DQ = (sram_write_i && !SRAM_CE_N) ? sram_data_i : 16'hZZZZ;

    // Ánh xạ trực tiếp đường địa chỉ từ Arbiter tới chân vật lý của chip [cite: 45]
    assign SRAM_ADDR = sram_addr_i;

    // Chip SRAM luôn luôn được chọn khi hệ thống không bị Reset [cite: 46]
    assign SRAM_CE_N = !rst_n;

    // Tín hiệu Cho phép Xuất dữ liệu (OE_N): Bật khi Arbiter kích hoạt sram_read_i
    assign SRAM_OE_N = !sram_read_i;

    // Tín hiệu Cho phép Ghi (WE_N): Bật khi Arbiter kích hoạt sram_write_i
    assign SRAM_WE_N = !sram_write_i;

    // Quản lý mặt nạ Byte dựa trên tín hiệu điều khiển sram_byte_en_i từ Arbiter [cite: 49, 50]
    // Nếu bạn luôn đọc/ghi trọn vẹn 16-bit (Pixel RGB565), Arbiter chỉ cần cấp sram_byte_en_i = 2'b11
    assign SRAM_LB_N = !(rst_n && sram_byte_en_i[0] && (sram_read_i || sram_write_i));
    assign SRAM_UB_N = !(rst_n && sram_byte_en_i[1] && (sram_read_i || sram_write_i));

    // Đồng bộ hóa dữ liệu đọc về theo cạnh dương xung nhịp hệ thống 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sram_data_o <= 16'h0000; 
        end else if (sram_read_i) begin
            sram_data_o <= SRAM_DQ; // Chốt dữ liệu từ chân Chip trả về cho Arbiter [cite: 53]
        end
    end

endmodule