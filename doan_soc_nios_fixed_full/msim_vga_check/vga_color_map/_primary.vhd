library verilog;
use verilog.vl_types.all;
entity vga_color_map is
    port(
        pixel           : in     vl_logic_vector(15 downto 0);
        VGA_R           : out    vl_logic_vector(9 downto 0);
        VGA_G           : out    vl_logic_vector(9 downto 0);
        VGA_B           : out    vl_logic_vector(9 downto 0)
    );
end vga_color_map;
