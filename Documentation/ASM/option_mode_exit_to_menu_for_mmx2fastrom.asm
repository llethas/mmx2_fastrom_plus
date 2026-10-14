; ============================================================================
;  Mega Man X2 (SNES, USA) [FastROM v4.0 patch]
;  OPTION MODE: EXIT returns directly to the main menu
;  Apply after (in this order):
;    Megaman X2 (U) - Fastrom v4.0.ips
;    skip_boss_intro_for_mmx2fastrom.ips
;    better_dialog_box_for_mmx2fastrom.ips
;    dash_L_for_mmx2fastrom.ips
;    extra_options_for_mmx2fastrom.ips
;  and then this patch.
; ============================================================================
;
;  ASSEMBLER
;    Written for Asar (https://github.com/RPGHacker/asar), LoROM, no header.
;    Build with checksum-fixing disabled because this patch does not modify
;    the SNES header or checksum bytes:
;
;        asar --fix-checksum=off option_mode_exit_to_menu_for_mmx2fastrom.asm rom.sfc
;
;  WHAT IT DOES
;    Vanilla: pressing EXIT in OPTION MODE fades out and returns to the main
;    menu code, which then resets the top-level game state to 0. State 0 is
;    the title/intro sequence, so the opening cutscene replays and you must
;    press START to get back to the menu.
;
;    Patched: the same fade-out and exit SFX happen, but the game state is set
;    to 2 (main menu) with its sub-state, timers, and cursor cleared. The main
;    menu therefore re-initialises and appears again immediately.
;
;    This is the same state setup used when the intro sequence enters the main
;    menu at $80:888A-8892, and the same basic re-entry behaviour used by the
;    EXTRA OPTIONS screen when it is exited.
;
;  OPTION MODE CODE PATH
;    The OPTION MODE screen itself (code $80:EA36-EE06, its strings/messages,
;    and its tables) is not modified. Only the main-menu cleanup that runs
;    after OPTION MODE returns is changed:
;
;      $80:9238  JSR $EA36            OPTION MODE
;      $80:923D  STZ $38              vanilla: top-level state := 0 (intro)
;                STZ $39 / $3A / $3B / $3C
;                RTS
;
;    The vanilla cleanup is replaced by a jump to OptionModeExit in free
;    space. That routine preserves the cleanup of $39-$3C but writes $02 to
;    $38 instead of $00, so control returns to the main-menu state machine.
;
;  MSU-1 COMPATIBILITY
;    OptionModeExit used to sit in bank $80 ($80:FF40).  Bank-$80 free space
;    is scarce and MSU-1 owns $00:FE78-$00:FF35, so it now lives in bank
;    $88 at $88:FFA0 (free tail of bank $08, behind extra_options' code and
;    MSU-1's $08:FDB0 block) and the vanilla cleanup jumps there with a JML.
;    It leaves through JML $809247, the RTS that ended the old cleanup, so
;    the return address is still the one for the bank-$80 caller.
; ============================================================================

lorom

assert read1($88FFA0) == $FF     ; free space we use ($88:FFA0-FFBF; FFC0+ is skip_boss_intro)
assert read1($88FFBF) == $FF

org $80923D
        JML OptionModeExit       ; 4 bytes; the rest of the old cleanup is dead
        NOP : NOP : NOP : NOP : NOP : NOP ; $80:9241-9246 (old bytes)
; $80:9247 (the RTS that ended the old cleanup) is deliberately kept:
; extra_options and password_exit jump to it (JML $809247).

org $88FFA0
OptionModeExit:
        SEP #$30                 ; the main menu code is 8-bit throughout
        LDA #$02
        STA $38                  ; top-level state 2 = main menu  (vanilla: 0)
        STZ $39                  ; main menu sub-state 0 = (re)initialise
        STZ $3A
        STZ $3B
        STZ $3C                  ; cursor on GAME START
OptionModeExitJML:
        JML $809247              ; the RTS at $80:9247 returns to the caller of
                                 ; the menu handler (sram_save extends this)
assert pc() <= $88FFB8           ; $88:FFB8-FFBF stays free for sram_save's extension
print "OptionModeExit JML at $", hex(OptionModeExitJML)

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
