; =====================================================================
;  Dr. Driving Lite  -  COAL Final Project (FAST Lahore)
;  drive.asm  -  the complete game in ONE file
; ---------------------------------------------------------------------
;  Build :  nasm drive.asm -o drive.com
;  Run   :  drive.com   (inside DOSBox)
;
;  Sections of this file, in order:
;    constants, graphics (video), text, road, cars, traffic,
;    cockpit, HUD, keyboard (INT 9), timer (INT 8), player,
;    gauges (time/distance/fuel), collisions, highway level,
;    menu, parking level, parking sensor, main program, data.
;
;  Phase 3: complete game. A start menu (1 = Highway, 2 = Parking),
;  level 1 = highway driving, level 2 = parking with a sensor.
;  After a level ends (or on ESC) the game goes back to the menu.
;  ESC in the menu returns to DOS.
; =====================================================================

        org 100h                ; .COM programs start at offset 100h

        jmp start               ; jump over the included routines

; =====================================================================
;  consts.asm  -  All fixed numbers (constants) used by the game
;  Dr. Driving Lite  -  COAL Final Project
; ---------------------------------------------------------------------
;  "equ" only gives a name to a number. It does NOT use any memory.
;  Keeping every magic number here makes the code easier to read and
;  lets us tune the game in one place.
; =====================================================================

; ---------------- Screen (VGA mode 13h = 320 x 200, 256 colours) ------
SCREEN_W        equ 320
SCREEN_H        equ 200
VIDEO_SEG       equ 0A000h          ; segment of the real VGA memory

; ---------------- Screen layout (y positions) -------------------------
HORIZON         equ 87              ; sky above this row, ground below
BONNET_TOP      equ 143             ; highest point of the orange bonnet
DASH_TOP        equ 167             ; dashboard panel starts here
BONNET_CURVE    equ 1067            ; bigger value = flatter bonnet curve

; ---------------- Colour numbers (palette indices) --------------------
; The real RGB values for each number are in "palette" in data.asm.
C_BLACK         equ 0
C_SKY           equ 1
C_GRASS         equ 2
C_ROAD          equ 3
C_WHITE         equ 4
C_ORANGE        equ 5               ; bonnet
C_ORANGE_DARK   equ 6               ; bonnet edge line
C_DASH          equ 7               ; dashboard panel
C_WHEEL         equ 8               ; steering wheel
C_YELLOW        equ 9               ; digits / score text
C_GREEN         equ 10              ; fuel bar (normal)
C_RED           equ 11              ; time bar, low fuel
C_CAR_BLUE      equ 12
C_CAR_TEAL      equ 13
C_WINDOW        equ 14              ; car rear window
C_TAIL          equ 15              ; car tail light
C_LIGHT_GREY    equ 16              ; labels, box borders
C_CAR_WHITE     equ 17
C_CAR_RED       equ 18
C_BAY           equ 19              ; parking bay (green)
C_CONE          equ 20              ; traffic cone orange
C_LOT           equ 21              ; parking lot floor
C_HUB           equ 22              ; steering wheel hub
C_DIM           equ 23              ; switched-off sensor segment
C_SENSOR_YEL    equ 24              ; sensor yellow
C_GRASS_DARK    equ 25              ; trees behind the parking lot
C_BAR_BG        equ 26              ; empty part of bars
C_BOX_BG        equ 27              ; inside of the speed box
C_CAR_YELLOW    equ 28
C_SENSOR_GRN    equ 29              ; sensor green
C_PANEL         equ 30              ; message boxes / banner
C_BROWN         equ 31              ; lane guide panel
C_ARROW_DIM     equ 32              ; lane guide arrow (not our lane)
C_GREEN_DIM     equ 33              ; indicator switched off
C_HAZARD        equ 34              ; hazard triangle (off)
C_SIDEWALK      equ 35              ; light grey pavement
C_BLD_1         equ 36              ; 4 building colours
C_BLD_2         equ 37
C_BLD_3         equ 38
C_BLD_4         equ 39
C_BLD_BASE      equ 40              ; brown shop fronts
C_BLD_WIN       equ 41              ; windows
C_BUSH          equ 42              ; round trees
C_FENCE         equ 43              ; fence behind the lot
C_SHADOW        equ 44              ; shadow under a car
C_BUMPER        equ 45              ; dark grey bumper
C_CURB          equ 46              ; kerb between road and pavement
C_WIN_LIT       equ 47              ; yellow lit window
C_ORANGE_LIGHT  equ 48              ; shine on the bonnet
C_DASH_EDGE     equ 49              ; top edge of the dashboard
PALETTE_COUNT   equ 50              ; how many colours we define

; ---------------- Perspective road ------------------------------------
; A world distance z (in world units) in front of the driver is drawn
; on screen row  HORIZON + PROJ_K / z.  Far things are near the horizon.
; One world unit = distance moved in one timer tick at 1 km/h
; (about 3.8 mm), so 262 units = 1 metre.
PROJ_K          equ 60000
UNITS_PER_METRE equ 262
CAR_Z_MIN       equ 530             ; closer than this: below the screen
CAR_Z_MAX       equ 26000           ; farther than this: too small to draw
DASH_PERIOD_MASK equ 2047           ; one dash + gap = 2048 units (~8 m)
DASH_LENGTH     equ 1024            ; length of the painted part

; ---------------- Lanes ------------------------------------------------
; Lanes are numbered 0 (left), 1 (middle), 2 (right).
; Across the road we measure in 1/16 of a lane width ("x16 units").
; Lane centres are at -16, 0 and +16.
LANE_LEFT       equ 0
LANE_MIDDLE     equ 1
LANE_RIGHT      equ 2

; ---------------- Fixed values shown in Phase 1 -----------------------
FUEL_MAX        equ 1000
TIME_MAX        equ 4380            ; 60 seconds x 73 ticks per second
LEVEL_DISTANCE  equ 1000            ; metres needed to finish highway

; ---------------- Keyboard scan codes ---------------------------------
; The keyboard sends these numbers to port 60h when a key is pressed.
SC_ESC          equ 01h
SC_ENTER        equ 1Ch
SC_SPACE        equ 39h
SC_UP           equ 48h
SC_LEFT         equ 4Bh
SC_RIGHT        equ 4Dh
SC_DOWN         equ 50h

; ---------------- Timer -----------------------------------------------
; The timer chip normally ticks 18.2 times a second (divisor 65536).
; We make it 4 times faster: 1193182 / 16384 = 72.8 ticks a second.
PIT_DIVISOR     equ 16384
TICKS_PER_SEC   equ 73
MAX_UPDATES     equ 8               ; max game updates before a redraw

; ---------------- Driving (speeds in 1/16 km/h per tick) --------------
MAX_SPEED       equ 140             ; km/h
ACCEL           equ 4               ; Up: +0.25 km/h every tick
BRAKE           equ 12              ; Space: -0.75 km/h every tick
COAST           equ 1               ; no pedal: -0.06 km/h every tick

; ---------------- Score ---------------------------------------------
SCORE_PER_METRE equ 10              ; points for every new metre

; ---------------- Lanes ---------------------------------------------
CAM_STEP        equ 2               ; lane change slide: 1/8 lane per tick

; ---------------- Traffic ---------------------------------------------
TRAFFIC_SPEED   equ 40              ; km/h, all traffic cars
RING_BACK       equ -3000           ; a car this far behind us ...
RING_LEN        equ 32488           ; ... is moved this far forward

; ---------------- Reverse gear --------------------------------------
MAX_REVERSE     equ 20              ; km/h when reversing
GEAR_D          equ 'D'             ; drive
GEAR_R          equ 'R'             ; reverse

; ---------------- Collisions ------------------------------------------
HIT_FRONT       equ 1100            ; car's back closer than this ...
HIT_MIN         equ 560             ; ... and at least this far = crash
CRASH_PENALTY   equ 50              ; points lost in a crash
CRASH_SHOW      equ 2 * TICKS_PER_SEC   ; "CRASH" text stays 2 seconds

; ---------------- Fuel ------------------------------------------------
FUEL_IDLE       equ 20              ; fuel use while moving ...
FUEL_DIV        equ 520             ; ... (IDLE + speed) / DIV per tick

; ---------------- Level state -----------------------------------------
STATE_PLAYING   equ 0
STATE_ENDED     equ 1
MSG_WIN         equ 1               ; reached 1000 m
MSG_TIME        equ 2               ; time ran out
MSG_FUEL        equ 3               ; fuel ran out

; ---------------- Game modes ------------------------------------------
MODE_MENU       equ 0               ; start menu on the screen
MODE_HIGHWAY    equ 1               ; level 1
MODE_PARKING    equ 2               ; level 2
SC_1            equ 02h             ; scan code of key 1
SC_2            equ 03h             ; scan code of key 2

; ---------------- Parking level ---------------------------------------
; Positions along the parking lot are world units (262 = 1 metre).
PARK_START_Z    equ 2000            ; where our car starts
BAY_START       equ 6000            ; the marked bay (middle lane) ...
BAY_END         equ 8000            ; ... from here to here
TREES_TOP       equ 67              ; green band behind the lot
PARK_SCORE      equ 1000            ; score at the start of level 2

PARK_MAX_SPEED  equ 25              ; km/h top speed in the parking lot
PARK_Z_MIN      equ 0               ; back wall of the lot
PARK_Z_MAX      equ 12000           ; far end of the lot

CAR_FRONT       equ 1100            ; our car reaches this far ahead
CAR_BACK        equ 500             ; ... and this far behind the driver
; one parking-lot object = 8 bytes:
OBJ_ZS          equ 0               ; word: where it starts (along lot)
OBJ_ZE          equ 2               ; word: where it ends
OBJ_LANE        equ 4               ; byte: lane 0, 1 or 2
OBJ_KIND        equ 5               ; byte: KIND_CAR or KIND_CONE
OBJ_COLOUR      equ 6               ; byte: colour of a car
OBJ_X16         equ 7               ; byte: sideways place to draw it
OBJ_SIZE        equ 8
KIND_CAR        equ 0
KIND_CONE       equ 1

; ---------------- Parking sensor --------------------------------------
SENSOR_Y        equ 122             ; row of the "SENSOR 0.8 m" text
SEG_X           equ 121             ; left x of the 8 lights
SEG_STEP        equ 10              ; 8 pixels light + 2 pixels gap

MSG_PARKED      equ 4               ; parked in the bay
PARK_HOLD       equ TICKS_PER_SEC / 2   ; must stay parked 0.5 s
TOUCH_GAP       equ 40              ; closer than 40 units = touching

END_WAIT        equ 8 * TICKS_PER_SEC   ; end message stays 8 seconds

; ---------------- Bonus: original Dr. Driving layout ------------------
SC_B            equ 30h             ; scan code of key B
LAYOUT_SIMPLE   equ 0               ; phases 1-3 screen
LAYOUT_ORIGINAL equ 1               ; bonus screen (Figures 3 and 4)

SPD_X           equ 112             ; speedometer centre
SPD_Y           equ 188
SPD_R           equ 37              ; speedometer radius

FG_X            equ 220             ; fuel gauge centre
FG_Y            equ 188
FG_R            equ 22              ; fuel gauge radius

LG_X_HIGHWAY    equ 205             ; lane guide panel, highway
LG_X_PARKING    equ 238             ; ... parking (right of the banner)
LG_Y            equ 2

IND_TIME        equ TICKS_PER_SEC   ; indicator flashes for 1 second
IND_L_X         equ 156             ; left indicator centre
IND_R_X         equ 192             ; right indicator centre
IND_Y           equ 179
HAZ_X           equ 174             ; hazard triangle centre

W2_X            equ 280             ; original wheel centre
W2_Y            equ 170
W2_R_OUT        equ 46
W2_R_IN         equ 38

WALL_X16        equ 33              ; building fronts: narrow pavement
CURB_X16        equ 26              ; outer side of the kerb

OVERTAKE_Z      equ -1800           ; a car this close behind us overtakes

; ---------------- Rear-view mirror ------------------------------------
MIR_X           equ 128             ; glass: left, top, width, height
MIR_Y           equ 24
MIR_W           equ 64
MIR_H           equ 16
MIR_RANGE       equ 6000            ; shows cars up to ~23 m behind us

SHOP_H          equ 8               ; shop front height (1/16 lanes)
WIN_H           equ 6               ; window height
FLOOR_H         equ 11              ; one floor = window + wall

; =====================================================================
;  video.asm  -  Graphics mode, palette, back buffer and basic shapes
; ---------------------------------------------------------------------
;  How drawing works in this game:
;   * We use VGA mode 13h: 320 x 200 pixels, 1 byte per pixel.
;     Pixel (x, y) is at offset  y*320 + x.
;   * We never draw directly on the screen (that would flicker).
;     We draw everything into a 64000-byte "back buffer" in another
;     segment, then copy the whole buffer to video memory (A000h) in
;     one go. This copy is called a "flip".
;   * All drawing routines expect ES = back buffer segment.
;   * The colour for every shape is taken from the byte [color].
; =====================================================================

; ---------------------------------------------------------------------
; video_init : switch to mode 13h, load our colours and the font,
;              and choose the segment of the back buffer.
; ---------------------------------------------------------------------
video_init:
        mov ax, 0013h           ; AH=00 set mode, AL=13h (320x200x256)
        int 10h
        call load_palette
        call load_font          ; (in text.asm)

        ; A .COM program owns its 64 KB segment (CS). DOS also gives it
        ; the free memory after it, so the next 64 KB (CS + 1000h) is ours.
        mov ax, cs
        add ax, 1000h
        mov [back_seg], ax
        ret

; ---------------------------------------------------------------------
; video_close : go back to normal 80x25 text mode before exiting.
; ---------------------------------------------------------------------
video_close:
        mov ax, 0003h
        int 10h
        ret

; ---------------------------------------------------------------------
; load_palette : send our RGB table to the VGA card.
;   Port 3C8h = first colour number to change,
;   Port 3C9h = then R, G, B (each 0..63) for each colour in turn.
; ---------------------------------------------------------------------
load_palette:
        push ax
        push cx
        push dx
        push si
        mov dx, 3C8h
        xor al, al              ; start at colour 0
        out dx, al
        inc dx                  ; DX = 3C9h
        mov si, palette
        mov cx, PALETTE_COUNT * 3
.next:  lodsb                   ; AL = [DS:SI], SI++
        out dx, al
        loop .next
        pop si
        pop dx
        pop cx
        pop ax
        ret

; ---------------------------------------------------------------------
; wait_vsync : wait for the start of the vertical retrace, so that
;              copying the frame does not cause tearing.
;   Bit 3 of port 3DAh is 1 while the retrace is happening.
; ---------------------------------------------------------------------
wait_vsync:
        push ax
        push dx
        mov dx, 3DAh
.in_retrace:
        in al, dx
        test al, 8
        jnz .in_retrace         ; wait for the current retrace to end
.no_retrace:
        in al, dx
        test al, 8
        jz .no_retrace          ; wait for a new retrace to begin
        pop dx
        pop ax
        ret

; ---------------------------------------------------------------------
; flip_screen : copy the back buffer to video memory (64000 bytes).
; ---------------------------------------------------------------------
flip_screen:
        push ax
        push cx
        push si
        push di
        push ds
        push es
        call wait_vsync
        mov ax, VIDEO_SEG
        mov es, ax              ; ES:DI -> screen
        mov ax, [back_seg]
        mov ds, ax              ; DS:SI -> back buffer
        xor si, si
        xor di, di
        mov cx, 32000           ; 32000 words = 64000 bytes
        cld
        rep movsw
        pop es
        pop ds
        pop di
        pop si
        pop cx
        pop ax
        ret

; ---------------------------------------------------------------------
; hline : draw a horizontal line from x1 to x2 on row y.
;   In : AX = x1, BX = x2, DX = y   (signed, may be off-screen)
;        [color] = colour
;   Parts outside the screen are cut off ("clipping"), so callers can
;   pass any numbers safely. All other shapes are built from hline.
; ---------------------------------------------------------------------
hline:
        push ax
        push bx
        push cx
        push dx
        push di
        cmp dx, 0
        jl .done                ; row above the screen
        cmp dx, SCREEN_H
        jge .done               ; row below the screen
        cmp ax, bx
        jle .ordered
        xchg ax, bx             ; make sure x1 <= x2
.ordered:
        cmp bx, 0
        jl .done                ; whole line left of the screen
        cmp ax, SCREEN_W
        jge .done               ; whole line right of the screen
        cmp ax, 0
        jge .left_ok
        xor ax, ax              ; cut at left edge
.left_ok:
        cmp bx, SCREEN_W - 1
        jle .right_ok
        mov bx, SCREEN_W - 1    ; cut at right edge
.right_ok:
        ; DI = y*320 + x1   (y*320 = y*256 + y*64)
        mov di, dx
        shl di, 6               ; y*64
        shl dx, 8               ; y*256
        add di, dx
        add di, ax
        mov cx, bx
        sub cx, ax
        inc cx                  ; number of pixels = x2 - x1 + 1
        mov al, [color]
        cld
        rep stosb               ; write CX bytes of AL to ES:DI
.done:
        pop di
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; put_pixel : one pixel.  In: AX = x, DX = y, [color]
; ---------------------------------------------------------------------
put_pixel:
        push bx
        mov bx, ax
        call hline              ; a line from x to x is one pixel
        pop bx
        ret

; ---------------------------------------------------------------------
; fill_rect : filled rectangle.
;   In : AX = x, BX = y, CX = width, DX = height, [color]
; ---------------------------------------------------------------------
fill_rect:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        cmp cx, 0
        jle .done
        cmp dx, 0
        jle .done
        mov si, ax              ; SI = left x
        add ax, cx
        dec ax
        mov di, ax              ; DI = right x
        mov cx, dx              ; CX = rows to draw
        mov dx, bx              ; DX = current row
.row:   mov ax, si
        mov bx, di
        call hline
        inc dx
        loop .row
.done:  pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; fill_circle : filled circle.  In: AX = cx, BX = cy, CX = radius
; ---------------------------------------------------------------------
fill_circle:
        push dx
        xor dx, dx              ; inner radius 0 = completely filled
        call fill_ring
        pop dx
        ret

; ---------------------------------------------------------------------
; fill_ring : a thick ring (like a steering wheel).
;   In : AX = centre x, BX = centre y, CX = outer radius,
;        DX = inner radius (0 gives a full circle), [color]
;
;   Idea: for every row dy = 0 .. outer radius we need the half width
;   of the circle on that row, i.e. the biggest x with x*x + dy*dy <= r*r.
;   As dy grows, x only gets smaller, so we start x at r and just
;   decrease it while the point (x, dy) is outside the circle.
;   We do this for the outer circle and for the inner circle, then
;   draw the part between them, above and below the centre.
; ---------------------------------------------------------------------
fill_ring:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov [ring_cx], ax
        mov [ring_cy], bx
        mov [ring_ro], cx
        mov [ring_ri], dx
        mov [ring_xo], cx       ; outer half width starts at ro
        mov [ring_xi], dx       ; inner half width starts at ri
        mov word [ring_dy], 0
.row:
        ; ---- shrink outer half width until xo^2 + dy^2 <= ro^2
.shrink_outer:
        mov ax, [ring_xo]
        mul ax
        mov si, ax              ; SI = xo^2
        mov ax, [ring_dy]
        mul ax
        add si, ax              ; SI = xo^2 + dy^2
        mov ax, [ring_ro]
        mul ax                  ; AX = ro^2
        cmp si, ax
        jbe .outer_ok
        dec word [ring_xo]
        jmp .shrink_outer
.outer_ok:
        ; ---- is this row inside the hole of the ring?
        mov ax, [ring_dy]
        cmp ax, [ring_ri]
        jae .solid_row          ; below/above the hole: full line
.shrink_inner:
        mov ax, [ring_xi]
        mul ax
        mov si, ax
        mov ax, [ring_dy]
        mul ax
        add si, ax
        mov ax, [ring_ri]
        mul ax
        cmp si, ax
        jbe .inner_ok
        dec word [ring_xi]
        jmp .shrink_inner
.inner_ok:
        ; two pieces: [cx-xo , cx-xi-1] and [cx+xi+1 , cx+xo]
        mov di, [ring_cy]
        add di, [ring_dy]       ; row below centre
        call .draw_two_parts
        mov di, [ring_cy]
        sub di, [ring_dy]       ; row above centre
        call .draw_two_parts
        jmp .next_row
.solid_row:
        mov ax, [ring_cx]
        sub ax, [ring_xo]
        mov bx, [ring_cx]
        add bx, [ring_xo]
        mov dx, [ring_cy]
        add dx, [ring_dy]
        call hline
        mov dx, [ring_cy]
        sub dx, [ring_dy]
        call hline
.next_row:
        inc word [ring_dy]
        mov ax, [ring_dy]
        cmp ax, [ring_ro]
        ja .ring_done           ; (short jump + JMP: target is far)
        jmp .row
.ring_done:
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; helper for fill_ring: draws the left and right piece on row DI
.draw_two_parts:
        mov dx, di
        mov ax, [ring_cx]
        sub ax, [ring_xo]
        mov bx, [ring_cx]
        sub bx, [ring_xi]
        dec bx
        call hline              ; left piece
        mov ax, [ring_cx]
        add ax, [ring_xi]
        inc ax
        mov bx, [ring_cx]
        add bx, [ring_xo]
        call hline              ; right piece
        ret

; ---------------------------------------------------------------------
; fill_trapezoid : shape with a flat top and flat bottom whose sides
;   are straight lines. Used for cones and the parking bay.
;   In : [tz_y1] top row,  [tz_xl1] [tz_xr1]  left/right x at the top
;        [tz_y2] bottom row, [tz_xl2] [tz_xr2] left/right x at bottom
;        [color]
;   For each row we find the x positions by linear interpolation:
;   x = x_top + (x_bottom - x_top) * (row - y1) / (y2 - y1)
; ---------------------------------------------------------------------
fill_trapezoid:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov cx, [tz_y2]
        sub cx, [tz_y1]         ; CX = height - 1 (rows between)
        jl .done
        xor si, si              ; SI = row number counted from the top
.row:
        ; left x
        mov ax, [tz_xl2]
        sub ax, [tz_xl1]
        call .interp
        add ax, [tz_xl1]
        mov di, ax              ; DI = left x for this row
        ; right x
        mov ax, [tz_xr2]
        sub ax, [tz_xr1]
        call .interp
        add ax, [tz_xr1]
        mov bx, ax
        mov ax, di
        mov dx, [tz_y1]
        add dx, si
        call hline
        inc si
        cmp si, cx
        jle .row
.done:  pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret
; AX = (AX * SI) / CX    (signed, CX = 0 gives 0)
.interp:
        cmp cx, 0
        jne .div_ok
        xor ax, ax
        ret
.div_ok:
        push dx
        imul si                 ; DX:AX = AX * SI
        idiv cx                 ; AX = DX:AX / CX
        pop dx
        ret

; ---------------------------------------------------------------------
; isqrt : integer square root.  In: AX = n.  Out: AX = floor(sqrt(n))
;   Simple method: count up while (root+1)^2 is still <= n.
; ---------------------------------------------------------------------
isqrt:
        push bx
        push cx
        push dx
        mov cx, ax              ; CX = n
        xor bx, bx              ; BX = root
.try:   mov ax, bx
        inc ax
        mul ax                  ; DX:AX = (root+1)^2
        or dx, dx
        jnz .found              ; too big for 16 bits: stop
        cmp ax, cx
        ja .found
        inc bx
        jmp .try
.found: mov ax, bx
        pop dx
        pop cx
        pop bx
        ret

; =====================================================================
;  text.asm  -  Drawing letters and numbers in graphics mode
; ---------------------------------------------------------------------
;  The VGA BIOS already contains an 8x8 pixel font. We copy it once
;  into our own memory (font_data). Each character uses 8 bytes, one
;  byte per row. In each byte, bit 7 is the leftmost pixel.
;
;  Example - the letter 'P' (1 = pixel on):
;      11111100      row 0
;      01100110      row 1
;      01100110      row 2
;      01111100      row 3
;      01100000      row 4  ... and so on
;
;  [text_scale] = 1 gives 8x8 letters, 2 gives 16x16, 3 gives 24x24.
;  [color]      = colour of the letters (background is left alone).
; =====================================================================

; ---------------------------------------------------------------------
; load_font : copy the BIOS 8x8 font (chars 0..127) into font_data.
;   INT 10h, AX=1130h, BH=03h returns ES:BP = address of the font.
; ---------------------------------------------------------------------
load_font:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        push ds
        push es
        mov ax, 1130h
        mov bh, 03h
        int 10h                 ; ES:BP -> BIOS font
        mov si, bp
        mov ax, es
        mov ds, ax              ; DS:SI -> BIOS font
        mov ax, cs
        mov es, ax
        mov di, font_data       ; ES:DI -> our copy
        mov cx, 128 * 8
        cld
        rep movsb
        pop es
        pop ds
        pop bp
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_char : draw one character.
;   In : AL = character, BX = x, DX = y, [color], [text_scale]
; ---------------------------------------------------------------------
draw_char:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        and ax, 007Fh           ; only chars 0..127 exist in our copy
        shl ax, 3               ; 8 bytes per character
        mov si, font_data
        add si, ax              ; SI -> first row of this character
        cmp byte [text_scale], 1
        je .fast                ; normal size: quick version below
        mov [ch_x], bx
        mov [ch_y], dx
        xor bp, bp              ; BP = row number 0..7
.row:
        mov ah, [si]            ; AH = bit pattern of this row
        inc si
        xor di, di              ; DI = column 0..7
.col:
        shl ah, 1               ; move leftmost bit into the carry flag
        jnc .skip               ; bit was 0 -> nothing to draw
        push ax
        ; pixel block position: x + col*scale , y + row*scale
        xor ch, ch
        mov cl, [text_scale]
        mov ax, di
        mul cx
        add ax, [ch_x]
        mov bx, ax              ; BX = block x
        mov ax, bp
        mul cx
        add ax, [ch_y]
        mov dx, ax              ; DX = block y
        mov ax, bx              ; AX = block x
        cmp cl, 1
        jne .big
        call put_pixel          ; scale 1: just one pixel (AX=x, DX=y)
        jmp .drawn
.big:   mov bx, dx              ; fill_rect wants AX=x BX=y CX=w DX=h
        mov dx, cx              ; width = height = scale
        call fill_rect
.drawn: pop ax
.skip:  inc di
        cmp di, 8
        jb .col
        inc bp
        cmp bp, 8
        jb .row
        jmp .done

        ; ---- quick version for scale 1 (most of the text).
        ;      Instead of calling put_pixel for every dot, we work out
        ;      the address once and write the bytes ourselves.
        ;      (No clipping here: our text is always fully on screen.)
.fast:  mov di, dx
        shl di, 6               ; y*64
        shl dx, 8               ; y*256
        add di, dx
        add di, bx              ; DI = y*320 + x
        mov al, [color]
        mov cx, 8               ; 8 rows
.f_row: mov ah, [si]            ; bit pattern of this row
        inc si
        push di
.f_col: shl ah, 1               ; next bit into the carry flag
        jnc .f_skip
        mov [es:di], al         ; bit was 1: one pixel
.f_skip:
        inc di
        or ah, ah
        jnz .f_col              ; stop early when no bits are left
        pop di
        add di, SCREEN_W        ; same x, next row
        loop .f_row
.done:  pop bp
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_string : draw a 0-terminated string.
;   In : SI -> string, BX = x, DX = y, [color], [text_scale]
; ---------------------------------------------------------------------
draw_string:
        push ax
        push bx
        push cx
        push si
        xor ch, ch
        mov cl, [text_scale]
        shl cx, 3               ; CX = width of one character (8*scale)
.next:  lodsb
        or al, al
        jz .done                ; 0 marks the end of the string
        call draw_char
        add bx, cx              ; move right by one character
        jmp .next
.done:  pop si
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; string_width : width in pixels of a string at the current scale.
;   In : SI -> string      Out: AX = width
; ---------------------------------------------------------------------
string_width:
        push cx
        push dx                 ; MUL below changes DX, so save it
        push si
        xor cx, cx
.count: lodsb
        or al, al
        jz .counted
        inc cx
        jmp .count
.counted:
        mov ax, cx
        shl ax, 3
        xor ch, ch
        mov cl, [text_scale]
        mul cx                  ; AX = length * 8 * scale
        pop si
        pop dx
        pop cx
        ret

; ---------------------------------------------------------------------
; draw_string_centered : draw a string centred on x = 160.
;   In : SI -> string, DX = y
; ---------------------------------------------------------------------
draw_string_centered:
        push ax
        push bx
        call string_width
        mov bx, SCREEN_W
        sub bx, ax
        sar bx, 1               ; x = (320 - width) / 2
        call draw_string
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; number_to_string : turn an unsigned number into decimal text.
;   In : AX = number, CX = minimum digits (leading zeros are added)
;   Out: SI -> 0-terminated text inside num_buf
;   Method: divide by 10 again and again; each remainder is the next
;   digit from the right.
; ---------------------------------------------------------------------
number_to_string:
        push ax
        push bx
        push cx
        push dx
        mov si, num_buf + 6
        mov byte [si], 0        ; end marker
        mov bx, 10
.digit: xor dx, dx
        div bx                  ; AX = AX / 10, DX = remainder
        add dl, '0'
        dec si
        mov [si], dl
        dec cx
        or ax, ax
        jnz .digit              ; more digits left
        cmp cx, 0
        jg .digit               ; still need leading zeros (AX is 0)
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_number : draw an unsigned number.
;   In : AX = number, CX = minimum digits, BX = x, DX = y
; ---------------------------------------------------------------------
draw_number:
        push si
        call number_to_string
        call draw_string
        pop si
        ret

; =====================================================================
;  road.asm  -  Sky, grass, the 3-lane road and the perspective maths
; ---------------------------------------------------------------------
;  Perspective in one sentence:
;     an object that is z units in front of us is drawn on screen row
;         y = HORIZON + t,   where  t = PROJ_K / z
;  So far objects (big z) are close to the horizon and near objects
;  (small z) are low on the screen.
;
;  On row t, one lane is (8 + t) pixels wide. That is why the road
;  looks narrow at the top and wide at the bottom.
;
;  [cam_x16] is the sideways position of our car in 1/16 lanes
;  (-16 = left lane, 0 = middle, +16 = right). When we move left, the
;  whole road is drawn shifted to the right, and the other way round.
; =====================================================================

; ---------------------------------------------------------------------
; project_row : world distance -> screen row offset
;   In : AX = z (must be > 0)      Out: AX = t = PROJ_K / z
; ---------------------------------------------------------------------
project_row:
        push bx
        push dx
        mov bx, ax
        mov ax, PROJ_K
        xor dx, dx              ; DX:AX = 60000
        div bx                  ; AX = 60000 / z
        pop dx
        pop bx
        ret

; ---------------------------------------------------------------------
; lane_x : where is a sideways world position on a given row?
;   In : AX = t (row offset below horizon), BX = world x in 1/16 lanes
;   Out: AX = screen x,  CX = lane width in pixels on that row (8 + t)
;   Formula: x = 160 + (worldX - cameraX) * laneWidth / 16
; ---------------------------------------------------------------------
lane_x:
        push dx
        mov cx, ax
        add cx, 8               ; CX = lane width on this row
        mov ax, bx
        sub ax, [cam_x16]       ; position relative to our car
        imul cx                 ; AX = (worldX - camX) * laneWidth
        sar ax, 4               ; divide by 16 (keeps the sign)
        add ax, SCREEN_W / 2
        pop dx
        ret

; ---------------------------------------------------------------------
; lane_to_x16 : lane number -> world x.   In: AL = lane (0,1,2)
;   Out: BX = (lane - 1) * 16   (i.e. -16, 0 or +16)
; ---------------------------------------------------------------------
lane_to_x16:
        xor bh, bh
        mov bl, al
        dec bx
        shl bx, 4
        ret

; ---------------------------------------------------------------------
; draw_sky_ground : blue sky above the horizon, green grass below.
; ---------------------------------------------------------------------
draw_sky_ground:
        push ax
        push bx
        push cx
        push dx
        mov byte [color], C_SKY
        xor ax, ax
        xor bx, bx
        mov cx, SCREEN_W
        mov dx, HORIZON
        call fill_rect
        mov byte [color], C_GRASS
        xor ax, ax
        mov bx, HORIZON
        mov cx, SCREEN_W
        mov dx, DASH_TOP - HORIZON  ; the dashboard covers the rest
        call fill_rect
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_road : draw the highway one screen row at a time.
;   For every row below the horizon we:
;     1. find the road centre and the lane width on that row,
;     2. paint the grey road (3 lanes wide),
;     3. paint the two solid white edge lines,
;     4. paint the two dashed lane lines, but only on rows whose world
;        distance falls on the "painted" part of the dash pattern.
;   [road_scroll] moves the dash pattern when the car drives, so the
;   dashes slide towards us.
; ---------------------------------------------------------------------
draw_road:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov word [rd_t], 1
.row:
        ; ---- 1. centre and lane width
        mov ax, [rd_t]
        xor bx, bx              ; world x = 0 is the road centre
        call lane_x             ; AX = centre x, CX = lane width
        mov [rd_cx], ax
        mov [rd_lw], cx
        mov si, cx
        shl si, 1
        add si, cx
        shr si, 1               ; SI = half road width = 1.5 lanes
        mov dx, [rd_t]
        add dx, HORIZON         ; DX = screen row

        ; ---- 2. grey road surface
        mov byte [color], C_ROAD
        mov ax, [rd_cx]
        sub ax, si
        mov bx, [rd_cx]
        add bx, si
        call hline

        ; line thickness grows a little towards the bottom
        mov ax, [rd_t]
        mov bl, 24
        div bl                  ; AL = t / 24
        xor ah, ah
        inc ax
        mov di, ax              ; DI = line width in pixels

        ; ---- 3. solid white edges
        mov byte [color], C_WHITE
        mov ax, [rd_cx]
        sub ax, si              ; left edge of the road
        mov bx, ax
        add bx, di
        dec bx
        call hline
        mov bx, [rd_cx]
        add bx, si              ; right edge of the road
        mov ax, bx
        sub ax, di
        inc ax
        call hline

        ; ---- 4. dashed lane lines
        cmp word [rd_t], 2
        jb .next_row            ; too close to the horizon to see
        mov ax, [rd_t]
        call project_row        ; AX = world distance of this row
        add ax, [road_scroll]
        and ax, DASH_PERIOD_MASK
        cmp ax, DASH_LENGTH
        jae .next_row           ; this row is in a gap between dashes
        mov cx, [rd_lw]
        shr cx, 1               ; CX = half lane width
        mov ax, di
        shr ax, 1               ; AX = half line width
        ; left lane line at centre - laneWidth/2
        mov bx, [rd_cx]
        sub bx, cx
        sub bx, ax
        push ax
        mov ax, bx
        add bx, di
        dec bx
        call hline
        pop ax
        ; right lane line at centre + laneWidth/2
        mov bx, [rd_cx]
        add bx, cx
        sub bx, ax
        mov ax, bx
        add bx, di
        dec bx
        call hline
.next_row:
        inc word [rd_t]
        cmp word [rd_t], DASH_TOP - HORIZON
        jae .road_done          ; (short jump + JMP: .row is far)
        jmp .row
.road_done:
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; =====================================================================
;  cars.asm  -  Drawing a car (seen from behind) in perspective
; ---------------------------------------------------------------------
;  Used for the highway traffic and for the parked cars.
;  The car is measured in 1/16 of its width (columns) and 1/16 of its
;  height (rows), so every part grows with the car:
;          ___________          rows  0..6  : roof with rear window
;         /  window   \                       (narrower at the top)
;        |[==]  ___ [==]|       rows  6..14 : body, tail lights,
;        |     |___|    |                     number plate, bumper
;        '--OO------OO--'       rows 13..16 : wheels, shadow
;  The size of the car is 3/4 of the lane width on the row where it
;  stands, so far cars are small and near cars are big. Very small
;  (far) cars are drawn as a simple box.
; =====================================================================

; ---------------------------------------------------------------------
; draw_car
;   In : AX = z (distance in front of us, world units)
;        BX = world x in 1/16 lanes (-16, 0, +16 for the lane centres)
;        CL = body colour
;   Cars that are too close (under the bonnet) or too far are skipped.
; ---------------------------------------------------------------------
draw_car:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        ; (old NASM versions only allow conditional jumps of up to
        ;  127 bytes, so for far targets we jump over a normal JMP)
        cmp ax, CAR_Z_MIN
        jae .not_too_near
        jmp .done               ; too close: hidden under the bonnet
.not_too_near:
        cmp ax, CAR_Z_MAX
        jbe .visible
        jmp .done               ; too far away to draw
.visible:
        mov [car_colour], cl
        call project_row        ; AX = t
        mov [car_bottom], ax
        add word [car_bottom], HORIZON   ; bottom row of the car
        call lane_x             ; AX = centre x, CX = lane width
        mov [car_xc], ax

        ; width = 3/4 of a lane, at least 3 pixels
        mov ax, cx
        shl ax, 1
        add ax, cx
        shr ax, 2
        cmp ax, 3
        jge .w_ok
        mov ax, 3
.w_ok:  mov [car_w], ax
        ; height = 13/16 of the width, at least 2 pixels
        mov bx, 13
        mul bx
        shr ax, 4
        cmp ax, 2
        jge .h_ok
        mov ax, 2
.h_ok:  mov [car_h], ax
        ; left = centre - width/2 ,  top = bottom - height + 1
        mov ax, [car_w]
        shr ax, 1
        mov bx, [car_xc]
        sub bx, ax
        mov [car_left], bx
        mov ax, [car_bottom]
        sub ax, [car_h]
        inc ax
        mov [car_top], ax
        cmp word [car_w], 10
        jae .detailed
        ; ---- far away: a box with two red dots
        mov al, [car_colour]
        mov [color], al
        mov ax, [car_left]
        mov bx, [car_top]
        mov cx, [car_w]
        mov dx, [car_h]
        call fill_rect
        mov byte [color], C_TAIL
        mov ax, [car_left]
        mov dx, [car_bottom]
        dec dx
        call put_pixel
        add ax, [car_w]
        dec ax
        call put_pixel
        jmp .done
.detailed:
        ; ---- shadow on the road under the car
        mov byte [color], C_SHADOW
        mov ax, [car_left]
        dec ax
        mov bx, [car_bottom]
        dec bx
        mov cx, [car_w]
        add cx, 2
        mov dx, 3
        call fill_rect
        ; ---- wheels (body covers their top)
        mov byte [color], C_WHEEL
        mov ax, 0401h           ; columns 1..4
        mov bx, 100Dh           ; rows 13..16
        call .part
        mov ax, 0F0Ch           ; columns 12..15
        call .part
        ; ---- body
        mov al, [car_colour]
        mov [color], al
        mov ax, 1000h           ; columns 0..16
        mov bx, 0E06h           ; rows 6..14
        call .part
        ; ---- roof: trapezoid, columns 3..13 at the top, 1..15 lower
        mov ax, 3
        call .col_at
        mov [tz_xl1], ax
        mov ax, 13
        call .col_at
        mov [tz_xr1], ax
        mov ax, 1
        call .col_at
        mov [tz_xl2], ax
        mov ax, 15
        call .col_at
        mov [tz_xr2], ax
        xor ax, ax
        call .row_at
        mov [tz_y1], ax
        mov ax, 6
        call .row_at
        mov [tz_y2], ax
        call fill_trapezoid
        ; ---- rear window inside the roof
        mov byte [color], C_WINDOW
        mov ax, 4
        call .col_at
        mov [tz_xl1], ax
        mov ax, 12
        call .col_at
        mov [tz_xr1], ax
        mov ax, 2
        call .col_at
        mov [tz_xl2], ax
        mov ax, 14
        call .col_at
        mov [tz_xr2], ax
        mov ax, 1
        call .row_at
        mov [tz_y1], ax
        mov ax, 6
        call .row_at
        mov [tz_y2], ax
        call fill_trapezoid
        ; ---- dark bumper
        mov byte [color], C_BUMPER
        mov ax, 1000h           ; columns 0..16
        mov bx, 0E0Ch           ; rows 12..14
        call .part
        ; ---- tail lights
        mov byte [color], C_TAIL
        mov ax, 0401h           ; columns 1..4
        mov bx, 0907h           ; rows 7..9
        call .part
        mov ax, 0F0Ch           ; columns 12..15
        call .part
        ; ---- white number plate in the middle
        mov byte [color], C_WHITE
        mov ax, 0A06h           ; columns 6..10
        mov bx, 0C09h           ; rows 9..12
        call .part
.done:
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; .part : one rectangle of the car, given in 1/16 steps.
;   In: AL = first column, AH = last column (0..16)
;       BL = first row,    BH = last row    (0..16)
.part:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov si, ax
        mov di, bx
        mov ax, si
        xor ah, ah
        call .col_at
        mov cx, ax              ; CX = left x
        mov ax, si
        mov al, ah
        xor ah, ah
        call .col_at
        sub ax, cx              ; AX = width
        jg .w_pos
        mov ax, 1
.w_pos: push ax
        mov ax, di
        xor ah, ah
        call .row_at
        mov bx, ax              ; BX = top y
        mov ax, di
        mov al, ah
        xor ah, ah
        call .row_at
        sub ax, bx
        jg .h_pos
        mov ax, 1
.h_pos: mov dx, ax              ; DX = height
        pop ax
        xchg ax, cx             ; AX = left x, CX = width
        call fill_rect
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; .col_at : AX = n (0..16) -> AX = car_left + car_w * n / 16
.col_at:
        push dx
        mul word [car_w]
        shr ax, 4
        add ax, [car_left]
        pop dx
        ret

; .row_at : AX = n (0..16) -> AX = car_top + car_h * n / 16
.row_at:
        push dx
        mul word [car_h]
        shr ax, 4
        add ax, [car_top]
        pop dx
        ret

; =====================================================================
;  traffic.asm  -  The other cars on the highway
; ---------------------------------------------------------------------
;  Every car is one 4-byte record in the table "traffic" (data.asm):
;      offset 0 : z      (word)  distance in front of us, world units
;                                (negative = behind us)
;      offset 2 : lane   (byte)  0 = left, 1 = middle, 2 = right
;      offset 3 : colour (byte)  palette colour of the body
;
;  All traffic drives forward at TRAFFIC_SPEED (40 km/h). When we are
;  faster, the cars come closer to us. The cars live on a "ring" of
;  RING_LEN units: a car that falls more than 3000 units behind us is
;  put RING_LEN units further forward, near the horizon. So the same
;  pattern of cars (traffic_pattern) repeats again and again.
;
;  When we drive slower than 40 km/h, cars come up behind us. A car
;  that reaches us in OUR lane does not drive through our car: it
;  changes to another lane and overtakes us. When it comes round the
;  ring again it gets its lane from traffic_pattern back.
; =====================================================================

CAR_REC_SIZE    equ 4
CAR_Z           equ 0
CAR_LANE        equ 2
CAR_COLOUR      equ 3

; ---------------------------------------------------------------------
; traffic_start : put the cars at their starting places.
;   Copies traffic_pattern (never changes) into traffic (moves).
; ---------------------------------------------------------------------
traffic_start:
        push ax
        push cx
        push si
        push di
        mov si, traffic_pattern
        mov di, traffic
        mov cx, TRAFFIC_COUNT * CAR_REC_SIZE / 2
.copy:  mov ax, [si]
        mov [di], ax
        add si, 2
        add di, 2
        loop .copy
        pop di
        pop si
        pop cx
        pop ax
        ret

; ---------------------------------------------------------------------
; traffic_update : move every car for one tick.
;   Each tick a car comes closer by  (our speed - traffic speed).
;   Example: we drive 100 km/h, traffic 40 km/h -> 60 units closer.
;   If we drive slower than 40, the result is negative and the cars
;   drive away from us.
; ---------------------------------------------------------------------
traffic_update:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        call player_velocity    ; AX = our speed (+ forward, - reverse)
        sub ax, TRAFFIC_SPEED   ; AX = how much closer each car comes
        mov si, traffic
        mov cx, TRAFFIC_COUNT
.next:  mov bx, [si + CAR_Z]
        sub bx, ax
        cmp bx, RING_BACK
        jge .not_behind
        add bx, RING_LEN        ; far behind us: back to the horizon
        mov di, si
        sub di, traffic         ; DI = offset of this car in the table
        mov dl, [traffic_pattern + di + CAR_LANE]
        mov [si + CAR_LANE], dl ; its lane from the pattern again
.not_behind:
        cmp bx, RING_BACK + RING_LEN
        jl .not_too_far
        sub bx, RING_LEN        ; drove away too far: put it behind us
.not_too_far:
        mov [si + CAR_Z], bx
        ; ---- is this car catching us up from behind in OUR lane?
        cmp ax, 0
        jge .no_overtake        ; we are faster: nobody catches us
        mov dl, [si + CAR_LANE]
        cmp dl, [player_lane]
        jne .no_overtake        ; other lane: it just drives past
        cmp bx, OVERTAKE_Z
        jl .no_overtake         ; still far behind us
        cmp bx, HIT_MIN
        jge .no_overtake        ; already in front of us
        ; ---- yes: move it to another lane (it overtakes us)
        mov dl, LANE_MIDDLE     ; we are on a side lane: use the middle
        cmp byte [player_lane], LANE_MIDDLE
        jne .set_lane
        mov dl, LANE_LEFT       ; we are in the middle: left or right,
        test cx, 1              ; depending on the car number
        jz .set_lane
        mov dl, LANE_RIGHT
.set_lane:
        mov [si + CAR_LANE], dl
.no_overtake:
        add si, CAR_REC_SIZE
        loop .next
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_traffic : draw all cars, the farthest one first.
;   A near car must cover a far car, so far cars are drawn first.
;   Because cars change places on the ring, we sort every frame:
;   again and again pick the car with the biggest z that is not
;   drawn yet ("selection"), draw it and mark it in drawn[].
;   Cars behind us (negative z) are skipped by draw_car.
; ---------------------------------------------------------------------
draw_traffic:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov cx, TRAFFIC_COUNT
        xor di, di
.clear: mov byte [drawn + di], 0
        inc di
        loop .clear
        mov dx, TRAFFIC_COUNT   ; DX = cars still to draw
.pick:
        mov word [best_z], -32768
        mov si, traffic
        xor di, di              ; DI = car number
.scan:  cmp byte [drawn + di], 1
        je .skip                ; already drawn
        mov ax, [si + CAR_Z]
        cmp ax, [best_z]
        jl .skip                ; nearer than the best so far
        mov [best_z], ax
        mov [best_car], si
        mov [best_index], di
.skip:  add si, CAR_REC_SIZE
        inc di
        cmp di, TRAFFIC_COUNT
        jb .scan
        ; draw the farthest remaining car and mark it
        mov di, [best_index]
        mov byte [drawn + di], 1
        mov si, [best_car]
        mov al, [si + CAR_LANE]
        call lane_to_x16        ; BX = world x of the lane
        mov cl, [si + CAR_COLOUR]
        mov ax, [si + CAR_Z]
        call draw_car
        dec dx
        jnz .pick
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; =====================================================================
;  cockpit.asm  -  Orange bonnet, dashboard panel and steering wheel
; ---------------------------------------------------------------------
;  These are drawn AFTER the road and the cars, so they cover anything
;  that is "under" our own car (this is called the painter's method:
;  things drawn later appear in front).
; =====================================================================

; ---------------------------------------------------------------------
; make_bonnet_table : work out the bonnet shape ONCE at the start.
;   The top edge is a parabola:  y = BONNET_TOP + (x-160)^2 / CURVE
;   For every row y we need the half width of the bonnet:
;       half = sqrt( (y - BONNET_TOP) * CURVE )
;   A square root is slow, and the bonnet never changes, so we keep
;   the answers in the table bonnet_half (one word per row).
; ---------------------------------------------------------------------
make_bonnet_table:
        push ax
        push cx
        push dx
        push si
        mov si, bonnet_half
        xor dx, dx              ; DX = row counted from BONNET_TOP
.row:   mov ax, dx
        mov cx, BONNET_CURVE
        push dx
        mul cx                  ; AX = row * CURVE
        pop dx
        call isqrt              ; AX = half width
        mov [si], ax
        add si, 2
        inc dx
        cmp dx, DASH_TOP - BONNET_TOP
        jb .row
        pop si
        pop dx
        pop cx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_bonnet : the orange curved bonnet (element 5).
;   For every row: read the half width from bonnet_half and draw one
;   horizontal line from 160-half to 160+half.
; ---------------------------------------------------------------------
draw_bonnet:
        push ax
        push bx
        push cx
        push dx
        push si
        mov dx, BONNET_TOP
.row:
        mov si, dx
        sub si, BONNET_TOP
        shl si, 1               ; 2 bytes per table entry
        mov si, [bonnet_half + si]  ; SI = half width of this row
        ; orange body of the bonnet
        mov byte [color], C_ORANGE
        mov ax, SCREEN_W / 2
        sub ax, si
        mov bx, SCREEN_W / 2
        add bx, si
        call hline
        ; a darker 2-pixel outline at both ends of the row
        mov byte [color], C_ORANGE_DARK
        mov ax, SCREEN_W / 2
        sub ax, si
        mov bx, ax
        inc bx
        call hline
        mov bx, SCREEN_W / 2
        add bx, si
        mov ax, bx
        dec ax
        call hline
        inc dx
        cmp dx, DASH_TOP
        jb .row
        ; darker line along the very top of the bonnet curve
        mov ax, SCREEN_W / 2 - 3
        mov bx, SCREEN_W / 2 + 3
        mov dx, BONNET_TOP
        call hline
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_dashboard : the dark panel across the bottom of the screen.
; ---------------------------------------------------------------------
draw_dashboard:
        push ax
        push bx
        push cx
        push dx
        mov byte [color], C_DASH
        xor ax, ax
        mov bx, DASH_TOP
        mov cx, SCREEN_W
        mov dx, SCREEN_H - DASH_TOP
        call fill_rect
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_wheel : steering wheel in the bottom-right corner (element 8).
;   A black ring, two horizontal spokes and a grey hub. Parts that go
;   past the screen edge are clipped automatically by hline.
; ---------------------------------------------------------------------
WHEEL_X         equ 300
WHEEL_Y         equ 187
WHEEL_R_OUT     equ 43
WHEEL_R_IN      equ 34

draw_wheel:
        push ax
        push bx
        push cx
        push dx
        mov byte [color], C_WHEEL
        mov ax, WHEEL_X
        mov bx, WHEEL_Y
        mov cx, WHEEL_R_OUT
        mov dx, WHEEL_R_IN
        call fill_ring
        ; spokes: one bar across the middle of the wheel
        mov ax, WHEEL_X - WHEEL_R_IN
        mov bx, WHEEL_Y - 7
        mov cx, 2 * WHEEL_R_IN
        mov dx, 5
        call fill_rect
        ; hub
        mov byte [color], C_HUB
        mov ax, WHEEL_X
        mov bx, WHEEL_Y
        mov cx, 12
        call fill_circle
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; =====================================================================
;  hud.asm  -  Time bar, distance & score, speed box and fuel bar
; ---------------------------------------------------------------------
;  HUD = "heads-up display": the numbers and bars drawn on top of the
;  game. Each routine only READS the game variables (time_left, fuel,
;  speed_kmh, distance, score) - it never changes them.
;  Element numbers refer to Figure 1 of the project document.
; =====================================================================

FUEL_LOW        equ 250             ; below this the fuel bar is red
HUD_TEXT_X      equ 40              ; left x of the DIST / SCORE text

; ---------------------------------------------------------------------
; draw_string_adv : draw string SI at (BX, DX) and move BX to the end
;   of the text, so the next piece can be drawn right after it.
; ---------------------------------------------------------------------
draw_string_adv:
        push ax
        call draw_string
        call string_width
        add bx, ax
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_time_bar : element 1. A tall rounded black track on the left.
;   The red part shows the time left:
;       red height = TRACK_H * time_left / TIME_MAX
; ---------------------------------------------------------------------
TBAR_X          equ 8               ; left x of the track
TBAR_W          equ 7
TBAR_TOP        equ 25              ; top of the straight part
TBAR_BOTTOM     equ 136             ; bottom of the straight part
TBAR_H          equ TBAR_BOTTOM - TBAR_TOP

draw_time_bar:
        push ax
        push bx
        push cx
        push dx
        push si
        mov byte [color], C_WHITE
        mov byte [text_scale], 1
        mov si, txt_time
        mov bx, 2
        mov dx, 12
        call draw_hud_text      ; (shadow in the original layout)
        ; ---- black track with round ends
        mov byte [color], C_BAR_BG
        mov ax, TBAR_X
        mov bx, TBAR_TOP
        mov cx, TBAR_W
        mov dx, TBAR_H
        call fill_rect
        mov ax, TBAR_X + 3
        mov bx, TBAR_TOP
        mov cx, 3
        call fill_circle
        mov bx, TBAR_BOTTOM
        call fill_circle
        ; ---- red part, growing up from the bottom
        mov ax, [time_left]
        cmp ax, 0
        jle .done
        mov cx, TBAR_H
        mul cx                  ; DX:AX = time_left * TBAR_H
        mov cx, TIME_MAX
        div cx                  ; AX = red height
        mov dx, ax              ; DX = height
        mov byte [color], C_RED
        mov bx, TBAR_BOTTOM
        sub bx, dx              ; BX = top of the red part
        mov ax, TBAR_X
        mov cx, TBAR_W
        call fill_rect
        mov ax, TBAR_X + 3      ; round red bottom end
        mov bx, TBAR_BOTTOM
        mov cx, 3
        call fill_circle
.done:  pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_dist_score : element 2.  "DIST 420 / 1000 m"  and  "SCORE 4793"
; ---------------------------------------------------------------------
draw_dist_score:
        push ax
        push bx
        push cx
        push dx
        push si
        mov byte [text_scale], 1
        mov byte [color], C_WHITE
        mov bx, HUD_TEXT_X
        mov dx, 3
        mov si, txt_dist
        call draw_hud_text
        mov ax, [distance]
        mov cx, 1
        call number_to_string   ; SI -> digits
        call draw_hud_text
        mov si, txt_dist_end
        call draw_hud_text
        ; score line in yellow
        mov byte [color], C_YELLOW
        mov bx, HUD_TEXT_X
        mov dx, 13
        mov si, txt_score
        call draw_hud_text
        mov ax, [score]
        mov cx, 1
        call number_to_string
        call draw_hud_text
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_score_only : just the score line (the parking level has no
;   distance, see Figure 2).
; ---------------------------------------------------------------------
draw_score_only:
        push ax
        push bx
        push cx
        push dx
        push si
        mov byte [text_scale], 1
        mov byte [color], C_YELLOW
        mov bx, 4               ; top-left corner, as in Figure 2
        mov dx, 2
        mov si, txt_score
        call draw_hud_text
        mov ax, [score]
        mov cx, 1
        call number_to_string
        call draw_hud_text
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_speed_box : element 6. Box with the speed as 3 yellow digits.
; ---------------------------------------------------------------------
SBOX_X          equ 97
SBOX_Y          equ 171
SBOX_W          equ 60
SBOX_H          equ 28

draw_speed_box:
        push ax
        push bx
        push cx
        push dx
        push si
        ; light border, then dark inside (1 pixel smaller on each side)
        mov byte [color], C_LIGHT_GREY
        mov ax, SBOX_X
        mov bx, SBOX_Y
        mov cx, SBOX_W
        mov dx, SBOX_H
        call fill_rect
        mov byte [color], C_BOX_BG
        mov ax, SBOX_X + 1
        mov bx, SBOX_Y + 1
        mov cx, SBOX_W - 2
        mov dx, SBOX_H - 2
        call fill_rect
        ; cut the 4 corners so the box looks rounded
        mov byte [color], C_DASH
        mov ax, SBOX_X
        mov dx, SBOX_Y
        call put_pixel
        mov dx, SBOX_Y + SBOX_H - 1
        call put_pixel
        mov ax, SBOX_X + SBOX_W - 1
        call put_pixel
        mov dx, SBOX_Y
        call put_pixel
        ; speed digits, double size, always 3 digits (e.g. 078)
        mov byte [color], C_YELLOW
        mov byte [text_scale], 2
        mov ax, [speed_kmh]
        mov cx, 3
        mov bx, SBOX_X + (SBOX_W - 48) / 2
        mov dx, SBOX_Y + 2
        call draw_number
        ; "km/h" under the digits
        mov byte [text_scale], 1
        mov byte [color], C_LIGHT_GREY
        mov si, txt_kmh
        mov bx, SBOX_X + (SBOX_W - 32) / 2
        mov dx, SBOX_Y + 19
        call draw_string
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_gear : small D (grey) or R (red) left of the speed box.
; ---------------------------------------------------------------------
draw_gear:
        push ax
        push bx
        push dx
        mov byte [text_scale], 1
        mov byte [color], C_LIGHT_GREY
        cmp byte [gear], GEAR_R
        jne .colour_ok
        mov byte [color], C_RED
.colour_ok:
        mov al, [gear]
        mov bx, SBOX_X - 11
        mov dx, SBOX_Y + 10
        call draw_char
        pop dx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_fuel_bar : element 7. "FUEL", a bar, and the letters E and F.
;   Filled width = FBAR_W * fuel / FUEL_MAX.
;   The bar is green, but red when fuel < FUEL_LOW.
; ---------------------------------------------------------------------
FBAR_X          equ 173
FBAR_Y          equ 180
FBAR_W          equ 60              ; inside width
FBAR_H          equ 9               ; inside height

draw_fuel_bar:
        push ax
        push bx
        push cx
        push dx
        push si
        mov byte [text_scale], 1
        mov byte [color], C_LIGHT_GREY
        mov si, txt_fuel
        mov bx, FBAR_X
        mov dx, FBAR_Y - 10
        call draw_string
        mov si, txt_e
        mov bx, FBAR_X
        mov dx, FBAR_Y + FBAR_H + 3
        call draw_string
        mov si, txt_f
        mov bx, FBAR_X + FBAR_W - 6
        call draw_string
        ; outline and empty inside
        mov ax, FBAR_X - 1
        mov bx, FBAR_Y - 1
        mov cx, FBAR_W + 2
        mov dx, FBAR_H + 2
        call fill_rect          ; still light grey = the border
        mov byte [color], C_BAR_BG
        mov ax, FBAR_X
        mov bx, FBAR_Y
        mov cx, FBAR_W
        mov dx, FBAR_H
        call fill_rect
        ; filled part
        mov byte [color], C_GREEN
        cmp word [fuel], FUEL_LOW
        jae .colour_ok
        mov byte [color], C_RED ; low fuel warning
.colour_ok:
        mov ax, [fuel]
        mov cx, FBAR_W
        mul cx
        mov cx, FUEL_MAX
        div cx                  ; AX = filled width
        mov cx, ax
        mov ax, FBAR_X
        mov bx, FBAR_Y
        mov dx, FBAR_H
        call fill_rect
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; =====================================================================
;  input  -  Our own keyboard interrupt handler (INT 9)
; ---------------------------------------------------------------------
;  Every time a key is pressed or released, the keyboard puts a
;  "scan code" in port 60h and the CPU runs interrupt 9:
;     pressed  : the scan code           (Up arrow = 48h)
;     released : the scan code + 80h     (Up arrow released = C8h)
;  Our handler only writes 1 (pressed) or 0 (released) into the
;  table key_down[scan code]. The game then looks at this table to
;  know which keys are HELD DOWN right now, even several at once
;  (for example Up + Left). INT 16h cannot do that: it gives one key
;  at a time and repeats a key that is held.
; =====================================================================

; ---------------------------------------------------------------------
; kb_isr : the interrupt service routine for INT 9.
;   An interrupt can happen in the middle of any instruction of the
;   game, so it must save every register it changes.
; ---------------------------------------------------------------------
kb_isr:
        push ax
        push bx
        push ds
        mov ax, cs
        mov ds, ax              ; our variables live in this segment
        in al, 60h              ; AL = scan code from the keyboard
        cmp al, 0E0h
        je .ack                 ; E0h only says "extended key": ignore
        mov bl, al
        and bx, 007Fh           ; BX = scan code without the release bit
        test al, 80h
        jnz .released
        mov byte [key_down + bx], 1     ; key went down
        jmp .ack
.released:
        mov byte [key_down + bx], 0     ; key went up
.ack:
        mov al, 20h
        out 20h, al             ; "End Of Interrupt" to the PIC
        pop ds
        pop bx
        pop ax
        iret

; ---------------------------------------------------------------------
; install_keyboard : put kb_isr in the interrupt vector table.
;   The table starts at 0000:0000. Entry n is 4 bytes at n*4:
;   first the offset, then the segment of the handler.
;   We save the old entry so we can put it back when we exit.
; ---------------------------------------------------------------------
install_keyboard:
        push ax
        push es
        xor ax, ax
        mov es, ax              ; ES = 0 -> interrupt vector table
        cli                     ; no interrupts while we change it
        mov ax, [es:9*4]
        mov [old_int9], ax      ; old offset
        mov ax, [es:9*4+2]
        mov [old_int9+2], ax    ; old segment
        mov word [es:9*4], kb_isr
        mov [es:9*4+2], cs
        sti
        pop es
        pop ax
        ret

; ---------------------------------------------------------------------
; remove_keyboard : give INT 9 back to the BIOS (before exiting).
; ---------------------------------------------------------------------
remove_keyboard:
        push ax
        push es
        xor ax, ax
        mov es, ax
        cli
        mov ax, [old_int9]
        mov [es:9*4], ax
        mov ax, [old_int9+2]
        mov [es:9*4+2], ax
        sti
        pop es
        pop ax
        ret

; =====================================================================
;  timer  -  Our own timer interrupt handler (INT 8)
; ---------------------------------------------------------------------
;  The game must run at the same speed on every computer. So we do
;  NOT move things "once per frame". Instead the timer interrupt adds
;  1 to tick_count about 73 times a second, and the main loop runs
;  one game update for every tick. A fast PC just draws more frames.
;
;  The BIOS also uses INT 8 for the DOS clock and expects 18.2 ticks
;  a second. Because our timer is 4 times faster, we call the old
;  BIOS handler only on every 4th tick.
; =====================================================================

; ---------------------------------------------------------------------
; timer_isr : the interrupt service routine for INT 8.
; ---------------------------------------------------------------------
timer_isr:
        push ax
        push ds
        mov ax, cs
        mov ds, ax
        inc word [tick_count]   ; one more game update is due
        inc byte [bios_div]
        cmp byte [bios_div], 4
        jb .own_eoi
        mov byte [bios_div], 0
        pop ds
        pop ax
        jmp far [cs:old_int8]   ; every 4th tick: BIOS handler (it sends EOI)
.own_eoi:
        mov al, 20h
        out 20h, al             ; End Of Interrupt
        pop ds
        pop ax
        iret

; ---------------------------------------------------------------------
; install_timer : hook INT 8 and speed up the timer chip (PIT).
;   Port 43h = PIT command, port 40h = channel 0 divisor (low, high).
; ---------------------------------------------------------------------
install_timer:
        push ax
        push es
        xor ax, ax
        mov es, ax
        cli
        mov ax, [es:8*4]
        mov [old_int8], ax
        mov ax, [es:8*4+2]
        mov [old_int8+2], ax
        mov word [es:8*4], timer_isr
        mov [es:8*4+2], cs
        mov al, 36h             ; channel 0, low+high byte, mode 3
        out 43h, al
        mov ax, PIT_DIVISOR
        out 40h, al             ; low byte of the divisor
        mov al, ah
        out 40h, al             ; high byte of the divisor
        sti
        pop es
        pop ax
        ret

; ---------------------------------------------------------------------
; remove_timer : normal timer speed again and the old INT 8 back.
; ---------------------------------------------------------------------
remove_timer:
        push ax
        push es
        xor ax, ax
        mov es, ax
        cli
        mov al, 36h
        out 43h, al
        xor al, al              ; divisor 0 means 65536 = normal speed
        out 40h, al
        out 40h, al
        mov ax, [old_int8]
        mov [es:8*4], ax
        mov ax, [old_int8+2]
        mov [es:8*4+2], ax
        sti
        pop es
        pop ax
        ret

; =====================================================================
;  player  -  Our car: speed, gear and lane
; ---------------------------------------------------------------------
;  speed_x16 is the speed in 1/16 km/h. Storing 16 times the speed
;  lets it grow by small steps (smooth acceleration) using only whole
;  numbers. speed_kmh = speed_x16 / 16 is what the speed box shows.
; =====================================================================

; ---------------------------------------------------------------------
; player_controls : Up = accelerate, Space = brake, no pedal = coast,
;   Down = reverse (only when the car is stopped).
; ---------------------------------------------------------------------
player_controls:
        push ax
        push bx
        mov ax, [speed_x16]
        ; ---- Up arrow: accelerate
        cmp byte [key_down + SC_UP], 1
        jne .no_up
        cmp byte [gear], GEAR_D
        je .up_drive
        or ax, ax
        jnz .no_up              ; still rolling backwards: Up waits
        mov byte [gear], GEAR_D ; stopped: shift to Drive
.up_drive:
        add ax, ACCEL
        cmp ax, [max_speed]
        jbe .no_up
        mov ax, [max_speed]     ; top speed of this level reached
.no_up:
        ; ---- Down arrow: reverse, but ONLY when the car is stopped.
        ;      Down never works as a brake.
        cmp byte [key_down + SC_DOWN], 1
        jne .no_down
        cmp byte [gear], GEAR_R
        je .down_reverse
        or ax, ax
        jnz .no_down            ; still moving forward: ignore Down
        mov byte [gear], GEAR_R ; stopped: shift to Reverse
.down_reverse:
        add ax, ACCEL
        cmp ax, MAX_REVERSE * 16
        jbe .no_down
        mov ax, MAX_REVERSE * 16
.no_down:
        ; ---- Space: brake gradually until the speed is 0
        cmp byte [key_down + SC_SPACE], 1
        jne .no_brake
        sub ax, BRAKE
        jnc .no_brake
        xor ax, ax              ; went below 0: stop at exactly 0
.no_brake:
        ; ---- no gas pedal held: the car slowly rolls to a stop
        mov bl, [key_down + SC_UP]      ; in D the gas pedal is Up
        cmp byte [gear], GEAR_R
        jne .check_gas
        mov bl, [key_down + SC_DOWN]    ; in R the gas pedal is Down
.check_gas:
        cmp bl, 1
        je .pedal_held
        sub ax, COAST
        jnc .pedal_held
        xor ax, ax
.pedal_held:
        mov [speed_x16], ax
        shr ax, 4               ; divide by 16
        mov [speed_kmh], ax     ; whole km/h for the speed box
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; player_lanes : Left / Right arrow = move one lane.
;   One key press moves only ONE lane, even if the key is held for a
;   long time. left_latch remembers that the key was already down in
;   the last tick; we only react when it changes from up to down.
;   The lane number changes at once (0..2, never outside the road),
;   but the camera (cam_x16) slides there in a few ticks, so the road
;   moves sideways smoothly on the screen.
; ---------------------------------------------------------------------
player_lanes:
        push ax
        push bx
        ; ---- indicator timers count down
        cmp word [ind_left], 0
        je .il_ok
        dec word [ind_left]
.il_ok: cmp word [ind_right], 0
        je .ir_ok
        dec word [ind_right]
.ir_ok:
        ; ---- Left arrow
        mov al, [key_down + SC_LEFT]
        cmp al, 1
        jne .left_done
        cmp byte [left_latch], 1
        je .left_done           ; same press as before: ignore
        cmp byte [player_lane], LANE_LEFT
        je .left_done           ; already in the leftmost lane
        dec byte [player_lane]
        mov word [ind_left], IND_TIME   ; left indicator flashes
.left_done:
        mov [left_latch], al
        ; ---- Right arrow
        mov al, [key_down + SC_RIGHT]
        cmp al, 1
        jne .right_done
        cmp byte [right_latch], 1
        je .right_done
        cmp byte [player_lane], LANE_RIGHT
        je .right_done          ; already in the rightmost lane
        inc byte [player_lane]
        mov word [ind_right], IND_TIME  ; right indicator flashes
.right_done:
        mov [right_latch], al
        ; ---- slide the camera towards the lane we are in
        mov al, [player_lane]
        call lane_to_x16        ; BX = where the camera should be
        mov ax, [cam_x16]
        cmp ax, bx
        je .cam_done
        jl .cam_right
        sub ax, CAM_STEP        ; camera is right of target: go left
        cmp ax, bx
        jge .cam_store
        mov ax, bx              ; do not go past the target
        jmp .cam_store
.cam_right:
        add ax, CAM_STEP        ; camera is left of target: go right
        cmp ax, bx
        jle .cam_store
        mov ax, bx
.cam_store:
        mov [cam_x16], ax
.cam_done:
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; player_velocity : AX = our speed in km/h with a sign
;   (positive = driving forward, negative = reversing).
; ---------------------------------------------------------------------
player_velocity:
        mov ax, [speed_kmh]
        cmp byte [gear], GEAR_R
        jne .forward
        neg ax                  ; reversing: negative speed
.forward:
        ret

; =====================================================================
;  gauges  -  Time, distance, score and fuel (game rules)
; =====================================================================

; ---------------------------------------------------------------------
; move_car : turn the speed into distance.
;   One world unit = distance moved in one tick at 1 km/h, so in one
;   tick the car moves exactly speed_kmh units. 262 units = 1 metre.
;   dist_acc collects the units; every 262 units = one more metre.
;   Example: at 131 km/h, every 2 ticks give one metre.
;   Score: +10 for every metre we have never reached before (so
;   reversing and driving the same metres again gives no points).
; ---------------------------------------------------------------------
move_car:
        push ax
        mov ax, [speed_kmh]
        cmp byte [gear], GEAR_R
        je .backwards
        add [road_scroll], ax   ; lane dashes slide towards us
        add [dist_acc], ax
.metre_loop:
        cmp word [dist_acc], UNITS_PER_METRE
        jb .done
        sub word [dist_acc], UNITS_PER_METRE
        inc word [distance]     ; one more metre
        mov ax, [distance]
        cmp ax, [best_distance]
        jbe .metre_loop         ; this metre already gave points
        mov [best_distance], ax
        add word [score], SCORE_PER_METRE
        jmp .metre_loop
        ; ---- reversing: distance goes down (never below 0)
.backwards:
        sub [road_scroll], ax   ; dashes slide away from us
        sub [dist_acc], ax
.back_loop:
        cmp word [dist_acc], 0
        jge .done               ; no full metre lost
        add word [dist_acc], UNITS_PER_METRE
        cmp word [distance], 0
        je .at_start
        dec word [distance]
        jmp .back_loop
.at_start:
        mov word [dist_acc], 0  ; cannot go behind the start line
.done:  pop ax
        ret

; ---------------------------------------------------------------------
; use_fuel : fuel goes down while the car moves.
;   Every tick:   fuel_acc = fuel_acc + FUEL_IDLE + speed
;   Every time fuel_acc reaches FUEL_DIV, one unit of fuel is used.
;   So at high speed the fuel goes down faster. Standing still uses
;   no fuel. (At 140 km/h a full tank lasts about 45 seconds.)
;   The fuel bar turns red by itself when fuel < FUEL_LOW (hud).
; ---------------------------------------------------------------------
use_fuel:
        push ax
        mov ax, [speed_kmh]
        or ax, ax
        jz .done                ; not moving: no fuel used
        add ax, FUEL_IDLE
        add [fuel_acc], ax
.unit_loop:
        cmp word [fuel_acc], FUEL_DIV
        jb .done
        sub word [fuel_acc], FUEL_DIV
        cmp word [fuel], 0
        je .unit_loop           ; tank already empty
        dec word [fuel]
        jmp .unit_loop
.done:  pop ax
        ret

; ---------------------------------------------------------------------
; count_down_time : one tick less on the clock (stops at 0).
; ---------------------------------------------------------------------
count_down_time:
        cmp word [time_left], 0
        je .done
        dec word [time_left]
.done:  ret

; =====================================================================
;  collisions  -  Did we drive into a traffic car?
; ---------------------------------------------------------------------
;  A traffic car hits us when it is in OUR lane and its z (distance
;  in front of the driver) is between HIT_MIN and HIT_FRONT. That is
;  exactly where a car is seen touching our bonnet on the screen.
;  Cars that are beside us or behind us (z < HIT_MIN) are not on the
;  screen, so they NEVER count as a crash: you only lose points for a
;  car you could see.
;
;  We only test while we are catching up with the traffic (our
;  forward speed is more than 40 km/h). Right after a crash we stand
;  still, so the same car can not hit us again; it simply drives away
;  and we can continue.
; =====================================================================

; ---------------------------------------------------------------------
; check_collisions : test every traffic car against our car.
; ---------------------------------------------------------------------
check_collisions:
        push ax
        push bx
        push cx
        push si
        cmp word [crash_timer], 0
        je .timer_ok
        dec word [crash_timer]  ; CRASH text shows a bit less long
.timer_ok:
        call player_velocity
        cmp ax, TRAFFIC_SPEED
        jle .done               ; not catching up with anybody
        mov si, traffic
        mov cx, TRAFFIC_COUNT
.next:  mov al, [si + CAR_LANE]
        cmp al, [player_lane]
        jne .skip               ; other lane: no crash
        mov bx, [si + CAR_Z]
        cmp bx, HIT_MIN
        jl .skip                ; beside or behind us: not visible
        cmp bx, HIT_FRONT
        jge .skip
        call crash              ; car is touching us
        jmp .done
.skip:  add si, CAR_REC_SIZE
        loop .next
.done:  pop si
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; crash : stop the car and take away CRASH_PENALTY points.
; ---------------------------------------------------------------------
crash:
        push ax
        mov word [speed_x16], 0
        mov word [speed_kmh], 0
        mov ax, [score]
        sub ax, CRASH_PENALTY
        jnc .score_ok
        xor ax, ax              ; score never goes below 0
.score_ok:
        mov [score], ax
        mov word [crash_timer], CRASH_SHOW
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_crash_message : big red "CRASH! -50" for 2 seconds.
; ---------------------------------------------------------------------
draw_crash_message:
        cmp word [crash_timer], 0
        je .done
        push dx
        push si
        mov byte [color], C_RED
        mov byte [text_scale], 2
        mov si, txt_crash
        mov dx, 40
        call draw_string_centered
        mov byte [text_scale], 1
        pop si
        pop dx
.done:  ret

; =====================================================================
;  highway.asm  -  Level 1: the highway screen
; ---------------------------------------------------------------------
;  highway_start  : sets all values for a new game
;  draw_mirror    : rear-view mirror with the cars behind us
;  highway_update : one game step (called once per timer tick)
;  draw_highway_frame : draws the picture. Order matters (painter's
;  method): background, road, cars, our own car, then the HUD.
; =====================================================================

; ---------------------------------------------------------------------
; highway_start : reset everything for a fresh highway level.
; ---------------------------------------------------------------------
highway_start:
        mov word [max_speed], MAX_SPEED * 16
        mov word [time_left], TIME_MAX
        mov word [tick_count], 0
        mov word [speed_x16], 0
        mov word [speed_kmh], 0
        mov word [distance], 0
        mov word [best_distance], 0
        mov word [dist_acc], 0
        mov word [score], 0
        mov word [road_scroll], 0
        mov byte [player_lane], LANE_MIDDLE
        mov word [cam_x16], 0
        mov byte [left_latch], 1    ; ignore keys that are already held
        mov byte [right_latch], 1
        call traffic_start
        mov word [ind_left], 0
        mov word [ind_right], 0
        mov byte [gear], GEAR_D
        mov word [crash_timer], 0
        mov word [fuel], FUEL_MAX
        mov word [fuel_acc], 0
        mov byte [hw_state], STATE_PLAYING
        ret

; ---------------------------------------------------------------------
; highway_update : one game step. Called once for every timer tick.
; ---------------------------------------------------------------------
highway_update:
        cmp byte [key_down + SC_ESC], 1
        jne .no_esc
        call go_menu            ; ESC: leave the level
        ret
.no_esc:
        cmp byte [hw_state], STATE_ENDED
        jne .playing
        call end_screen_keys    ; level over: only wait for ENTER
        ret
.playing:
        call player_controls    ; read the pedals
        call player_lanes       ; lane changes
        call move_car           ; distance, score, road movement
        call traffic_update     ; other cars move
        call check_collisions   ; crash?
        call use_fuel           ; fuel goes down
        call count_down_time
        call check_level_end    ; 1000 m, time up or no fuel?
        ret

; ---------------------------------------------------------------------
; check_level_end : has the level finished?
;   1. distance reached 1000 m -> success (distance stays exactly 1000)
;   2. time_left is 0         -> "TIME UP"
;   3. fuel is 0              -> "NO FUEL"
; ---------------------------------------------------------------------
check_level_end:
        push ax
        cmp word [distance], LEVEL_DISTANCE
        jb .not_finished
        mov word [distance], LEVEL_DISTANCE
        mov al, MSG_WIN
        jmp .end_level
.not_finished:
        cmp word [time_left], 0
        jne .time_ok
        mov al, MSG_TIME
        jmp .end_level
.time_ok:
        cmp word [fuel], 0
        jne .done
        mov al, MSG_FUEL
.end_level:
        mov [end_msg], al
        mov byte [hw_state], STATE_ENDED
        mov word [speed_x16], 0 ; the car stops
        mov word [speed_kmh], 0
.done:  pop ax
        ret

; ---------------------------------------------------------------------
; draw_end_message : the box shown when the level has ended.
; ---------------------------------------------------------------------
MBOX_X          equ 40
MBOX_Y          equ 55
MBOX_W          equ 240
MBOX_H          equ 82

draw_end_message:
        cmp byte [hw_state], STATE_ENDED
        je .show
        ret
.show:  push ax
        push bx
        push cx
        push dx
        push si
        push di
        ; box: light border, dark inside
        mov byte [color], C_LIGHT_GREY
        mov ax, MBOX_X
        mov bx, MBOX_Y
        mov cx, MBOX_W
        mov dx, MBOX_H
        call fill_rect
        mov byte [color], C_PANEL
        mov ax, MBOX_X + 2
        mov bx, MBOX_Y + 2
        mov cx, MBOX_W - 4
        mov dx, MBOX_H - 4
        call fill_rect
        ; choose the two text lines for this ending
        mov si, txt_win_1
        mov di, txt_win_2
        mov byte [color], C_GREEN
        cmp byte [end_msg], MSG_WIN
        je .write
        mov si, txt_timeup_1
        mov di, txt_timeup_2
        mov byte [color], C_RED
        cmp byte [end_msg], MSG_TIME
        je .write
        mov si, txt_park_1
        mov di, txt_park_2
        mov byte [color], C_GREEN
        cmp byte [end_msg], MSG_PARKED
        je .write
        mov byte [color], C_RED
        mov si, txt_nofuel_1
        mov di, txt_nofuel_2
.write: mov byte [text_scale], 2
        mov dx, MBOX_Y + 8
        call draw_string_centered       ; big title
        mov byte [text_scale], 1
        mov byte [color], C_WHITE
        mov si, di
        mov dx, MBOX_Y + 32
        call draw_string_centered       ; explanation
        ; "SCORE 1234"
        mov byte [color], C_YELLOW
        mov si, txt_score
        mov bx, 120
        mov dx, MBOX_Y + 48
        call draw_string_adv
        mov ax, [score]
        mov cx, 1
        call number_to_string
        call draw_string_adv
        mov byte [color], C_LIGHT_GREY
        mov si, txt_again
        mov dx, MBOX_Y + 66
        call draw_string_centered
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; end_screen_keys : after the level ended, ENTER goes to the menu.
;   If nobody presses ENTER, we go back by ourselves after 8 seconds.
; ---------------------------------------------------------------------
end_screen_keys:
        inc word [end_timer]
        cmp word [end_timer], END_WAIT
        jae .back               ; waited long enough
        cmp byte [key_down + SC_ENTER], 1
        jne .wait
.back:  call go_menu
.wait:  ret

; ---------------------------------------------------------------------
; draw_mirror : rear-view mirror at the top of the screen.
;   Every traffic car with z between -MIR_RANGE and 0 is behind us.
;   For such a car, d = -z is how far behind it is:
;     size   = 16 - d * 10 / MIR_RANGE    (16 px near, 6 px far)
;     bottom = lower in the glass when it is near
;     x      = centre + (its lane - our lane) * size * 5/4
;   (left lanes appear on the left, like in a real mirror).
;   We see the FRONT of these cars: windscreen and yellow headlights.
; ---------------------------------------------------------------------
draw_mirror:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        ; ---- black frame, sky and road in the glass
        mov byte [color], C_WHEEL
        mov ax, MIR_X - 2
        mov bx, MIR_Y - 2
        mov cx, MIR_W + 4
        mov dx, MIR_H + 4
        call fill_rect
        mov byte [color], C_SKY
        mov ax, MIR_X
        mov bx, MIR_Y
        mov cx, MIR_W
        mov dx, 6
        call fill_rect
        mov byte [color], C_ROAD
        mov bx, MIR_Y + 6
        mov dx, MIR_H - 6
        call fill_rect
        ; ---- cars behind us
        mov si, traffic
        mov cx, TRAFFIC_COUNT
.next:  push cx
        mov ax, [si + CAR_Z]
        cmp ax, 0
        jle .is_behind
        jmp .skip               ; in front of us: not in the mirror
.is_behind:
        neg ax                  ; AX = distance behind us
        cmp ax, MIR_RANGE
        jb .in_range
        jmp .skip               ; too far behind
.in_range:
        mov di, ax              ; DI = distance
        ; size = 16 - d * 10 / MIR_RANGE
        mov bx, 10
        mul bx
        mov bx, MIR_RANGE
        div bx
        mov bx, 16
        sub bx, ax
        mov [mr_w], bx
        shr bx, 1
        mov [mr_h], bx          ; height = size / 2
        ; bottom row = MIR_Y + MIR_H - 1 - d * (MIR_H - 7) / MIR_RANGE
        mov ax, di
        mov bx, MIR_H - 7
        mul bx
        mov bx, MIR_RANGE
        div bx
        mov bx, MIR_Y + MIR_H
        sub bx, ax
        sub bx, [mr_h]
        mov [mr_y], bx          ; top row of the car
        ; x = centre + (lane - our lane) * size * 5/4 - size/2
        mov al, [si + CAR_LANE]
        sub al, [player_lane]
        cbw                     ; AX = lane difference (-2..2)
        mov bx, [mr_w]
        mov cx, bx
        shr cx, 2
        add bx, cx              ; BX = size * 5/4 (one lane)
        imul bx
        add ax, MIR_X + MIR_W / 2
        mov bx, [mr_w]
        shr bx, 1
        sub ax, bx
        mov [mr_x], ax          ; left x of the car
        ; ---- body
        mov dl, [si + CAR_COLOUR]
        mov [color], dl
        mov ax, [mr_x]
        mov bx, [mr_y]
        mov cx, [mr_w]
        mov dx, [mr_h]
        call mirror_box
        ; ---- windscreen (upper half, a bit narrower)
        mov byte [color], C_WINDOW
        mov ax, [mr_x]
        inc ax
        mov cx, [mr_w]
        sub cx, 2
        mov dx, [mr_h]
        shr dx, 1
        call mirror_box
        ; ---- two yellow headlights at the bottom corners
        mov byte [color], C_YELLOW
        mov ax, [mr_x]
        mov bx, [mr_y]
        add bx, [mr_h]
        dec bx
        mov cx, [mr_w]
        shr cx, 2
        mov dx, 1
        call mirror_box
        add ax, [mr_w]
        sub ax, cx
        call mirror_box
.skip:  pop cx
        add si, CAR_REC_SIZE
        dec cx
        jz .done
        jmp .next
.done:  pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; mirror_box : fill_rect, but cut to the glass of the mirror.
;   In: AX = x, BX = y, CX = width, DX = height, [color]
; ---------------------------------------------------------------------
mirror_box:
        push ax
        push bx
        push cx
        push dx
        cmp ax, MIR_X           ; cut on the left
        jge .left_ok
        add cx, ax
        sub cx, MIR_X
        mov ax, MIR_X
.left_ok:
        push ax                 ; cut on the right
        add ax, cx
        cmp ax, MIR_X + MIR_W
        pop ax
        jle .right_ok
        mov cx, MIR_X + MIR_W
        sub cx, ax
.right_ok:
        cmp bx, MIR_Y           ; cut at the top
        jge .top_ok
        add dx, bx
        sub dx, MIR_Y
        mov bx, MIR_Y
.top_ok:
        push bx                 ; cut at the bottom
        add bx, dx
        cmp bx, MIR_Y + MIR_H
        pop bx
        jle .bottom_ok
        mov dx, MIR_Y + MIR_H
        sub dx, bx
.bottom_ok:
        call fill_rect          ; does nothing if width/height <= 0
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_highway_frame : build one complete picture in the back buffer.
; ---------------------------------------------------------------------
draw_highway_frame:
        call draw_background    ; sky and grass, or the city
        call draw_road          ; element 3: road and lane lines
        call draw_traffic       ; element 4: traffic cars
        call draw_bonnet        ; element 5: orange bonnet
        call draw_dashboard
        call draw_instruments   ; elements 6, 7, 8 (depends on layout)
        call draw_time_bar      ; element 1
        call draw_dist_score    ; element 2
        call draw_mirror        ; cars behind us
        call draw_crash_message
        call draw_end_message   ; only when the level has ended
        ret


; =====================================================================
;  menu  -  The start menu and switching between game modes
; ---------------------------------------------------------------------
;  game_mode says what the game is doing right now:
;     MODE_MENU    : the start menu is shown
;     MODE_HIGHWAY : level 1 (highway)
;     MODE_PARKING : level 2 (parking)
;  The main loop always calls game_update and game_draw. These only
;  look at game_mode and call the routine of the current mode.
;  Keys 1 and 2 are checked only in menu_update, so they only work
;  while the menu is on the screen.
; =====================================================================

; ---------------------------------------------------------------------
; game_update : one game step for the current mode.
; ---------------------------------------------------------------------
game_update:
        cmp byte [game_mode], MODE_HIGHWAY
        jne .not_highway
        call highway_update
        ret
.not_highway:
        cmp byte [game_mode], MODE_PARKING
        jne .not_parking
        call parking_update
        ret
.not_parking:
        call menu_update
        ret

; ---------------------------------------------------------------------
; game_draw : draw the picture for the current mode.
; ---------------------------------------------------------------------
game_draw:
        cmp byte [game_mode], MODE_HIGHWAY
        jne .not_highway
        call draw_highway_frame
        ret
.not_highway:
        cmp byte [game_mode], MODE_PARKING
        jne .not_parking
        call draw_parking_frame
        ret
.not_parking:
        call draw_menu
        ret

; ---------------------------------------------------------------------
; go_menu : back to the start menu (level ended, or ESC pressed).
; ---------------------------------------------------------------------
go_menu:
        mov byte [game_mode], MODE_MENU
        mov byte [esc_latch], 1 ; ESC must be let go before it quits
        mov word [cam_x16], 0   ; road straight behind the menu
        mov word [end_timer], 0 ; ready for the next level's ending
        ret

; ---------------------------------------------------------------------
; menu_update : ESC = quit to DOS, 1 = highway, 2 = parking.
; ---------------------------------------------------------------------
menu_update:
        push ax
        add word [road_scroll], 30      ; road keeps moving behind the menu
        ; ---- ESC quits, but only on a NEW press (see go_menu)
        mov al, [key_down + SC_ESC]
        cmp al, 1
        jne .esc_done
        cmp byte [esc_latch], 1
        je .esc_done
        mov byte [quit_flag], 1
.esc_done:
        mov [esc_latch], al
        ; ---- key B: switch the layout (once per press)
        mov al, [key_down + SC_B]
        cmp al, 1
        jne .b_done
        cmp byte [b_latch], 1
        je .b_done
        xor byte [layout], 1    ; 0 -> 1 and 1 -> 0
.b_done:
        mov [b_latch], al
        ; ---- key 1: highway
        cmp byte [key_down + SC_1], 1
        jne .no_1
        call highway_start
        mov byte [game_mode], MODE_HIGHWAY
.no_1:
        ; ---- key 2: parking
        cmp byte [key_down + SC_2], 1
        jne .no_2
        call parking_start
        mov byte [game_mode], MODE_PARKING
.no_2:
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_menu : moving road in the background, title and the choices.
; ---------------------------------------------------------------------
MENU_X          equ 40
MENU_Y          equ 44
MENU_W          equ 240
MENU_H          equ 98

draw_menu:
        push ax
        push bx
        push cx
        push dx
        push si
        call draw_sky_ground
        call draw_road
        call draw_bonnet
        call draw_dashboard
        call draw_wheel
        ; ---- title
        mov byte [color], C_YELLOW
        mov byte [text_scale], 2
        mov si, txt_title
        mov dx, 14
        call draw_string_centered
        mov byte [text_scale], 1
        ; ---- panel: light border, dark inside
        mov byte [color], C_LIGHT_GREY
        mov ax, MENU_X
        mov bx, MENU_Y
        mov cx, MENU_W
        mov dx, MENU_H
        call fill_rect
        mov byte [color], C_PANEL
        mov ax, MENU_X + 2
        mov bx, MENU_Y + 2
        mov cx, MENU_W - 4
        mov dx, MENU_H - 4
        call fill_rect
        ; ---- choices
        mov byte [color], C_YELLOW
        mov bx, MENU_X + 16
        mov si, txt_menu_1
        mov dx, MENU_Y + 10
        call draw_string
        mov si, txt_menu_2
        mov dx, MENU_Y + 22
        call draw_string
        mov si, txt_menu_b      ; "B   LAYOUT: " + SIMPLE / ORIGINAL
        mov dx, MENU_Y + 34
        call draw_string_adv
        mov si, txt_simple
        cmp byte [layout], LAYOUT_ORIGINAL
        jne .layout_name
        mov si, txt_original
.layout_name:
        call draw_string
        mov byte [color], C_LIGHT_GREY
        mov bx, MENU_X + 16
        mov si, txt_menu_esc
        mov dx, MENU_Y + 46
        call draw_string
        ; ---- controls
        mov bx, MENU_X + 12
        mov si, txt_help_1
        mov dx, MENU_Y + 60
        call draw_string
        mov si, txt_help_2
        mov dx, MENU_Y + 72
        call draw_string
        mov si, txt_help_3
        mov dx, MENU_Y + 84
        call draw_string
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; =====================================================================
;  parking  -  Level 2: park the car in the marked bay
; ---------------------------------------------------------------------
;  The parking lot uses the same 3 lanes and the same perspective as
;  the highway. park_z is how far along the lot our car (the driver)
;  is. Everything in the lot has a fixed place z along the lot, so on
;  the screen it is (z - park_z) units in front of us.
;  The bay is in the middle lane, from BAY_START to BAY_END.
; =====================================================================

; ---------------------------------------------------------------------
; parking_start : set everything for a fresh parking level.
; ---------------------------------------------------------------------
parking_start:
        mov word [max_speed], PARK_MAX_SPEED * 16
        mov word [park_z], PARK_START_Z
        mov byte [player_lane], LANE_MIDDLE
        mov word [cam_x16], 0
        mov byte [left_latch], 1
        mov byte [right_latch], 1
        mov word [ind_left], 0
        mov word [ind_right], 0
        mov word [speed_x16], 0
        mov word [speed_kmh], 0
        mov byte [gear], GEAR_D
        mov word [time_left], TIME_MAX
        mov word [fuel], FUEL_MAX
        mov word [fuel_acc], 0
        mov word [score], PARK_SCORE
        mov word [crash_timer], 0
        mov byte [hw_state], STATE_PLAYING
        mov word [tick_count], 0
        mov word [park_hold], 0
        call park_sensor        ; correct reading from the first frame
        ret

; ---------------------------------------------------------------------
; parking_update : one game step of the parking level.
; ---------------------------------------------------------------------
parking_update:
        cmp byte [key_down + SC_ESC], 1
        jne .no_esc
        call go_menu            ; ESC: leave the level
        ret
.no_esc:
        cmp byte [hw_state], STATE_ENDED
        jne .playing
        call end_screen_keys    ; level over: wait for ENTER
        ret
.playing:
        mov al, [player_lane]
        mov [old_lane], al
        call player_controls    ; Up, Space, Down (same as highway)
        call player_lanes       ; Left, Right (same as highway)
        ; ---- changed into a lane where something is standing?
        mov ax, [park_z]
        mov bl, [player_lane]
        call park_overlap
        jnc .lane_ok
        mov al, [old_lane]
        mov [player_lane], al   ; stay in the old lane
        call park_crash
.lane_ok:
        ; ---- move, and undo the move if we drove into something
        mov ax, [park_z]
        mov [old_z], ax
        call park_move
        mov ax, [park_z]
        mov bl, [player_lane]
        call park_overlap
        jnc .move_ok
        mov ax, [old_z]
        mov [park_z], ax        ; back to where we were
        call park_crash
.move_ok:
        cmp word [crash_timer], 0
        je .timer_ok
        dec word [crash_timer]
.timer_ok:
        call use_fuel
        call count_down_time
        call park_sensor        ; measure the nearest gap
        call check_park_end     ; parked? time up? no fuel?
        ret

; ---------------------------------------------------------------------
; park_move : move our car along the lot by its speed.
;   player_velocity is + when driving forward and - when reversing,
;   in world units per tick, so we simply add it to park_z.
;   At the walls of the lot the car stops.
; ---------------------------------------------------------------------
park_move:
        push ax
        call player_velocity
        add ax, [park_z]
        cmp ax, PARK_Z_MIN
        jge .min_ok
        mov ax, PARK_Z_MIN      ; back wall: stop here
        mov word [speed_x16], 0
        mov word [speed_kmh], 0
.min_ok:
        cmp ax, PARK_Z_MAX
        jle .max_ok
        mov ax, PARK_Z_MAX      ; far wall: stop here
        mov word [speed_x16], 0
        mov word [speed_kmh], 0
.max_ok:
        mov [park_z], ax
        pop ax
        ret

; ---------------------------------------------------------------------
; park_overlap : would our car touch something?
;   In : AX = park_z to test, BL = lane to test
;   Out: carry flag = 1 if it overlaps a car or a cone.
;   Our car covers  park_z - CAR_BACK  ..  park_z + CAR_FRONT.
;   Two pieces overlap when each one starts before the other ends.
; ---------------------------------------------------------------------
park_overlap:
        push cx
        push dx
        push si
        push di
        mov dx, ax
        add dx, CAR_FRONT       ; DX = our front
        mov di, ax
        sub di, CAR_BACK        ; DI = our back
        mov si, park_objects
        mov cx, PARK_OBJ_COUNT
.next:  cmp [si + OBJ_LANE], bl
        jne .skip               ; other lane: cannot touch
        cmp dx, [si + OBJ_ZS]
        jle .skip               ; our front is before the object
        cmp di, [si + OBJ_ZE]
        jge .skip               ; our back is past the object
        stc                     ; overlap!
        jmp .done
.skip:  add si, OBJ_SIZE
        loop .next
        clc                     ; no overlap
.done:  pop di
        pop si
        pop dx
        pop cx
        ret

; ---------------------------------------------------------------------
; park_crash : we touched a car or a cone.
;   The car stops. Points are taken only once per 2 seconds, so
;   pushing against the same car does not take 50 points every tick.
; ---------------------------------------------------------------------
park_crash:
        cmp word [crash_timer], 0
        je .new_crash
        mov word [speed_x16], 0
        mov word [speed_kmh], 0
        ret
.new_crash:
        call crash              ; stop, -50 points, "CRASH" text
        ret

; ---------------------------------------------------------------------
; draw_park_objects : draw the cars and cones, the farthest first
;   (same "pick the farthest not drawn yet" method as draw_traffic).
; ---------------------------------------------------------------------
draw_park_objects:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov cx, PARK_OBJ_COUNT
        xor di, di
.clear: mov byte [obj_drawn + di], 0
        inc di
        loop .clear
        mov dx, PARK_OBJ_COUNT  ; DX = objects still to draw
.pick:  mov word [best_z], -32768
        mov si, park_objects
        xor di, di
.scan:  cmp byte [obj_drawn + di], 1
        je .skip
        mov ax, [si + OBJ_ZS]
        cmp ax, [best_z]
        jl .skip
        mov [best_z], ax
        mov [best_car], si
        mov [best_index], di
.skip:  add si, OBJ_SIZE
        inc di
        cmp di, PARK_OBJ_COUNT
        jb .scan
        mov di, [best_index]
        mov byte [obj_drawn + di], 1
        mov si, [best_car]
        mov al, [si + OBJ_X16]
        cbw                     ; signed byte -> signed word
        mov bx, ax              ; BX = world x
        mov ax, [si + OBJ_ZS]
        sub ax, [park_z]        ; AX = distance in front of us
        cmp byte [si + OBJ_KIND], KIND_CONE
        je .cone
        mov cl, [si + OBJ_COLOUR]
        call draw_car
        jmp .drawn
.cone:  call draw_cone
.drawn: dec dx
        jz .all_done
        jmp .pick
.all_done:
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_cone : orange traffic cone with a white stripe.
;   In : AX = z (distance in front of us), BX = world x
;   Width = a quarter lane, height = 1.5 x width. The width grows evenly
;   from 0 at the tip to full at the bottom, so we draw 3 trapezoids
;   on top of each other: orange tip, white stripe, orange bottom.
; ---------------------------------------------------------------------
draw_cone:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        cmp ax, CAR_Z_MIN
        jb .done
        cmp ax, CAR_Z_MAX
        ja .done
        call project_row        ; AX = t
        mov dx, ax
        add dx, HORIZON         ; DX = bottom row of the cone
        call lane_x             ; AX = centre x, CX = lane width
        mov [cone_x], ax
        shr cx, 3               ; half of the width = lane / 8
        cmp cx, 2
        jge .hw_ok
        mov cx, 2
.hw_ok: mov [cone_hw], cx
        mov [cone_top], dx      ; keep the bottom row (MUL changes DX)
        mov ax, cx
        mul word [three]        ; height = 3 * half width
        mov [cone_h], ax
        sub [cone_top], ax
        inc word [cone_top]     ; top row = bottom - height + 1
        ; ---- the 3 parts (rows counted from the tip)
        mov byte [color], C_CONE
        xor si, si
        mov di, [cone_h]
        shr di, 1               ; tip: rows 0 .. h/2
        call .part
        mov byte [color], C_WHITE
        mov si, di
        mov ax, [cone_h]
        shr ax, 2
        add di, ax              ; stripe: h/4 rows
        call .part
        mov byte [color], C_CONE
        mov si, di
        mov di, [cone_h]
        dec di                  ; bottom part down to the base
        call .part
.done:  pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; .part : trapezoid of the cone from row SI to row DI (from the tip).
;   half width at row r = cone_hw * r / cone_h
.part:
        mov ax, [cone_hw]
        mul si
        div word [cone_h]
        mov bx, [cone_x]
        sub bx, ax
        mov [tz_xl1], bx
        mov bx, [cone_x]
        add bx, ax
        mov [tz_xr1], bx
        mov ax, [cone_hw]
        mul di
        div word [cone_h]
        mov bx, [cone_x]
        sub bx, ax
        mov [tz_xl2], bx
        mov bx, [cone_x]
        add bx, ax
        mov [tz_xr2], bx
        mov ax, [cone_top]
        add ax, si
        mov [tz_y1], ax
        mov ax, [cone_top]
        add ax, di
        mov [tz_y2], ax
        call fill_trapezoid
        ret

; ---------------------------------------------------------------------
; park_sensor : distance from our car to the nearest object in our
;   lane, in front of us OR behind us.
;      in front : object start - our front  = OBJ_ZS - (park_z+CAR_FRONT)
;      behind   : our back - object end     = (park_z-CAR_BACK) - OBJ_ZE
;   The smallest gap is kept in sensor_gap (world units), and also
;   in decimetres in sensor_dm (shown as metres with one decimal).
; ---------------------------------------------------------------------
park_sensor:
        push ax
        push bx
        push cx
        push dx
        push si
        mov word [sensor_gap], 32767    ; "nothing found" = very far
        mov dx, [park_z]
        add dx, CAR_FRONT       ; DX = our front
        mov bx, [park_z]
        sub bx, CAR_BACK        ; BX = our back
        mov si, park_objects
        mov cx, PARK_OBJ_COUNT
.next:  mov al, [si + OBJ_LANE]
        cmp al, [player_lane]
        jne .skip               ; only our lane
        mov ax, [si + OBJ_ZS]
        sub ax, dx              ; gap to an object in front
        jge .compare
        mov ax, bx
        sub ax, [si + OBJ_ZE]   ; gap to an object behind
        jl .skip
.compare:
        cmp ax, [sensor_gap]
        jge .skip
        mov [sensor_gap], ax    ; nearest so far
.skip:  add si, OBJ_SIZE
        loop .next
        ; ---- decimetres = units * 10 / 262  (shown up to 9.9 m)
        mov ax, [sensor_gap]
        cmp ax, 2594            ; 2594 units = 9.9 m
        jbe .in_range
        mov ax, 2594
.in_range:
        mov cx, 10
        mul cx
        mov cx, UNITS_PER_METRE
        div cx
        mov [sensor_dm], ax
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_sensor : "SENSOR 0.8 m" and a bar of 8 lights.
;   lights on = 8 - (distance in dm) / 6, at least 1
;   (every 0.6 m closer turns on one more light).
;   Lights 1-3 are green, 4-5 yellow, 6-8 red, so the bar changes
;   from green to yellow to red as we get closer.
; ---------------------------------------------------------------------
draw_sensor:
        push ax
        push bx
        push cx
        push dx
        push si
        ; ---- how many lights are on?
        mov ax, [sensor_dm]
        mov bl, 6
        div bl                  ; AL = dm / 6
        xor ah, ah
        mov cx, 8
        sub cx, ax
        cmp cx, 1
        jge .lit_ok
        mov cx, 1
.lit_ok:
        mov [sensor_lit], cx
        mov byte [color], C_WHITE
        ; ---- put the digits into "SENSOR 0.0 m"
        mov ax, [sensor_dm]
        mov bl, 10
        div bl                  ; AL = metres, AH = tenths
        add al, '0'
        mov [sensor_txt + 7], al
        add ah, '0'
        mov [sensor_txt + 9], ah
        mov byte [text_scale], 1
        mov si, sensor_txt
        mov dx, SENSOR_Y
        call draw_string_centered
        ; ---- the 8 lights
        xor si, si              ; SI = light number 0..7
.light: mov byte [color], C_DIM ; off
        cmp si, [sensor_lit]
        jae .off
        mov al, [seg_colours + si]
        mov [color], al         ; on: its own colour
.off:   mov ax, si
        mov bl, SEG_STEP
        mul bl
        add ax, SEG_X           ; AX = x of this light
        mov bx, SENSOR_Y + 10
        mov cx, SEG_STEP - 2
        mov dx, 5
        call fill_rect
        inc si
        cmp si, 8
        jb .light
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; check_park_end : parked, time up or no fuel?
;   We are parked when ALL of these are true for half a second:
;     1. we are in the middle lane (the lane of the bay),
;     2. the speed is exactly 0,
;     3. the WHOLE car is inside the bay:
;          back  = park_z - CAR_BACK   >= BAY_START   and
;          front = park_z + CAR_FRONT  <= BAY_END,
;     4. nothing touches us: nearest object >= TOUCH_GAP away.
;   Just touching the bay is not enough (rule 3), and rolling
;   through the bay is not enough (rules 2 and the half second).
; ---------------------------------------------------------------------
check_park_end:
        push ax
        push cx
        push dx
        cmp byte [player_lane], LANE_MIDDLE
        jne .not_parked
        cmp word [speed_x16], 0
        jne .not_parked
        mov ax, [park_z]
        sub ax, CAR_BACK
        cmp ax, BAY_START
        jl .not_parked          ; back of the car outside the bay
        mov ax, [park_z]
        add ax, CAR_FRONT
        cmp ax, BAY_END
        jg .not_parked          ; front of the car outside the bay
        cmp word [sensor_gap], TOUCH_GAP
        jl .not_parked          ; touching a car
        inc word [park_hold]
        cmp word [park_hold], PARK_HOLD
        jb .check_time
        ; ---- success: +10 points for every second left
        mov ax, [time_left]
        xor dx, dx
        mov cx, TICKS_PER_SEC
        div cx                  ; AX = seconds left
        mov cx, 10
        mul cx
        add [score], ax
        mov al, MSG_PARKED
        jmp .end_level
.not_parked:
        mov word [park_hold], 0
.check_time:
        cmp word [time_left], 0
        jne .time_ok
        mov al, MSG_TIME
        jmp .end_level
.time_ok:
        cmp word [fuel], 0
        jne .done
        mov al, MSG_FUEL
.end_level:
        mov [end_msg], al
        mov byte [hw_state], STATE_ENDED
        mov word [speed_x16], 0
        mov word [speed_kmh], 0
.done:  pop dx
        pop cx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_parking_frame : the whole parking picture (painter's method).
; ---------------------------------------------------------------------
draw_parking_frame:
        call draw_lot           ; sky, trees, lot floor, lane lines
        call draw_park_scenery  ; round trees and fence (original)
        call draw_bay           ; green bay with the letter P
        call draw_park_objects  ; parked cars and cones
        call draw_sensor        ; distance to the nearest object
        call draw_bonnet
        call draw_dashboard
        call draw_instruments   ; speed, gear, fuel, wheel (layout)
        call draw_time_bar
        call draw_score_only
        call draw_banner        ; "PARKING - LEVEL 2"
        call draw_crash_message
        call draw_end_message   ; only when the level has ended
        ret

; ---------------------------------------------------------------------
; draw_lot : sky, a green band of trees, the grey lot and white lines
;   along the lanes. Each line is drawn row by row with lane_x, so it
;   follows the perspective exactly like the highway edges.
; ---------------------------------------------------------------------
draw_lot:
        push ax
        push bx
        push cx
        push dx
        push si
        mov byte [color], C_SKY
        xor ax, ax
        xor bx, bx
        mov cx, SCREEN_W
        mov dx, TREES_TOP
        call fill_rect
        mov byte [color], C_GRASS_DARK
        mov bx, TREES_TOP
        mov dx, HORIZON - TREES_TOP
        call fill_rect
        mov byte [color], C_LOT
        mov bx, HORIZON
        mov dx, DASH_TOP - HORIZON
        call fill_rect
        ; ---- white lines at world x = -24, -8, +8, +24 (lane edges)
        mov byte [color], C_WHITE
        mov word [lot_t], 1
.row:   mov si, lot_lines
        mov cx, 4
.line:  push cx
        mov ax, [lot_t]
        mov bx, [si]
        call lane_x             ; AX = x of this line on this row
        mov bx, ax
        mov cx, [lot_t]
        shr cx, 5               ; lines get a bit thicker near us
        add bx, cx
        mov dx, [lot_t]
        add dx, HORIZON
        call hline
        pop cx
        add si, 2
        loop .line
        inc word [lot_t]
        cmp word [lot_t], DASH_TOP - HORIZON
        jb .row
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_bay : the parking bay as a green trapezoid with a white border
;   and a big letter P in the middle.
;   Far edge row  = PROJ_K / (BAY_END   - park_z)
;   Near edge row = PROJ_K / (BAY_START - park_z), or the lowest row
;                   if the near edge is already under our car.
;   The sides are the middle lane's edges (world x -8 and +8).
; ---------------------------------------------------------------------
draw_bay:
        push ax
        push bx
        push cx
        push dx
        push si
        mov ax, BAY_END
        sub ax, [park_z]        ; distance to the far edge
        cmp ax, CAR_Z_MIN
        jge .far_ok
        jmp .done               ; we are past the bay: nothing to see
.far_ok:
        call project_row
        mov [bay_t1], ax        ; row of the far edge
        mov ax, BAY_START
        sub ax, [park_z]        ; distance to the near edge
        mov bx, DASH_TOP - HORIZON
        cmp ax, CAR_Z_MIN
        jl .near_set            ; under our car: use the lowest row
        call project_row
        mov bx, ax
        cmp bx, DASH_TOP - HORIZON
        jbe .near_set
        mov bx, DASH_TOP - HORIZON
.near_set:
        mov [bay_t2], bx        ; row of the near edge
        ; ---- white border, then the green inside
        mov byte [color], C_WHITE
        mov cx, 8               ; from world x -8 to +8
        call .shape
        inc word [bay_t1]
        mov byte [color], C_BAY
        mov cx, 7               ; a little narrower
        call .shape
        dec word [bay_t1]
        ; ---- letter P at the middle of the bay
        mov ax, (BAY_START + BAY_END) / 2
        sub ax, [park_z]
        cmp ax, CAR_Z_MIN
        jl .done
        call project_row
        mov si, ax              ; SI = row of the middle
        mov cx, ax
        add cx, 8               ; lane width on that row
        shr cx, 4               ; letter scale = lane width / 16
        cmp cx, 1
        jge .s_min
        mov cx, 1
.s_min: cmp cx, 4
        jle .s_max
        mov cx, 4
.s_max: mov [text_scale], cl
        shl cx, 2               ; CX = half the letter size (4 * scale)
        push cx
        mov ax, si
        xor bx, bx
        call lane_x             ; AX = centre x of the bay
        pop cx
        sub ax, cx
        mov bx, ax              ; letter x
        mov dx, si
        add dx, HORIZON
        sub dx, cx              ; letter y
        mov byte [color], C_WHITE
        mov al, 'P'
        call draw_char
        mov byte [text_scale], 1
.done:  pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; .shape : bay trapezoid from row bay_t1 to bay_t2, world x -CX .. +CX
.shape:
        push ax
        push bx
        push cx
        push dx
        mov dx, cx              ; DX = half width (world x)
        mov ax, [bay_t1]
        mov bx, dx
        neg bx
        call lane_x
        mov [tz_xl1], ax
        mov ax, [bay_t1]
        mov bx, dx
        call lane_x
        mov [tz_xr1], ax
        mov ax, [bay_t2]
        mov bx, dx
        neg bx
        call lane_x
        mov [tz_xl2], ax
        mov ax, [bay_t2]
        mov bx, dx
        call lane_x
        mov [tz_xr2], ax
        mov ax, [bay_t1]
        add ax, HORIZON
        mov [tz_y1], ax
        mov ax, [bay_t2]
        add ax, HORIZON
        mov [tz_y2], ax
        call fill_trapezoid
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_banner : dark rounded box at the top: "PARKING * LEVEL 2".
; ---------------------------------------------------------------------
BANNER_X        equ 94
BANNER_W        equ 132

draw_banner:
        push ax
        push bx
        push cx
        push dx
        push si
        mov byte [color], C_PANEL
        mov ax, BANNER_X
        mov bx, 2
        mov cx, BANNER_W
        mov dx, 15
        call fill_rect
        mov bx, 9
        mov cx, 7
        call fill_circle        ; round left end
        mov ax, BANNER_X + BANNER_W - 1
        call fill_circle        ; round right end
        mov byte [color], C_WHITE
        mov byte [text_scale], 1
        mov si, txt_banner
        mov dx, 6
        call draw_string_centered
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; =====================================================================
;  bonus  -  The original Dr. Driving layout (Figures 3 and 4)
; ---------------------------------------------------------------------
;  In the menu, key B switches between the simple layout (phases 1-3)
;  and the original layout. The GAME RULES ARE EXACTLY THE SAME: only
;  some parts of the screen are drawn in a different way.
;     simple   : speed box, D/R letter, fuel bar, simple wheel
;     original : gear box, light panel, speedometer dial, indicators,
;                hazard, fuel gauge dial, lane guide arrows, big wheel,
;                city street (highway) and trees + fence (parking)
; =====================================================================

; ---------------------------------------------------------------------
; draw_instruments : the dashboard parts of the chosen layout.
; ---------------------------------------------------------------------
draw_instruments:
        cmp byte [layout], LAYOUT_ORIGINAL
        je .original
        call draw_speed_box     ; element 6
        call draw_gear          ; D or R
        call draw_fuel_bar      ; element 7
        call draw_wheel         ; element 8
        ret
.original:
        call draw_cockpit_shine ; bonnet shine, dashboard edge
        call draw_gear_box      ; D / R box, bottom left
        call draw_light_panel   ; the 9 small lights
        call draw_lane_guide    ; arrows at the top
        call draw_speedometer   ; dial 0..200 km/h
        call draw_indicators    ; green arrows and hazard
        call draw_fuel_gauge    ; dial E..F
        call draw_wheel2        ; big wheel with 3 spokes
        ret

; ---------------------------------------------------------------------
; sin256 : AX = angle in degrees  ->  AX = sin(angle) * 256
;   The table sin_table has sin(0..90 degrees) * 256. Other angles use
;   the rules  sin(180 - a) = sin(a)  and  sin(a + 180) = -sin(a).
;   We multiply by 256 so that we can use whole numbers only.
; cos256 : cos(a) = sin(a + 90)
; ---------------------------------------------------------------------
cos256:
        add ax, 90
sin256:
        push bx
        push dx
.too_small:
        cmp ax, 0
        jge .not_neg
        add ax, 360             ; bring the angle into 0..359
        jmp .too_small
.not_neg:
        cmp ax, 360
        jl .in_range
        sub ax, 360
        jmp .not_neg
.in_range:
        xor dx, dx              ; DX = 0: answer is positive
        cmp ax, 180
        jl .upper_half
        sub ax, 180             ; 180..359: same as 0..179, negative
        mov dx, 1
.upper_half:
        cmp ax, 90
        jle .first_quarter
        neg ax
        add ax, 180             ; 91..179 -> 89..1
.first_quarter:
        mov bx, ax
        shl bx, 1               ; 2 bytes per table entry
        mov ax, [sin_table + bx]
        or dx, dx
        jz .done
        neg ax
.done:  pop dx
        pop bx
        ret

; ---------------------------------------------------------------------
; dial_point : a point on a circle around (dial_cx, dial_cy).
;   In : AX = angle in degrees (0 = right, 90 = up), CX = radius
;   Out: AX = x, BX = y
;        x = cx + radius * cos(angle)
;        y = cy - radius * sin(angle)   (minus: screen y grows down)
; ---------------------------------------------------------------------
dial_point:
        push cx
        push dx
        push si
        mov si, ax              ; SI = angle
        call cos256
        imul cx                 ; AX = cos * radius (still * 256)
        sar ax, 8               ; divide by 256
        add ax, [dial_cx]
        push ax
        mov ax, si
        call sin256
        imul cx
        sar ax, 8
        mov bx, [dial_cy]
        sub bx, ax
        pop ax
        pop si
        pop dx
        pop cx
        ret

; ---------------------------------------------------------------------
; draw_line : straight line from (ln_x1, ln_y1) to (ln_x2, ln_y2).
;   Bresenham's method: step one pixel at a time along the line and
;   keep an "error" number that says when to also step in the other
;   direction. Only adding and comparing, no division.
;   Note: ln_x1 and ln_y1 are changed (they walk along the line).
; ---------------------------------------------------------------------
draw_line:
        push ax
        push bx
        push dx
        mov ax, [ln_x2]
        sub ax, [ln_x1]
        mov word [ln_sx], 1     ; step right ...
        jge .dx_ok
        neg ax
        mov word [ln_sx], -1    ; ... or left
.dx_ok: mov [ln_dx], ax         ; ln_dx = |x2 - x1|
        mov ax, [ln_y2]
        sub ax, [ln_y1]
        mov word [ln_sy], 1     ; step down ...
        jge .dy_ok
        neg ax
        mov word [ln_sy], -1    ; ... or up
.dy_ok: neg ax
        mov [ln_dy], ax         ; ln_dy = -|y2 - y1|
        add ax, [ln_dx]
        mov [ln_err], ax        ; error = dx + dy
.plot:  mov ax, [ln_x1]
        mov dx, [ln_y1]
        call put_pixel
        mov ax, [ln_x1]
        cmp ax, [ln_x2]
        jne .step
        mov ax, [ln_y1]
        cmp ax, [ln_y2]
        je .done                ; reached the end point
.step:  mov ax, [ln_err]
        shl ax, 1               ; AX = 2 * error
        cmp ax, [ln_dy]
        jl .no_x
        mov bx, [ln_dy]
        add [ln_err], bx
        mov bx, [ln_sx]
        add [ln_x1], bx         ; step in x
.no_x:  cmp ax, [ln_dx]
        jg .no_y
        mov bx, [ln_dx]
        add [ln_err], bx
        mov bx, [ln_sy]
        add [ln_y1], bx         ; step in y
.no_y:  jmp .plot
.done:  pop dx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; dial_line : line between two points of the dial, same angle AX,
;   from radius CX (inner) to radius DX (outer).
; ---------------------------------------------------------------------
dial_line:
        push ax
        push bx
        push cx
        push si
        mov si, ax
        call dial_point
        mov [ln_x1], ax
        mov [ln_y1], bx
        mov ax, si
        mov cx, dx
        call dial_point
        mov [ln_x2], ax
        mov [ln_y2], bx
        call draw_line
        pop si
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; speed_angle : AX = speed (km/h)  ->  AX = needle angle in degrees.
;   0 km/h points down-left (225 degrees), 200 km/h down-right
;   (-45 degrees): 270 degrees for 200 km/h.
;       angle = 225 - speed * 27 / 20
; ---------------------------------------------------------------------
speed_angle:
        push cx
        push dx
        mov cx, 27
        mul cx
        mov cx, 20
        div cx
        neg ax
        add ax, 225
        pop dx
        pop cx
        ret

; ---------------------------------------------------------------------
; draw_speedometer : element 7 of Figure 3. Round dial 0..200 km/h,
;   ticks every 20 km/h (red from 160), numbers 40 80 120 160, a red
;   needle and the speed as 3 yellow digits under the centre.
; ---------------------------------------------------------------------
draw_speedometer:
        push ax
        push bx
        push cx
        push dx
        push si
        mov word [dial_cx], SPD_X
        mov word [dial_cy], SPD_Y
        ; ---- light rim and dark face
        mov byte [color], C_LIGHT_GREY
        mov ax, SPD_X
        mov bx, SPD_Y
        mov cx, SPD_R
        call fill_circle
        mov byte [color], C_BOX_BG
        mov cx, SPD_R - 2
        call fill_circle
        ; ---- ticks every 20 km/h (long ones every 40 km/h)
        xor si, si              ; SI = speed of this tick
.tick:  mov byte [color], C_WHITE
        cmp si, 160
        jb .tick_colour
        mov byte [color], C_RED ; high speeds in red
.tick_colour:
        mov cx, SPD_R - 8       ; long tick for 0, 40, 80 ...
        mov ax, si
        mov dl, 40
        div dl                  ; AH = speed mod 40
        or ah, ah
        jz .long
        mov cx, SPD_R - 5       ; short tick for 20, 60, 100 ...
.long:  mov ax, si
        call speed_angle
        mov dx, SPD_R - 3
        call dial_line
        add si, 20
        cmp si, 200
        jbe .tick
        ; ---- numbers 40, 80, 120, 160
        mov byte [color], C_WHITE
        mov byte [text_scale], 1
        mov si, 40
.label: mov ax, si
        call speed_angle
        mov cx, SPD_R - 12
        call dial_point         ; AX, BX = centre of the number
        push ax
        push bx
        mov ax, si
        mov cx, 1
        push si
        call number_to_string   ; SI -> text of the number
        call string_width       ; AX = its width
        pop cx                  ; CX = the speed again
        pop dx                  ; DX = y
        pop bx                  ; BX = x
        shr ax, 1
        sub bx, ax              ; centre the text
        sub dx, 4
        call draw_string
        mov si, cx
        add si, 40
        cmp si, 160
        jbe .label
        ; ---- needle (2 pixels thick) for the current speed
        mov byte [color], C_RED
        mov ax, [speed_kmh]
        cmp ax, 200
        jbe .speed_ok
        mov ax, 200
.speed_ok:
        call speed_angle
        mov cx, 0
        mov dx, SPD_R - 5
        call dial_line
        inc word [dial_cx]
        call dial_line
        dec word [dial_cx]
        mov byte [color], C_HUB
        mov ax, SPD_X
        mov bx, SPD_Y
        mov cx, 2
        call fill_circle        ; centre cap
        ; ---- digital speed, 3 yellow digits below the centre
        mov byte [color], C_YELLOW
        mov ax, [speed_kmh]
        mov cx, 3
        mov bx, SPD_X - 12
        mov dx, SPD_Y + 4
        call draw_number
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; fuel_angle : AX = fuel (0..FUEL_MAX) -> AX = needle angle.
;   E (empty) is down-left at 210 degrees, F (full) is down-right at
;   -30 degrees, so the needle turns 240 degrees over the top.
;       angle = 210 - fuel * 240 / FUEL_MAX
; ---------------------------------------------------------------------
fuel_angle:
        push cx
        push dx
        mov cx, 240
        mul cx                  ; DX:AX = fuel * 240 (can be > 65535)
        mov cx, FUEL_MAX
        div cx
        neg ax
        add ax, 210
        pop dx
        pop cx
        ret

; ---------------------------------------------------------------------
; draw_fuel_gauge : element 9 of Figure 3. Round dial from E to F,
;   a red needle, and a fuel pump icon that turns red when low.
; ---------------------------------------------------------------------
draw_fuel_gauge:
        push ax
        push bx
        push cx
        push dx
        push si
        mov word [dial_cx], FG_X
        mov word [dial_cy], FG_Y
        mov byte [color], C_LIGHT_GREY
        mov ax, FG_X
        mov bx, FG_Y
        mov cx, FG_R
        call fill_circle
        mov byte [color], C_BOX_BG
        mov cx, FG_R - 2
        call fill_circle
        ; ---- 5 ticks: E, 1/4, 1/2, 3/4, F
        xor si, si
.tick:  mov byte [color], C_WHITE
        or si, si
        jnz .tick_colour
        mov byte [color], C_RED ; the E tick is red
.tick_colour:
        mov ax, si
        call fuel_angle
        mov cx, FG_R - 6
        mov dx, FG_R - 3
        call dial_line
        add si, FUEL_MAX / 4
        cmp si, FUEL_MAX
        jbe .tick
        ; ---- letters E and F
        mov byte [text_scale], 1
        mov byte [color], C_RED
        mov al, 'E'
        mov bx, FG_X - 14
        mov dx, FG_Y + 2
        call draw_char
        mov byte [color], C_WHITE
        mov al, 'F'
        mov bx, FG_X + 6
        call draw_char
        ; ---- fuel pump icon: white, red when fuel is low
        mov byte [color], C_WHITE
        cmp word [fuel], FUEL_LOW
        jae .icon_colour
        mov byte [color], C_RED
.icon_colour:
        mov ax, FG_X - 5
        mov bx, FG_Y - 12
        mov cx, 5
        mov dx, 8
        call fill_rect          ; pump body
        mov ax, FG_X
        mov bx, FG_Y - 10
        mov cx, 2
        mov dx, 1
        call fill_rect          ; hose
        mov ax, FG_X + 1
        mov bx, FG_Y - 10
        mov cx, 1
        mov dx, 5
        call fill_rect          ; nozzle
        mov byte [color], C_BOX_BG
        mov ax, FG_X - 4
        mov bx, FG_Y - 11
        mov cx, 3
        mov dx, 2
        call fill_rect          ; little window of the pump
        ; ---- needle
        mov byte [color], C_RED
        mov ax, [fuel]
        call fuel_angle
        mov cx, 0
        mov dx, FG_R - 4
        call dial_line
        inc word [dial_cx]
        call dial_line
        mov byte [color], C_HUB
        mov ax, FG_X
        mov bx, FG_Y
        mov cx, 2
        call fill_circle
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_lane_guide : element 3 of Figure 3. A small panel at the top
;   with one up-arrow per lane. The arrow of OUR lane is highlighted
;   (orange background, light arrow); the others are dim.
; ---------------------------------------------------------------------
draw_lane_guide:
        push ax
        push bx
        push cx
        push dx
        push si
        mov ax, LG_X_HIGHWAY
        cmp byte [game_mode], MODE_PARKING
        jne .x_ok
        mov ax, LG_X_PARKING
.x_ok:  mov [lg_x], ax
        ; ---- orange border, brown inside
        mov byte [color], C_ORANGE
        mov bx, LG_Y
        mov cx, 28
        mov dx, 25
        call fill_rect
        mov byte [color], C_BROWN
        inc ax
        inc bx
        mov cx, 26
        mov dx, 23
        call fill_rect
        ; ---- 3 arrows, lane 0 on the left
        xor si, si              ; SI = lane number
.arrow: mov ax, si
        shl ax, 3               ; 8 pixels per lane
        add ax, [lg_x]
        add ax, 2
        mov [lg_col], ax        ; left x of this lane's column
        mov byte [lg_arrow], C_ARROW_DIM
        mov ax, si
        cmp al, [player_lane]
        jne .draw_arrow
        ; our lane: orange column, light arrow
        mov byte [color], C_ORANGE
        mov ax, [lg_col]
        mov bx, LG_Y + 2
        mov cx, 8
        mov dx, 21
        call fill_rect
        mov byte [lg_arrow], C_WHITE
.draw_arrow:
        mov al, [lg_arrow]
        mov [color], al
        ; arrow head: triangle, tip at the top
        mov ax, [lg_col]
        add ax, 4
        mov [tz_xl1], ax
        mov [tz_xr1], ax
        sub ax, 3
        mov [tz_xl2], ax
        add ax, 6
        mov [tz_xr2], ax
        mov word [tz_y1], LG_Y + 4
        mov word [tz_y2], LG_Y + 9
        call fill_trapezoid
        ; arrow shaft
        mov ax, [lg_col]
        add ax, 3
        mov bx, LG_Y + 10
        mov cx, 2
        mov dx, 11
        call fill_rect
        inc si
        cmp si, 3
        jb .arrow
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_indicators : element 8 of Figure 3.
;   Left and right green arrows: they flash (on/off every 16 ticks)
;   for one second after we move one lane towards that side.
;   The red hazard triangle in the middle stays off.
; ---------------------------------------------------------------------
draw_indicators:
        push ax
        push bx
        push cx
        push dx
        ; ---- left arrow
        mov byte [color], C_GREEN_DIM
        mov ax, [ind_left]
        test ax, 16
        jz .left_colour         ; off half of the flash (or not moving)
        mov byte [color], C_GREEN
.left_colour:
        mov ax, IND_L_X
        mov dx, -1              ; DX = -1: arrow points left
        call .arrow
        ; ---- right arrow
        mov byte [color], C_GREEN_DIM
        mov ax, [ind_right]
        test ax, 16
        jz .right_colour
        mov byte [color], C_GREEN
.right_colour:
        mov ax, IND_R_X
        mov dx, 1               ; DX = +1: arrow points right
        call .arrow
        ; ---- hazard triangle: two outlines, switched off
        mov byte [color], C_HAZARD
        mov bx, 7               ; outer triangle, size 7
        call .triangle
        mov bx, 4               ; inner triangle, size 4
        call .triangle
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; .arrow : AX = centre x, DX = direction (-1 left, +1 right).
;   Head: 11 rows (-5..+5). Row r is 6 - |r| pixels long, so the
;   rows make a triangle with its tip 6 pixels from the centre.
;   Tail: a 7 x 5 rectangle on the other side of the centre.
.arrow:
        push si
        push di
        mov si, ax              ; SI = centre x
        mov di, dx              ; DI = direction (IMUL changes DX)
        mov cx, -5              ; CX = row offset -5..+5
.head_row:
        mov ax, cx
        cmp ax, 0
        jge .abs_ok
        neg ax                  ; AX = |row offset|
.abs_ok:
        neg ax
        add ax, 6               ; AX = 6 - |row|
        imul di                 ; negative for the left arrow
        add ax, si              ; x at the tip side of this row
        mov bx, si              ; x at the base of the head
        mov dx, IND_Y
        add dx, cx
        call hline
        inc cx
        cmp cx, 5
        jle .head_row
        ; tail
        mov ax, si
        cmp di, 0
        jl .tail_left
        sub ax, 6               ; right arrow: tail on the left side
.tail_left:
        mov bx, IND_Y - 2
        mov cx, 7
        mov dx, 5
        call fill_rect
        pop di
        pop si
        ret

; .triangle : outline of a triangle around (HAZ_X, IND_Y), size BX.
.triangle:
        push ax
        mov ax, HAZ_X
        mov [ln_x1], ax
        mov ax, IND_Y
        sub ax, bx
        mov [ln_y1], ax         ; top corner
        mov ax, HAZ_X
        sub ax, bx
        mov [ln_x2], ax
        mov ax, IND_Y
        add ax, bx
        mov [ln_y2], ax         ; bottom-left corner
        call draw_line
        mov ax, HAZ_X
        sub ax, bx
        mov [ln_x1], ax
        mov ax, IND_Y
        add ax, bx
        mov [ln_y1], ax
        mov ax, HAZ_X
        add ax, bx
        mov [ln_x2], ax
        mov ax, IND_Y
        add ax, bx
        mov [ln_y2], ax         ; bottom-right corner
        call draw_line
        mov ax, HAZ_X
        add ax, bx
        mov [ln_x1], ax
        mov ax, IND_Y
        add ax, bx
        mov [ln_y1], ax
        mov ax, HAZ_X
        mov [ln_x2], ax
        mov ax, IND_Y
        sub ax, bx
        mov [ln_y2], ax         ; back to the top
        call draw_line
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_wheel2 : element 10 of Figure 3. Big black wheel with a grey
;   inner edge, spokes to the left, right and down, and a hub with S.
; ---------------------------------------------------------------------
draw_wheel2:
        push ax
        push bx
        push cx
        push dx
        mov byte [color], C_WHEEL
        mov ax, W2_X
        mov bx, W2_Y
        mov cx, W2_R_OUT
        mov dx, W2_R_IN
        call fill_ring          ; rim
        mov byte [color], C_HUB
        mov cx, W2_R_IN + 1
        mov dx, W2_R_IN - 1
        call fill_ring          ; grey inner edge of the rim
        ; ---- spokes
        mov byte [color], C_WHEEL
        mov ax, W2_X - W2_R_IN
        mov bx, W2_Y - 4
        mov cx, 2 * W2_R_IN
        mov dx, 7
        call fill_rect          ; left and right spokes
        mov ax, W2_X - 4
        mov bx, W2_Y
        mov cx, 8
        mov dx, W2_R_IN
        call fill_rect          ; spoke going down
        ; ---- hub: black ring, grey middle, letter S
        mov ax, W2_X
        mov bx, W2_Y
        mov cx, 13
        call fill_circle
        mov byte [color], C_LIGHT_GREY
        mov cx, 8
        call fill_circle
        mov byte [color], C_WHEEL
        mov byte [text_scale], 1
        mov al, 'S'
        mov bx, W2_X - 3
        mov dx, W2_Y - 4
        call draw_char
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_background : sky and ground of the highway for the layout.
; ---------------------------------------------------------------------
draw_background:
        cmp byte [layout], LAYOUT_ORIGINAL
        je .city
        call draw_sky_ground    ; simple: sky and grass
        ret
.city:  call draw_city          ; original: city street
        ret

; ---------------------------------------------------------------------
; vline : vertical line.  In: AX = x, BX = y1, DX = y2 (y1 <= y2)
;   Clipped to the screen. Writes the bytes directly, 320 apart.
; ---------------------------------------------------------------------
vline:
        push ax
        push bx
        push cx
        push dx
        push di
        cmp ax, 0
        jl .done
        cmp ax, SCREEN_W
        jge .done
        cmp bx, 0
        jge .top_ok
        xor bx, bx
.top_ok:
        cmp dx, SCREEN_H - 1
        jle .bottom_ok
        mov dx, SCREEN_H - 1
.bottom_ok:
        mov cx, dx
        sub cx, bx
        jl .done                ; nothing left after clipping
        inc cx                  ; CX = number of pixels
        mov di, bx
        shl di, 6
        shl bx, 8
        add di, bx
        add di, ax              ; DI = y1*320 + x
        mov al, [color]
.pixel: mov [es:di], al
        add di, SCREEN_W        ; one row down
        loop .pixel
.done:  pop di
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_city : sky, pavement and two rows of buildings (Figure 3).
;   The building fronts are two flat walls, WALL_X16 to the left and
;   to the right of the road centre. For every row t of the road we
;   know the distance z = PROJ_K / t, and the wall at that distance is
;   at screen x = lane_x(t, -WALL_X16). We fill the screen columns
;   between the wall at row t-1 and row t with vertical lines.
;   Which building we see depends on (z + road_scroll), so the
;   buildings slide past while we drive:
;     building number = (z + road_scroll) / 2048, colour and height
;     come from small tables; windows are columns where a bit of the
;     same number is set.
; ---------------------------------------------------------------------
draw_city:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov byte [color], C_SKY
        xor ax, ax
        xor bx, bx
        mov cx, SCREEN_W
        mov dx, HORIZON
        call fill_rect
        mov byte [color], C_SIDEWALK
        mov bx, HORIZON
        mov dx, DASH_TOP - HORIZON
        call fill_rect          ; the road is drawn on top later
        ; ---- previous wall x positions start at the horizon
        mov ax, 0
        mov bx, -WALL_X16
        call lane_x
        mov [city_xl], ax
        mov ax, 0
        mov bx, WALL_X16
        call lane_x
        mov [city_xr], ax
        mov word [city_t], 1
.row:   ; ---- building at this distance
        mov ax, [city_t]
        call project_row        ; AX = z of this row
        add ax, [road_scroll]
        mov [city_p], ax        ; position along the street
        mov bx, ax
        mov cl, 11
        shr bx, cl              ; building number (2048 units each)
        mov [city_bno], bl      ; (used to choose the lit windows)
        and bx, 3               ; 4 different buildings, repeating
        mov al, [bld_colour + bx]
        mov [city_col], al
        shl bx, 1
        mov ax, [bld_height + bx]
        mov [city_h], ax        ; height in 1/16 lane units
        ; height in pixels = h * lane width / 16
        mov ax, [city_t]
        add ax, 8
        mul word [city_h]
        mov cl, 4
        shr ax, cl
        mov [city_hpx], ax
        ; ---- kerbs: a darker strip just outside both road edges
        mov byte [color], C_CURB
        mov ax, [city_t]
        mov bx, -CURB_X16
        call lane_x
        push ax
        mov ax, [city_t]
        mov bx, -24
        call lane_x
        mov bx, ax
        pop ax
        mov dx, [city_t]
        add dx, HORIZON
        call hline              ; left kerb
        mov ax, [city_t]
        mov bx, 24
        call lane_x
        push ax
        mov ax, [city_t]
        mov bx, CURB_X16
        call lane_x
        mov bx, ax
        pop ax
        call hline              ; right kerb
        ; ---- left wall: columns from x(t) to x(t-1) - 1
        mov ax, [city_t]
        mov bx, -WALL_X16
        call lane_x
        mov si, ax              ; SI = x(t)
        mov di, [city_xl]       ; DI = x(t-1)
        mov [city_xl], si
.left_col:
        cmp si, di
        jge .left_done
        mov ax, si
        call .column
        inc si
        jmp .left_col
.left_done:
        ; ---- right wall: columns from x(t-1) + 1 to x(t)
        mov ax, [city_t]
        mov bx, WALL_X16
        call lane_x
        mov di, ax              ; DI = x(t)
        mov si, [city_xr]
        mov [city_xr], di
.right_col:
        cmp si, di
        jge .right_done
        inc si
        mov ax, si
        call .column
        jmp .right_col
.right_done:
        inc word [city_t]
        cmp word [city_t], DASH_TOP - HORIZON
        jae .done
        jmp .row
.done:  pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; .column : one column of a building at screen x = AX.
;   bottom = HORIZON + t, top = bottom - building height in pixels.
;   Heights are in 1/16 lanes and become pixels with .px, so the
;   shop front and the windows are always at the same height above
;   the street, like real floors:
;     shop front : 0 .. SHOP_H
;     windows    : WIN_H high, one floor every FLOOR_H
.column:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        cmp ax, 0
        jge .x_not_left
        jmp .col_done           ; left of the screen (far jump)
.x_not_left:
        cmp ax, SCREEN_W
        jl .x_on_screen
        jmp .col_done           ; right of the screen
.x_on_screen:
        mov si, ax              ; SI = x
        mov di, [city_t]
        add di, HORIZON         ; DI = bottom row (street level)
        mov cx, [city_p]
        and cx, 2047            ; CX = place inside this building
        ; ---- the whole wall (or a dark gap between two buildings)
        mov byte [color], C_BLD_WIN
        cmp cx, 80
        jb .paint_wall
        mov al, [city_col]
        mov [color], al
.paint_wall:
        mov bx, di
        sub bx, [city_hpx]      ; BX = top row
        mov dx, di
        mov ax, si
        call vline
        cmp cx, 80
        jb .col_done            ; gap: nothing more to draw
        ; ---- brown shop front: height 0 .. SHOP_H
        mov byte [color], C_BLD_BASE
        mov ax, SHOP_H
        call .px
        mov bx, di
        sub bx, ax
        mov dx, di
        mov ax, si
        call vline
        ; ---- windows, only in some columns (bit 7 of the place)
        test cx, 128
        jz .col_done
        cmp cx, 1900
        ja .col_done            ; no window right at the building end
        mov byte [color], C_BLD_WIN
        mov cx, SHOP_H + 4      ; CX = height of the window bottom
.window:
        mov ax, cx
        add ax, WIN_H
        cmp ax, [city_h]
        ja .col_done            ; window would be above the roof
        ; lit (yellow) or dark window: depends on building and floor
        mov ax, cx
        mov bl, FLOOR_H
        div bl                  ; AL = floor number
        add al, [city_bno]
        and al, 3
        mov byte [color], C_BLD_WIN
        cmp al, 1
        jne .win_colour
        mov byte [color], C_WIN_LIT
.win_colour:
        mov ax, cx
        add ax, WIN_H
        call .px
        mov bx, di
        sub bx, ax              ; BX = window top row
        mov ax, cx
        call .px
        mov dx, di
        sub dx, ax              ; DX = window bottom row
        cmp dx, 0
        jl .col_done            ; already above the screen
        mov ax, si
        call vline
        add cx, FLOOR_H         ; next floor
        jmp .window
.col_done:
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; .px : AX = height in 1/16 lanes -> AX = pixels on this row
;       pixels = height * (8 + t) / 16
.px:    push dx
        push cx
        mov cx, [city_t]
        add cx, 8
        mul cx
        mov cl, 4
        shr ax, cl
        pop cx
        pop dx
        ret

; ---------------------------------------------------------------------
; draw_park_scenery : original layout only (Figure 4).
;   A row of round trees and a fence between the trees and the lot.
; ---------------------------------------------------------------------
draw_park_scenery:
        cmp byte [layout], LAYOUT_ORIGINAL
        je .draw
        ret
.draw:  push ax
        push bx
        push cx
        push dx
        ; ---- round trees: a circle every 18 pixels, two sizes
        mov byte [color], C_BUSH
        mov ax, 6
        mov dx, 0               ; DX counts the trees (big / small)
.tree:  mov bx, TREES_TOP + 7
        mov cx, 11              ; big tree
        test dx, 1
        jz .size_ok
        mov bx, TREES_TOP + 9
        mov cx, 9               ; small tree
.size_ok:
        call fill_circle
        inc dx
        add ax, 18
        cmp ax, SCREEN_W + 10
        jb .tree
        ; ---- fence: two rails and a post every 8 pixels
        mov byte [color], C_FENCE
        xor ax, ax
        mov bx, HORIZON - 9
        mov cx, SCREEN_W
        mov dx, 1
        call fill_rect          ; top rail
        mov bx, HORIZON - 4
        call fill_rect          ; lower rail
        xor ax, ax
.post:  mov bx, HORIZON - 10
        mov cx, 1
        mov dx, 9
        call fill_rect
        add ax, 8
        cmp ax, SCREEN_W
        jb .post
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_hud_text : like draw_string_adv, but in the original layout the
;   text first gets a black shadow 1 pixel down and right, so it can
;   be read on top of the light buildings (as in Figure 3).
;   In: SI -> text, BX = x, DX = y.   Out: BX = x after the text.
; ---------------------------------------------------------------------
draw_hud_text:
        cmp byte [layout], LAYOUT_ORIGINAL
        jne .plain
        push ax
        push bx
        push dx
        mov al, [color]
        push ax                 ; remember the text colour
        mov byte [color], C_BLACK
        inc bx
        inc dx
        call draw_string        ; shadow
        pop ax
        mov [color], al
        pop dx
        pop bx
        pop ax
.plain: jmp draw_string_adv     ; the text itself

; ---------------------------------------------------------------------
; draw_cockpit_shine : original layout. A light line along the bonnet
;   (the shine in Figure 3), a darker band at its lower edge, and a
;   light + dark line on the top edge of the dashboard.
;   The shine follows the bonnet curve, 6 pixels lower:
;       y = BONNET_TOP + (x - 160)^2 / BONNET_CURVE + 6
; ---------------------------------------------------------------------
draw_cockpit_shine:
        push ax
        push bx
        push cx
        push dx
        push si
        mov byte [color], C_ORANGE_LIGHT
        mov si, 60              ; SI = x
.shine: mov ax, si
        sub ax, SCREEN_W / 2
        imul ax                 ; AX = (x - 160)^2
        mov cx, BONNET_CURVE
        div cx
        add ax, BONNET_TOP + 6
        mov dx, ax
        mov ax, si
        call put_pixel
        inc si
        cmp si, 200
        jb .shine
        ; ---- darker band: the 3 lowest rows of the bonnet
        mov byte [color], C_ORANGE_DARK
        mov dx, DASH_TOP - 3
.band:  mov si, dx
        sub si, BONNET_TOP
        shl si, 1
        mov cx, [bonnet_half + si]
        mov ax, SCREEN_W / 2
        sub ax, cx
        mov bx, SCREEN_W / 2
        add bx, cx
        call hline
        inc dx
        cmp dx, DASH_TOP
        jb .band
        ; ---- dashboard edge: light line, then a black line
        mov byte [color], C_DASH_EDGE
        xor ax, ax
        mov bx, SCREEN_W - 1
        mov dx, DASH_TOP
        call hline
        mov byte [color], C_BLACK
        inc dx
        call hline
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_gear_box : rounded box with a ring and a big D (green) or
;   R (red), bottom left of the dashboard.
; ---------------------------------------------------------------------
GBOX_X          equ 7
GBOX_Y          equ 176
GBOX_W          equ 24
GBOX_H          equ 21

draw_gear_box:
        push ax
        push bx
        push cx
        push dx
        mov byte [color], C_LIGHT_GREY
        mov ax, GBOX_X
        mov bx, GBOX_Y
        mov cx, GBOX_W
        mov dx, GBOX_H
        call fill_rect
        mov byte [color], C_PANEL
        mov ax, GBOX_X + 1
        mov bx, GBOX_Y + 1
        mov cx, GBOX_W - 2
        mov dx, GBOX_H - 2
        call fill_rect
        ; ring around the letter
        mov byte [color], C_LIGHT_GREY
        mov ax, GBOX_X + GBOX_W / 2
        mov bx, GBOX_Y + GBOX_H / 2
        mov cx, 8
        mov dx, 7
        call fill_ring
        ; the letter: D in green, R in red
        mov byte [color], C_GREEN
        cmp byte [gear], GEAR_R
        jne .colour_ok
        mov byte [color], C_RED
.colour_ok:
        mov byte [text_scale], 1
        mov al, [gear]
        mov bx, GBOX_X + GBOX_W / 2 - 4
        mov dx, GBOX_Y + GBOX_H / 2 - 4
        call draw_char
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---------------------------------------------------------------------
; draw_light_panel : small box with 3 x 3 coloured lights (decoration,
;   like the original game). Colours come from the table panel_lights.
; ---------------------------------------------------------------------
LPANEL_X        equ 35
LPANEL_Y        equ 174

draw_light_panel:
        push ax
        push bx
        push cx
        push dx
        push si
        mov byte [color], C_LIGHT_GREY
        mov ax, LPANEL_X
        mov bx, LPANEL_Y
        mov cx, 28
        mov dx, 24
        call fill_rect
        mov byte [color], C_PANEL
        mov ax, LPANEL_X + 1
        mov bx, LPANEL_Y + 1
        mov cx, 26
        mov dx, 22
        call fill_rect
        mov si, panel_lights    ; 9 colours, row by row
        mov bx, LPANEL_Y + 5    ; BX = y of the first row
.row:   mov ax, LPANEL_X + 6    ; AX = x of the first light
.light: mov dl, [si]
        mov [color], dl
        inc si
        mov cx, 2
        call fill_circle
        add ax, 8
        cmp ax, LPANEL_X + 6 + 3 * 8
        jb .light
        add bx, 7
        cmp bx, LPANEL_Y + 5 + 3 * 7
        jb .row
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; =====================================================================
;  main program
; ---------------------------------------------------------------------
;  The game loop:  update the game  ->  draw a frame  ->  show it,
;  again and again until ESC is pressed in the menu (quit_flag).
; =====================================================================
start:
        call video_init         ; mode 13h, palette, font, buffer
        call install_keyboard   ; our INT 9 handler
        call install_timer      ; our INT 8 handler, 73 ticks/second
        call make_bonnet_table  ; bonnet shape, worked out once
        mov es, [back_seg]      ; ES = back buffer for all drawing
        call go_menu            ; the game starts in the menu

main_loop:
        ; ---- 1. one game update for every timer tick that has passed
        cmp word [tick_count], MAX_UPDATES
        jbe .catch_up
        mov word [tick_count], MAX_UPDATES  ; very slow PC: skip some
.catch_up:
        cmp word [tick_count], 0
        je .draw
        dec word [tick_count]
        call game_update        ; menu, highway or parking
        jmp .catch_up
        ; ---- 2. draw the new picture and show it
.draw:
        call game_draw          ; draw the picture in the buffer
        call flip_screen        ; show it
        cmp byte [quit_flag], 1
        jne main_loop           ; until ESC is pressed in the menu

        call remove_timer       ; normal timer again
        call remove_keyboard    ; give the keyboard back to DOS
        call video_close        ; back to text mode
        mov ax, 4C00h           ; return to DOS
        int 21h

; =====================================================================
;  data.asm  -  All variables, tables and text of the game
; ---------------------------------------------------------------------
;  This file is included at the END of main.asm, after all the code,
;  so the CPU never tries to run these bytes as instructions.
; =====================================================================

; ---------------- Game values shown on the screen ---------------------
; Starting values (highway_start sets them again for every game).
speed_kmh       dw 78               ; shown as 078 km/h
fuel            dw FUEL_MAX / 2     ; half-full fuel bar
time_left       dw TIME_MAX * 6 / 10 ; time bar 60% full
distance        dw 420              ; metres driven
score           dw 4793

; ---------------- Camera / road ---------------------------------------
cam_x16         dw 0                ; our sideways position (0 = middle)
road_scroll     dw 0                ; moves the lane dashes

; ---------------- Traffic (see traffic.asm) ---------------------------
; The repeating pattern: z (world units), lane, colour.
; The cars are 6500 units (about 25 m) apart and two cars in a row are
; never in the same lane, so there is always a free lane to go to.
TRAFFIC_COUNT   equ 5
traffic_pattern:
        dw 4000
        db LANE_LEFT,   C_CAR_BLUE
        dw 10500
        db LANE_RIGHT,  C_CAR_TEAL
        dw 17000
        db LANE_MIDDLE, C_CAR_RED
        dw 23500
        db LANE_LEFT,   C_CAR_WHITE
        dw -2500
        db LANE_RIGHT,  C_CAR_YELLOW
traffic         times TRAFFIC_COUNT * 4 db 0   ; the moving copy
drawn           times TRAFFIC_COUNT db 0       ; draw_traffic marks
best_z          dw 0
best_car        dw 0
best_index      dw 0

; ---------------- Text strings (0 = end of string) --------------------
txt_time        db 'Time', 0
txt_dist        db 'DIST ', 0
txt_dist_end    db ' / 1000 m', 0
txt_score       db 'SCORE ', 0
txt_kmh         db 'km/h', 0
txt_fuel        db 'FUEL', 0
txt_e           db 'E', 0
txt_f           db 'F', 0
txt_crash       db 'CRASH! -50', 0
txt_win_1       db 'COMPLETE!', 0
txt_win_2       db 'You drove 1000 m. Well done!', 0
txt_timeup_1    db 'TIME UP!', 0
txt_timeup_2    db 'The time has run out.', 0
txt_nofuel_1    db 'NO FUEL!', 0
txt_nofuel_2    db 'The fuel tank is empty.', 0
txt_again       db 'ENTER = menu (or wait 8 s)', 0
txt_park_1      db 'PARKED!', 0
txt_park_2      db 'Inside the bay. Well done!', 0
txt_title       db 'DR. DRIVING LITE', 0
txt_menu_1      db '1   HIGHWAY    (Level 1)', 0
txt_menu_2      db '2   PARKING    (Level 2)', 0
txt_menu_esc    db 'ESC QUIT', 0
txt_menu_b      db 'B   LAYOUT: ', 0
txt_simple      db 'SIMPLE', 0
txt_original    db 'ORIGINAL', 0
txt_help_1      db 'UP = gas     SPACE = brake', 0
txt_help_2      db 'LEFT / RIGHT = change lane', 0
txt_help_3      db 'DOWN = reverse (at 0 km/h)', 0
txt_banner      db 'PARKING ', 7, ' LEVEL 2', 0   ; 7 = round dot

; ---------------- Colour palette: R, G, B (each 0..63) ----------------
; The order must match the C_... numbers in consts.asm.
palette:
        db  0,  0,  0           ; 0  C_BLACK
        db 34, 49, 59           ; 1  C_SKY
        db 30, 42, 24           ; 2  C_GRASS
        db 22, 22, 24           ; 3  C_ROAD
        db 62, 62, 62           ; 4  C_WHITE
        db 58, 30,  8           ; 5  C_ORANGE
        db 47, 22,  5           ; 6  C_ORANGE_DARK
        db 10, 10, 12           ; 7  C_DASH
        db  3,  3,  4           ; 8  C_WHEEL
        db 62, 50, 10           ; 9  C_YELLOW
        db 16, 50, 24           ; 10 C_GREEN
        db 58, 18, 10           ; 11 C_RED
        db 10, 22, 50           ; 12 C_CAR_BLUE
        db  7, 40, 37           ; 13 C_CAR_TEAL
        db  9, 14, 22           ; 14 C_WINDOW
        db 59, 10, 10           ; 15 C_TAIL
        db 52, 52, 52           ; 16 C_LIGHT_GREY
        db 59, 59, 59           ; 17 C_CAR_WHITE
        db 47, 11, 11           ; 18 C_CAR_RED
        db 11, 28, 20           ; 19 C_BAY
        db 60, 30,  8           ; 20 C_CONE
        db 28, 28, 30           ; 21 C_LOT
        db 20, 20, 22           ; 22 C_HUB
        db 11, 11, 10           ; 23 C_DIM
        db 60, 50, 15           ; 24 C_SENSOR_YEL
        db 21, 35, 21           ; 25 C_GRASS_DARK
        db  5,  5,  5           ; 26 C_BAR_BG
        db  3,  3,  4           ; 27 C_BOX_BG
        db 57, 47, 10           ; 28 C_CAR_YELLOW
        db 17, 50, 25           ; 29 C_SENSOR_GRN
        db  6,  6,  8           ; 30 C_PANEL
        db 12,  8,  5           ; 31 C_BROWN
        db 27, 24, 21           ; 32 C_ARROW_DIM
        db  5, 17, 10           ; 33 C_GREEN_DIM
        db 32,  8,  8           ; 34 C_HAZARD
        db 44, 44, 45           ; 35 C_SIDEWALK
        db 45, 48, 53           ; 36 C_BLD_1  light blue-grey
        db 58, 54, 47           ; 37 C_BLD_2  cream
        db 54, 46, 40           ; 38 C_BLD_3  light brown
        db 51, 51, 53           ; 39 C_BLD_4  light grey
        db 30, 21, 17           ; 40 C_BLD_BASE
        db 27, 33, 44           ; 41 C_BLD_WIN
        db 24, 37, 26           ; 42 C_BUSH
        db 22, 25, 24           ; 43 C_FENCE
        db  8,  8,  9           ; 44 C_SHADOW
        db 14, 14, 15           ; 45 C_BUMPER
        db 33, 33, 34           ; 46 C_CURB
        db 62, 57, 35           ; 47 C_WIN_LIT
        db 62, 42, 22           ; 48 C_ORANGE_LIGHT
        db 19, 19, 20           ; 49 C_DASH_EDGE

; ---------------- Work variables of the drawing routines --------------
back_seg        dw 0                ; segment of the back buffer
color           db 0                ; colour used by all shapes
text_scale      db 1                ; 1 = 8x8 letters, 2 = 16x16 ...

ring_cx         dw 0                ; fill_ring
ring_cy         dw 0
ring_ro         dw 0
ring_ri         dw 0
ring_xo         dw 0
ring_xi         dw 0
ring_dy         dw 0

tz_y1           dw 0                ; fill_trapezoid
tz_xl1          dw 0
tz_xr1          dw 0
tz_y2           dw 0
tz_xl2          dw 0
tz_xr2          dw 0

ch_x            dw 0                ; draw_char
ch_y            dw 0
num_buf         times 8 db 0        ; number_to_string

rd_t            dw 0                ; draw_road
rd_cx           dw 0
rd_lw           dw 0

car_colour      db 0                ; draw_car
car_xc          dw 0
car_w           dw 0
car_h           dw 0
car_left        dw 0
car_top         dw 0
car_bottom      dw 0

font_data       times 128 * 8 db 0  ; copy of the BIOS 8x8 font

; ---------------- Keyboard (INT 9) ------------------------------------
key_down        times 128 db 0      ; 1 = key is held down right now
old_int9        dw 0, 0             ; old handler: offset, segment

; ---------------- Timer (INT 8) ---------------------------------------
old_int8        dw 0, 0             ; old handler: offset, segment
tick_count      dw 0                ; game updates still to do
bios_div        db 0                ; counts 0..3, BIOS runs on 4th tick

; ---------------- Player ----------------------------------------------
speed_x16       dw 0                ; speed in 1/16 km/h
max_speed       dw MAX_SPEED * 16   ; top speed of the current level
player_lane     db LANE_MIDDLE      ; 0 = left, 1 = middle, 2 = right
gear            db GEAR_D           ; 'D' = drive, 'R' = reverse
left_latch      db 0                ; Left was held in the last tick
right_latch     db 0                ; Right was held in the last tick

; ---------------- Distance --------------------------------------------
dist_acc        dw 0                ; world units not yet a full metre
best_distance   dw 0                ; farthest metre reached (for score)

; ---------------- Collisions ------------------------------------------
crash_timer     dw 0                ; ticks the CRASH text stays

; ---------------- Fuel ------------------------------------------------
fuel_acc        dw 0                ; collects use until FUEL_DIV

; ---------------- Level state -----------------------------------------
hw_state        db STATE_PLAYING    ; playing or ended
end_msg         db 0                ; which end message to show

; ---------------- Bonnet shape ----------------------------------------
bonnet_half     times DASH_TOP - BONNET_TOP dw 0   ; half width per row

; ---------------- Game mode / menu ------------------------------------
game_mode       db MODE_MENU        ; what the game is doing now
quit_flag       db 0                ; 1 = leave the game loop
esc_latch       db 0                ; ESC was held in the last tick
end_timer       dw 0                ; ticks since the level ended

; ---------------- Parking level ---------------------------------------
park_z          dw 0                ; our position along the lot
lot_t           dw 0                ; draw_lot row counter
lot_lines       dw -24, -8, 8, 24   ; world x of the white lot lines
bay_t1          dw 0                ; draw_bay: far edge row
bay_t2          dw 0                ; draw_bay: near edge row

; ---------------- Parking lot objects ---------------------------------
; zs, ze (along the lot), lane, kind, colour, x to draw at
PARK_OBJ_COUNT  equ 5
park_objects:
        dw 5800, 5950                           ; cone left of the bay
        db LANE_LEFT,   KIND_CONE, C_CONE, -12
        dw 5800, 5950                           ; cone right of the bay
        db LANE_RIGHT,  KIND_CONE, C_CONE, 12
        dw 6300, 7350                           ; car left of the bay
        db LANE_LEFT,   KIND_CAR, C_CAR_WHITE, -16
        dw 6300, 7350                           ; car right of the bay
        db LANE_RIGHT,  KIND_CAR, C_CAR_RED, 16
        dw 8400, 9450                           ; car after the bay
        db LANE_MIDDLE, KIND_CAR, C_CAR_RED, 0
obj_drawn       times PARK_OBJ_COUNT db 0
old_z           dw 0                ; park_z before the move
old_lane        db 0                ; lane before the lane change
park_hold       dw 0                ; ticks we have stood in the bay
cone_x          dw 0                ; draw_cone
cone_hw         dw 0
cone_h          dw 0
cone_top        dw 0
three           dw 3

; ---------------- Parking sensor --------------------------------------
sensor_gap      dw 0                ; nearest gap in world units
sensor_dm       dw 0                ; the same in decimetres (0..99)
sensor_lit      dw 0                ; how many lights are on
sensor_txt      db 'SENSOR 0.0 m', 0
seg_colours     db C_SENSOR_GRN, C_SENSOR_GRN, C_SENSOR_GRN
                db C_SENSOR_YEL, C_SENSOR_YEL
                db C_RED, C_RED, C_RED

; ---------------- Bonus layout ----------------------------------------
layout          db LAYOUT_SIMPLE    ; which screen layout is used
b_latch         db 0                ; B was held in the last tick
panel_lights    db C_CAR_BLUE, C_CAR_RED, C_GREEN
                db C_CAR_BLUE, C_CAR_RED, C_GREEN
                db C_CAR_RED, C_GREEN, C_CAR_YELLOW
dial_cx         dw 0                ; centre of the dial being drawn
dial_cy         dw 0
ln_x1           dw 0                ; draw_line
ln_y1           dw 0
ln_x2           dw 0
ln_y2           dw 0
ln_dx           dw 0
ln_dy           dw 0
ln_sx           dw 0
ln_sy           dw 0
ln_err          dw 0
; sin(0..90 degrees) * 256
sin_table:
        dw 0, 4, 9, 13, 18, 22, 27, 31, 36, 40
        dw 44, 49, 53, 58, 62, 66, 71, 75, 79, 83
        dw 88, 92, 96, 100, 104, 108, 112, 116, 120, 124
        dw 128, 132, 136, 139, 143, 147, 150, 154, 158, 161
        dw 165, 168, 171, 175, 178, 181, 184, 187, 190, 193
        dw 196, 199, 202, 204, 207, 210, 212, 215, 217, 219
        dw 222, 224, 226, 228, 230, 232, 234, 236, 237, 239
        dw 241, 242, 243, 245, 246, 247, 248, 249, 250, 251
        dw 252, 253, 254, 254, 255, 255, 255, 256, 256, 256
        dw 256
lg_x            dw 0                ; draw_lane_guide
lg_col          dw 0
lg_arrow        db 0
ind_left        dw 0                ; ticks the left indicator flashes
ind_right       dw 0                ; ticks the right indicator flashes
city_t          dw 0                ; draw_city: row counter
city_xl         dw 0                ; left wall x on the previous row
city_xr         dw 0                ; right wall x on the previous row
city_p          dw 0                ; place along the street
city_col        db 0                ; colour of this building
city_h          dw 0                ; height (1/16 lanes)
city_hpx        dw 0                ; height in pixels on this row
bld_colour      db C_BLD_1, C_BLD_2, C_BLD_3, C_BLD_4
bld_height      dw 70, 100, 85, 120
mr_x            dw 0                ; draw_mirror: car in the glass
mr_y            dw 0
mr_w            dw 0
mr_h            dw 0
city_bno        db 0                ; building number (lit windows)
