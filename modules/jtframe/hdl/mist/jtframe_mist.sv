/*  This file is part of JTFRAME.
    JTFRAME program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTFRAME program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTFRAME.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 7-3-2019 */

module jtframe_mist #(parameter
    SIGNED_SND             = 1'b0,
    BUTTONS                = 2,
    GAME_INPUTS_ACTIVE_LOW = 1'b1,
    CONF_STR               = "",
    COLORW                 = 4,
    VIDEO_WIDTH            = 384,
    VIDEO_HEIGHT           = 224
)(
    input           clk_sys,
    input           clk_rom,
    input           pll_locked,
    // interface with microcontroller
    output  [63:0]  status,
    // Base video
    input [COLORW-1:0] game_r,
    input [COLORW-1:0] game_g,
    input [COLORW-1:0] game_b,
    input              LHBL,
    input              LVBL,
    input              hs,
    input              vs,
    input              pxl_cen,
    input              pxl2_cen,
    // LED
    input        [1:0] game_led,
    // MiST VGA pins
    output       [5:0] VGA_R,
    output       [5:0] VGA_G,
    output       [5:0] VGA_B,
    output             VGA_HS,
    output             VGA_VS,
    // ROM programming
    input        [21:0] prog_addr,
    input        [15:0] prog_data,
    input        [ 1:0] prog_mask,
    input        [ 1:0] prog_ba,
    input               prog_we,
    input               prog_rd,
    output              prog_rdy,
    output              prog_ack,
    // ROM access from game
    input        [21:0] ba0_addr,
    input               ba0_rd,
    input               ba0_wr,
    input        [15:0] ba0_din,
    input        [ 1:0] ba0_din_m,  // write mask
    output              ba0_rdy,
    output              ba0_ack,
    input        [21:0] ba1_addr,
    input               ba1_rd,
    output              ba1_rdy,
    output              ba1_ack,
    input        [21:0] ba2_addr,
    input               ba2_rd,
    output              ba2_rdy,
    output              ba2_ack,
    input        [21:0] ba3_addr,
    input               ba3_rd,
    output              ba3_rdy,
    output              ba3_ack,

    input               rfsh_en,   // ok to refresh
    output     [  31:0] sdram_dout,
    // SDRAM interface
    inout    [15:0] SDRAM_DQ,       // SDRAM Data bus 16 Bits
    output   [12:0] SDRAM_A,        // SDRAM Address bus 13 Bits
    output          SDRAM_DQML,     // SDRAM Low-byte Data Mask
    output          SDRAM_DQMH,     // SDRAM High-byte Data Mask
    output          SDRAM_nWE,      // SDRAM Write Enable
    output          SDRAM_nCAS,     // SDRAM Column Address Strobe
    output          SDRAM_nRAS,     // SDRAM Row Address Strobe
    output          SDRAM_nCS,      // SDRAM Chip Select
    output    [1:0] SDRAM_BA,       // SDRAM Bank Address
    output          SDRAM_CKE,      // SDRAM Clock Enable
    // SPI interface to arm io controller
    inout           SPI_DO,
    input           SPI_DI,
    input           SPI_SCK,
    input           SPI_SS2,
    input           SPI_SS3,
    input           SPI_SS4,
    input           CONF_DATA0,
    // ROM load from SPI
    output   [24:0] ioctl_addr,
    output   [ 7:0] ioctl_data,
    output          ioctl_wr,
    input    [ 7:0] ioctl_data2sd,
    output          ioctl_ram,
    input           dwnld_busy,
    output          downloading,

//////////// board
    output          rst,      // synchronous reset
    output          rst_n,    // asynchronous reset
    output          game_rst,
    output          game_rst_n,
    // reset forcing signals:
    input           rst_req,
    // Sound
    input   [15:0]  snd_left,
    input   [15:0]  snd_right,
    output          AUDIO_L,
    output          AUDIO_R,
    // joystick
    output   [9:0]  game_joystick1,
    output   [9:0]  game_joystick2,
    output   [9:0]  game_joystick3,
    output   [9:0]  game_joystick4,
    output   [3:0]  game_coin,
    output   [3:0]  game_start,
    output          game_service,
    output  [15:0]  joystick_analog_0,
    output  [15:0]  joystick_analog_1,
    // DIP and OSD settings
    output          enable_fm,
    output          enable_psg,

    output          dip_test,
    // non standard:
    output          dip_pause,
    inout           dip_flip,     // A change in dip_flip implies a reset
    output  [ 1:0]  dip_fxlevel,
    // Debug
    output          LED,
    output   [3:0]  gfx_en
);

localparam SDRAMW=22;

// control
wire [31:0]   joystick1, joystick2, joystick3, joystick4;
wire          ps2_kbd_clk, ps2_kbd_data;
wire          osd_shown;

wire [7:0]    scan2x_r, scan2x_g, scan2x_b;
wire          scan2x_hs, scan2x_vs, scan2x_clk;
wire          scan2x_enb;
wire [6:0]    core_mod;

wire  [ 1:0]  rotate;

jtframe_mist_base #(
    .CONF_STR    (CONF_STR          ),
    .CONF_STR_LEN($size(CONF_STR)/8 ),
    .SIGNED_SND  (SIGNED_SND        ),
    .COLORW      ( COLORW           )
) u_base(
    .rst            ( rst           ),
    .clk_sys        ( clk_sys       ),
    .clk_rom        ( clk_rom       ),
    .core_mod       ( core_mod      ),
    .osd_shown      ( osd_shown     ),
    // Base video
    .osd_rotate     ( rotate        ),
    .game_r         ( game_r        ),
    .game_g         ( game_g        ),
    .game_b         ( game_b        ),
    .LHBL           ( LHBL          ),
    .LVBL           ( LVBL          ),
    .hs             ( hs            ),
    .vs             ( vs            ),
    .pxl_cen        ( pxl_cen       ),
    // Scan-doubler video
    .scan2x_r       ( scan2x_r[7:2] ),
    .scan2x_g       ( scan2x_g[7:2] ),
    .scan2x_b       ( scan2x_b[7:2] ),
    .scan2x_hs      ( scan2x_hs     ),
    .scan2x_vs      ( scan2x_vs     ),
    .scan2x_enb     ( scan2x_enb    ),
    .scan2x_clk     ( scan2x_clk    ),
    // MiST VGA pins (includes OSD)
    .VIDEO_R        ( VGA_R         ),
    .VIDEO_G        ( VGA_G         ),
    .VIDEO_B        ( VGA_B         ),
    .VIDEO_HS       ( VGA_HS        ),
    .VIDEO_VS       ( VGA_VS        ),
    // SPI interface to arm io controller
    .SPI_DO         ( SPI_DO        ),
    .SPI_DI         ( SPI_DI        ),
    .SPI_SCK        ( SPI_SCK       ),
    .SPI_SS2        ( SPI_SS2       ),
    .SPI_SS3        ( SPI_SS3       ),
    .SPI_SS4        ( SPI_SS4       ),
    .CONF_DATA0     ( CONF_DATA0    ),
    // control
    .status         ( status        ),
    .joystick1      ( joystick1     ),
    .joystick2      ( joystick2     ),
    .joystick3      ( joystick3     ),
    .joystick4      ( joystick4     ),
    // Analog joystick
    .joystick_analog_0( joystick_analog_0   ),
    .joystick_analog_1( joystick_analog_1   ),
    // Keyobard
    .ps2_kbd_clk    ( ps2_kbd_clk   ),
    .ps2_kbd_data   ( ps2_kbd_data  ),
    // audio
    .clk_dac        ( clk_sys       ),
    .snd_left       ( snd_left      ),
    .snd_right      ( snd_right     ),
    .snd_pwm_left   ( AUDIO_L       ),
    .snd_pwm_right  ( AUDIO_R       ),
    // ROM load from SPI
    .ioctl_addr     ( ioctl_addr    ),
    .ioctl_data     ( ioctl_data    ),
    .ioctl_data2sd  ( ioctl_data2sd ),
    .ioctl_wr       ( ioctl_wr      ),
    .ioctl_ram      ( ioctl_ram     ),
    .downloading    ( downloading   )
);

jtframe_board #(
    .BUTTONS               ( BUTTONS               ),
    .GAME_INPUTS_ACTIVE_LOW( GAME_INPUTS_ACTIVE_LOW),
    .COLORW                ( COLORW                ),
    .VIDEO_WIDTH           ( VIDEO_WIDTH           ),
    .VIDEO_HEIGHT          ( VIDEO_HEIGHT          )
) u_board(
    .rst            ( rst             ),
    .rst_n          ( rst_n           ),
    .game_rst       ( game_rst        ),
    .game_rst_n     ( game_rst_n      ),
    .rst_req        ( rst_req         ),
    .downloading    ( dwnld_busy      ), // use busy signal from game module

    .clk_sys        ( clk_sys         ),
    .clk_rom        ( clk_rom         ),

    .core_mod       ( core_mod        ),
    // joystick
    .ps2_kbd_clk    ( ps2_kbd_clk     ),
    .ps2_kbd_data   ( ps2_kbd_data    ),
    .board_joystick1( joystick1[15:0] ),
    .board_joystick2( joystick2[15:0] ),
    .board_joystick3( joystick3[15:0] ),
    .board_joystick4( joystick4[15:0] ),
    .game_joystick1 ( game_joystick1  ),
    .game_joystick2 ( game_joystick2  ),
    .game_joystick3 ( game_joystick3  ),
    .game_joystick4 ( game_joystick4  ),
    .game_coin      ( game_coin       ),
    .game_start     ( game_start      ),
    .game_service   ( game_service    ),
    // DIP and OSD settings
    .status         ( status[31:0]    ),
    .enable_fm      ( enable_fm       ),
    .enable_psg     ( enable_psg      ),
    .dip_test       ( dip_test        ),
    .dip_pause      ( dip_pause       ),
    .dip_flip       ( dip_flip        ),
    .dip_fxlevel    ( dip_fxlevel     ),
    // screen
    .rotate         ( rotate          ),
    // LED
    .osd_shown      ( osd_shown       ),
    .game_led       ( game_led        ),
    .led            ( LED             ),
    // SDRAM interface
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

    // ROM-load interface
    .prog_addr  ( prog_addr     ),
    .prog_ba    ( prog_ba       ),
    .prog_rd    ( prog_rd       ),
    .prog_we    ( prog_we       ),
    .prog_data  ( prog_data     ),
    .prog_mask  ( prog_mask     ),
    .prog_rdy   ( prog_rdy      ),
    .prog_ack   ( prog_ack      ),
    // SDRAM interface
    .SDRAM_DQ   ( SDRAM_DQ      ),
    .SDRAM_A    ( SDRAM_A       ),
    .SDRAM_DQML ( SDRAM_DQML    ),
    .SDRAM_DQMH ( SDRAM_DQMH    ),
    .SDRAM_nWE  ( SDRAM_nWE     ),
    .SDRAM_nCAS ( SDRAM_nCAS    ),
    .SDRAM_nRAS ( SDRAM_nRAS    ),
    .SDRAM_nCS  ( SDRAM_nCS     ),
    .SDRAM_BA   ( SDRAM_BA      ),
    .SDRAM_CKE  ( SDRAM_CKE     ),

    // Common signals
    .sdram_dout ( sdram_dout    ),
    .rfsh_en    ( rfsh_en       ),

    // Base video
    .osd_rotate     ( rotate          ),
    .game_r         ( game_r          ),
    .game_g         ( game_g          ),
    .game_b         ( game_b          ),
    .LHBL           ( LHBL            ),
    .LVBL           ( LVBL            ),
    .hs             ( hs              ),
    .vs             ( vs              ),
    .pxl_cen        ( pxl_cen         ),
    .pxl2_cen       ( pxl2_cen        ),
    // Scan-doubler video
    .scan2x_r       ( scan2x_r        ),
    .scan2x_g       ( scan2x_g        ),
    .scan2x_b       ( scan2x_b        ),
    .scan2x_hs      ( scan2x_hs       ),
    .scan2x_vs      ( scan2x_vs       ),
    .scan2x_enb     ( scan2x_enb      ),
    .scan2x_clk     ( scan2x_clk      ),
    // Debug
    .gfx_en         ( gfx_en          ),
    // Unused ports (MiSTer)
    .gamma_bus      (                 ),
    .direct_video   ( 1'b0            ),
    .hdmi_arx       (                 ),
    .hdmi_ary       (                 ),
    .scan2x_cen     (                 ),
    .scan2x_de      (                 )
);

endmodule // jtframe