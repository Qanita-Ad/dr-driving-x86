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
;    main program, data.
;
;  Phase 2: highway driving. Arrow keys and Space drive the car,
;  traffic moves, collisions, fuel, time, distance and score work.
;  ESC returns to DOS.
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
PALETTE_COUNT   equ 31              ; how many colours we define

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
HIT_BACK        equ -1700           ; ... but not further behind = crash
CRASH_PENALTY   equ 50              ; points lost in a crash
CRASH_SHOW      equ 2 * TICKS_PER_SEC   ; "CRASH" text stays 2 seconds

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
        pop bp
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
        mov dx, SCREEN_H - HORIZON
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
;  A car is just a few rectangles:
;      +-------------+   <- body (car colour)
;      |  +-------+  |   <- rear window (dark blue)
;      |  +-------+  |
;      |[]         []|   <- tail lights (red)
;      +=============+   <- bumper (dark)
;  The size of every part is a fraction of the lane width on the row
;  where the car stands, so far cars are small and near cars are big.
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
        ; height = 5/8 of the width, at least 2 pixels
        mov bx, 5
        mul bx
        shr ax, 3
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

        ; ---- body
        mov al, [car_colour]
        mov [color], al
        mov ax, [car_left]
        mov bx, [car_top]
        mov cx, [car_w]
        mov dx, [car_h]
        call fill_rect

        ; ---- rear window: inset by width/8, from h/6 down to h/2
        mov byte [color], C_WINDOW
        mov si, [car_w]
        shr si, 3               ; SI = width / 8
        mov ax, [car_h]
        xor dx, dx
        mov bx, 6
        div bx
        mov di, ax              ; DI = height / 6
        mov ax, [car_left]
        add ax, si
        mov bx, [car_top]
        add bx, di
        mov cx, [car_w]
        sub cx, si
        sub cx, si
        mov dx, [car_h]
        shr dx, 1
        sub dx, di              ; window height = h/2 - h/6
        jg .win_ok
        mov dx, 1
.win_ok:
        call fill_rect

        ; ---- tail lights: size w/6 x h/5, placed at 3/5 of the height
        mov byte [color], C_TAIL
        mov ax, [car_w]
        xor dx, dx
        mov bx, 6
        div bx
        cmp ax, 1
        jge .lw_ok
        mov ax, 1
.lw_ok: mov si, ax              ; SI = light width
        mov ax, [car_h]
        xor dx, dx
        mov bx, 5
        div bx
        cmp ax, 1
        jge .lh_ok
        mov ax, 1
.lh_ok: mov di, ax              ; DI = light height
        mov ax, [car_h]
        mov bx, 3
        mul bx
        mov bx, 5
        div bx                  ; AX = 3h/5
        add ax, [car_top]
        mov bx, ax              ; BX = light top row
        mov ax, [car_left]
        mov cx, si
        mov dx, di
        call fill_rect          ; left light
        mov ax, [car_left]
        add ax, [car_w]
        sub ax, si
        call fill_rect          ; right light

        ; ---- dark bumper on the bottom row(s)
        mov byte [color], C_WHEEL
        mov dx, [car_h]
        shr dx, 3               ; bumper height = h/8
        cmp dx, 1
        jge .b_ok
        mov dx, 1
.b_ok:  mov bx, [car_bottom]
        sub bx, dx
        inc bx
        mov ax, [car_left]
        mov cx, [car_w]
        call fill_rect
.done:
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
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
        push si
        call player_velocity    ; AX = our speed (+ forward, - reverse)
        sub ax, TRAFFIC_SPEED   ; AX = how much closer each car comes
        mov si, traffic
        mov cx, TRAFFIC_COUNT
.next:  mov bx, [si + CAR_Z]
        sub bx, ax
        cmp bx, RING_BACK
        jge .not_behind
        add bx, RING_LEN        ; far behind us: back to the horizon
.not_behind:
        cmp bx, RING_BACK + RING_LEN
        jl .not_too_far
        sub bx, RING_LEN        ; drove away too far: put it behind us
.not_too_far:
        mov [si + CAR_Z], bx
        add si, CAR_REC_SIZE
        loop .next
        pop si
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
; draw_bonnet : the orange curved bonnet (element 5).
;   The top edge is a parabola:  y = BONNET_TOP + (x-160)^2 / CURVE
;   For every row y we need the half width of the bonnet:
;       half = sqrt( (y - BONNET_TOP) * CURVE )
;   and then draw one horizontal line from 160-half to 160+half.
; ---------------------------------------------------------------------
draw_bonnet:
        push ax
        push bx
        push cx
        push dx
        push si
        mov dx, BONNET_TOP
.row:
        mov ax, dx
        sub ax, BONNET_TOP
        mov cx, BONNET_CURVE
        push dx
        mul cx                  ; AX = (y - top) * CURVE
        pop dx
        call isqrt              ; AX = half width
        mov si, ax
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
        call draw_string
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
        call draw_string_adv
        mov ax, [distance]
        mov cx, 1
        call number_to_string   ; SI -> digits
        call draw_string_adv
        mov si, txt_dist_end
        call draw_string_adv
        ; score line in yellow
        mov byte [color], C_YELLOW
        mov bx, HUD_TEXT_X
        mov dx, 13
        mov si, txt_score
        call draw_string_adv
        mov ax, [score]
        mov cx, 1
        call number_to_string
        call draw_string_adv
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
        mov bx, HUD_TEXT_X
        mov dx, 8
        mov si, txt_score
        call draw_string_adv
        mov ax, [score]
        mov cx, 1
        call number_to_string
        call draw_string_adv
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
        cmp ax, MAX_SPEED * 16
        jbe .no_up
        mov ax, MAX_SPEED * 16  ; top speed reached
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
        ; ---- Left arrow
        mov al, [key_down + SC_LEFT]
        cmp al, 1
        jne .left_done
        cmp byte [left_latch], 1
        je .left_done           ; same press as before: ignore
        cmp byte [player_lane], LANE_LEFT
        je .left_done           ; already in the leftmost lane
        dec byte [player_lane]
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
;  Our car takes the space from HIT_BACK to HIT_FRONT (world units,
;  measured from the driver). A traffic car hits us when it is in OUR
;  lane and its z is inside that space. HIT_FRONT is the place where
;  a car touches the bonnet on the screen.
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
        cmp bx, HIT_BACK
        jle .skip
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
;  highway_update : one game step (called once per timer tick)
;  draw_highway_frame : draws the picture. Order matters (painter's
;  method): background, road, cars, our own car, then the HUD.
; =====================================================================

; ---------------------------------------------------------------------
; highway_start : reset everything for a fresh highway level.
; ---------------------------------------------------------------------
highway_start:
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
        mov byte [gear], GEAR_D
        mov word [crash_timer], 0
        ret

; ---------------------------------------------------------------------
; highway_update : one game step. Called once for every timer tick.
; ---------------------------------------------------------------------
highway_update:
        call player_controls    ; read the pedals
        call player_lanes       ; lane changes
        call move_car           ; distance, score, road movement
        call traffic_update     ; other cars move
        call check_collisions   ; crash?
        call count_down_time
        ret

; ---------------------------------------------------------------------
; draw_highway_frame : build one complete picture in the back buffer.
; ---------------------------------------------------------------------
draw_highway_frame:
        call draw_sky_ground    ; sky and grass
        call draw_road          ; element 3: road and lane lines
        call draw_traffic       ; element 4: traffic cars
        call draw_bonnet        ; element 5: orange bonnet
        call draw_dashboard
        call draw_speed_box     ; element 6
        call draw_gear          ; D or R
        call draw_fuel_bar      ; element 7
        call draw_wheel         ; element 8
        call draw_time_bar      ; element 1
        call draw_dist_score    ; element 2
        call draw_crash_message
        ret


; =====================================================================
;  main program
; ---------------------------------------------------------------------
;  The game loop:  update the game  ->  draw a frame  ->  show it,
;  again and again until ESC is pressed.
; =====================================================================
start:
        call video_init         ; mode 13h, palette, font, buffer
        call install_keyboard   ; our INT 9 handler
        call install_timer      ; our INT 8 handler, 73 ticks/second
        mov es, [back_seg]      ; ES = back buffer for all drawing
        call highway_start

main_loop:
        ; ---- 1. one game update for every timer tick that has passed
        cmp word [tick_count], MAX_UPDATES
        jbe .catch_up
        mov word [tick_count], MAX_UPDATES  ; very slow PC: skip some
.catch_up:
        cmp word [tick_count], 0
        je .draw
        dec word [tick_count]
        call highway_update
        jmp .catch_up
        ; ---- 2. draw the new picture and show it
.draw:
        call draw_highway_frame ; draw the picture in the buffer
        call flip_screen        ; show it
        cmp byte [key_down + SC_ESC], 1
        jne main_loop           ; keep going until ESC is held

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
player_lane     db LANE_MIDDLE      ; 0 = left, 1 = middle, 2 = right
gear            db GEAR_D           ; 'D' = drive, 'R' = reverse
left_latch      db 0                ; Left was held in the last tick
right_latch     db 0                ; Right was held in the last tick

; ---------------- Distance --------------------------------------------
dist_acc        dw 0                ; world units not yet a full metre
best_distance   dw 0                ; farthest metre reached (for score)

; ---------------- Collisions ------------------------------------------
crash_timer     dw 0                ; ticks the CRASH text stays
