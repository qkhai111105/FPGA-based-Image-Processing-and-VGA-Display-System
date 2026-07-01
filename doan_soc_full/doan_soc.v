module doan_soc (
	input CLOCK_50,
	input [0:0] KEY,
	
	input UART_RXD,
	output [9:0] VGA_R,
	output [9:0] VGA_G,
	output [9:0] VGA_B,
	output VGA_HS,
	output VGA_VS,
	output VGA_BLANK,
	output VGA_CLK,
	output [17:0] SRAM_ADDR,
	inout [15:0] SRAM_DQ,
	output SRAM_WE_N,
	output SRAM_OE_N,
	output SRAM_UB_N,
	output SRAM_LB_N,
	output SRAM_CE_N
	
);

	system u_system(
	.clk_clk(CLOCK_50),
	.reset_reset_n(KEY[0]),
	.uart_rx_export(UART_RXD),
	.vga_R(VGA_R),
	.vga_G(VGA_G),
	.vga_B(VGA_B),
	.vga_BLANK(VGA_BLANK),
	.vga_HS(VGA_HS),
	.vga_VS(VGA_VS),
	.vga_CLK(VGA_CLK),
	.sram_ADDR(SRAM_ADDR),
	.sram_DQ(SRAM_DQ),
	.sram_WE_N(SRAM_WE_N),
	.sram_OE_N(SRAM_OE_N),
	.sram_UB_N(SRAM_UB_N),
	.sram_LB_N(SRAM_LB_N),
	.sram_CE_N(SRAM_CE_N)
	);

endmodule