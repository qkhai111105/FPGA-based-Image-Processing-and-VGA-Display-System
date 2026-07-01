`timescale 1ns/1ps

module tb_sobel_edge;

    localparam IMG_WIDTH  = 8;
    localparam IMG_HEIGHT = 6;
    localparam THRESHOLD  = 100;
    localparam FRAME_SIZE = IMG_WIDTH * IMG_HEIGHT;

    reg clk;
    reg rst_n;
    reg gray_valid_in;
    reg [7:0] gray8_in;

    wire edge_valid_out;
    wire [15:0] edge_pixel_out;

    reg [7:0] frame [0:FRAME_SIZE-1];

    integer x;
    integer y;
    integer k;
    integer out_count;
    integer center_x;
    integer center_y;

    sobel_edge #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .THRESHOLD(THRESHOLD)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .gray_valid_in(gray_valid_in),
        .gray8_in(gray8_in),
        .edge_valid_out(edge_valid_out),
        .edge_pixel_out(edge_pixel_out)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
            for (x = 0; x < IMG_WIDTH; x = x + 1) begin
                // Left half dark, right half bright. This creates a vertical edge.
                if (x < (IMG_WIDTH / 2))
                    frame[y * IMG_WIDTH + x] = 8'd0;
                else
                    frame[y * IMG_WIDTH + x] = 8'd255;
            end
        end
    end

    initial begin
        $dumpfile("tb_sobel_edge.vcd");
        $dumpvars(0, tb_sobel_edge);

        rst_n = 1'b0;
        gray_valid_in = 1'b0;
        gray8_in = 8'd0;
        out_count = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("Feed image in raster order: (0,0), (1,0), ... (7,0), (0,1), ...");
        $display("When input corner is x_s5/y_s5, Sobel output belongs to center x_s5-1/y_s5-1.");
        $display("");
        $display("time  in_x in_y  center_x center_y  pixel  edge_mag");

        for (k = 0; k < FRAME_SIZE; k = k + 1) begin
            @(negedge clk);
            gray_valid_in = 1'b1;
            gray8_in = frame[k];
        end

        @(negedge clk);
        gray_valid_in = 1'b0;
        gray8_in = 8'd0;

        // Let the 5-stage Sobel pipeline drain.
        repeat (12) @(posedge clk);

        $display("");
        $display("Total valid output cycles: %0d", out_count);
        $finish;
    end

    always @(posedge clk) begin
        if (edge_valid_out) begin
            out_count = out_count + 1;
            center_x = dut.x_s5 - 1;
            center_y = dut.y_s5 - 1;
            $display("%4t  %4d %4d  %8d %8d  %h  %7d",
                     $time,
                     dut.x_s5,
                     dut.y_s5,
                     center_x,
                     center_y,
                     edge_pixel_out,
                     dut.edge_mag_s5);
        end
    end

endmodule
