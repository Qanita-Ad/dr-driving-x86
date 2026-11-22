; =====================================================================
;  Dr. Driving Lite  -  COAL Final Project (FAST Lahore)
;  drive.asm  -  the complete game in ONE file
; ---------------------------------------------------------------------
;  Build :  nasm drive.asm -o drive.com
;  Run   :  drive.com   (inside DOSBox)
;
;  Sections of this file, in order:
;    constants, graphics (video), text, road, cars, traffic,
;    cockpit, HUD, highway level, main program, data.
;
;  Phase 1: draws the highway screen with all 8 elements and fixed
;  values, then waits for any key and returns to DOS.
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

; =====================================================================
;  highway.asm  -  Level 1: the highway screen
; ---------------------------------------------------------------------
;  Phase 1: only draws the screen with fixed values.
;  Order matters (painter's method): background first, then the road,
;  then the cars, then our own car (bonnet, dashboard), then the HUD.
; =====================================================================

; ---------------------------------------------------------------------
; draw_highway_frame : build one complete picture in the back buffer.
; ---------------------------------------------------------------------
draw_highway_frame:
        call draw_sky_ground    ; sky and grass
        ret


start:
        call video_init         ; mode 13h, palette, font, buffer
        mov es, [back_seg]      ; ES = back buffer for all drawing

        call draw_highway_frame ; draw the picture in the buffer
        call flip_screen        ; show it

        mov ah, 00h             ; wait for any key (BIOS keyboard)
        int 16h

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
; Phase 1: fixed numbers, exactly like Figure 1.




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






