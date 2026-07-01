module vga_color_map (
    input  wire [15:0] pixel,  // Dữ liệu đầu vào RGB565
    output wire [9:0]  VGA_R,  // Đầu ra Red 10-bit
    output wire [9:0]  VGA_G,  // Đầu ra Green 10-bit
    output wire [9:0]  VGA_B   // Đầu ra Blue 10-bit
);

    // Phân tích định dạng RGB565:
    // - Red:   5 bit (pixel[15:11])
    // - Green: 6 bit (pixel[10:5])
    // - Blue:  5 bit (pixel[4:0])

    // Ánh xạ sang 10-bit (Sử dụng kỹ thuật Bit Replication để nội suy màu chuẩn nhất)
    
    // Đỏ (Red): 5 bit mở rộng thành 10 bit bằng cách lặp lại 5 bit gốc
    assign VGA_R = {pixel[15:11], pixel[15:11]};

    // Xanh lá (Green): 6 bit mở rộng thành 10 bit bằng cách lấy 6 bit gốc ghép với 4 bit cao nhất của nó
    assign VGA_G = {pixel[10:5], pixel[10:7]};

    // Xanh dương (Blue): 5 bit mở rộng thành 10 bit bằng cách lặp lại 5 bit gốc
    assign VGA_B = {pixel[4:0], pixel[4:0]};

endmodule