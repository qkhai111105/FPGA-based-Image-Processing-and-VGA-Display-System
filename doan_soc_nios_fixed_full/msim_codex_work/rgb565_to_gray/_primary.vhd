library verilog;
use verilog.vl_types.all;
entity rgb565_to_gray is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        valid_in        : in     vl_logic;
        rgb565_in       : in     vl_logic_vector(15 downto 0);
        valid_out       : out    vl_logic;
        gray8_out       : out    vl_logic_vector(7 downto 0);
        gray565_out     : out    vl_logic_vector(15 downto 0)
    );
end rgb565_to_gray;
