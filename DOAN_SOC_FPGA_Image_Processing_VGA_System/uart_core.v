module uart_core #(
    // Khai báo tham số với giá trị mặc định
    parameter CLOCK_FREQ = 50_000_000, // Tần số hệ thống mặc định (50 MHz)
    parameter BAUD_RATE  = 115200      // Tốc độ baud mặc định (115200 bps)
)(
    // System Signals
    input  wire       clk,      
    input  wire       rst_n,    

    // Physical Interface (To MAX232/Pins)
    input  wire       uart_rx,
    output wire       uart_tx,

    // Internal TX Interface (Giao tiếp với Arbiter)
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    output wire       tx_busy,

    // Internal RX Interface (Giao tiếp với Arbiter)
    output wire [7:0] rx_data,
    output wire       rx_done
);

    // =========================================================
    // BAUD RATE GENERATOR (Tạo xung tick 16x Baudrate)
    // =========================================================
    // Công thức tính toán hệ số chia: DIVISOR = CLOCK_FREQ / (BAUD_RATE * 16)
    // Để Verilog tự động làm tròn chuẩn xác nhất, ta áp dụng mẹo cộng thêm một nửa mẫu số:
    // (Tử số + Mẫu số / 2) / Mẫu số
    localparam DIVISOR = (CLOCK_FREQ + (BAUD_RATE * 8)) / (BAUD_RATE * 16); 
    
    // Tăng kích thước bộ đếm lên 16-bit để không bao giờ bị tràn 
    // ngay cả khi bạn dùng clock lớn hơn hoặc baudrate siêu thấp
    reg [15:0] baud_counter;
    wire tick_16x;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_counter <= 16'd0;
        end else begin
            if (baud_counter >= DIVISOR - 1)
                baud_counter <= 16'd0;
            else
                baud_counter <= baud_counter + 16'd1;
        end
    end

    // Xung tick_16x chỉ tồn tại trong đúng 1 chu kỳ xung nhịp clk
    assign tick_16x = (baud_counter == DIVISOR - 1);

    // =========================================================
    // KHỞI TẠO KHỐI TX VÀ RX
    // =========================================================
    // LƯU Ý: Phải đảm bảo module uart_tx và uart_rx của bạn 
    // cũng nhận tín hiệu tick_16x để làm nhịp đồng bộ
    
    uart_tx tx_inst (
        .clk(clk), 
        .rst_n(rst_n), 
        .tick_16x(tick_16x), // Cấp xung baudrate vào đây
        .tx_data(tx_data), 
        .tx_start(tx_start), 
        .tx_busy(tx_busy), 
        .uart_tx(uart_tx)
    );

    uart_rx rx_inst (
        .clk(clk), 
        .rst_n(rst_n), 
        .tick_16x(tick_16x), // Cấp xung baudrate vào đây
        .uart_rx(uart_rx), 
        .rx_data(rx_data), 
        .rx_done(rx_done)
    );

endmodule