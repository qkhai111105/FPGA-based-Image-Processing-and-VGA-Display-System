module uart_rx ( 
    input wire clk,           // Xung 50MHz
    input wire rst_n,
    input wire tick_16x,      // Xung nhịp mẫu (16x Baud)
    input wire uart_rx,       // Tín hiệu vào
    
    output reg [7:0] rx_data, // Giữ nguyên dữ liệu cho đến khi byte mới đến
    output reg       rx_done  // Chỉ bật 1 chu kỳ clk
);

    localparam IDLE = 2'b00, START = 2'b01, DATA = 2'b10, STOP = 2'b11;

    reg [1:0] state, next_state;
    reg [3:0] tick_counter;   // Đếm 16 tick
    reg [2:0] bit_counter;    // Đếm 8 bit dữ liệu
    reg [7:0] shift_reg;      // Thanh ghi dịch

    // Mạch khử á ổn định (Metastability) cho tín hiệu RX từ bên ngoài
    reg rx_sync1, rx_sync2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) {rx_sync2, rx_sync1} <= 2'b11; // Trạng thái nghỉ của UART là 1
        else {rx_sync2, rx_sync1} <= {rx_sync1, uart_rx};
    end

    // Xử lý chuyển trạng thái và biến đếm
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            tick_counter <= 0;
            bit_counter <= 0;
            shift_reg <= 0;
            rx_data <= 0;
            rx_done <= 0;
        end else begin
            rx_done <= 0; // Luôn tự động kéo xuống 0 sau 1 chu kỳ

            case (state)
                IDLE: begin
                    if (rx_sync2 == 1'b0) begin // Phát hiện cạnh xuống (Start bit)
                        state <= START;
                        tick_counter <= 0;
                    end
                end

                START: begin
                    if (tick_16x) begin
                        if (tick_counter == 7) begin // Lấy mẫu tại ĐIỂM GIỮA của Start bit
                            if (rx_sync2 == 1'b0) begin // Vẫn là mức 0 -> Start bit hợp lệ
                                state <= DATA;
                                tick_counter <= 0;
                                bit_counter <= 0;
                            end else begin
                                state <= IDLE; // Nếu là mức 1 -> Do nhiễu, quay lại IDLE
                            end
                        end else begin
                            tick_counter <= tick_counter + 1;
                        end
                    end
                end

                DATA: begin
                    if (tick_16x) begin
                        if (tick_counter == 15) begin // Đợi đủ 1 bit time
                            tick_counter <= 0;
                            shift_reg <= {rx_sync2, shift_reg[7:1]}; // Dịch bit LSB vào trước
                            if (bit_counter == 7)
                                state <= STOP;
                            else
                                bit_counter <= bit_counter + 1;
                        end else begin
                            tick_counter <= tick_counter + 1;
                        end
                    end
                end

                STOP: begin
                    if (tick_16x) begin
                        if (tick_counter == 15) begin // Đợi đủ 1 bit time của Stop bit
                            state <= IDLE;
                            rx_done <= 1'b1; // Phát xung rx_done
                            rx_data <= shift_reg; // Đẩy dữ liệu ra cổng
                        end else begin
                            tick_counter <= tick_counter + 1;
                        end
                    end
                end
            endcase
        end
    end

endmodule