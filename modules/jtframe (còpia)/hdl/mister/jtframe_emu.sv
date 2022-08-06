//============================================================================
//  JTFRAME by Jose Tejada Gomez. Twitter: @topapate
//
//  Port to MiSTer
//  Thanks to Sorgelig for his continuous support
//  Original repository: http://github.com/jotego/jt_gng
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
    //Master input clock
    input         CLK_50M,

    //Async reset from top-level module.
    //Can be used as initial reset.
    input         RESET,

    //Must be passed to hps_io module
    inout  [45:0] HPS_BUS,

    //Base video clock. Usually equals to CLK_SYS.
    output        CLK_VIDEO,

    //Multiple resolutions are supported using different CE_PIXEL rates.
    //Must be based on CLK_VIDEO
    output        CE_PIXEL,

    output  [7:0] VGA_R,
    output  [7:0] VGA_G,
    output  [7:0] VGA_B,
    output        VGA_HS,
    output        VGA_VS,
    output        VGA_DE,    // = ~(VBlank | HBlank)
    output        VGA_F1,
    output  [1:0] VGA_SL,
    output        VGA_SCALER,

    //Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
    output [11:0] VIDEO_ARX,
    output [11:0] VIDEO_ARY,

    output        LED_USER,  // 1 - ON, 0 - OFF.

    // b[1]: 0 - LED status is system status OR'd with b[0]
    //       1 - LED status is controled solely by b[0]
    // hint: supply 2'b00 to let the system control the LED.
    output  [1:0] LED_POWER,
    output  [1:0] LED_DISK,

    // I/O board button press simulation (active high)
    // b[1]: user button
    // b[0]: osd button
    // output  [1:0] BUTTONS,

    input         CLK_AUDIO,
    output reg [15:0] AUDIO_L,
    output reg [15:0] AUDIO_R,
    output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned

    //SDRAM interface with lower latency
    output        SDRAM_CLK,
    output        SDRAM_CKE,
    output [12:0] SDRAM_A,
    output  [1:0] SDRAM_BA,
    inout  [15:0] SDRAM_DQ,
    output        SDRAM_DQML,
    output        SDRAM_DQMH,
    output        SDRAM_nCS,
    output        SDRAM_nCAS,
    output        SDRAM_nRAS,
    output        SDRAM_nWE,

    // Open-drain User port.
    // 0 - D+/RX
    // 1 - D-/TX
    // 2..6 - USR2..USR6
    // Set USER_OUT to 1 to read from USER_IN.
    input   [6:0] USER_IN,
    output  [6:0] USER_OUT
    `ifdef SIMULATION
    ,output         sim_pxl_cen,
    output          sim_pxl_clk,
    output          sim_vb,
    output          sim_hb
    `endif
);

// Config string
`include "build_id.v"
`define SEPARATOR "-;",

`ifdef SIMULATION
localparam CONF_STR="JTGNG;;";
`else
localparam CONF_STR = {
    `CORENAME,";;",
    "OOR,CRT H adjust,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
    "OSV,CRT V adjust,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
    // Common MiSTer options
    `ifndef JTFRAME_OSD_NOLOAD
    "F,rom;",
    `endif
    "H0OB,Aspect Ratio,Original,Wide;",
    `ifdef VERTICAL_SCREEN
        `ifdef JTFRAME_OSD_FLIP
        "O1,Flip screen,Off,On;",
        `endif
    "O2,Rotate screen,Yes,No;",
    `endif
    "O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",

    `ifndef NOSOUND
        // sound OSD options are ommitted for compilations without sound
        `ifdef JT12
        "O8,PSG,On,Off;",
        "O9,FM ,On,Off;",
        "O67,FX volume, high, very high, very low, low;",
        `else
            `ifdef JTFRAME_ADPCM
            "O8,ADPCM,On,Off;",
            `endif
            `ifdef JT51
            "O9,FM ,On,Off;",
            `endif
        `endif
    `endif
    `ifdef JTFRAME_OSD_TEST
    "OA,Test mode,Off,On;",
    `endif
    `SEPARATOR
    `ifdef JTFRAME_MRA_DIP
    "DIP;",
    `endif
    `ifdef CORE_OSD
    `CORE_OSD
    `endif
    `SEPARATOR
    "R0,Reset;",
    `ifndef JTFRAME_OSD_NOCREDITS
    "OC,Credits,Off,On;",
    `endif
    `ifdef CORE_KEYMAP
    `CORE_KEYMAP
    `endif
    "V,v",`BUILD_DATE," jotego;"
};
`endif

`undef SEPARATOR

`ifndef JTFRAME_INTERLACED
assign VGA_F1=1'b0;
`else
wire   field;
assign VGA_F1=field;
`endif

assign VGA_SL     = 2'd0;
assign VGA_SCALER = 0;
assign USER_OUT   = '1;
// assign BUTTONS    = 2'd0; // MiSTer board button emulation from core

wire [3:0] hoffset, voffset;

////////////////////   CLOCKS   ///////////////////

wire clk_sys, clk_rom, clk96, clk96sh, clk48, clk48sh, clk24, clk6;
wire pxl2_cen, pxl_cen;
wire pll_locked;
reg  pll_rst = 1'b0;

// Resets the PLL if it looses lock
always @(posedge clk_sys or posedge RESET) begin : pll_controller
    reg last_locked;
    reg [7:0] rst_cnt;

    if( RESET ) begin
        pll_rst <= 1'b0;
        rst_cnt <= 8'hd0;
    end else begin
        last_locked <= pll_locked;
        if( last_locked && !pll_locked ) begin
            rst_cnt <= 8'hff; // keep reset high for 256 cycles
            pll_rst <= 1'b1;
        end else begin
            if( rst_cnt != 8'h00 )
                rst_cnt <= rst_cnt - 8'h1;
            else
                pll_rst <= 1'b0;
        end
    end
end

pll pll(
    .refclk     ( CLK_50M    ),
    .rst        ( pll_rst    ),
    .locked     ( pll_locked ),
    .outclk_0   ( clk48      ),
    .outclk_1   ( clk48sh    ),
    .outclk_2   ( clk24      ),
    .outclk_3   ( clk6       ),
    .outclk_4   ( clk96      ),
    .outclk_5   ( clk96sh    )
);


`ifdef JTFRAME_SDRAM96
    assign clk_rom = clk96;
    assign clk_sys = clk96;
`else
    assign clk_rom = clk48;
    `ifdef JTFRAME_CLK96
    assign clk_sys = clk96;
    `else
    assign clk_sys = clk48;
    `endif
`endif

`ifndef JTFRAME_180SHIFT
    `ifdef JTFRAME_SDRAM96
    assign SDRAM_CLK   = clk96sh;
    `else
    assign SDRAM_CLK   = clk48sh;
    `endif
`else
    altddio_out
    #(
        .extend_oe_disable("OFF"),
        .intended_device_family("Cyclone V"),
        .invert_output("OFF"),
        .lpm_hint("UNUSED"),
        .lpm_type("altddio_out"),
        .oe_reg("UNREGISTERED"),
        .power_up_high("OFF"),
        .width(1)
    )
    sdramclk_ddr
    (
        .datain_h(1'b0),
        .datain_l(1'b1),
        .outclock(clk_rom),
        .dataout(SDRAM_CLK),
        .aclr(1'b0),
        .aset(1'b0),
        .oe(1'b1),
        .outclocken(1'b1),
        .sclr(1'b0),
        .sset(1'b0)
    );
`endif

///////////////////////////////////////////////////

wire [31:0] status;
wire [ 1:0] buttons, game_led;

wire [ 1:0] dip_fxlevel;
wire        enable_fm, enable_psg;
wire        dip_pause, dip_flip, dip_test;
wire [31:0] dipsw;

wire        ioctl_rom_wr;
wire [24:0] ioctl_addr;
wire [ 7:0] ioctl_data;

wire [ 9:0] game_joy1, game_joy2, game_joy3, game_joy4;
wire [ 3:0] game_coin, game_start;
wire [ 3:0] gfx_en;
wire [15:0] joystick_analog_0, joystick_analog_1;

wire        game_rst, rst, rst_n;
wire        rst_req   = RESET | status[0] | buttons[1];

assign LED_DISK  = 2'b0;
assign LED_POWER = 2'b0;

// ROM download
wire        downloading, dwnld_busy;

wire [21:0] prog_addr;
wire [15:0] prog_data;
`ifndef JTFRAME_SDRAM_BANKS
wire [ 7:0]   prog_data8;
`endif
wire [ 1:0] prog_mask, prog_ba;
wire        prog_we, prog_rd, prog_rdy, prog_ack;

// ROM access from game
wire [21:0] ba0_addr;
wire        ba0_rd, ba0_wr, ba0_rdy, ba0_ack;
wire [15:0] ba0_din;
wire [ 1:0] ba0_din_m;
wire [21:0] ba1_addr;
wire        ba1_rd, ba1_rdy, ba1_ack;
wire [21:0] ba2_addr;
wire        ba2_rd, ba2_rdy, ba2_ack;
wire [21:0] ba3_addr;
wire        ba3_rd, ba3_rdy, ba3_ack;
wire        sdram_req, rfsh_en;
wire [31:0] sdram_dout;

`ifndef COLORW
`define COLORW 4
`endif

`ifndef BUTTONS
`define BUTTONS 2
`endif

localparam COLORW=`COLORW;
localparam GAME_BUTTONS=`BUTTONS;

wire [COLORW-1:0] game_r, game_g, game_b;
wire              LHBL, LVBL;
wire              hs, vs, sample;

`ifdef JTFRAME_GAME_LED
assign game_led[1] = 1'b1;
`else
assign game_led = 2'b0;
`endif

`ifndef SIGNED_SND
assign AUDIO_S = 1'b1; // Assume signed by default
`else
assign AUDIO_S = `SIGNED_SND;
`endif

`ifndef JTFRAME_SDRAM_BANKS
assign prog_data = {2{prog_data8}};
`endif

jtframe_mister #(
    .CONF_STR      ( CONF_STR       ),
    .BUTTONS       ( GAME_BUTTONS        ),
    .COLORW        ( COLORW         )
    `ifdef VIDEO_WIDTH
    ,.VIDEO_WIDTH   ( `VIDEO_WIDTH   )
    `endif
    `ifdef VIDEO_HEIGHT
    ,.VIDEO_HEIGHT  ( `VIDEO_HEIGHT  )
    `endif
)
u_frame(
    .clk_sys        ( clk_sys        ),
    .clk_rom        ( clk_rom        ),
    .pll_locked     ( pll_locked     ),
    // interface with microcontroller
    .status         ( status         ),
    .HPS_BUS        ( HPS_BUS        ),
    .buttons        ( buttons        ),
    // LED
    .game_led       ( game_led       ),
    // Base video
    .game_r         ( game_r         ),
    .game_g         ( game_g         ),
    .game_b         ( game_b         ),
    .LHBL           ( LHBL           ),
    .LVBL           ( LVBL           ),
    .hs             ( hs             ),
    .vs             ( vs             ),
    .pxl_cen        ( pxl_cen        ),
    .pxl2_cen       ( pxl2_cen       ),
    // SDRAM interface
    .SDRAM_CLK      ( SDRAM_CLK      ),
    .SDRAM_DQ       ( SDRAM_DQ       ),
    .SDRAM_A        ( SDRAM_A        ),
    .SDRAM_DQML     ( SDRAM_DQML     ),
    .SDRAM_DQMH     ( SDRAM_DQMH     ),
    .SDRAM_nWE      ( SDRAM_nWE      ),
    .SDRAM_nCAS     ( SDRAM_nCAS     ),
    .SDRAM_nRAS     ( SDRAM_nRAS     ),
    .SDRAM_nCS      ( SDRAM_nCS      ),
    .SDRAM_BA       ( SDRAM_BA       ),
    .SDRAM_CKE      ( SDRAM_CKE      ),
    // ROM access from game
    // Bank 0: allows R/W
    .ba0_addr       ( ba0_addr       ),
    .ba0_rd         ( ba0_rd         ),
    .ba0_wr         ( ba0_wr         ),
    .ba0_din        ( ba0_din        ),
    .ba0_din_m      ( ba0_din_m      ),  // write mask
    .ba0_rdy        ( ba0_rdy        ),
    .ba0_ack        ( ba0_ack        ),

    // Bank 1: Read only
    .ba1_addr       ( ba1_addr       ),
    .ba1_rd         ( ba1_rd         ),
    .ba1_rdy        ( ba1_rdy        ),
    .ba1_ack        ( ba1_ack        ),

    // Bank 2: Read only
    .ba2_addr       ( ba2_addr       ),
    .ba2_rd         ( ba2_rd         ),
    .ba2_rdy        ( ba2_rdy        ),
    .ba2_ack        ( ba2_ack        ),

    // Bank 3: Read only
    .ba3_addr       ( ba3_addr       ),
    .ba3_rd         ( ba3_rd         ),
    .ba3_rdy        ( ba3_rdy        ),
    .ba3_ack        ( ba3_ack        ),

    .rfsh_en        ( rfsh_en        ),
    .sdram_dout     ( sdram_dout     ),

    // ROM load
    .ioctl_addr     ( ioctl_addr     ),
    .ioctl_data     ( ioctl_data     ),
    .ioctl_rom_wr   ( ioctl_rom_wr   ),

    .prog_addr      ( prog_addr      ),
    .prog_data      ( prog_data      ),
    .prog_rd        ( prog_rd        ),
    .prog_we        ( prog_we        ),
    .prog_mask      ( prog_mask      ),
    .prog_ba        ( prog_ba        ),
    .prog_rdy       ( prog_rdy       ),
    .prog_ack       ( prog_ack       ),

    .downloading    ( downloading    ),
    .dwnld_busy     ( dwnld_busy     ),
//////////// board
    .rst            ( rst            ),
    .rst_n          ( rst_n          ), // unused
    .game_rst       ( game_rst       ),
    .game_rst_n     (                ),
    // reset forcing signals:
    .rst_req        ( rst_req        ),
    // joystick
    .game_joystick1 ( game_joy1      ),
    .game_joystick2 ( game_joy2      ),
    .game_joystick3 ( game_joy3      ),
    .game_joystick4 ( game_joy4      ),
    .game_coin      ( game_coin      ),
    .game_start     ( game_start     ),
    .game_service   (                ), // unused
    .joystick_analog_0( joystick_analog_0 ),
    .joystick_analog_1( joystick_analog_1 ),
    .LED            ( LED_USER       ),
    // DIP and OSD settings
    .enable_fm      ( enable_fm      ),
    .enable_psg     ( enable_psg     ),
    .dip_test       ( dip_test       ),
    .dip_pause      ( dip_pause      ),
    .dip_flip       ( dip_flip       ),
    .dip_fxlevel    ( dip_fxlevel    ),
    .dipsw          ( dipsw          ),
    // screen
    .rotate         (                ),
    // HDMI
    .hdmi_arx       ( VIDEO_ARX      ),
    .hdmi_ary       ( VIDEO_ARY      ),
    // scan doubler output to VGA pins
    .scan2x_r       ( VGA_R          ),
    .scan2x_g       ( VGA_G          ),
    .scan2x_b       ( VGA_B          ),
    .scan2x_hs      ( VGA_HS         ),
    .scan2x_vs      ( VGA_VS         ),
    .scan2x_clk     ( CLK_VIDEO      ),
    .scan2x_cen     ( CE_PIXEL       ),
    .scan2x_de      ( VGA_DE         ),
    // Debug
    .gfx_en         ( gfx_en         )
);

`ifdef SIMULATION
assign sim_hb = ~LHBL;
assign sim_vb = ~LVBL;
assign sim_pxl_clk = clk_sys;
assign sim_pxl_cen = pxl_cen;
`endif

///////////////////////////////////////////////////////////////////

`ifdef SIMULATION
assign sim_pxl_clk = clk_sys;
assign sim_pxl_cen = pxl_cen;
`endif

wire [15:0] snd_left, snd_right;
reg  [15:0] snd_lsync, snd_rsync;

always @(posedge CLK_AUDIO) begin
    snd_lsync <= snd_left;
    snd_rsync <= snd_right;
    AUDIO_L   <= snd_lsync;
    AUDIO_R   <= snd_rsync;
end

`GAMETOP u_game
(
    .rst          ( game_rst         ),
    // clock inputs
    // By default clk is 48MHz, but JTFRAME_CLK96 overrides it to 96MHz
    .clk          ( clk_rom          ),
    `ifdef JTFRAME_CLK96
    .clk96        ( clk96            ),
    `endif
    `ifdef JTFRAME_CLK48
    .clk48        ( clk48            ),
    `endif
    `ifdef JTFRAME_CLK24
    .clk24        ( clk24            ),
    `endif
    `ifdef JTFRAME_CLK6
    .clk6         ( clk6             ),
    `endif
    .pxl2_cen     ( pxl2_cen         ),
    .pxl_cen      ( pxl_cen          ),

    .red          ( game_r           ),
    .green        ( game_g           ),
    .blue         ( game_b           ),
    .LHBL_dly     ( LHBL             ), // Final timing
    .LVBL_dly     ( LVBL             ),
    .HS           ( hs               ),
    .VS           ( vs               ),
`ifdef JTFRAME_INTERLACED
    .field        ( field            ),
`endif
    // LED
`ifdef JTFRAME_GAME_LED
    .game_led    ( game_led[0]    ),
`endif

    .start_button ( game_start       ),
    .coin_input   ( game_coin        ),
    .joystick1    ( game_joy1[GAME_BUTTONS+3:0]   ),
    .joystick2    ( game_joy2[GAME_BUTTONS+3:0]   ),
    `ifdef JTFRAME_4PLAYERS
    .joystick3    ( game_joy3[GAME_BUTTONS+3:0]   ),
    .joystick4    ( game_joy4[GAME_BUTTONS+3:0]   ),
    `endif
    `ifdef JTFRAME_ANALOG
    .joystick_analog_0( joystick_analog_0   ),
    .joystick_analog_1( joystick_analog_1   ),
    `endif
    // Sound control
    .enable_fm    ( enable_fm        ),
    .enable_psg   ( enable_psg       ),
    // PROM programming
    .ioctl_addr   ( ioctl_addr       ),
    .ioctl_data   ( ioctl_data       ),
    .ioctl_wr     ( ioctl_rom_wr     ),

    // ROM load
    .downloading ( downloading    ),
    .dwnld_busy  ( dwnld_busy     ),
    .data_read   ( sdram_dout     ),
    .refresh_en  ( rfsh_en        ),

    `ifdef JTFRAME_SDRAM_BANKS
    // Bank 0: allows R/W
    .ba0_addr   ( ba0_addr      ),
    .ba0_rd     ( ba0_rd        ),
    .ba0_wr     ( ba0_wr        ),
    .ba0_din    ( ba0_din       ),
    .ba0_din_m  ( ba0_din_m     ),  // write mask
    .ba0_rdy    ( ba0_rdy       ),
    .ba0_ack    ( ba0_ack       ),

    // Bank 1: Read only
    .ba1_addr   ( ba1_addr      ),
    .ba1_rd     ( ba1_rd        ),
    .ba1_rdy    ( ba1_rdy       ),
    .ba1_ack    ( ba1_ack       ),

    // Bank 2: Read only
    .ba2_addr   ( ba2_addr      ),
    .ba2_rd     ( ba2_rd        ),
    .ba2_rdy    ( ba2_rdy       ),
    .ba2_ack    ( ba2_ack       ),

    // Bank 3: Read only
    .ba3_addr   ( ba3_addr      ),
    .ba3_rd     ( ba3_rd        ),
    .ba3_rdy    ( ba3_rdy       ),
    .ba3_ack    ( ba3_ack       ),
    `else
    .loop_rst   ( 1'b0          ),
    .sdram_req  ( ba0_rd        ),
    .sdram_addr ( ba0_addr      ),
    .data_rdy   ( ba0_rdy       ),
    .sdram_ack  ( ba0_ack | prog_ack ),
    `endif

    // ROM-load interface
    `ifdef JTFRAME_SDRAM_BANKS
    .prog_ba    ( prog_ba       ),
    .prog_rdy   ( prog_rdy      ),
    .prog_ack   ( prog_ack      ),
    .prog_data  ( prog_data     ),
    `else
    .prog_data  ( prog_data8    ),
    `endif
    .prog_addr  ( prog_addr     ),
    .prog_rd    ( prog_rd       ),
    .prog_we    ( prog_we       ),
    .prog_mask  ( prog_mask     ),

    // DIP switches
    .status       ( status           ),
    .dip_pause    ( dip_pause        ),
    .dip_flip     ( dip_flip         ),
    .dip_test     ( dip_test         ),
    .dip_fxlevel  ( dip_fxlevel      ),
    `ifdef JTFRAME_MRA_DIP
    .dipsw        ( dipsw            ),
    `endif

    `ifdef STEREO_GAME
    .snd_left     ( snd_left         ),
    .snd_right    ( snd_right        ),
    `else
    .snd          ( snd_left         ),
    `endif
    .gfx_en       ( gfx_en           ),

    // unconnected
    .sample       ( sample           )
);

`ifndef STEREO_GAME
    assign snd_right = snd_left;
`endif

`ifndef JTFRAME_SDRAM_BANKS
assign ba0_wr    = 1'b0;
assign prog_ba   = 2'd0;
// tie down unused bank signals
assign ba1_addr = 22'd0;
assign ba1_rd   = 0;
assign ba2_addr = 22'd0;
assign ba2_ack  = 0;
assign ba3_addr = 22'd0;
assign ba3_rd   = 0;
`endif

`ifdef SIMULATION
integer fsnd;
initial begin
    fsnd=$fopen("sound.raw","wb");
end
always @(posedge sample) begin
    $fwrite(fsnd,"%u", {AUDIO_L, AUDIO_R});
end
`endif


endmodule
