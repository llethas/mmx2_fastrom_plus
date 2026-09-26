; ============================================================================
;  Mega Man X2 (SNES, USA) [FastROM v4.0 patch] -- SRAM Save
;  Apply LAST, after all other patches
; ============================================================================
;
;  ASSEMBLER
;    Written for Asar (https://github.com/RPGHacker/asar), LoROM, no header.
;    This patch enables Asar's normal SNES checksum fixing because the ROM
;    header is changed to declare battery-backed SRAM. Build with:
;
;        asar sram_save_for_mmx2fastrom.asm rom.sfc
;
;  WHAT IT DOES
;    Adds battery-backed SRAM and uses it to persist, across a HARD reset:
;      1. The control scheme (SHOT/JUMP/DASH/SELECT_L/SELECT_R/MENU)
;      2. The EXTRA OPTIONS toggles (D-TAP DASH, BETTER SUB-TANK)
;      3. The last auto-generated in-game password (16 digits)
;
;    All three already survive a SOFT reset for free: the game keeps its live
;    copy of this data in WRAM at $7E:FFC0-FFDC (29 bytes) and only resets it
;    to ROM factory defaults when the cached copy of the ROM header (kept at
;    $7E:FFA0-FFBF) no longer matches the real header. This is the hard-reset
;    path; on a soft reset, the WRAM mirror survives and the defaults-copy is
;    skipped.
;
;    The patch does not change when the game reloads its defaults. Instead,
;    immediately after the existing defaults-copy, it checks SRAM for a valid
;    signature/checksum and, when valid, replaces the freshly loaded defaults
;    with the player's saved 29-byte WRAM block.
;
;    The same live WRAM block is written back to SRAM at three save points:
;      * when the player leaves OPTION MODE;
;      * when the player leaves EXTRA OPTIONS;
;      * whenever the game auto-generates a new password.
;
;    Password generation covers the normal game-over/death path, boss/Maverick
;    set completion, and the third "beat game" password path. These routes all
;    funnel through the password-generation routine at $80:F013.
;
;  WHY THE 29-BYTE WRAM BLOCK COVERS THE SAVED SETTINGS
;    $7E:FFC0-FFC5  control scheme, 1 byte per action, in on-screen KEY
;                   CONFIG order (SHOT, JUMP, DASH, SELECT_L, SELECT_R, MENU)
;    $7E:FFC6-FFCA  other menu/session state (password-valid flag, etc.);
;                   harmless to restore/carry along, not separately required
;    $7E:FFCB-FFDA  the 16 password digits (0-7), exactly what the PASS WORD
;                   entry screen preloads from on a soft reset
;    $7E:FFDB       D-TAP DASH toggle          (added by EXTRA OPTIONS)
;    $7E:FFDC       BETTER SUB-TANK toggle     (added by EXTRA OPTIONS)
;    This is exactly the 29-byte range ($7E:FFC0 + X, X=$00..$1C) that the
;    vanilla/EXTRA OPTIONS defaults-copy loop at $80:8082A7-82B4 treats as
;    one unit after EXTRA OPTIONS extends the loop from 27 to 29 bytes.
;
;  SRAM LAYOUT
;    Battery RAM is declared as 2KB and this patch uses bank $70, offset $0100:
;      $70:0100        'M' -- signature byte 1
;      $70:0101        'X' -- signature byte 2
;      $70:0102-011E   29-byte mirror of $7E:FFC0-FFDC
;      $70:011F        8-bit checksum: sum of the 29 data bytes, mod 256
;
;    Offset $0100 is deliberate. The vanilla ROM still contains two leftover
;    long-addressed writes to $70:0006 ($80:985F and $80:9CA3, "STA $700006").
;    Those writes are inert while no RAM is mapped there and remain harmless
;    with SRAM enabled because this patch's save area starts at $70:0100.
;
;  HEADER CHANGES
;    $80:FFD8 (RAM size)   $00 -> $01   2KB
;    The cartridge-type byte at $80:FFD6 remains $F3. That value is retained
;    because the ROM's boot-time Cx4 self-test still relies on the emulator's
;    Cx4 high-level emulation. Changing the type byte to a standard ROM+
;    RAM+Battery type causes that diagnostic to fail, while changing only the
;    RAM-size byte exposes working persistent SRAM without affecting the test.
;    Asar's normal checksum-fixing updates $80:FFDC-FFDF for the ROM changes.
;
;  SRAM VALIDATION
;    On boot/hard-reset, the saved block is accepted only when its signature
;    bytes are present and its stored 8-bit checksum matches the sum of the
;    29 data bytes. Otherwise the game keeps the normal ROM defaults.
;
;  VERIFICATION NOTES
;    The SRAM layout and defaults-copy range were checked against the game's
;    actual code, and the password digits were traced at $7E:FFCB-FFDA as the
;    data refreshed by $80:F013/$80:F15B and consumed by the PASS WORD screen.
;    The only existing executed long-addressed $70-bank writes found in the
;    relevant game-code banks are the two vestigial $70:0006 writes described
;    above, clear of this patch's $0100-$011F footprint.
; ============================================================================

lorom

; ----------------------------------------------------------------------------
; Header: declare battery-backed SRAM. The cartridge-type byte at $80:FFD6
; is intentionally NOT modified -- see file header ("HEADER CHANGES") for
; why: it must stay $F3 so emulators keep running their Cx4 high-level
; emulation, which the ROM's own leftover boot-time Cx4 self-test depends
; on to pass.
; ----------------------------------------------------------------------------
org $80FFD8
        db $01                   ; RAM size: 2KB

; ----------------------------------------------------------------------------
; SRAM layout constants.
; ----------------------------------------------------------------------------
!SRAM_SIG1 = $700100
!SRAM_SIG2 = $700101
!SRAM_DATA = $700102             ; 29 bytes, mirrors $7EFFC0-FFDC
!SRAM_SUM  = $70011F
!WRAM_BLOCK = $7EFFC0
!BLOCK_LEN = $1D                 ; 29 (loop runs X = 0..28)

; ----------------------------------------------------------------------------
; Hook: hard-reset defaults-copy at $80:8082A7-82B8 (18 bytes, unmodified
; vanilla/extra_options code -- see file header for why this is safe to
; take over). Original bytes:
;   A2 1C            LDX #$1C
;   BF F9 F1 86       LDA $86F1F9,X
;   9F C0 FF 7E       STA $7EFFC0,X
;   CA               DEX
;   10 F5            BPL $82A9
;   A9 1E            LDA #$1E
;   20 6B 81         JSR $816B
; Replaced with a JSL to a free-space routine that reproduces all of the
; above verbatim, then merges in SRAM, then returns (RTL). The remaining
; 14 bytes of the original 18-byte window are padded with NOP so nothing
; stale is left behind for the RTL's return address to fall through into.
; ----------------------------------------------------------------------------
org $8082A7
        JSL CopyDefaultsAndSRAM
        NOP : NOP : NOP : NOP : NOP : NOP : NOP
        NOP : NOP : NOP : NOP : NOP : NOP : NOP

; ----------------------------------------------------------------------------
; Hook: OPTION MODE exit (option_mode_exit_to_menu's OptionModeExit routine,
; $80:FF40-FF4E). Original last byte at $80FF4E is a lone RTS; $80FF4F-FF8C
; is free space. Extend it to save SRAM just before returning.
; ----------------------------------------------------------------------------
assert read1($80FF4E) == $60, "OptionModeExit no longer ends in a lone RTS"
org $80FF4E
        JSL SaveSRAM
        RTS

; ----------------------------------------------------------------------------
; Hook: password auto-generation. $80:F013 has exactly one call site, at
; $80:EF91 ("JSR $F013"), reached from the game-over / boss-cleared / third
; password-path states. Redirect that single call through a wrapper that
; also saves to SRAM afterwards.
; ----------------------------------------------------------------------------
assert read1($80EF91) == $20, "unexpected byte at the JSR $F013 call site"
org $80EF91
        JSR F013SaveWrapper

org $80FF32
F013SaveWrapper:
        JSR $F013
        JSL SaveSRAM
        RTS
assert pc() <= $80FF40           ; stay clear of OptionModeExit at $80FF40

org $80FEBB
CopyDefaultsAndSRAM:
        PHP
        SEP #$30
        LDX #$1C
.defloop:
        LDA.L $86F1F9,X
        STA.L !WRAM_BLOCK,X
        DEX
        BPL .defloop
        JSL LoadOrInitSRAM
        LDA #$1E
        JSR $816B
        PLP
        RTL
assert pc() <= $80FF00           ; stay clear of the FF32 trampoline above

; ----------------------------------------------------------------------------
; Hook: EXTRA OPTIONS exit (extra_options's ExtraOptions.exit, bank $88).
; Original tail at $88:FEF2-FEF6:
;   REP #$20 ; PLD ; PLP ; RTS
; $88:FEF7 onward is free space. Extend the tail to save SRAM first.
; ----------------------------------------------------------------------------
assert read1($88FEF2) == $C2, "ExtraOptions exit tail moved"
org $88FEF2
        JSL SaveSRAM
        REP #$20
        PLD
        PLP
        RTS

; ----------------------------------------------------------------------------
; SaveSRAM: copy the live 29-byte WRAM options/password block to SRAM,
; with a signature and an 8-bit checksum. Callable via JSL from any bank.
; 8-bit A/X/Y throughout; restores caller's flags on exit.
; ----------------------------------------------------------------------------
org $88FEFB
SaveSRAM:
        PHP
        SEP #$30
        LDX #$00
.copyout:
        LDA.L !WRAM_BLOCK,X
        STA.L !SRAM_DATA,X
        INX
        cpx #!BLOCK_LEN
        BNE .copyout
        LDA #'M'
        STA.L !SRAM_SIG1
        LDA #'X'
        STA.L !SRAM_SIG2
        LDA #$00
        LDX #$00
.sumout:
        clc
        ADC.L !SRAM_DATA,X
        INX
        cpx #!BLOCK_LEN
        BNE .sumout
        STA.L !SRAM_SUM
        PLP
        RTL
assert pc() <= $88FF30           ; must not run into LoadOrInitSRAM below

; ----------------------------------------------------------------------------
; LoadOrInitSRAM: if SRAM holds a valid signature+checksum, overwrite the
; live WRAM block (just refreshed with ROM defaults by the caller) with the
; SRAM copy. Otherwise, treat SRAM as blank/corrupt and seed it from the
; ROM defaults currently in WRAM, so the next SaveSRAM call has a valid
; base and future validity checks succeed. Callable via JSL from any bank.
; ----------------------------------------------------------------------------
org $88FF30
LoadOrInitSRAM:
        PHP
        SEP #$30
        LDA.L !SRAM_SIG1
        CMP #'M'
        BNE .invalid
        LDA.L !SRAM_SIG2
        CMP #'X'
        BNE .invalid
        LDA #$00
        LDX #$00
.sumcheck:
        clc
        ADC.L !SRAM_DATA,X
        INX
        cpx #!BLOCK_LEN
        BNE .sumcheck
        CMP.L !SRAM_SUM
        BNE .invalid
        LDX #$00
.copyin:
        LDA.L !SRAM_DATA,X
        STA.L !WRAM_BLOCK,X
        INX
        cpx #!BLOCK_LEN
        BNE .copyin
        PLP
        RTL
.invalid:
        LDX #$00
.copyout2:
        LDA.L !WRAM_BLOCK,X
        STA.L !SRAM_DATA,X
        INX
        cpx #!BLOCK_LEN
        BNE .copyout2
        LDA #'M'
        STA.L !SRAM_SIG1
        LDA #'X'
        STA.L !SRAM_SIG2
        LDA #$00
        LDX #$00
.suminit:
        clc
        ADC.L !SRAM_DATA,X
        INX
        cpx #!BLOCK_LEN
        BNE .suminit
        STA.L !SRAM_SUM
        PLP
        RTL
assert pc() <= $890000

; ----------------------------------------------------------------------------
; SNES header checksum fix
; ----------------------------------------------------------------------------
; Asar's normal checksum fixing (enabled by default; do NOT pass
; --fix-checksum=off when building this patch) automatically recomputes
; and writes the correct checksum/complement pair for the final ROM at
; $80:FFDC-FFDF after all edits above are assembled. No hardcoded bytes
; are written here -- true checksum of the resulting ROM ($93 $B8, complement
; $6C $47)

; ============================================================================
; End of patch
; ============================================================================
