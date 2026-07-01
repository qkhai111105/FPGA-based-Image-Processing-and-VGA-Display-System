module sobel_top (
    clk,
    rst_n,

    pixel_valid_in,
    rgb565_in,

    edge565_out,
	 
	 fifo_full,
	 fifo_rdreq,
	 fifo_almost_full,
	 fifo_empty
);

    parameter IMG_WIDTH  = 320;
    parameter IMG_HEIGHT = 240;
    parameter THRESHOLD  = 100;

    input clk;
    input rst_n;

    input pixel_valid_in;
    input [15:0] rgb565_in;

    wire edge_valid_out;
    output [15:0] edge565_out;
	 
	 input wire fifo_rdreq;
	 output wire fifo_full;
	 output wire fifo_empty;
	 output wire fifo_almost_full;

	 wire [15:0] edge565_out_internal;
    wire gray_valid;
    wire [7:0] gray8;
    wire [15:0] gray565;

    rgb565_to_gray u_gray (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(pixel_valid_in),
        .rgb565_in(rgb565_in),
        .valid_out(gray_valid),
        .gray8_out(gray8),
        .gray565_out(gray565)
    );

    sobel_edge #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .THRESHOLD(THRESHOLD)
    ) u_sobel (
        .clk(clk),
        .rst_n(rst_n),
        .gray_valid_in(gray_valid),
        .gray8_in(gray8),
        .edge_valid_out(edge_valid_out),
        .edge_pixel_out(edge565_out_internal)
    );
	 
	 sobel_fifo u_sobel_fifo(
		.clock(clk),
		.data(edge565_out_internal),
		.q(edge565_out),
		.wrreq(edge_valid_out),
		.rdreq(fifo_rdreq),
		.empty(fifo_empty),
		.full(fifo_full),
		.almost_full(fifo_almost_full)
	 );

endmodule
