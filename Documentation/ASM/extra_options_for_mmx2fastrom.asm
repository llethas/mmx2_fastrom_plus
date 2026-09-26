; ============================================================================
;  Mega Man X2 (SNES, USA) [FastROM v4.0 patch] -- EXTRA OPTIONS menu
;  Apply after: "Megaman X2 (U) - Fastrom v4.0.ips"
; ============================================================================
;
;  ASSEMBLER
;    Written for Asar (https://github.com/RPGHacker/asar), LoROM, no header.
;    Build with checksum-fixing disabled because this patch does not modify
;    the SNES header or checksum bytes:
;
;        asar --fix-checksum=off extra_options_for_mmx2fastrom.asm rom.sfc
;
;  WHAT IT DOES
;    Adds a 4th item to the title-screen main menu, below OPTION MODE:
;          GAME START / PASS WORD / OPTION MODE / EXTRA OPTIONS
;
;    EXTRA OPTIONS opens a separate screen containing:
;          D-TAP DASH       OFF/ON   (LEFT/RIGHT toggles, OFF by default)
;          BETTER SUB-TANK  ON/OFF   (LEFT/RIGHT toggles, ON by default)
;          EXIT                      (returns to the main menu)
;
;    D-TAP DASH gates the double-tap-to-dash detector in gameplay.
;      OFF: double-tapping a direction, on the ground or in the air, does
;           nothing. The DASH button still works normally.
;      ON : the existing vanilla double-tap behaviour remains enabled.
;
;    BETTER SUB-TANK switches the Sub-Tank behaviour implemented by this
;    patch's runtime gate:
;      ON : (1) a Sub-Tank stops draining the moment X's health is full and
;               keeps its remaining energy;
;           (2) the refill SFX and transfer-active state end at once, so the
;               weapon-menu cursor unlocks immediately;
;           (3) Sub-Tanks never consolidate / move energy between each other.
;      OFF: the vanilla game behaviour is used: the tank drains all of its
;           stored energy, including the normal refill SFX, and the tanks
;           consolidate afterwards.
;
;    OPTION MODE (the original screen: code $80:EA36-EE06, its strings,
;    messages, and tables) is NOT modified. EXTRA OPTIONS is an independent
;    screen built from the same menu structure and shared engine routines.
;    Its two option bytes live in the existing extended default-options WRAM
;    block at $7E:FFDB-$7E:FFDC. The separate SRAM save patch persists them
;    across a hard reset.
;
;  NOTE ON MAIN MENU LAYOUT
;    With four rows, the bottom row plus the cursor sprite (which is about
;    33px tall and centred on its Y position) would be clipped by the bottom
;    of the screen if the original three rows stayed where they were.
;    The whole main menu is therefore shifted up by two tile rows (16px):
;    rows 18/20/22/24 are used instead of 20/22/24.
;
;    The original main-menu messages $10-$12 are left in the ROM untouched;
;    they are simply no longer selected by the four-row menu.
; ============================================================================

lorom

!DTAP_FLAG = $7EFFDB             ; $00 = OFF (default), $01 = ON
!SUB_FLAG  = $7EFFDC             ; $00 = OFF (vanilla), $01 = ON (default)
!CURSOR    = $7EFF80             ; scratch, same byte OPTION MODE uses for its cursor
; (re-initialised on every entry to either screen)

; message IDs ($55-$58 are deliberately left free; $75+ are not valid IDs)
!MSG_MAIN0   = $59               ; $59-$5C main menu, cursor on row 0-3
!MSG_BOX_LIT = $5D               ; frame around the toggles, highlighted
!MSG_BOX_DIM = $5E               ; frame, dimmed (cursor on EXIT)
!MSG_DTAP_OFF = $5F              ; $5F-$62: "D-TAP DASH  OFF" normal / hi, "ON" normal / hi
!MSG_SUB_OFF  = $63              ; $63-$66: "BETTER SUB-TANK  OFF" normal / hi, "ON" normal / hi
!MSG_EXIT    = $2F               ; existing OPTION MODE "EXIT" (normal)   -- reused, not edited
!MSG_EXIT_HI = $30               ; existing OPTION MODE "EXIT" (highlighted)

; ============================================================================
; 1. Default values: extend the 27-byte "default options" copy to 29 bytes so
;    $7E:FFDB and $7E:FFDC get their defaults from ROM:
;      $86:F214 = $00 -> D-TAP DASH OFF
;      $86:F215 = $01 -> BETTER SUB-TANK ON
;    (Both bytes were unused: the only neighbours are the 16-byte block
;     $7EFFCB-FFDA and nothing in the ROM references $7EFFDB-FFDF.)
; ============================================================================
assert read1($86F214) == $00, "default table byte for D-TAP DASH changed"
assert read1($86F215) == $01, "default table byte for BETTER SUB-TANK changed"
org $8082A8
        db $1C                   ; was $1A  (LDX #$1A -> LDX #$1C)

; ============================================================================
; 2. Main menu ($80:9043 state machine)
; ============================================================================
; state 0 (init): initial draw with cursor on row 0, and cursor sprite Y
org $8090E3
        db $96                   ; sprite Y for row 0: was $A6 (shifted up 16px)
org $809114
        db !MSG_MAIN0            ; was $10

; state 2 (cursor): 4 rows instead of 3
org $809160
        db $03                   ; UP from row 0 wraps to row 3  (was #$02)
org $80916B
        db $04                   ; DOWN wraps after row 3         (was #$03)
org $809174
        dw MainMenuSpriteY       ; LDA MainMenuSpriteY,X          (was $8742)
org $80917D
        db !MSG_MAIN0            ; message = !MSG_MAIN0 + cursor  (was +$10)

; state 4 (selection): route through our dispatcher.
; original: LDA $3C / ASL A / TAX  (4 bytes), followed by JMP ($9204,X)
org $8091FD
        JML ExtraDispatch

; ============================================================================
; 3. Message pointer table entries
; ============================================================================
org $868C6F+(!MSG_MAIN0*2)
        dw MsgMain0, MsgMain1, MsgMain2, MsgMain3
org $868C6F+(!MSG_BOX_LIT*2)
        dw MsgBoxLit, MsgBoxDim
        dw MsgDTapOff, MsgDTapOffHi, MsgDTapOn, MsgDTapOnHi
        dw MsgSubOff,  MsgSubOffHi,  MsgSubOn,  MsgSubOnHi

; ============================================================================
; 4. Sub-Tank behaviour, switchable at run time  (was subtank_stop_on_full)
;
;    Vanilla transfer handler at $80:C2CB (per frame while a Sub-Tank refills):
;       C2CB  DEC $2A / BNE $C300 / LDA #$02 / STA $2A / LDA #$15 / JSL $808549
;       C2D9  (body: INC health, DEC $2B, DEC tank energy ...)
;       C2F9  JSR $C5DA      <- consolidate all tanks (the only call site)
;       C300  RTS
;    Every byte the sub-tank patch touches is (re)written here, so this works
;    on top of the vanilla bytes and on top of subtank_stop_on_full alike.
; ============================================================================
; per-frame handler: replace the 14-byte prologue with a hook.
; (NB: the branch target must be a label.  asar silently assembles a branch to
;  a bare address such as "bra $C300" as offset 0, which would fall through
;  into the vanilla body a second time.)
OrigHandlerExit = $80C300
org $80C2CB
        JSR SubTankFrame
        BRA OrigHandlerExit      ; original handler exit (RTS)
        NOP : NOP : NOP : NOP : NOP : NOP : NOP : NOP : NOP

; end of transfer: JSR $C5DA (consolidate)  ->  JSR gate
org $80C2F9
        JSR SubTankConsolidate

; consolidate routine: vanilla first byte ($9C = STZ $0000).
; (subtank_stop_on_full turned it into RTS; the gate below decides now)
org $80C5DA
        db $9C

; new routines, in the free space the old patch used ($80:FF00-FF21 and on)
org $80FF00
SubTankFrame:
        DEC $2A                  ; frame timer
        BNE .exit                ; not yet time for a tick

        LDA #$02
        STA $2A                  ; reload timer (same as vanilla)

        LDA.L !SUB_FLAG
        BEQ .vanilla             ; option OFF: vanilla path, nothing else

        LDA.W $09FF              ; option ON: current health ...
        CMP.W $1FD1              ; ... vs max health
        BEQ .stop                ; already full -> abort the transfer

.vanilla:                        ; play the refill SFX, then the vanilla body
        LDA #$15
        JSL $808549
        JMP $C2D9                ; (its RTS returns to the BRA at $C2CF's hook)

.stop:                           ; health is full: clear the whole transfer state so
        STZ $2A                  ; the menu unlocks at once, no SFX, and the
        STZ $2B                  ; remaining energy stays in the tank
        STZ $34
        STZ $03
.exit:
        RTS

SubTankConsolidate:
        LDA.L !SUB_FLAG
        BEQ .vanilla
        RTS                      ; option ON: tanks keep their own energy
.vanilla:
        JMP $C5DA                ; option OFF: vanilla consolidate (its RTS returns
; to the caller of this gate)
assert pc() <= $80FF8D           ; free space ends at $80:FF8C

; ============================================================================
; 5. Bank $80 trampolines: bank-$80 engine routines return with RTS, so they
;    can only be JSR'd from bank $80.  JSL to these stubs, which JSR + RTL.
;    (placed in the free gap after skip_boss_intro's $FE80-FE96)
; ============================================================================
org $80FE97
        T_815F: JSR $815F : RTL  ; yield one frame
        T_8669: JSR $8669 : RTL  ; draw message A
        T_86CD: JSR $86CD : RTL  ; clear sprites/queue
        T_87FC: JSR $87FC : RTL
        T_8568: JSR $8568 : RTL  ; BG register setup
        T_AFB6: JSR $AFB6 : RTL  ; graphics loader (Y = list)
        T_85F7: JSR $85F7 : RTL  ; fade in
        T_8619: JSR $8619 : RTL  ; fade out
        T_8507: JSR $8507 : RTL  ; queue sound A
assert pc() <= $80FF00           ; stay clear of subtank/skip_boss regions

; ============================================================================
; 6. Bank $86 data (free space at the end of the bank)
; ============================================================================
org $86FD3A

MainMenuSpriteY:
        db $96, $A6, $B6, $C6

; ---- main menu (4 rows).  VRAM word address = $0800 + row*32 + col ----------
macro mainmenu(a1, a2, a3, a4)
        db 11, <a1> : dw $0A4A : db "GAME  START" ; row 18, col 10
        db  9, <a2> : dw $0A8A : db "PASS WORD" ; row 20
        db 11, <a3> : dw $0ACA : db "OPTION MODE" ; row 22
        db 13, <a4> : dw $0B0A : db "EXTRA OPTIONS" ; row 24
        db 0
endmacro

        MsgMain0: %mainmenu($24, $20, $20, $20)
        MsgMain1: %mainmenu($20, $24, $20, $20)
        MsgMain2: %mainmenu($20, $20, $24, $20)
        MsgMain3: %mainmenu($20, $20, $20, $24)

; ---- frame around the toggles (same tiles OPTION MODE's boxes use) ----------
; tiles: $AB corner, $AC edge, $AA title cap, $AD side.
; 26 tiles wide (cols 3-28), 6 tall (rows 10-15).  attrs (dim / lit): corner
; $24/$2C, title $30/$34, right half $64/$6C (H-flip), bottom $A4/$AC (V-flip),
; bottom-right $E4/$EC (H+V flip).
macro box(tl, ti, tr, bl, br)
        db 6,  <tl> : dw $0943 : db $AB,$AC,$AC,$AC,$AC,$AA     ; top-left   (cols 3-8)
        db 13, <ti> : dw $0949 : db "EXTRA OPTIONS"             ; title      (cols 9-21)
        db 7,  <tr> : dw $0956 : db $AA,$AC,$AC,$AC,$AC,$AC,$AB ; top-right  (cols 22-28)
        db 1,  <tl> : dw $0963 : db $AD                         ; sides, rows 11-14
        db 1,  <tr> : dw $097C : db $AD
        db 1,  <tl> : dw $0983 : db $AD
        db 1,  <tr> : dw $099C : db $AD
        db 1,  <tl> : dw $09A3 : db $AD
        db 1,  <tr> : dw $09BC : db $AD
        db 1,  <tl> : dw $09C3 : db $AD
        db 1,  <tr> : dw $09DC : db $AD
        db 25, <bl> : dw $09E3 : db $AB                         ; bottom (row 15)
        db $AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC
        db $AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC
        db 1,  <br> : dw $09FC : db $AB                         ; bottom-right corner
        db 0
endmacro

        MsgBoxDim: %box($24, $30, $64, $A4, $E4)
        MsgBoxLit: %box($2C, $34, $6C, $AC, $EC)

; ---- toggle rows: label + blank tiles + OFF/ON  (rows 12 and 13, col 6) ----
; Both rows are 20 tiles wide and the value always starts at tile 17, so the
; ON/OFF words line up vertically.
; $00 is used as an invisible filler tile (ASCII space renders zero width in
; this font); "ON" is padded with a trailing $00 so it fully overwrites "OFF".
        MsgDTapOff:   db 20, $20 : dw $0986 : db "D-TAP DASH", 0,0,0,0,0,0,0, "OFF", 0
        MsgDTapOffHi: db 20, $28 : dw $0986 : db "D-TAP DASH", 0,0,0,0,0,0,0, "OFF", 0
        MsgDTapOn:    db 20, $20 : dw $0986 : db "D-TAP DASH", 0,0,0,0,0,0,0, "ON", 0, 0
        MsgDTapOnHi:  db 20, $28 : dw $0986 : db "D-TAP DASH", 0,0,0,0,0,0,0, "ON", 0, 0

        MsgSubOff:    db 20, $20 : dw $09A6 : db "BETTER SUB-TANK", 0, 0, "OFF", 0
        MsgSubOffHi:  db 20, $28 : dw $09A6 : db "BETTER SUB-TANK", 0, 0, "OFF", 0
        MsgSubOn:     db 20, $20 : dw $09A6 : db "BETTER SUB-TANK", 0, 0, "ON", 0, 0
        MsgSubOnHi:   db 20, $28 : dw $09A6 : db "BETTER SUB-TANK", 0, 0, "ON", 0, 0
assert pc() <= $870000           ; end of bank $86

; ============================================================================
; 7. Bank $88 (FastROM mirror of bank $08) code
; ============================================================================
org $88FDA6

; ---- gameplay gate (same gate as the reference dtap_dash patch) ------------
; $88:9608 originally JSR $BAE7, the per-frame double-tap dash state machine
; (ground and air both go through it).  When the flag is OFF it is skipped.
DTapGate:
        LDA.L !DTAP_FLAG
        BEQ .skip
        JSR $BAE7
.skip:
        RTS

; ---- main menu selection dispatcher ----------------------------------------
; Entered by JML from $80:91FD with 8-bit A/X/Y, DB=$86, DP=0.
; Cursor 0-2 : continue into the original jump table, exactly as before.
; Cursor 3   : run the EXTRA OPTIONS screen, then return to the main menu.
;              (OPTION MODE instead resets $38 to 0, which replays the intro
;              sequence first; EXTRA OPTIONS goes directly back to the menu.)
ExtraDispatch:
        LDA $3C
        CMP #$03
        BEQ .extra
        ASL a
        TAX
        JML $809201              ; original JMP ($9204,X)
.extra:
        JSR ExtraOptions
; Return straight to the main menu: top-level state $38 = 2 (main menu),
; sub-state/timers/cursor = 0 so its init (state 0) runs again.  This is
; exactly how the intro sequence enters the menu ($80:888A-8892).
        LDA #$02
        STA $38
        STZ $39
        STZ $3A
        STZ $3B
        STZ $3C
        JML $809247              ; the RTS that ends the original dispatch

; ---- draw helpers -----------------------------------------------------------
DrawMsg:                         ; A = message id
        JSL T_8669
        RTS

Yield:
        JSL T_815F
        RTS

; in: A = item index (0 D-TAP, 1 SUB-TANK, 2 EXIT)   out: A = 1 if the cursor is on it
IsCursor:
        CMP.L !CURSOR
        BEQ .yes
        LDA #$00
        RTS
.yes:
        LDA #$01
        RTS

; A = 0: draw the toggle row normal, A = 1: highlighted.  Picks OFF/ON from
; its flag.  Message order per row: OFF, OFF hi, ON, ON hi.
DrawDTap:
        PHA
        LDX #!MSG_DTAP_OFF
        LDA.L !DTAP_FLAG
        BRA DrawToggle
DrawSub:
        PHA
        LDX #!MSG_SUB_OFF
        LDA.L !SUB_FLAG
DrawToggle:                      ; stack: hi ; A = flag (Z set if OFF) ; X = first id
        BEQ .off
        INX
        INX
.off:
        PLA
        BEQ .draw
        INX
.draw:
        TXA
        JSL T_8669
        RTS

; redraw the whole screen for the current cursor
Redraw:
        LDA #$02
        JSR IsCursor
        BNE .boxDim
        LDA #!MSG_BOX_LIT
        BRA .box
.boxDim:
        LDA #!MSG_BOX_DIM
.box:
        JSR DrawMsg
        JSR Yield
        LDA #$00
        JSR IsCursor
        JSR DrawDTap
        LDA #$01
        JSR IsCursor
        JSR DrawSub
        LDA #$02
        JSR IsCursor
        BNE .exitHi
        LDA #!MSG_EXIT
        BRA .exit
.exitHi:
        LDA #!MSG_EXIT_HI
.exit:
        JSR DrawMsg
        RTS

; ---- the EXTRA OPTIONS screen ----------------------------------------------
; Same skeleton as OPTION MODE ($80:EA36): blocking loop, one yield per frame.
; Runs with the screen faded out (the main menu already faded before dispatch).
ExtraOptions:
        PHP
        REP #$20
        PHD
        LDA #$0000
        TCD
        SEP #$30

        JSL T_86CD               ; clear sprite/queue state, flush
        JSL T_87FC
        LDA #$00
        STA.L !CURSOR
        JSL T_8568               ; BG3 tilemap $0800, BG1/2 $5000/$5800, chars
        JSR Redraw               ; ($86CD already requested the tilemap-shadow upload;
        JSR Yield                ; a second request would wipe what is drawn here)

        LDY #$4E                 ; same graphics/palette sets OPTION MODE loads
        JSL T_AFB6
        SEP #$30
        JSR Yield
        REP #$10
        LDY #$0172
        JSL $818011
        SEP #$30
        JSR Yield
        JSL T_85F7               ; fade in

.loop:
        LDA $AD                  ; newly pressed: UP/DOWN
        AND #$0C
        BEQ .noMove
        LDA $AD
        BIT #$08
        BNE .up
        LDA.L !CURSOR            ; DOWN: 0 -> 1 -> 2 -> 0
        INC a
        CMP #$03
        BNE .setCursor
        LDA #$00
        BRA .setCursor
.up:
        LDA.L !CURSOR            ; UP: 0 -> 2 -> 1 -> 0
        DEC a
        BPL .setCursor
        LDA #$02
.setCursor:
        STA.L !CURSOR
        JSR Redraw
        BRA .frame

.noMove:
        LDA.L !CURSOR
        CMP #$02
        BEQ .exitRow
        LDA $AD                  ; LEFT/RIGHT toggles the highlighted option
        AND #$03
        BEQ .frame
        LDA.L !CURSOR
        BNE .toggleSub
        LDA.L !DTAP_FLAG
        EOR #$01
        STA.L !DTAP_FLAG
        LDA #$01
        JSR DrawDTap
        BRA .frame
.toggleSub:
        LDA.L !SUB_FLAG
        EOR #$01
        STA.L !SUB_FLAG
        LDA #$01
        JSR DrawSub
        BRA .frame

.exitRow:
        LDA $AD                  ; START / Y  (same test OPTION MODE's EXIT uses)
        AND #$50
        BNE .exit
        LDA $AC                  ; A
        AND #$80
        BNE .exit
.frame:
        JSR Yield
        BRA .loop

.exit:
        LDA #$F1                 ; confirm SFX (same one the intro plays on START)
        JSL T_8507
        JSL T_8619               ; fade out
        REP #$20
        PLD
        PLP
        RTS
assert pc() <= $890000           ; end of bank $88

; ============================================================================
; 8. Gameplay hook: double-tap dash detector -> gate
; ============================================================================
org $889608
        JSR DTapGate

; ----------------------------------------------------------------------------
; SNES header checksum fix
; ----------------------------------------------------------------------------
; The ROM header checksum is unchanged by this patch. On the intended
; input ROM the existing checksum bytes are already $8C $F3 $73 $0C.
; Keep them unchanged so checksum-fixing remains disabled and the
; generated IPS contains exactly the patch's intended data edits.
assert read1($80FFDC) == $8C
assert read1($80FFDD) == $F3
assert read1($80FFDE) == $73
assert read1($80FFDF) == $0C

; ============================================================================
; End of patch
; ============================================================================
