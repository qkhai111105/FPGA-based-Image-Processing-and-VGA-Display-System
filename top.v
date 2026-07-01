module top (
	input clock_50,
	input clock_25,
	input rst_n,
	
	input UART_RXD,
	output [9:0] VGA_R,
	output [9:0] VGA_G,
	output [9:0] VGA_B,
	output VGA_CLK,
	output VGA_BLANK,
	output VGA_HS,
	output VGA_VS,
	
	output [17:0] SRAM_ADDR,
	inout [15:0] SRAM_DQ,
	output SRAM_WE_N,
	output SRAM_OE_N,
	output SRAM_UB_N,
	output SRAM_LB_N,
	output SRAM_CE_N,
	
	// avalon mm slave interface
	input wire [2:0] avs_address_i,
	input wire avs_read_i,
	input wire avs_write_i,
	input wire [31:0] avs_writedata_i,
	output wire [31:0] avs_readdata_o,
	output wire avs_readdatavalid_o,
	output wire avs_irq_o
);

	// uart
	wire [7:0] uart_rx_data;
	wire uart_rx_done;
	// vga
	wire [15:0] vga_data;
	wire vga_wr_en;
	wire vga_full;
	
	//sram 
	wire [17:0] sram_addr;
	wire sram_read;
	wire sram_write;
	wire [15:0] sram_data_o;
	wire [15:0] sram_data_i;
	wire [1:0] sram_byte_en;
	
	// edge
	wire edge_pixel_valid;
	wire [15:0] edge_rgb565_i;
	wire [15:0] edge_rgb565_o;
	wire edge_fifo_rdreq;
	wire edge_fifo_empty;
	wire edge_fifo_full;
	wire edge_fifo_almost_full;
	

	uart_core #(.CLOCK_FREQ(50_000_000), .BAUD_RATE(115200)) u_uart_core(
	.clk(clock_50),
	.rst_n(rst_n),
	.uart_rx(UART_RXD),
	.rx_data(uart_rx_data),
	.rx_done(uart_rx_done)
	);
	
	vga u_vga(
	.clk_i(clock_50),
	.rst_n_i(rst_n),
	.vga_data_i(vga_data),
	.vga_wr_en_i(vga_wr_en),
	.vga_full_o(vga_full),
	.vga_clk_25(clock_25),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_BLANK(VGA_BLANK),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_CLK(VGA_CLK)
	);
	
	arbiter u_arbiter( 
	.clk(clock_50),
	.rst_n(rst_n),
	.uart_rx_data(uart_rx_data),
	.uart_rx_done(uart_rx_done),
	.vga_data_o(vga_data),
	.vga_wr_en_o(vga_wr_en),
	.vga_full_i(vga_full),
	.sram_addr_o(sram_addr),
	.sram_read_o(sram_read),
	.sram_write_o(sram_write),
	.sram_data_o(sram_data_o),
	.sram_data_i(sram_data_i),
	.sram_byte_en_o(sram_byte_en),
	.edge_pixel_valid_o(edge_pixel_valid),
	.edge_rgb565_o(edge_rgb565_o),
	.edge_rgb565_i(edge_rgb565_i),
	.edge_fifo_rdreq_o(edge_fifo_rdreq),
	.edge_fifo_full_i(edge_fifo_full),
	.edge_fifo_empty_i(edge_fifo_empty),
	.edge_fifo_almost_full_i(edge_fifo_almost_full),
	.avs_address_i(avs_address_i),
	.avs_read_i(avs_read_i),
	.avs_write_i(avs_write_i),
	.avs_writedata_i(avs_writedata_i),
	.avs_readdata_o(avs_readdata_o),
	.avs_readdatavalid_o(avs_readdatavalid_o),
	.avs_irq_o(avs_irq_o)
	);
	
	sram_controller u_sram_controller(
	.clk(clock_50),
	.rst_n(rst_n),
	.sram_addr_i(sram_addr),
	.sram_read_i(sram_read),
	.sram_write_i(sram_write),
	.sram_data_i(sram_data_o),
	.sram_data_o(sram_data_i),
	.sram_byte_en_i(sram_byte_en),
	.SRAM_ADDR(SRAM_ADDR),
	.SRAM_DQ(SRAM_DQ),
	.SRAM_CE_N(SRAM_CE_N),
	.SRAM_OE_N(SRAM_OE_N),
	.SRAM_WE_N(SRAM_WE_N),
	.SRAM_UB_N(SRAM_UB_N),
	.SRAM_LB_N(SRAM_LB_N)
	);
	
	sobel_top u_sobel_edge_detect(
	.clk (clock_50),
	.rst_n(rst_n),
	.pixel_valid_in(edge_pixel_valid),
	.rgb565_in(edge_rgb565_o),
	.edge565_out(edge_rgb565_i),
	.fifo_full(edge_fifo_full),
	.fifo_empty(edge_fifo_empty),
	.fifo_almost_full(edge_fifo_almost_full),
	.fifo_rdreq(edge_fifo_rdreq)
	);
	
endmodule