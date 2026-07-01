`timescale 1ns/1ps

module tb_gray_sram_sobel_matrix;

    localparam IMG_WIDTH  = 8;
    localparam IMG_HEIGHT = 6;
    localparam FRAME_SIZE = IMG_WIDTH * IMG_HEIGHT;
    localparam THRESHOLD  = 100;

    reg clk;
    reg rst_n;

    reg        rgb_valid_in;
    reg [15:0] rgb565_in;
    wire       gray_valid_out;
    wire [7:0] gray8_out;
    wire [15:0] gray565_out;

    reg        sobel_valid_in;
    reg [7:0]  sobel_gray_in;
    wire       sobel_valid_out;
    wire [15:0] sobel_pixel_out;

    reg [15:0] rgb_sram [0:FRAME_SIZE-1];
    reg [7:0]  gray_sram [0:FRAME_SIZE-1];
    reg [15:0] sobel_seq_sram [0:FRAME_SIZE-1];
    reg [15:0] sobel_addr_sram [0:FRAME_SIZE-1];

    integer x;
    integer y;
    integer k;
    integer gray_wr_addr;
    integer sobel_seq_wr_addr;
    integer corrected_addr;
    integer center_x;
    integer center_y;
    integer sample_x_s5;
    integer sample_y_s5;
    integer sample_edge_mag_s5;

    rgb565_to_gray u_gray (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(rgb_valid_in),
        .rgb565_in(rgb565_in),
        .valid_out(gray_valid_out),
        .gray8_out(gray8_out),
        .gray565_out(gray565_out)
    );

    sobel_edge #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .THRESHOLD(THRESHOLD)
    ) u_sobel (
        .clk(clk),
        .rst_n(rst_n),
        .gray_valid_in(sobel_valid_in),
        .gray8_in(sobel_gray_in),
        .edge_valid_out(sobel_valid_out),
        .edge_pixel_out(sobel_pixel_out)
    );

    function [15:0] gray_to_rgb565;
        input [7:0] gray;
        begin
            gray_to_rgb565 = {gray[7:3], gray[7:2], gray[7:3]};
        end
    endfunction

    task print_rgb565_matrix;
        begin
            $display("");
            $display("RGB SRAM matrix, RGB565 hex:");
            for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
                $write("row %0d: ", y);
                for (x = 0; x < IMG_WIDTH; x = x + 1) begin
                    $write("%h ", rgb_sram[y * IMG_WIDTH + x]);
                end
                $write("\n");
            end
        end
    endtask

    task print_gray_matrix;
        begin
            $display("");
            $display("GRAY SRAM matrix, 8-bit decimal:");
            for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
                $write("row %0d: ", y);
                for (x = 0; x < IMG_WIDTH; x = x + 1) begin
                    $write("%3d ", gray_sram[y * IMG_WIDTH + x]);
                end
                $write("\n");
            end
        end
    endtask

    task print_sobel_seq_matrix;
        begin
            $display("");
            $display("SOBEL SRAM if written sequentially, like edge_detect_write_offset:");
            for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
                $write("row %0d: ", y);
                for (x = 0; x < IMG_WIDTH; x = x + 1) begin
                    if (sobel_seq_sram[y * IMG_WIDTH + x] == 16'hFFFF)
                        $write("255 ");
                    else
                        $write("  0 ");
                end
                $write("\n");
            end
        end
    endtask

    task print_sobel_addr_matrix;
        begin
            $display("");
            $display("SOBEL SRAM if written by corrected center address:");
            $display("correct_addr = (y_s5 - 1) * IMG_WIDTH + (x_s5 - 1)");
            for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
                $write("row %0d: ", y);
                for (x = 0; x < IMG_WIDTH; x = x + 1) begin
                    if (sobel_addr_sram[y * IMG_WIDTH + x] == 16'hFFFF)
                        $write("255 ");
                    else
                        $write("  0 ");
                end
                $write("\n");
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        for (k = 0; k < FRAME_SIZE; k = k + 1) begin
            rgb_sram[k] = 16'h0000;
            gray_sram[k] = 8'd0;
            sobel_seq_sram[k] = 16'h0000;
            sobel_addr_sram[k] = 16'h0000;
        end

        for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
            for (x = 0; x < IMG_WIDTH; x = x + 1) begin
                // Left half dark, right half bright. This makes a vertical edge.
                if (x < 4)
                    rgb_sram[y * IMG_WIDTH + x] = gray_to_rgb565(20 + y);
                else
                    rgb_sram[y * IMG_WIDTH + x] = gray_to_rgb565(220 - y);
            end
        end
    end

    initial begin
        $dumpfile("tb_gray_sram_sobel_matrix.vcd");
        $dumpvars(0, tb_gray_sram_sobel_matrix);

        rst_n = 1'b0;
        rgb_valid_in = 1'b0;
        rgb565_in = 16'h0000;
        sobel_valid_in = 1'b0;
        sobel_gray_in = 8'd0;
        gray_wr_addr = 0;
        sobel_seq_wr_addr = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        print_rgb565_matrix;

        $display("");
        $display("==== RGB SRAM -> rgb565_to_gray -> write GRAY SRAM ====");
        for (k = 0; k < FRAME_SIZE; k = k + 1) begin
            @(negedge clk);
            rgb_valid_in = 1'b1;
            rgb565_in = rgb_sram[k];
        end

        @(negedge clk);
        rgb_valid_in = 1'b0;
        rgb565_in = 16'h0000;
        repeat (3) @(posedge clk);

        print_gray_matrix;

        $display("");
        $display("==== Read GRAY SRAM sequentially -> sobel_edge ====");
        for (k = 0; k < FRAME_SIZE; k = k + 1) begin
            @(negedge clk);
            sobel_valid_in = 1'b1;
            sobel_gray_in = gray_sram[k];
            $display("READ_GRAY  addr=%2d  x=%0d y=%0d  gray=%3d",
                     k, k % IMG_WIDTH, k / IMG_WIDTH, gray_sram[k]);
        end

        @(negedge clk);
        sobel_valid_in = 1'b0;
        sobel_gray_in = 8'd0;
        repeat (12) @(posedge clk);

        print_sobel_seq_matrix;
        print_sobel_addr_matrix;

        $display("");
        $display("Done. Open tb_gray_sram_sobel_matrix.vcd to inspect waveform.");
        $finish;
    end

    always @(posedge clk) begin
        if (gray_valid_out) begin
            gray_sram[gray_wr_addr] = gray8_out;
            $display("WRITE_GRAY addr=%2d  x=%0d y=%0d  gray8=%3d  gray565=%h",
                     gray_wr_addr,
                     gray_wr_addr % IMG_WIDTH,
                     gray_wr_addr / IMG_WIDTH,
                     gray8_out,
                     gray565_out);
            gray_wr_addr = gray_wr_addr + 1;
        end
    end

    always @(posedge clk) begin
        sample_x_s5 = u_sobel.x_s5;
        sample_y_s5 = u_sobel.y_s5;
        sample_edge_mag_s5 = u_sobel.edge_mag_s5;

        #1;

        if (sobel_valid_out) begin
            if (sobel_seq_wr_addr < FRAME_SIZE)
                sobel_seq_sram[sobel_seq_wr_addr] = sobel_pixel_out;

            center_x = sample_x_s5 - 1;
            center_y = sample_y_s5 - 1;
            corrected_addr = center_y * IMG_WIDTH + center_x;

            if ((sample_x_s5 >= 2) &&
                (sample_y_s5 >= 2) &&
                (sample_x_s5 < IMG_WIDTH) &&
                (sample_y_s5 < IMG_HEIGHT)) begin
                sobel_addr_sram[corrected_addr] = sobel_pixel_out;

                $display("SOBEL_OUT input_corner=(%0d,%0d) center=(%0d,%0d) mag=%4d pixel=%h | seq_addr=%2d corrected_addr=%2d",
                         sample_x_s5,
                         sample_y_s5,
                         center_x,
                         center_y,
                         sample_edge_mag_s5,
                         sobel_pixel_out,
                         sobel_seq_wr_addr,
                         corrected_addr);
            end else begin
                $display("SOBEL_OUT input_corner=(%0d,%0d) border/invalid mag=%4d pixel=%h | seq_addr=%2d corrected_addr=none",
                         sample_x_s5,
                         sample_y_s5,
                         sample_edge_mag_s5,
                         sobel_pixel_out,
                         sobel_seq_wr_addr);
            end

            sobel_seq_wr_addr = sobel_seq_wr_addr + 1;
        end
    end

endmodule
