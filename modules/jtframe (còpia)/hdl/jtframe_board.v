/*  This file is part of JT_FRAME.
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
    Date: 25-9-2019 */

module jtframe_board #(parameter
    BUTTONS                 = 2, // number of buttons used by the game
    // coin and start buttons will be mapped.
    GAME_INPUTS_ACTIVE_LOW  = 1'b1,
    COLORW                  = 4,
    SDRAMW                  = 22,
    VIDEO_WIDTH             = 384,
    VIDEO_HEIGHT            = 224
)(
    output            rst,
    output            rst_n,
    output            game_rst,
    output            game_rst_n,
    // reset forcing signals:
    input             rst_req,

    input             clk_sys,
    input             clk_rom,

    input  [ 6:0]     core_mod,
    // LED
    input               osd_shown,
    input        [ 1:0] game_led,
    output              led,
    // ROM access from game
    input  [SDRAMW-1:0] ba0_addr,
    input               ba0_rd,
    input               ba0_wr,
    input        [15:0] ba0_din,
    input        [ 1:0] ba0_din_m,  // write mask
    output              ba0_rdy,
    output              ba0_ack,
    input  [SDRAMW-1:0] ba1_addr,
    input               ba1_rd,
    output              ba1_rdy,
    output              ba1_ack,
    input  [SDRAMW-1:0] ba2_addr,
    input               ba2_rd,
    output              ba2_rdy,
    output              ba2_ack,
    input  [SDRAMW-1:0] ba3_addr,
    input               ba3_rd,
    output              ba3_rdy,
    output              ba3_ack,

    input               rfsh_en,   // ok to refresh
    output       [31:0] sdram_dout,
    // ROM programming
    input  [SDRAMW-1:0] prog_addr,
    input        [15:0] prog_data,
    input        [ 1:0] prog_mask,
    input        [ 1:0] prog_ba,
    input               prog_we,
    input               prog_rd,
    output              prog_rdy,
    output              prog_ack,
    input               downloading,
    // SDRAM interface
    inout  [15:0]     SDRAM_DQ,       // SDRAM Data bus 16 Bits
    output [12:0]     SDRAM_A,        // SDRAM Address bus 13 Bits
    output            SDRAM_DQML,     // SDRAM Low-byte Data Mask
    output            SDRAM_DQMH,     // SDRAM High-byte Data Mask
    output            SDRAM_nWE,      // SDRAM Write Enable
    output            SDRAM_nCAS,     // SDRAM Column Address Strobe
    output            SDRAM_nRAS,     // SDRAM Row Address Strobe
    output            SDRAM_nCS,      // SDRAM Chip Select
    output [1:0]      SDRAM_BA,       // SDRAM Bank Address
    output            SDRAM_CKE,      // SDRAM Clock Enable
    // keyboard
    input             ps2_kbd_clk,
    input             ps2_kbd_data,
    // joystick
    input     [15:0]  board_joystick1,
    input     [15:0]  board_joystick2,
    input     [15:0]  board_joystick3,
    input     [15:0]  board_joystick4,
    output reg [9:0]  game_joystick1,
    output reg [9:0]  game_joystick2,
    output reg [9:0]  game_joystick3,
    output reg [9:0]  game_joystick4,
    output reg [3:0]  game_coin,
    output reg [3:0]  game_start,
    output reg        game_service,
    // DIP and OSD settings
    input     [31:0]  status,
    output    [11:0]  hdmi_arx,
    output    [11:0]  hdmi_ary,
    output    [ 1:0]  rotate,

    output            enable_fm,
    output            enable_psg,

    output            dip_test,
    // non standard:
    output            dip_pause,
    inout             dip_flip,     // A change in dip_flip implies a reset if JTFRAME_FLIP_RESET is defined
    output    [ 1:0]  dip_fxlevel,
    // Base video
    input     [ 1:0]  osd_rotate,
    input [COLORW-1:0] game_r,
    input [COLORW-1:0] game_g,
    input [COLORW-1:0] game_b,
    input             LHBL,
    input             LVBL,
    input             hs,
    input             vs,
    input             pxl_cen,
    input             pxl2_cen,
    // HDMI outputs (only for MiSTer)
    inout     [21:0]  gamma_bus,
    input             direct_video,
    // scan doubler
    input             scan2x_enb,
    output    [7:0]   scan2x_r,
    output    [7:0]   scan2x_g,
    output    [7:0]   scan2x_b,
    output            scan2x_hs,
    output            scan2x_vs,
    output            scan2x_clk,
    output            scan2x_cen,
    output            scan2x_de,
    // GFX enable
    output reg [3:0]  gfx_en
);

wire  [ 2:0]  scanlines;
wire          bw_en, blend_en;
wire          en_mixing;
wire          osd_pause;

wire invert_inputs = GAME_INPUTS_ACTIVE_LOW[0];
wire key_reset, key_pause, rot_control;
reg       game_pause, soft_rst;
wire      scandoubler = ~scan2x_enb;

`ifdef JTFRAME_MISTER_VIDEO_DW
localparam arcade_fx_dw = `JTFRAME_MISTER_VIDEO_DW;
`else
localparam arcade_fx_dw = COLORW*3;
`endif

wire [9:0] key_joy1, key_joy2, key_joy3;
wire [3:0] key_start, key_coin;
wire [3:0] key_gfx;
wire       key_service;

jtframe_reset u_reset(
    .clk_sys    ( clk_sys       ),
    .clk_rom    ( clk_rom       ),

    .downloading( downloading   ),
    .dip_flip   ( dip_flip      ),
    .soft_rst   ( soft_rst      ),
    .rst_req    ( rst_req       ),

    .rst        ( rst           ),
    .rst_n      ( rst_n         ),
    .game_rst   ( game_rst      ),
    .game_rst_n ( game_rst_n    )
);

jtframe_led u_led(
    .rst        ( rst           ),
    .clk        ( clk_sys       ),
    .downloading( downloading   ),
    .osd_shown  ( osd_shown     ),
    .gfx_en     ( gfx_en        ),
    .game_led   ( game_led      ),
    .led        ( led           )
);

`ifndef SIMULATION
jtframe_keyboard u_keyboard(
    .clk         ( clk_sys       ),
    .rst         ( rst           ),
    // ps2 interface
    .ps2_clk     ( ps2_kbd_clk   ),
    .ps2_data    ( ps2_kbd_data  ),
    // decoded keys
    .key_joy1    ( key_joy1      ),
    .key_joy2    ( key_joy2      ),
    .key_joy3    ( key_joy3      ),
    .key_start   ( key_start     ),
    .key_coin    ( key_coin      ),
    .key_reset   ( key_reset     ),
    .key_pause   ( key_pause     ),
    .key_service ( key_service   ),
    .key_gfx     ( key_gfx       )
);
`else
assign key_joy3    = 10'h0;
assign key_joy2    = 10'h0;
assign key_joy1    = 10'h0;
assign key_start   = 2'd0;
assign key_coin    = 2'd0;
assign key_reset   = 1'b0;
assign key_pause   = 1'b0;
assign key_service = 1'b0;
`endif

reg  [15:0] joy1_sync, joy2_sync, joy3_sync, joy4_sync;
wire [ 3:0] joy4way1p, joy4way2p, joy4way3p, joy4way4p;
wire        en4way = core_mod[1];

always @(posedge clk_sys) begin
    joy1_sync <= { board_joystick1[15:4], joy4way1p[3:0] };
    joy2_sync <= { board_joystick2[15:4], joy4way2p[3:0] };
    joy3_sync <= { board_joystick3[15:4], joy4way3p[3:0] };
    joy4_sync <= { board_joystick4[15:4], joy4way4p[3:0] };
end

jtframe_4wayjoy u_4way_1p(
    .rst        ( rst                    ),
    .clk        ( clk_sys                ),
    .enable     ( en4way                 ),
    .joy8way    ( board_joystick1[3:0]   ),
    .joy4way    ( joy4way1p              )
);

jtframe_4wayjoy u_4way_2p(
    .rst        ( rst                    ),
    .clk        ( clk_sys                ),
    .enable     ( en4way                 ),
    .joy8way    ( board_joystick2[3:0]   ),
    .joy4way    ( joy4way2p              )
);

jtframe_4wayjoy u_4way_3p(
    .rst        ( rst                    ),
    .clk        ( clk_sys                ),
    .enable     ( en4way                 ),
    .joy8way    ( board_joystick3[3:0]   ),
    .joy4way    ( joy4way3p              )
);

jtframe_4wayjoy u_4way_4p(
    .rst        ( rst                    ),
    .clk        ( clk_sys                ),
    .enable     ( en4way                 ),
    .joy8way    ( board_joystick4[3:0]   ),
    .joy4way    ( joy4way4p              )
);

localparam START_BIT  = 6+(BUTTONS-2);
localparam COIN_BIT   = 7+(BUTTONS-2);
localparam PAUSE_BIT  = 8+(BUTTONS-2);

reg last_pause, last_osd_pause, last_joypause, last_reset;
reg [3:0] last_gfx;
wire joy_pause = joy1_sync[PAUSE_BIT] | joy2_sync[PAUSE_BIT];

integer cnt;

function [9:0] apply_rotation;
    input [9:0] joy_in;
    input       rot;
    input       flip;
    input       invert;
    begin
    apply_rotation = {10{invert}} ^
        (!rot ? joy_in :
        flip ?
         { joy_in[9:4], joy_in[1], joy_in[0], joy_in[2], joy_in[3] } :
         { joy_in[9:4], joy_in[0], joy_in[1], joy_in[3], joy_in[2] });
    end
endfunction

`ifdef SIM_INPUTS
    reg [15:0] sim_inputs[0:16383];
    integer frame_cnt;
    initial begin : read_sim_inputs
        integer c;
        for( c=0; c<16384; c=c+1 ) sim_inputs[c] = 8'h0;
        $display("INFO: input simulation enabled");
        $readmemh( "sim_inputs.hex", sim_inputs );
    end
    always @(negedge LVBL, posedge rst) begin
        if( rst )
            frame_cnt <= 0;
        else frame_cnt <= frame_cnt+1;
    end
`endif

always @(posedge clk_sys)
    if(rst ) begin
        game_pause   <= 1'b0;
        game_service <= 1'b0 ^ invert_inputs;
        soft_rst     <= 1'b0;
        gfx_en       <= 4'hf;
    end else begin
        last_pause   <= key_pause;
        last_osd_pause <= osd_pause;
        last_reset   <= key_reset;
        last_joypause <= joy_pause; // joy is active low!

        // joystick, coin, start and service inputs are inverted
        // as indicated in the instance parameter

        `ifdef SIM_INPUTS
        game_coin  = {4{invert_inputs}} ^ { 2'b0, sim_inputs[frame_cnt][1:0] };
        game_start = {4{invert_inputs}} ^ { 2'b0, sim_inputs[frame_cnt][3:2] };
        game_joystick1 <= {10{invert_inputs}} ^ { 4'd0, sim_inputs[frame_cnt][9:4]};
        `else
        game_joystick1 <= apply_rotation(joy1_sync | key_joy1, rot_control, ~dip_flip, invert_inputs);
        game_coin      <= {4{invert_inputs}} ^
            ({  joy4_sync[COIN_BIT],joy3_sync[COIN_BIT],
                joy2_sync[COIN_BIT],joy1_sync[COIN_BIT]} | key_coin);

        game_start     <= {4{invert_inputs}} ^
            ({  joy4_sync[START_BIT],joy3_sync[START_BIT],
                joy2_sync[START_BIT],joy1_sync[START_BIT]} | key_start);
        `endif
        game_joystick2 <= apply_rotation(joy2_sync | key_joy2, rot_control, ~dip_flip, invert_inputs);
        game_joystick3 <= apply_rotation(joy3_sync | key_joy3, rot_control, ~dip_flip, invert_inputs);
        game_joystick4 <= apply_rotation(joy4_sync           , rot_control, ~dip_flip, invert_inputs);

        soft_rst <= key_reset && !last_reset;

        `ifndef JTFRAME_RELEASE
        last_gfx <= key_gfx;
        for(cnt=0; cnt<4; cnt=cnt+1)
            if( key_gfx[cnt] && !last_gfx[cnt] ) gfx_en[cnt] <= ~gfx_en[cnt];
        `endif
        // state variables:
        `ifndef DIP_PAUSE // Forces pause during simulation
        if( downloading )
            game_pause<=0;
        else begin// toggle
            if( (key_pause && !last_pause) || (joy_pause && !last_joypause) )
                game_pause   <= ~game_pause;
            if (last_osd_pause ^ osd_pause) game_pause <= osd_pause;
        end
        `else
        game_pause <= 1'b1;
        `endif
        game_service <= key_service ^ invert_inputs;
    end

jtframe_dip u_dip(
    .clk        ( clk_sys       ),
    .status     ( status        ),
    .core_mod   ( core_mod      ),
    .game_pause ( game_pause    ),
    .hdmi_arx   ( hdmi_arx      ),
    .hdmi_ary   ( hdmi_ary      ),
    .rotate     ( rotate        ),
    .rot_control( rot_control   ),
    .en_mixing  ( en_mixing     ),
    .scanlines  ( scanlines     ),
    .blend_en   ( blend_en      ),
    .bw_en      ( bw_en         ),
    .enable_fm  ( enable_fm     ),
    .enable_psg ( enable_psg    ),
    .osd_pause  ( osd_pause     ),
    .dip_test   ( dip_test      ),
    .dip_pause  ( dip_pause     ),
    .dip_flip   ( dip_flip      ),
    .dip_fxlevel( dip_fxlevel   )
);

// support for 48MHz
// Above 64MHz HF should be 1. SHIFTED depends on whether the SDRAM
// clock is shifted or not.
jtframe_sdram_bank #(.AW(SDRAMW),
`ifdef JTFRAME_SDRAM96
    .HF(1),
    .SHIFTED(0)
`else
    .HF(0),
    `ifdef JTFRAME_180SHIFT
        .SHIFTED(0)
    `else
        .SHIFTED(1)
    `endif
`endif
) u_sdram(
    .rst        ( rst           ),
    .clk        ( clk_rom       ), // 96MHz = 32 * 6 MHz -> CL=2

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
    .prog_en    ( downloading   ),
    .prog_addr  ( prog_addr     ),
    .prog_ba    ( prog_ba       ),
    .prog_rd    ( prog_rd       ),
    .prog_wr    ( prog_we       ),
    .prog_din   ( prog_data     ),
    .prog_din_m ( prog_mask     ),
    .prog_rdy   ( prog_rdy      ),
    .prog_ack   ( prog_ack      ),
    // SDRAM interface
    .sdram_dq   ( SDRAM_DQ      ),
    .sdram_a    ( SDRAM_A       ),
    .sdram_dqml ( SDRAM_DQML    ),
    .sdram_dqmh ( SDRAM_DQMH    ),
    .sdram_nwe  ( SDRAM_nWE     ),
    .sdram_ncas ( SDRAM_nCAS    ),
    .sdram_nras ( SDRAM_nRAS    ),
    .sdram_ncs  ( SDRAM_nCS     ),
    .sdram_ba   ( SDRAM_BA      ),
    .sdram_cke  ( SDRAM_CKE     ),

    // Common signals
    .dout       ( sdram_dout    ),
    .rfsh_en    ( rfsh_en       )
);

wire [COLORW-1:0] pre2x_r, pre2x_g, pre2x_b;
wire              pre2x_LHBL, pre2x_LVBL;

`ifdef JTFRAME_CREDITS
    `ifndef JTFRAME_CREDITS_PAGES
    `define JTFRAME_CREDITS_PAGES 3
    `endif
    wire toggle = |(game_start ^ {4{invert_inputs}});
    // To do: HS and VS should actually be delayed inside jtframe_credits too
    jtframe_credits #(
        .PAGES  ( `JTFRAME_CREDITS_PAGES ),
        .COLW   ( COLORW                 ),
        .BLKPOL (      0                 ) // 0 for active low signals
    ) u_credits(
        .rst        ( rst           ),
        .clk        ( clk_sys       ),
        .pxl_cen    ( pxl_cen       ),

        // input image
        .HB         ( LHBL          ),
        .VB         ( LVBL          ),
        .rgb_in     ( { game_r, game_g, game_b } ),
        `ifdef JTFRAME_CREDITS_AON
            .enable ( 1'b1          ),
        `else
            .enable ( ~dip_pause    ),
        `endif
        .toggle     ( toggle        ),
        // output image
        .HB_out     ( pre2x_LHBL      ),
        .VB_out     ( pre2x_LVBL      ),
        .rgb_out    ( {pre2x_r, pre2x_g, pre2x_b } )
    );
`else
    assign { pre2x_r, pre2x_g, pre2x_b } = { game_r, game_g, game_b };
    assign { pre2x_LHBL, pre2x_LVBL    } = { LHBL, LVBL };
`endif

// By pass scan2x in simulation by default
// enable it by defining JTFRAME_SIM_SCAN2X

`ifdef SIMULATION
    `ifdef NOVIDEO
    `define JTFRAME_DONTSIM_SCAN2X
    `endif
    `ifndef JTFRAME_SIM_SCAN2X
    `define JTFRAME_DONTSIM_SCAN2X
    `endif
`endif


`ifdef JTFRAME_DONTSIM_SCAN2X
initial $display("INFO: Scan2x simulation bypassed");
assign scan2x_r    = pre2x_r;
assign scan2x_g    = pre2x_g;
assign scan2x_b    = pre2x_b;
assign scan2x_hs   = hs;
assign scan2x_vs   = vs;
assign scan2x_clk  = clk_sys;
assign scan2x_cen  = pxl_cen;
assign scan2x_de   = LVBL && LHBL;
`else
// Always use JTFRAME_SCAN2X for MiST and SiDi
`ifndef MISTER
`define JTFRAME_SCAN2X
`endif

`ifdef JTFRAME_SCAN2X
    localparam CLROUTW = COLORW < 5 ? COLORW+1 : COLORW;

    wire [CLROUTW-1:0] r_ana, g_ana, b_ana;
    wire               hs_ana, vs_ana;
    wire               pxl_ana;

    jtframe_wirebw #(.WIN(COLORW), .WOUT(CLROUTW)) u_wirebw(
        .clk        ( clk_sys   ),
        .spl_in     ( pxl_cen   ),
        .r_in       ( pre2x_r   ),
        .g_in       ( pre2x_g   ),
        .b_in       ( pre2x_b   ),
        .HS_in      ( hs        ),
        .VS_in      ( vs        ),
        .enable     ( bw_en     ),
        // filtered video
        .HS_out     ( hs_ana    ),
        .VS_out     ( vs_ana    ),
        .spl_out    (           ),
        .r_out      ( r_ana     ),
        .g_out      ( g_ana     ),
        .b_out      ( b_ana     )
    );

    function [7:0] extend8;
        input [CLROUTW-1:0] a;
        case( CLROUTW )
            3: extend8 = { a, a, a[2:1] };
            4: extend8 = { a, a         };
            5: extend8 = { a, a[4:2]    };
            6: extend8 = { a, a[5:4]    };
            7: extend8 = { a, a[6]      };
            8: extend8 = a;
        endcase
    endfunction

    // This scan doubler takes very little memory. Some games in MiST
    // can only use this
    wire [CLROUTW*3-1:0] rgbx2;
    wire [CLROUTW*3-1:0] game_rgb = { r_ana, g_ana, b_ana };
    wire scan2x_hsin = bw_en ? hs_ana : hs;

    // Note that VIDEO_WIDTH must include blanking for JTFRAME_SCAN2X
    jtframe_scan2x #(.COLORW(CLROUTW), .HLEN(VIDEO_WIDTH)) u_scan2x(
        .rst_n      ( rst_n          ),
        .clk        ( clk_sys        ),
        .pxl_cen    ( pxl_cen        ),
        // settings
        .sl_mode    ( scanlines[1:0] ),
        .blend_en   ( blend_en       ),
        // video inputs
        .pxl2_cen   ( pxl2_cen       ),
        .base_pxl   ( game_rgb       ),
        .HS         ( scan2x_hsin    ),
        // outputs
        .x2_pxl     ( rgbx2          ),
        .x2_HS      ( scan2x_hs      )
    );
    assign scan2x_vs    = bw_en ? vs_ana : vs;
    assign scan2x_r     = extend8( rgbx2[CLROUTW*3-1:CLROUTW*2] );
    assign scan2x_g     = extend8( rgbx2[CLROUTW*2-1:CLROUTW] );
    assign scan2x_b     = extend8( rgbx2[CLROUTW-1:0] );
    assign scan2x_de    = ~(scan2x_vs | scan2x_hs);
    assign scan2x_cen   = pxl2_cen;
    assign scan2x_clk   = clk_sys;
    // unused in MiST
    assign gamma_bus    = 22'd0;
`else
    localparam VIDEO_DW = COLORW!=5 ? 3*COLORW : 24;

    wire [VIDEO_DW-1:0] game_rgb;

    // arcade video does not support 15bpp colour, so for that
    // case we need to convert it to 24bpp
    generate
        if( COLORW!=5 ) begin
            assign game_rgb = {pre2x_r, pre2x_g, pre2x_b };
        end else begin
            assign game_rgb = {
                pre2x_r, pre2x_r[4:2],
                pre2x_g, pre2x_g[4:2],
                pre2x_b, pre2x_b[4:2]
            };
        end
    endgenerate

    // VIDEO_WIDTH does not include blanking:
    arcade_video #(.WIDTH(VIDEO_WIDTH),.HEIGHT(VIDEO_HEIGHT),.DW(VIDEO_DW)
        // Disable Gamma correction for MiST/SiDi
        `ifndef MISTER
        ,.GAMMA(0)
        `endif
        )
    u_arcade_video(
        .clk_video  ( clk_sys       ),
        .ce_pix     ( pxl_cen       ),

        .RGB_in     ( game_rgb      ),
        .HBlank     ( ~pre2x_LHBL   ),
        .VBlank     ( ~pre2x_LVBL   ),
        .HSync      ( hs            ),
        .VSync      ( vs            ),

        .VGA_CLK    (  scan2x_clk   ),
        .VGA_CE     (  scan2x_cen   ),
        .VGA_R      (  scan2x_r     ),
        .VGA_G      (  scan2x_g     ),
        .VGA_B      (  scan2x_b     ),
        .VGA_HS     (  scan2x_hs    ),
        .VGA_VS     (  scan2x_vs    ),
        .VGA_DE     (  scan2x_de    ),

        .HDMI_CLK   (               ),
        .HDMI_CE    (               ),
        .HDMI_R     (               ),
        .HDMI_G     (               ),
        .HDMI_B     (               ),
        .HDMI_HS    (               ),
        .HDMI_VS    (               ),
        .HDMI_DE    (               ),
        .HDMI_SL    (               ),
        .gamma_bus  ( gamma_bus     ),


        .fx                ( scanlines   ),
        .forced_scandoubler( scandoubler ),
        .rotate_ccw        ( 1'b0        ),
        `ifdef MISTER
        .no_rotate         ( ~rotate[0]  ) // the no_rotate name
            // is misleading. A low value in no_rotate will actually
            // rotate the game video. If the game is vertical, a low value
            // presents the game correctly on a horizontal screen
        `else
        // MiST / SiDi don't have enough BRAM to rotate the video
        // nor do they have HDMI pins
        .no_rotate         ( 1'b1        )
        `endif
    );
`endif
`endif

endmodule
