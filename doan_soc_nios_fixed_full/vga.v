module vga (
    input wire clk_i,
    input wire rst_n_i,

    input  wire [15:0] vga_data_i,
    input  wire        vga_wr_en_i,
    output wire        vga_full_o,

    input  wire        vga_clk_25,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_BLANK,
    output wire [9:0]  VGA_R,
    output wire [9:0]  VGA_G,
    output wire [9:0]  VGA_B,
    output wire        VGA_CLK
);

    localparam IMG_WIDTH = 320;
    localparam FIFO_ALMOST_FULL = 10'd800;

    wire [15:0] fifo_data_out;
    wire        fifo_rdreq;
    wire        fifo_rdempty;
    wire        fifo_wrfull;
    wire [9:0]  fifo_wrusedw;

    reg [15:0] display_pixel;
    reg [15:0] pair_pixel;
    reg [8:0]  src_x;
    reg        h_phase;
    reg        line_phase;
    reg        prev_blank;

    reg [15:0] line_buffer [0:IMG_WIDTH-1];

    vga_sync_gen u_vga_sync_gen (
        .clk(vga_clk_25),
        .reset_n(rst_n_i),
        .hsync(VGA_HS),
        .vsync(VGA_VS),
        .blank_n(VGA_BLANK)
    );

    vga_fifo u_vga_fifo (
        .aclr(!rst_n_i || (VGA_VS == 1'b0)),
        .data(vga_data_i),
        .rdclk(vga_clk_25),
        .rdreq(fifo_rdreq),
        .wrclk(clk_i),
        .wrreq(vga_wr_en_i && !fifo_wrfull),
        .q(fifo_data_out),
        .rdempty(fifo_rdempty),
        .wrfull(fifo_wrfull),
        .wrusedw(fifo_wrusedw)
    );

    vga_color_map u_vga_color_map (
        .pixel(VGA_BLANK ? display_pixel : 16'h0000),
        .VGA_R(VGA_R),
        .VGA_G(VGA_G),
        .VGA_B(VGA_B)
    );

    assign VGA_CLK = vga_clk_25;
    assign vga_full_o = (fifo_wrusedw >= FIFO_ALMOST_FULL) || fifo_wrfull;

    // Read one source pixel for every two VGA pixels on the first display line,
    // then replay the saved 320-pixel line on the duplicated display line.
    assign fifo_rdreq = VGA_BLANK && !line_phase && !h_phase && !fifo_rdempty;

    always @(posedge vga_clk_25 or negedge rst_n_i) begin
        if (!rst_n_i) begin
            display_pixel <= 16'h0000;
            pair_pixel <= 16'h0000;
            src_x <= 9'd0;
            h_phase <= 1'b0;
            line_phase <= 1'b0;
            prev_blank <= 1'b0;
        end else begin
            prev_blank <= VGA_BLANK;

            if (VGA_VS == 1'b0) begin
                line_phase <= 1'b0;
            end

            if (prev_blank == 1'b0 && VGA_BLANK == 1'b1) begin
                src_x <= 9'd0;
                h_phase <= 1'b0;
            end

            if (prev_blank == 1'b1 && VGA_BLANK == 1'b0) begin
                src_x <= 9'd0;
                h_phase <= 1'b0;
                line_phase <= ~line_phase;
                display_pixel <= 16'h0000;
            end else if (VGA_BLANK) begin
                if (h_phase == 1'b0) begin
                    if (line_phase == 1'b0) begin
                        pair_pixel <= fifo_rdempty ? 16'h0000 : fifo_data_out;
                        display_pixel <= fifo_rdempty ? 16'h0000 : fifo_data_out;
                        line_buffer[src_x] <= fifo_rdempty ? 16'h0000 : fifo_data_out;
                    end else begin
                        pair_pixel <= line_buffer[src_x];
                        display_pixel <= line_buffer[src_x];
                    end
                    h_phase <= 1'b1;
                end else begin
                    display_pixel <= pair_pixel;
                    h_phase <= 1'b0;
                    if (src_x == IMG_WIDTH - 1)
                        src_x <= 9'd0;
                    else
                        src_x <= src_x + 9'd1;
                end
            end else begin
                display_pixel <= 16'h0000;
                h_phase <= 1'b0;
            end
        end
    end

endmodule
