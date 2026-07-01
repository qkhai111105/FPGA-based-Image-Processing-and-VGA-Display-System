library verilog;
use verilog.vl_types.all;
entity sobel_edge is
    generic(
        IMG_WIDTH       : integer := 320;
        IMG_HEIGHT      : integer := 240;
        THRESHOLD       : integer := 175
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        gray_valid_in   : in     vl_logic;
        gray8_in        : in     vl_logic_vector(7 downto 0);
        edge_valid_out  : out    vl_logic;
        edge_pixel_out  : out    vl_logic_vector(15 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of IMG_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of IMG_HEIGHT : constant is 1;
    attribute mti_svvh_generic_type of THRESHOLD : constant is 1;
end sobel_edge;
