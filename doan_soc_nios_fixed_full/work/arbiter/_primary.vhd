library verilog;
use verilog.vl_types.all;
entity arbiter is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        uart_rx_data    : in     vl_logic_vector(7 downto 0);
        uart_rx_done    : in     vl_logic;
        vga_data_o      : out    vl_logic_vector(15 downto 0);
        vga_wr_en_o     : out    vl_logic;
        vga_full_i      : in     vl_logic;
        vga_vsync_i     : in     vl_logic;
        sram_addr_o     : out    vl_logic_vector(17 downto 0);
        sram_read_o     : out    vl_logic;
        sram_write_o    : out    vl_logic;
        sram_data_o     : out    vl_logic_vector(15 downto 0);
        sram_data_i     : in     vl_logic_vector(15 downto 0);
        sram_byte_en_o  : out    vl_logic_vector(1 downto 0);
        edge_pixel_valid_o: out    vl_logic;
        edge_rgb565_o   : out    vl_logic_vector(15 downto 0);
        edge_rgb565_i   : in     vl_logic_vector(15 downto 0);
        edge_fifo_rdreq_o: out    vl_logic;
        edge_fifo_full_i: in     vl_logic;
        edge_fifo_empty_i: in     vl_logic;
        edge_fifo_almost_full_i: in     vl_logic;
        avs_address_i   : in     vl_logic_vector(2 downto 0);
        avs_read_i      : in     vl_logic;
        avs_write_i     : in     vl_logic;
        avs_writedata_i : in     vl_logic_vector(31 downto 0);
        avs_readdata_o  : out    vl_logic_vector(31 downto 0);
        avs_readdatavalid_o: out    vl_logic;
        avs_irq_o       : out    vl_logic
    );
end arbiter;
