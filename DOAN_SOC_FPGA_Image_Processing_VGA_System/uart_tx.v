module uart_tx ( 
    input wire clk,           // Xung 50MHz
    input wire rst_n,
    input wire tick_16x,      // Xung nhịp mẫu (16x Baud)
    
    input wire [7:0] tx_data,
    input wire       tx_start,
    output reg       tx_busy,
    output reg       uart_tx
);

    localparam IDLE = 2'b00, START = 2'b01, DATA = 2'b10, STOP = 2'b11;

    reg [1:0] state;
    reg [3:0] tick_counter;   // Đếm 16 tick
    reg [2:0] bit_counter;    // Đếm 8 bit dữ liệu
    reg [7:0] shift_reg;      // Thanh ghi dịch

    // Bắt cạnh lên (Rising Edge Detection) của tx_start
    reg tx_start_delay;
    wire tx_start_pulse;
    always @(posedge clk) tx_start_delay <= tx_start;
    assign tx_start_pulse = tx_start & ~tx_start_delay; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            tick_counter <= 0;
            bit_counter <= 0;
            shift_reg <= 0;
            uart_tx <= 1'b1;
            tx_busy <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    uart_tx <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_start_pulse) begin // Chỉ chạy khi phát hiện cạnh sườn lên
                        state <= START;
                        shift_reg <= tx_data;
                        tick_counter <= 0;
                        tx_busy <= 1'b1; // Báo bận ngay lập tức
                    end
                end

                START: begin
                    uart_tx <= 1'b0; // Kéo xuống mức thấp (Start bit)
                    if (tick_16x) begin
                        if (tick_counter == 15) begin // Giữ Start bit trong 16 ticks
                            state <= DATA;
                            tick_counter <= 0;
                            bit_counter <= 0;
                        end else begin
                            tick_counter <= tick_counter + 1;
                        end
                    end
                end

                DATA: begin
                    uart_tx <= shift_reg[0]; // Phát LSB trước
                    if (tick_16x) begin
                        if (tick_counter == 15) begin
                            tick_counter <= 0;
                            shift_reg <= shift_reg >> 1; // Dịch phải thanh ghi
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
                    uart_tx <= 1'b1; // Kéo lên mức cao (Stop bit)
                    if (tick_16x) begin
                        if (tick_counter == 15) begin // Giữ Stop bit trong 16 ticks
                            state <= IDLE;
                        end else begin
                            tick_counter <= tick_counter + 1;
                        end
                    end
                end
            endcase
        end
    end

endmodule