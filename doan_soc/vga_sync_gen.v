module vga_sync_gen
#(
	// horizontal parameter (pixels)
	parameter H_BACK_PORCH	=	48,
	parameter H_ACTIVE 		=	640,
	parameter H_FRONT_PORCH	=	16,
	parameter H_SYNC_PULSE	= 	96,
	
	// vertical parameter (lines)
	parameter V_BACK_PORCH 	=	33,
	parameter V_ACTIVE 		= 	480,
	parameter V_FRONT_PORCH	= 	10,
	parameter V_SYNC_PULSE	= 	2
	
)
(clk, reset_n, hsync, vsync, blank_n);
	input wire clk; 		// clock source input
	input wire reset_n; 	// active low reset input;
	output wire hsync;	// horizontal synchronization output signal
	output wire vsync;	// vertical synchronization output signal 
	output wire blank_n;	// blank_n signal
	
	// total h and v
	localparam H_TOTAL = H_BACK_PORCH + H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE; // 800
   localparam V_TOTAL = V_BACK_PORCH + V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE; // 525

   localparam H_ACTIVE_START = H_BACK_PORCH;                        // 48
   localparam H_ACTIVE_END   = H_BACK_PORCH + H_ACTIVE;             // 688
   localparam H_SYNC_START   = H_ACTIVE_END + H_FRONT_PORCH;        // 704
    
   localparam V_ACTIVE_START = V_BACK_PORCH;                        // 33
   localparam V_ACTIVE_END   = V_BACK_PORCH + V_ACTIVE;             // 513
   localparam V_SYNC_START   = V_ACTIVE_END + V_FRONT_PORCH;        // 523
	
	reg [9:0] hcount;		// horizontal counter
	reg [9:0] vcount; 	// vertical counter
	
	always @(posedge clk or negedge reset_n) begin
		if (reset_n == 1'b0) begin 
			hcount <= 0;
			vcount <= 0;
		end
		else if (hcount < H_TOTAL - 1) hcount <= hcount + 1;
		else begin
			hcount <= 0;
			if (vcount < V_TOTAL - 1) vcount <= vcount + 1;
			else vcount <= 0;
		end
	end
	
	assign hsync = (hcount >= H_SYNC_START && hcount < H_TOTAL)?0:1;
	assign vsync = (vcount >= V_SYNC_START && vcount < V_TOTAL)?0:1;
	
	// blank_n signal turn 1 in active region
	assign blank_n = (	(hcount >= H_ACTIVE_START  && hcount < H_ACTIVE_END) &&
								(vcount >= V_ACTIVE_START && vcount < V_ACTIVE_END))?1:0;
	
endmodule