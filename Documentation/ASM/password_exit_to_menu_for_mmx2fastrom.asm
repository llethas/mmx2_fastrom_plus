; ============================================================================
;  Mega Man X2 (SNES, USA) [FastROM v4.0 patch] -- "PASS WORD: EXIT to menu"
;  Apply after (in this order):
;    Megaman X2 (U) - Fastrom v4.0.ips
;    skip_boss_intro_for_mmx2fastrom.ips
;    better_dialog_box_for_mmx2fastrom.ips
;    dash_L_for_mmx2fastrom.ips
;    extra_options_for_mmx2fastrom.ips
;    option_mode_exit_to_menu_for_mmx2fastrom.ips
;  and then this patch, and then sram_save_for_mmx2fastrom.ips.
; ============================================================================
;
;  ASSEMBLER
;    Written for Asar (https://github.com/RPGHacker/asar), LoROM, no header.
;    Build with checksum-fixing disabled because this patch does not modify
;    the SNES header or checksum bytes:
;
;        asar --fix-checksum=off password_exit_to_menu_for_mmx2fastrom.asm rom.sfc
;
;  WHAT IT DOES
;    Adds an "EXIT" entry below "START" on the PASS WORD screen that the Main
;    Menu opens. DOWN from START (or UP from the top digit row) moves the
;    pointer arrow onto EXIT; START on EXIT fades out (no sound) and returns
;    directly to the Main Menu, skipping the intro. UP from EXIT goes back to
;    START, DOWN from EXIT wraps to the first digit row. Digit editing and
;    START = "submit password" are unchanged. While the "PASS WORD ERROR"
;    message is up, EXIT is hidden; it comes back when the message is gone.
;
;  SCOPE
;    The only caller of the PASS WORD loop ($80:EDCB) is the Main Menu entry
;    $80:9216. The password screens shown after beating a boss use other code
;    and are never touched.
;
;  HOW IT WORKS
;    START, the digits and the pointer arrow are sprite objects drawn by the
;    game's object engine; the panel behind them is a background tilemap.
;
;    * "EXIT" is drawn as 5 background tiles (BG map row 25, columns 7-11,
;      VRAM tiles $C0-$C4) with the same glyphs and colors as START. E, I and
;      T were copied from START's sprite font; X was drawn to match. They use
;      BG palette row 5 (unused on this screen), written through the palette
;      shadow at $7E:03A0. Tiles and map words are queued through the game's
;      own VRAM DMA queue ($7E:0500, 8-byte entries, count in $7E:00A4) at
;      the end of the screen's init state, so EXIT fades in with the rest.
;    * Hiding EXIT = queueing 5 blank panel tiles ($080F) over the same map
;      cells; showing it again = queueing the 5 EXIT words. This is decided
;      every frame from the screen's state byte ($01 = $0A: error message).
;    * START is a sprite, so it is moved up 4 px to make room. The pointer
;      arrow is a sprite object too; its Y is rewritten every frame, in every
;      state of the screen, to sit beside START or beside EXIT.
;    * Leaving: START on EXIT sets the marker $39 := $EE and state $01 := 8,
;      the game's own fade-out state (it clears the screen objects and ends
;      the loop). Back in $80:9216 a hook at $80:922F sees the marker and
;      returns to the menu exactly like option_mode_exit_to_menu does
;      ($38 = 2, $39-$3C = 0, RTS at $80:9247) instead of starting the game.
;
;  FREE SPACE USED
;    $80:FF64-FF74   17 bytes of bank-$80 stubs.  (MSU-1 compatibility: bank
;                    $80 only has $FF36-$FFAF left once MSU-1 has taken
;                    $00:FE78-$00:FF35; the windows are $FF36-FF3F and
;                    $FF40-FF63 extra_options, $FF64-FF74 this patch,
;                    $FF75-FF94 skip_boss_intro, $FF95-FFA0 sram_save.)
;    $92:FB00-FE1F   code and data in the unused tail of bank $92.
;
;  RAM USED
;    DP $1E58+$46/$47/$48   flags (EXIT selected / graphics queued / EXIT
;                           hidden). Free in this screen's code and cleared
;                           by its $DA55 call at $80:9223.
;    $7E:0039               menu sub-state, used as the "leave" marker and
;                           cleared again by the hook.
;    $7E:0500-05FF queue, $7E:03A0-03BF palette shadow (BG row 5).
; ============================================================================

lorom

; ############################################################################
; # Original code this patch relies on (asserted)
; ############################################################################

assert read1($80EDEB) == $20 && read1($80EDEC) == $DA && read1($80EDED) == $F4   ; JSR $F4DA
assert read1($80EE60) == $64 && read1($80EE61) == $04                             ; STZ $04
assert read1($80EE62) == $64 && read1($80EE63) == $07                             ; STZ $07
assert read1($80EE81) == $20 && read1($80EE82) == $42 && read1($80EE83) == $F5   ; JSR $F542
assert read1($80EF5A) == $20 && read1($80EF5B) == $DA && read1($80EF5C) == $F4   ; JSR $F4DA
assert read1($80F513) == $A9 && read1($80F514) == $C3                             ; LDA #$C3 (START Y)
assert read1($80922F) == $A9 && read1($809230) == $02                             ; LDA #$02
assert read1($809231) == $85 && read1($809232) == $D0                             ; STA $D0
assert read1($809247) == $60                      ; RTS used as the exit tail
assert read1($88FFA0) == $E2                      ; OptionModeExit present (option_mode_exit applied)
assert read1($80FF64) == $FF && read1($80FF74) == $FF
assert read1($92FB00) == $FF && read1($92FFFF) == $FF

; ############################################################################
; # Constants
; ############################################################################

!STATE         = $01             ; DP: screen state (4 = input, 8 = fade out, $0A = error)
!ROW           = $07             ; DP: cursor row (4 = START row)
!SEL           = $46             ; DP: 1 = pointer is on EXIT
!INIT          = $47             ; DP: 1 = graphics already queued
!HIDE          = $48             ; DP: 1 = EXIT currently hidden
!DPBASE        = $7E1E58         ; long address of the screen's direct page
!BTN           = $7E00AD         ; new button presses (UP $08, DOWN $04, START $10)
!MARK          = $7E0039         ; menu sub-state, used as the "leave" marker
!QUEUE         = $7E0500         ; VRAM DMA queue (8-byte entries)
!QCOUNT        = $7E00A4         ; end offset of the queue
!PALROW5       = $7E03A0         ; palette shadow, BG palette row 5
!ARROW_START_Y = $BE             ; pointer arrow Y beside START
!ARROW_EXIT_Y  = $CA             ; pointer arrow Y beside EXIT

; ############################################################################
; # PART 1 - Hijack points
; ############################################################################

; ----------------------------------------------------------------------------
; End of the screen's init state (state 0): queue the EXIT graphics before the
; fade-in. Original 4 bytes: STZ $04 / STZ $07 (PwInit executes them itself).
; ----------------------------------------------------------------------------
org $80EE60
        JSL PwInit

; ----------------------------------------------------------------------------
; Input state: the D-pad update. Same size in, same size out.
; Original: JSR $F542
; ----------------------------------------------------------------------------
org $80EE81
        JSR PwStub               ; was JSR $F542

; ----------------------------------------------------------------------------
; Per-frame object update, both loops of the screen (input loop and the
; error/fade loop). Same size in, same size out.
; Original: JSR $F4DA
; ----------------------------------------------------------------------------
org $80EDEB
        JSR PwFrameStub          ; was JSR $F4DA

org $80EF5A
        JSR PwFrameStub          ; was JSR $F4DA

; ----------------------------------------------------------------------------
; START label Y: $C3 -> $BF (4 px up, makes room for EXIT)
; ----------------------------------------------------------------------------
org $80F514
        db $BF                   ; was $C3

; ----------------------------------------------------------------------------
; Right after JSR $EDCB in the Main Menu's PASS WORD routine.
; Original 4 bytes: LDA #$02 / STA $D0 (PwPostLoop executes them itself)
; ----------------------------------------------------------------------------
org $80922F
        JML PwPostLoop

; ############################################################################
; # PART 2 - Bank $80 stubs
; ############################################################################
;
; The hooks are JSRs inside bank $80, so they land on small stubs here that
; JSL into bank $92 and give the bank-$92 code a way back to $80:F542.
; ----------------------------------------------------------------------------
org $80FF64
PwStub:
        JSL PwMain
        RTS

PwOrigDpad:
        JSR $F542                ; original D-pad -> row/column update
        RTL

PwFrameStub:
        JSR $F4DA                ; original per-frame object update
        JSL PwFrame
        RTS
assert pc() <= $80FF75           ; stay clear of skip_boss_intro at $80:FF75

; ############################################################################
; # PART 3 - Bank $92 code
; ############################################################################

; ----------------------------------------------------------------------------
; PwInit - end of the screen's init state (A/X/Y 8-bit, DP = $1E58)
;   Runs the two original instructions, then queues the EXIT graphics. If the
;   queue happens to be full, PwMain retries on the first input frame.
; ----------------------------------------------------------------------------
org $92FB00
PwInit:
        PHP
        SEP #$30
        STZ.b !ROW-3             ; original STZ $04 (cursor column)
        STZ.b !ROW               ; original STZ $07 (cursor row)
        JSR QueueGfx
        BCS .retry               ; queue full: PwMain retries
        INC.b !INIT
        .retry
        PLP
        RTL
assert pc() <= $92FB20

; ----------------------------------------------------------------------------
; PwFrame - every frame of the screen, in every state (DP = $0000 here, so
;           the screen's variables are reached with long addresses)
;   1. EXIT label: hidden while the error message is up ($01 = $0A), shown
;      otherwise. Only touches the tilemap when that changes.
;   2. Pointer arrow: kept beside START, or beside EXIT when selected, so it
;      is never seen at the game's original, unshifted position.
; ----------------------------------------------------------------------------
org $92FB20
PwFrame:
        PHP
        SEP #$30
        LDX #$00                 ; X = 1 when EXIT must be hidden
        LDA.l !DPBASE+!STATE
        CMP #$0A
        BNE .wanted
        INX
        .wanted
        TXA
        CMP.l !DPBASE+!HIDE
        BEQ .arrow               ; label already in the wanted state
        LDA #$00                 ; map offset: EXIT words
        CPX #$00
        BEQ .queue
        LDA.b #PwBlank-PwMap       ; map offset: blank panel tiles
        .queue
        JSR QueueMap
        BCS .arrow               ; queue full: try again next frame
        TXA
        STA.l !DPBASE+!HIDE
        .arrow
        LDA.l !DPBASE+!SEL
        BEQ .onStart
        LDA #!ARROW_EXIT_Y
        BRA .setY
        .onStart
        LDA #!ARROW_START_Y
        .setY
        JSR SetArrowY
        PLP
        RTL
assert pc() <= $92FB80

; ----------------------------------------------------------------------------
; PwMain - input state, replaces the D-pad update (DP = $1E58)
;   Handles the moves to/from EXIT itself and consumes the buttons it used
;   (the original code after the hook then sees no input). Everything else is
;   passed through to the original D-pad update.
;
;   On START row, DOWN       -> EXIT
;   On top row,   UP         -> EXIT (wrap)
;   On EXIT,      UP         -> START
;   On EXIT,      DOWN       -> first digit row
;   On EXIT,      START      -> leave to the Main Menu
; ----------------------------------------------------------------------------
org $92FB80
PwMain:
        PHP
        SEP #$30
        LDA.b !INIT
        BNE .ready
        JSR QueueGfx             ; first-frame retry (see PwInit)
        BCS .ready
        INC.b !INIT
        .ready
        LDA.b !SEL
        BNE .onExit
        LDA.b !ROW
        CMP #$04
        BNE .notStart
        LDA.l !BTN
        AND #$04                 ; DOWN on START -> EXIT
        BEQ .pass
        LDA #$01
        STA.b !SEL
        BRA .consume
        .notStart
        CMP #$00
        BNE .pass
        LDA.l !BTN
        AND #$08                 ; UP on the top row -> wrap to EXIT
        BEQ .pass
        LDA #$04
        STA.b !ROW
        LDA #$01
        STA.b !SEL
        BRA .consume
        .pass
        JSL PwOrigDpad
        PLP
        RTL
        .onExit
        LDA.l !BTN
        BIT #$08
        BNE .toStart             ; UP    -> START
        BIT #$04
        BNE .toTop               ; DOWN  -> first digit row
        BIT #$10
        BNE .doExit              ; START -> leave
        BRA .consume
        .toStart
        STZ.b !SEL
        BRA .consume
        .toTop
        STZ.b !SEL
        STZ.b !ROW
        BRA .consume
        .doExit
        LDA #$EE
        STA.l !MARK              ; tells the hook at $80:922F to go to the menu
        LDA #$08
        STA.b !STATE             ; game's own fade-out state (no sound)
        .consume
        LDA #$00
        STA.l !BTN               ; the original code must see no input
        PLP
        RTL
assert pc() <= $92FC00

; ----------------------------------------------------------------------------
; SetArrowY - A = new Y for the pointer arrow
;   The arrow is an object of type $55 at X = $30, somewhere in the object
;   pool. Scans the pool (slots are $20 apart) and sets its Y if found.
; ----------------------------------------------------------------------------
org $92FC00
SetArrowY:
        PHA
        REP #$10
        LDX #$0C18
        .next
        LDA.l $7E0016,x          ; object type
        CMP #$55
        BNE .skip
        LDA.l $7E0005,x          ; X position, low
        CMP #$30
        BNE .skip
        LDA.l $7E0006,x          ; X position, high
        BNE .skip
        PLA
        STA.l $7E0008,x          ; Y position
        SEP #$10
        RTS
        .skip
        REP #$21
        TXA
        ADC #$0020
        TAX
        SEP #$20
        CPX #$0F18
        BCC .next
        PLA                      ; not on screen right now
        SEP #$10
        RTS
assert pc() <= $92FC40

; ----------------------------------------------------------------------------
; QueueMap - queue the 5 map words of the EXIT row (8-bit A/X)
;   In:  A = offset into PwMap (0 = EXIT words, PwBlank-PwMap = blank panel)
;   Out: carry set = queue full, nothing queued. X is preserved.
;   Destination: VRAM word $5327 = BG map row 25, column 7.
; ----------------------------------------------------------------------------
org $92FC40
QueueMap:
        PHX
        PHA
        LDA.l !QCOUNT
        CMP #$E0
        BCS .full
        TAX
        LDA #$80
        STA.l !QUEUE+0,x         ; VMAIN: word increment
        LDA #$27
        STA.l !QUEUE+1,x         ; VRAM word address $5327
        LDA #$53
        STA.l !QUEUE+2,x
        LDA #$0A
        STA.l !QUEUE+3,x         ; size $000A (5 words)
        LDA #$00
        STA.l !QUEUE+4,x
        PLA
        CLC
        ADC.b #PwMap             ; source = PwMap + offset
        STA.l !QUEUE+5,x
        LDA.b #PwMap>>8
        ADC #$00
        STA.l !QUEUE+6,x
        LDA.b #PwMap>>16
        STA.l !QUEUE+7,x
        TXA
        CLC
        ADC #$08
        STA.l !QCOUNT            ; commit
        PLX
        CLC
        RTS
        .full
        PLA
        PLX
        SEC
        RTS
assert pc() <= $92FCA0

; ----------------------------------------------------------------------------
; QueueGfx - set up the EXIT graphics (8-bit A/X)
;   Writes the BG palette row 5, queues the 5 tiles (VRAM word $1C00 = tile
;   $C0) and the 5 EXIT map words. Out: carry set = queue full, retry later.
; ----------------------------------------------------------------------------
org $92FCA0
QueueGfx:
        LDA.l !QCOUNT
        CMP #$D0                 ; room for two entries
        BCS .full
        LDX #$00
        .pal
        LDA.l PwPal,x
        STA.l !PALROW5,x
        INX
        CPX #$20
        BNE .pal
        LDA.l !QCOUNT
        TAX
        LDA #$80
        STA.l !QUEUE+0,x         ; VMAIN: word increment
        LDA #$00
        STA.l !QUEUE+1,x         ; VRAM word address $1C00
        LDA #$1C
        STA.l !QUEUE+2,x
        LDA #$A0
        STA.l !QUEUE+3,x         ; size $00A0 (5 tiles)
        LDA #$00
        STA.l !QUEUE+4,x
        LDA.b #PwTiles
        STA.l !QUEUE+5,x
        LDA.b #PwTiles>>8
        STA.l !QUEUE+6,x
        LDA.b #PwTiles>>16
        STA.l !QUEUE+7,x
        TXA
        CLC
        ADC #$08
        STA.l !QCOUNT            ; commit
        LDA #$00
        JMP QueueMap             ; EXIT map words (returns carry)
        .full
        SEC
        RTS
assert pc() <= $92FD00

; ----------------------------------------------------------------------------
; PwPostLoop - runs right after JSR $EDCB in $80:9216 (the PASS WORD loop)
;   Marker set: go back to the Main Menu the same way option_mode_exit does.
;   Otherwise: the two original instructions, then the original game start.
; ----------------------------------------------------------------------------
org $92FD00
PwPostLoop:
        SEP #$30
        LDA.l !MARK
        CMP #$EE
        BNE .normal
        LDA #$00
        STA.l !MARK
        LDA #$02
        STA $38                  ; top-level state: main menu
        STZ $39                  ; sub-state, timers and cursor cleared
        STZ $3A
        STZ $3B
        STZ $3C
        JML $809247              ; RTS (kept by option_mode_exit)
        .normal
        LDA #$02                 ; original LDA #$02
        STA $D0                  ; original STA $D0
        JML $809233              ; continue with the original code
assert pc() <= $92FD40

; ############################################################################
; # PART 4 - Data
; ############################################################################

; ----------------------------------------------------------------------------
; BG palette row 5: START's sprite colors ($739C/$6F38/$6AF4/$6AB0 = indexes
; 1-4) on the panel color ($40E9 = index 15). Written to the palette shadow.
; ----------------------------------------------------------------------------
org $92FD40
PwPal:
        dw $0000,$739C,$6F38,$6AF4,$6AB0,$0000,$0000,$0000
        dw $0000,$0000,$0000,$0000,$0000,$0000,$0000,$40E9
assert pc() <= $92FD60

; ----------------------------------------------------------------------------
; Map words for BG row 25, columns 7-11 (queue source for QueueMap).
; Attribute $14xx = palette 5; $080F = the plain panel tile (palette 2).
; ----------------------------------------------------------------------------
org $92FD60
PwMap:
        dw $14C0,$14C1,$14C2,$14C3,$14C4     ; "EXIT" (tiles $C0-$C4)
PwBlank:
        dw $080F,$080F,$080F,$080F,$080F     ; blank panel
assert pc() <= $92FD80

; ----------------------------------------------------------------------------
; "EXIT" tiles, 4bpp, 5 tiles (160 bytes). The word is laid out on the same
; pixel columns as START and spans 5 background tiles.
; ----------------------------------------------------------------------------
org $92FD80
PwTiles:
        db $EF,$E0,$FF,$E0,$F7,$E7,$FF,$E1,$FF,$E1,$F7,$E7,$FF,$E0,$EF,$E0
        db $F0,$E0,$E0,$E0,$EF,$E7,$E0,$E0,$E0,$E0,$EF,$E7,$E0,$E0,$F0,$E0
        db $EF,$E7,$FF,$F2,$FF,$F8,$FF,$FD,$FF,$FD,$FF,$F8,$FF,$F2,$EF,$E7
        db $77,$67,$72,$72,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$72,$72,$77,$67
        db $BF,$3F,$FF,$79,$FF,$F9,$FF,$F9,$FF,$F9,$FF,$F9,$FF,$79,$BF,$3F
        db $79,$39,$79,$79,$F9,$F9,$F9,$F9,$F9,$F9,$F9,$F9,$79,$79,$79,$39
        db $FF,$F0,$FF,$F0,$FF,$FD,$FF,$FD,$FF,$FD,$FF,$FD,$FF,$FD,$FF,$FF
        db $E0,$E0,$E0,$E0,$F8,$F8,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD
        db $FF,$7F,$FF,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        db $3F,$3F,$3F,$3F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
assert pc() <= $92FE20

; ############################################################################
; # SNES header checksum
; ############################################################################
; The ROM header checksum is unchanged by this patch. On the intended input
; ROM (everything up to option_mode_exit applied) the existing checksum bytes
; are still $8C $F3 $73 $0C. Keep them unchanged so checksum-fixing remains
; disabled and the generated IPS contains exactly the patch's data edits.
; (sram_save, applied last, is the patch that rewrites the checksum.)
assert read1($80FFDC) == $8C
assert read1($80FFDD) == $F3
assert read1($80FFDE) == $73
assert read1($80FFDF) == $0C

; ============================================================================
; End of patch
; ============================================================================
