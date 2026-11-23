[org 0x0100]

%macro RECT 5
    mov ax, %1
    mov bx, %2
    mov dx, %3
    mov cx, %4
    mov si, %5
    call drawRect
%endmacro

jmp start

;------------------------------
; SECTION 1: HARDWARE KEYBOARD ISR (INT 9)
;------------------------------
installKeyboard:
    pusha
    push es
    xor ax, ax
    mov es, ax
    cli
    mov ax, [es:9*4]
    mov [oldInt9Off], ax
    mov ax, [es:9*4+2]
    mov [oldInt9Seg], ax
    mov word [es:9*4], int9Handler
    mov [es:9*4+2], cs
    sti
    pop es
    popa
    ret

restoreKeyboard:
    pusha
    push es
    xor ax, ax
    mov es, ax
    cli
    mov ax, [oldInt9Off]
    mov [es:9*4], ax
    mov ax, [oldInt9Seg]
    mov [es:9*4+2], ax
    sti
    pop es
    popa
    ret

int9Handler:
    push ax
    push bx
    push ds
    push cs
    pop ds

    in al, 0x60             ; Read scan code
    mov bl, al              ; Save scan code in BL

    ; Acknowledge/clear keyboard controller latch on Port 0x61
    in al, 0x61
    or al, 0x80
    out 0x61, al
    and al, 0x7F
    out 0x61, al

    cmp bl, 0xE0            ; Ignore 0xE0 extended prefix
    je i9_ack

    test bl, 0x80           ; Bit 7 = 1 means key released
    jnz i9_key_up

    and bl, 0x7F
    xor bh, bh
    mov byte [keyDown + bx], 1
    jmp i9_ack

i9_key_up:
    and bl, 0x7F
    xor bh, bh
    mov byte [keyDown + bx], 0

i9_ack:
    mov al, 0x20            ; Send EOI to PIC
    out 0x20, al
    pop ds
    pop bx
    pop ax
    iret

;------------------------------
; SECTION 2: RENDERING ROUTINES
;------------------------------
drawSky:
    pusha
    mov cx, 32000
    mov ax, [vbufSeg]
    mov es, ax
    xor di, di
    mov al, 54
    rep stosb
    popa
    ret

drawGrass:
    pusha
    mov cx, 32000
    mov ax, [vbufSeg]
    mov es, ax
    mov di, 32000
    mov al, 10
    rep stosb
    popa
    ret

hline:
    push dx
    push si
    mov dx, [roadY]
    mov si, 1
    call drawRect
    pop si
    pop dx
    ret

drawRoad:
    pusha
    mov word [roadY], 100

road_loop:
    mov ax, [roadY]
    sub ax, 100
    mov [roadRel], ax

    ; Calculate road width and force it to be even
    mov bx, 3
    mul bx
    add ax, 20
    and ax, 0xFFFE
    mov [roadW], ax

    ; Shift the entire road left/right based on roadShift
    shr ax, 1
    mov bx, 160
    add bx, [roadShift]
    sub bx, ax
    mov [roadL], bx

    ; 1. Clean 1px black outer borders
    xor ax, ax
    mov bx, [roadL]
    dec bx
    mov cx, 1
    call hline

    xor ax, ax
    mov bx, [roadL]
    add bx, [roadW]
    mov cx, 1
    call hline

    ; 2. Main asphalt surface (color 8 = dark gray)
    mov ax, 8
    mov bx, [roadL]
    mov cx, [roadW]
    call hline

    ; 3. Clean, uniform 2px white inner shoulder lines
    mov ax, 15
    mov bx, [roadL]
    mov cx, 2
    call hline

    mov ax, 15
    mov bx, [roadL]
    add bx, [roadW]
    sub bx, 2
    mov cx, 2
    call hline

    ; 4. Animated 2px dashed lane dividers
    mov ax, [roadY]
    sub ax, [dashPhase]
    test ax, 8
    jnz skip_dash

    mov ax, [roadW]
    xor dx, dx
    mov bx, 3
    div bx
    mov [roadThird], ax

    mov bx, [roadL]
    add bx, ax
    mov ax, 15
    mov cx, 2
    call hline

    mov ax, [roadThird]
    shl ax, 1
    mov bx, [roadL]
    add bx, ax
    mov ax, 15
    mov cx, 2
    call hline

skip_dash:
    inc word [roadY]
    cmp word [roadY], 175
    jl near road_loop
    popa
    ret

drawTrafficCars:
    pusha
    mov si, 0

dtc_loop:
    cmp si, 3
    jge near dtc_done

    mov di, si
    shl di, 1
    mov ax, [carY + di]
    cmp ax, 100
    jl near dtc_next
    cmp ax, 174
    jge near dtc_next

    mov [curCarY], ax
    sub ax, 100
    mov [curRelY], ax

    ; Road width at curCarY
    mov bx, 3
    mul bx
    add ax, 20
    and ax, 0xFFFE
    mov [curRoadW], ax

    ; Road left X at curCarY (includes roadShift so traffic moves with the road)
    shr ax, 1
    mov bx, 160
    add bx, [roadShift]
    sub bx, ax
    mov [curRoadL], bx

    ; Scale car width (8 + relY / 3) and height (5 + relY / 3)
    mov ax, [curRelY]
    xor dx, dx
    mov bx, 3
    div bx
    add ax, 8
    mov [curCarW], ax

    mov ax, [curRelY]
    xor dx, dx
    mov bx, 3
    div bx
    add ax, 5
    mov [curCarH], ax

    ; Lane center X = curRoadL + (curRoadW * (2*lane + 1)) / 6
    mov bl, [carLane + si]
    xor bh, bh
    shl bx, 1
    inc bx
    mov ax, [curRoadW]
    mul bx
    xor dx, dx
    mov bx, 6
    div bx
    add ax, [curRoadL]

    ; Top-left X = centerX - (curCarW / 2)
    mov bx, [curCarW]
    shr bx, 1
    sub ax, bx
    mov [curCarX], ax

    ; Draw car body
    xor ax, ax
    mov al, [carColor + si]
    mov bx, [curCarX]
    mov dx, [curCarY]
    mov cx, [curCarW]
    mov bp, [curCarH]
    push si
    mov si, bp
    call drawRect
    pop si

    ; Draw red taillights
    mov dx, [curCarY]
    add dx, [curCarH]
    sub dx, 2
    cmp dx, 174
    jge dtc_next

    mov bx, [curCarX]
    inc bx
    push si
    RECT 4, bx, dx, 2, 1
    pop si

    mov bx, [curCarX]
    add bx, [curCarW]
    sub bx, 3
    push si
    RECT 4, bx, dx, 2, 1
    pop si

dtc_next:
    inc si
    jmp dtc_loop

dtc_done:
    popa
    ret

drawBonnetAndDash:
    pusha
    mov ax, [vbufSeg]
    mov es, ax
    mov dx, 140

bonnet_loop:
    mov ax, dx
    sub ax, 140
    mov bx, 14
    push dx
    mul bx
    pop dx
    add ax, 100
    mov cx, ax
    cmp cx, 320
    jle width_ok
    mov cx, 320

width_ok:
    mov bx, cx
    shr bx, 1
    mov ax, 160
    sub ax, bx
    mov bx, ax
    push dx
    mov ax, 320
    mul dx
    add ax, bx
    mov di, ax
    pop dx
    ; Flash bonnet white briefly on crash, otherwise orange-red (42)
    mov al, 42
    cmp byte [crashTimer], 0
    je bonnet_color_ok
    mov al, 15
	
bonnet_color_ok:
    rep stosb
    inc dx
    cmp dx, 175
    jl bonnet_loop

    ; Black dashboard area (Y = 175..199)
    mov dx, 175
dash_loop:
    push dx
    mov ax, 320
    mul dx
    mov di, ax
    pop dx
    mov cx, 320
    mov al, 0
    rep stosb
    inc dx
    cmp dx, 200
    jl dash_loop
    popa
    ret

drawRect:
    pusha
    mov bp, ax

rect_row:
    cmp dx, 0
    jl rect_skip_row
    cmp dx, 200
    jge rect_done

    push cx
    push dx
    push bx

    cmp bx, 0
    jge rx_left_ok
    add cx, bx
    xor bx, bx
	
rx_left_ok:
    cmp cx, 0
    jle rx_skip_draw
    mov ax, bx
    add ax, cx
    cmp ax, 320
    jle rx_right_ok
    mov cx, 320
    sub cx, bx
    cmp cx, 0
    jle rx_skip_draw
	
rx_right_ok:
    mov ax, 320
    mul dx
    add ax, bx
    mov di, ax
    mov ax, [vbufSeg]
    mov es, ax
    mov ax, bp
    rep stosb

rx_skip_draw:
    pop bx
    pop dx
    pop cx

rect_skip_row:
    inc dx
    dec si
    jnz rect_row

rect_done:
    popa
    ret

drawRing:
    pusha
    mov [ringColor], al
    mov [cenX], bx
    mov [cenY], dx
    mov [rad], si
    mov ax, si
    mul ax
    mov [outR2], ax
    mov ax, si
    sub ax, cx
    mul ax
    mov [inR2], ax
    mov ax, [vbufSeg]
    mov es, ax
    mov bp, si
    neg bp

ring_y:
    mov si, [rad]
    neg si

ring_x:
    mov ax, bp
    imul ax
    mov bx, ax
    mov ax, si
    imul ax
    add bx, ax
    cmp bx, [outR2]
    ja ring_skip
    cmp bx, [inR2]
    jb ring_skip
    mov ax, [cenY]
    add ax, bp
    mov dx, 320
    mul dx
    add ax, [cenX]
    add ax, si
    mov di, ax
    mov al, [ringColor]
    mov [es:di], al

ring_skip:
    inc si
    cmp si, [rad]
    jle ring_x
    inc bp
    cmp bp, [rad]
    jle ring_y
    popa
    ret

flipScreen:
    pusha
    mov dx, 0x03DA
vsync_1:
    in al, dx
    test al, 8
    jnz vsync_1
vsync_2:
    in al, dx
    test al, 8
    jz vsync_2

    push ds
    mov ax, 0xa000
    mov es, ax
    mov ax, [vbufSeg]
    mov ds, ax
    xor si, si
    xor di, di
    mov cx, 32000
    rep movsw
    pop ds
    popa
    ret

;------------------------------
; SECTION 3: TEXT & HUD ROUTINES
;------------------------------
gotoRC:
    pusha
    mov ah, 02h
    mov bh, 0
    int 0x10
    popa
    ret

putc:
    pusha
    mov ah, 0Eh
    mov bh, 0
    mov bl, [txtColor]
    int 0x10
    popa
    ret

printStr:
    pusha
ps_next:
    lodsb
    or al, al
    jz ps_done
    call putc
    jmp ps_next
ps_done:
    popa
    ret

printDec:
    pusha
    mov si, cx
    mov bx, 10
pd_div:
    xor dx, dx
    div bx
    push dx
    loop pd_div
    mov cx, si
pd_out:
    pop ax
    add al, '0'
    call putc
    loop pd_out
    popa
    ret

drawUIGraphics:
    pusha
    ; Time bar (vertical on left: X = 10, Y = 25..125, max height = 100)
    RECT 0, 9, 24, 8, 102
    mov ax, [timeVal]
    xor dx, dx
    mov bx, 10
    div bx
    cmp ax, 0
    jle skip_time_fill
    mov si, ax
    mov dx, 125
    sub dx, ax
    RECT 11, 10, dx, 6, si

skip_time_fill:
    ; Fuel bar (horizontal on dashboard: X = 200, Y = 185, max width = 40)
    RECT 8, 200, 185, 40, 6
    mov ax, [fuelVal]
    xor dx, dx
    mov bx, 10
    div bx
    cmp ax, 0
    jle skip_fuel_fill
    mov cx, ax
    mov ax, 2
    cmp word [fuelVal], 100
    ja fuel_color_ok
    mov ax, 12
fuel_color_ok:
    RECT ax, 200, 185, cx, 6

skip_fuel_fill:
    ; HUD text backgrounds
    RECT 0, 2, 4, 118, 14       ; distance box (top-left)
    RECT 0, 214, 4, 102, 14     ; score box (top-right)
    RECT 8, 116, 180, 72, 16    ; speedometer box (center dash)

    ; Steering wheel
    mov bx, 275
    mov dx, 165
    mov si, 25
    mov cx, 4
    mov al, 7
    call drawRing
    RECT 7, 254, 164, 43, 3
    RECT 7, 274, 166, 3, 20
    mov bx, 275
    mov dx, 165
    mov si, 7
    mov cx, 7
    mov al, 8
    call drawRing
    popa
    ret

drawUIText:
    pusha
    ; TIME label
    mov byte [txtColor], 15
    mov dh, 2
    mov dl, 0
    call gotoRC
    mov si, strTime
    call printStr

    ; FUEL, E, F labels
    mov byte [txtColor], 15
    mov dh, 22
    mov dl, 25
    call gotoRC
    mov si, strFuel
    call printStr

    mov byte [txtColor], 12
    mov dh, 23
    mov dl, 24
    call gotoRC
    mov si, strE
    call printStr

    mov byte [txtColor], 10
    mov dh, 23
    mov dl, 30
    call gotoRC
    mov si, strF
    call printStr

    ; SPEED readout
    mov dh, 23
	mov dl, 15
	call gotoRC
	mov byte [txtColor], 15
	mov ax, [speed]
	mov cx, 3
	call printDec
	mov byte [txtColor], 7
	mov si, strKmh
	call printStr
	
	; DISTANCE readout (00.00 KM -> 01.00 KM = 1000m)
	mov dh, 1
	mov dl, 1
	call gotoRC
	mov byte [txtColor], 7
	mov si, strDist
	call printStr
	mov byte [txtColor], 15
	mov ax, [distMeters]
	xor dx, dx
	mov bx, 10
	div bx
	xor dx, dx
	mov bx, 100
	div bx
	push dx
	mov cx, 2
	call printDec
	mov al, '.'
	call putc
	pop ax
	mov cx, 2
	call printDec
	mov byte [txtColor], 7
	mov si, strKm
	
	call printStr

	; SCORE readout (top-right)
	mov dh, 1
	mov dl, 27
	call gotoRC
	mov byte [txtColor], 7
	mov si, strScore
	call printStr
	mov byte [txtColor], 14
	mov ax, [score]
	mov cx, 4
	call printDec
	popa
	ret
	
;------------------------------------
; SECTION 4: GAMEPLAY & LOGIC ROUTINES
;------------------------------------
handleInput:
    pusha

    ; ESC (0x01) -> exit
    cmp byte [keyDown + 0x01], 1
    je near exit_prog

    ; Left Arrow (0x4B) or 'A' (0x1E) -> move 1 lane left
    mov al, [keyDown + 0x4B]
    or al, [keyDown + 0x1E]
    cmp al, 1
    jne chk_right_key
    cmp byte [leftLock], 1
    je chk_speed_keys
    mov byte [leftLock], 1
    cmp byte [playerLane], 0
    je chk_speed_keys
    dec byte [playerLane]
    jmp chk_speed_keys
chk_right_key:
    mov byte [leftLock], 0

    ; Right Arrow (0x4D) or 'D' (0x20) -> move 1 lane right
    mov al, [keyDown + 0x4D]
    or al, [keyDown + 0x20]
    cmp al, 1
    jne release_right_lock
    cmp byte [rightLock], 1
    je chk_speed_keys
    mov byte [rightLock], 1
    cmp byte [playerLane], 2
    je chk_speed_keys
    inc byte [playerLane]
    jmp chk_speed_keys
	
release_right_lock:
    mov byte [rightLock], 0

chk_speed_keys:
    ; Spacebar (0x39) -> gradual brake to 0
    cmp byte [keyDown + 0x39], 1
    je do_brake

    ; Up Arrow (0x48) or 'W' (0x11) -> accelerate up to 180 KM/H
    mov al, [keyDown + 0x48]
    or al, [keyDown + 0x11]
    cmp al, 1
    je do_accel

    ; Down Arrow (0x50) or 'S' (0x1F) -> reverse ONLY when speed == 0
    mov al, [keyDown + 0x50]
    or al, [keyDown + 0x1F]
    cmp al, 1
    jne do_coast
    cmp word [speed], 0
    jne do_coast
    cmp word [distSub], 20
    jb update_road_shift
    sub word [distSub], 20
    jmp update_road_shift

do_coast:
    cmp word [speed], 0
    je update_road_shift
    dec word [speed]
    jmp update_road_shift

do_brake:
    cmp word [speed], 6
    jbe brake_zero
    sub word [speed], 6
    jmp update_road_shift
brake_zero:
    mov word [speed], 0
    jmp update_road_shift

do_accel:
    add word [speed], 4
    cmp word [speed], 180
    jle update_road_shift
    mov word [speed], 180

update_road_shift:
    mov al, [playerLane]
    cmp al, 0
    je target_left
    cmp al, 2
    je target_right
    mov bx, 0
    jmp slide_road

target_left:
    mov bx, 66
    jmp slide_road

target_right:
    mov bx, -66

slide_road:
    mov ax, [roadShift]
    cmp ax, bx
    je hi_done
    jl slide_inc
    sub ax, 11
    cmp ax, bx
    jge store_shift
    mov ax, bx
    jmp store_shift
slide_inc:
    add ax, 11
    cmp ax, bx
    jle store_shift
    mov ax, bx
store_shift:
    mov [roadShift], ax

hi_done:
    popa
    ret

updateTraffic:
    pusha
    ; Traffic approach speed = 1 + (playerSpeed / 45)
    mov ax, [speed]
    xor dx, dx
    mov bx, 45
    div bx
    inc ax
    mov [trafficStep], ax

    mov si, 0
ut_loop:
    cmp si, 3
    jge ut_done

    mov di, si
    shl di, 1
    mov ax, [carY + di]
    add ax, [trafficStep]
    mov [carY + di], ax

    ; Trigger collision only when car visually hits the bonnet (Y = 136..158)
    cmp ax, 136
    jl ut_chk_wrap
    cmp ax, 158
    jg ut_chk_wrap

    mov bl, [carLane + si]
    cmp bl, [playerLane]
    jne ut_chk_wrap

    ; COLLISION DETECTED -> Game Over
    mov word [speed], 0
    mov byte [crashedFlag], 1
    jmp ut_done

ut_chk_wrap:
    cmp ax, 174
    jl ut_next
    ; Wrap 156px back (3 cars * 52px spacing = 156px) for wide, fair gaps
    sub word [carY + di], 156
    mov al, [carLane + si]
    inc al
    cmp al, 3
    jb ut_store_lane
    xor al, al
ut_store_lane:
    mov [carLane + si], al

ut_next:
    inc si
    jmp ut_loop

ut_done:
    popa
    ret

updateBars:
	pusha
	cmp word [timeVal], 0
	je ub_after_time
	dec word [timeVal]

ub_after_time:
	mov ax, [speed]
	cmp ax, 0
	je ub_done
	mov bx, 1
	cmp ax, 100
	jbe ub_drain_fuel
	inc bx

ub_drain_fuel:
	cmp word [fuelVal], bx
	jbe ub_empty_fuel
	sub [fuelVal], bx
	jmp ub_done

ub_empty_fuel:
	mov word [fuelVal], 0

ub_done:
	popa
	ret

updateProgress:
	pusha
	mov ax, [speed]
	add [distSub], ax

up_tick_loop:
	cmp word [distSub], 90
	jb up_done
	sub word [distSub], 90
	inc word [distMeters]
	add word [score], 5
	jmp up_tick_loop

up_done:
	mov ax, [speed]
	cmp ax, 0
	je up_ret
	mov cl, 4
	shr ax, cl
	inc ax
	add [dashPhase], ax

up_ret:
	popa
	ret

updateGame:
	call updateTraffic
	call updateBars
	call updateProgress
	ret

level_won:
	mov si, msgWin
	jmp showEndMessage

level_out_of_time:
	mov si, msgTime
	jmp showEndMessage

level_out_of_fuel:
	mov si, msgFuel
	jmp showEndMessage

level_crashed:
	mov si, msgCrash
	jmp showEndMessage
	
showEndMessage:
	push si
	RECT 0, 48, 72, 224, 52
	RECT 15, 50, 74, 220, 48
	RECT 1, 52, 76, 216, 44
	call flipScreen
	mov byte [txtColor], 14
	mov dh, 10
	mov dl, 9
	call gotoRC
	pop si
	call printStr
	mov byte [txtColor], 15
	mov dh, 12
	mov dl, 12
	call gotoRC
	mov si, strFinalScore
	call printStr
	mov ax, [score]
	mov cx, 4
	call printDec
	mov byte [txtColor], 7
	mov dh, 14
	mov dl, 9
	call gotoRC
	mov si, strPressKey
	call printStr
	call restoreKeyboard

flush_keys:
	mov ah, 01h
	int 0x16
	jz wait_end_key
	mov ah, 00h
	int 0x16
	jmp flush_keys

wait_end_key:
	mov ah, 00h
	int 0x16
	jmp exit_prog_direct

;---------------------------------------
; SECTION 5: MAIN ENTRY POINT & GAME LOOP
;---------------------------------------
start:
	cld
	mov ax, cs
	add ax, 0x1000
	
	mov [vbufSeg], ax
	call installKeyboard
	mov ah, 00h
	mov al, 13h
	int 0x10

game_loop:
	call handleInput
	call updateGame
	
	cmp byte [crashedFlag], 1
	je level_crashed
	cmp word [distMeters], 1000
	jge level_won
	cmp word [timeVal], 0
	je level_out_of_time
	cmp word [fuelVal], 0
	je level_out_of_fuel
	
	call drawSky
	call drawGrass
	call drawRoad
	call drawTrafficCars
	call drawBonnetAndDash
	call drawUIGraphics
	call flipScreen
	call drawUIText
	jmp game_loop

exit_prog:
	call restoreKeyboard

exit_prog_direct:
	mov ah, 00h
	mov al, 03h
	int 0x10	
	mov ax, 0x4c00
	int 0x21

;---------------------------
; SECTION 6: DATA & VARIABLES
;---------------------------
oldInt9Off    dw 0
oldInt9Seg    dw 0
keyDown       times 128 db 0
leftLock      db 0
rightLock     db 0
crashTimer    db 0
vbufSeg       dw 0
cenX          dw 0
cenY          dw 0
rad           dw 0
outR2         dw 0
inR2          dw 0
ringColor     db 0
roadY         dw 0
roadRel       dw 0
roadW         dw 0
roadL         dw 0
roadThird     dw 0
roadShift     dw 0
dashPhase     dw 0
playerLane    db 1
speed         dw 0
distSub       dw 0
distMeters    dw 0
score         dw 0
timeVal       dw 1500
fuelVal       dw 400
txtColor      db 15
strDist       db 'DIST ', 0
strKm         db ' KM', 0
strScore      db 'SCORE ', 0
strKmh        db ' KM/H', 0
strTime       db 'TIME', 0
strFuel       db 'FUEL', 0
strE          db 'E', 0
strF          db 'F', 0
crashedFlag   db 0
carY          dw 100, 48, -4      ;Cars are 52 pixels apart
carLane       db 0, 2, 1
carColor      db 1, 4, 14
trafficStep   dw 1
curCarX       dw 0
curCarY       dw 0
curRelY       dw 0
curRoadW      dw 0
curRoadL      dw 0
curCarW       dw 0
curCarH       dw 0
msgWin        db 'LEVEL COMPLETE! 1000M!', 0
msgTime       db 'GAME OVER: OUT OF TIME', 0
msgFuel       db 'GAME OVER: OUT OF FUEL', 0
msgCrash	  db 'GAME OVER: CAR CRASHED', 0
strFinalScore db 'FINAL SCORE: ', 0
strPressKey   db 'PRESS ANY KEY TO EXIT', 0