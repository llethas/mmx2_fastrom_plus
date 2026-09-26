; ============================================================================
;  Mega Man X2 (SNES, USA) [FastROM v4.0 patch] -- Default Key Config Swap
;  + Leg Armor AirDash + Head Armor I.TRACE demonstration scripted-input
;    compatibility
;  Apply after: "Megaman X2 (U) - Fastrom v4.0.ips"
; ============================================================================
;
;  ASSEMBLER
;    Written for Asar (https://github.com/RPGHacker/asar), LoROM, no header.
;    This patch is data-only. It changes the factory-default key-config table
;    and three demonstration scripted-input records. Build with
;    checksum-fixing disabled so the result matches the shipped IPS
;    byte-for-byte:
;
;        asar --fix-checksum=off dash_L_for_mmx2fastrom.asm rom.sfc
;
;  WHAT IT DOES
;    Changes the factory-default gamepad assignments shown on OPTION MODE ->
;    KEY CONFIG, moving DASH from A to L and SELECT_L from L to A. The same
;    logical actions are preserved in the Leg Armor AirDash and Head Armor
;    demonstrations by changing their scripted controller records.
; ============================================================================

lorom

;
;  THE INITIALIZATION ROUTINE (unmodified -- shown for reference only)
;    This routine runs during the save-data validity check (well before the
;    title screen is interactive) and decides whether the six-function
;    key-config block plus the surrounding option defaults need to be
;    (re)written from ROM. Addresses are for this FastROM-patched ROM;
;    bank $00 here is the slow (compatibility) mirror of the same bank $80
;    the CPU actually fetches from at runtime.
;
;      $00:828E   LDX #$1F                 ; 32 header bytes to check
;      $00:8291   LDY #$00                 ; mismatch counter
;      .compare_loop:
;      $00:8292   LDA $80FFC0,X            ; byte from the LIVE ROM header
;      $00:8296   CMP $7EFFA0,X            ; vs. the copy cached in WRAM
;                                           ;   (mirrors what was in SRAM
;                                           ;    when the save was made)
;      $00:829A   STA $7EFFA0,X            ; refresh the cached copy either way
;      $00:829E   BEQ .no_mismatch
;      $00:82A0   INY                      ; byte differed -> count it
;      .no_mismatch:
;      $00:82A1   DEX
;      $00:82A2   BPL .compare_loop
;      $00:82A4   DEY
;      $00:82A5   BMI .header_matched      ; Y was 0 -> no mismatches at all
;
;      ; --- header didn't match (new/foreign save): (re)write defaults ---
;      $00:82A7   LDX #$1A                 ; 27 bytes, index 26 downto 0
;      .default_copy_loop:
;      $00:82A9   LDA $86F1F9,X            ; <-- the table this patch edits
;      $00:82AD   STA $7EFFC0,X            ; <-- lands here (KeyConfig, etc.)
;      $00:82B1   DEX
;      $00:82B2   BPL .default_copy_loop
;      $00:82B4   LDA #$1E
;      $00:82B6   JSR $816B                ; end-of-reset housekeeping/SFX
;      .header_matched:
;      $00:82B9   ...                      ; execution continues either way
;
;    In plain terms: the game keeps a cached copy of its own 32-byte ROM
;    header inside WRAM (refreshed from SRAM at boot). If that cached copy
;    doesn't match the header of the ROM actually running, it treats the
;    options block (and the data around it) as belonging to a different
;    game/version and reloads all 27 bytes -- key config included -- from
;    this ROM table. If it DOES match, none of this block runs and whatever
;    the player already configured is left completely alone.
;
;  WHEN THE NEW DEFAULTS ACTUALLY APPLY
;    - Brand-new save / first boot ever: WRAM's cached header starts blank,
;      guaranteed to mismatch, so the copy loop runs and the save picks up
;      DASH=L / SELECT_L=A immediately.
;    - A save made on the *unpatched* FastROM v4.0 ROM, loaded after this
;      patch is applied: still matches, because this patch does not touch
;      any of the 32 header bytes being compared (title, mode byte, ROM/RAM
;      size, checksum, etc. are all untouched, and the checksum header itself
;      remains unchanged by this patch). The existing save's own key config is
;      kept exactly as the player left it; nothing is remapped out from under
;      them.
;
;  CHECKSUM BEHAVIOR
;    The DASH/SELECT_L table bytes are swapped ($20 <-> $08), so they have
;    no net effect on the ROM-wide byte sum. The Leg Armor demonstration edit
;    is $80 -> $20 (-$60). The two Head Armor edits are $30 -> $90 (+$60)
;    and $20 -> $80 (+$60), for a combined demonstration change of +$60.
;    The IPS and ASM therefore intentionally leave the SNES checksum
;    header unchanged.
;    Build with checksum fixing disabled, as shown above, to reproduce the
;    supplied IPS exactly.
;
;  RAM (read-only reference; not touched by this patch)
;    $7E:FFC0   current SHOT button (one-hot)
;    $7E:FFC1   current JUMP button (one-hot)
;    $7E:FFC2   current DASH button (one-hot)
;    $7E:FFC3   current SELECT_L button (one-hot)
;    $7E:FFC4   current SELECT_R button (one-hot)
;    $7E:FFC5   current MENU button (one-hot)
;    $7E:FFC6   $00 in the defaults table (unused/reserved)
;    $7E:FFC7   explicitly zeroed by the validation routine before this
;               block is copied (not part of the copied 27 bytes)
;    $7E:FFCA   current SOUND MODE flag ($F7 = STEREO, else MONAURAL)
;    $7E:FFA0-FFBF  cached copy of the 32-byte ROM header, used only for
;                   the "does this save belong to this ROM" check above
;    $7E:FFFC/FFFD  set to $FF once defaults have been (re)written
;    $7E:FFFF   "options already initialized" flag checked earlier in the
;               same routine (not part of the 27-byte block copied here)
;
;    One-hot encoding used ONLY by this table/WRAM block (it is the game's
;    own compact index for the 6 remappable functions, not a raw SNES
;    joypad bitmask): B=$80, Y=$40, A=$20, X=$10, L=$08, R=$04,
;    SELECT=$02, START=$01.
;
;  SCRIPTED INPUT (read-only reference; three records are changed below)
;    $86:D73C-$86:D73E  01 00 02  ; Head Armor: D-pad LEFT -- unchanged
;    $86:D73F-$86:D741  01 30 00  ; Head Armor: L+R -> A+R
;    $86:D745-$86:D747  01 20 00  ; Head Armor: L   -> A
;    $86:D75B-$86:D75D  20 80 00  ; Leg Armor: A   -> L
;
;    The Head Armor demonstration's first record uses raw $0200, which is the
;    SNES D-pad LEFT input, not the L button. It is therefore left untouched.
;    The later records contain the stock SELECT_L inputs: $0030 contains L+R,
;    and $0020 contains L. Under the patched defaults, L is DASH and A is
;    SELECT_L, so only the L bits are replaced: $0030 -> $0090 and $0020 ->
;    $0080. This preserves the other button in the $0030 record.
;
;    The Leg Armor record is a separate stock A input used for its scripted
;    dash. Changing $80 (A) to $20 (L) makes the tutorial's scripted dash follow
;    the patched DASH assignment.
;
;  FREE SPACE
;    None used -- this patch only overwrites five existing data bytes.
; ============================================================================

; ----------------------------------------------------------------------------
; Head Armor demonstration scripted input compatibility.
; The demonstration uses the stock physical L button for its SELECT_L actions,
; but the default key swap changes SELECT_L from L to A. The first record below
; is intentionally untouched: $0200 is the SNES D-pad LEFT input, not L.
;
;   $86D73C  01 00 02   ; D-pad LEFT -- unchanged
;
; The later SELECT_L records are converted by replacing only their L bit:
;
;   $86D73F  01 30 00   ; stock raw $0030 = L+R
;            01 90 00   ; patched raw $0090 = A+R
;
;   $86D745  01 20 00   ; stock raw $0020 = L
;            01 80 00   ; patched raw $0080 = A
;
; The game's existing scripted-input path consumes these raw controller words.
; The R bit in the first SELECT_L record is preserved, and no controller-reading
; or gameplay input routine is modified.
; ----------------------------------------------------------------------------

org $86D740
ScriptedHeadArmorDemoSelectLInput1:
        db $90                   ; was $30 (L+R) -> now $90 (A+R)

org $86D746
ScriptedHeadArmorDemoSelectLInput2:
        db $80                   ; was $20 (L) -> now $80 (A)

; ----------------------------------------------------------------------------
; Leg Armor AirDash demonstration scripted input record.
; The three-byte record begins at $86D75B. Its middle byte is the scripted
; controller value used for the demonstration's dash input.
;
;   $86D75B  20 80 00   ; stock record: scripted A
;            --^^--
;   $86D75B  20 20 00   ; patched record: scripted L
;
; The game's existing input conversion maps raw L ($20) to the compact L code
; ($08), which is the patched DASH assignment below.
; ----------------------------------------------------------------------------

org $86D75C
ScriptedAirDashDemoInput:
        db $20                   ; was $80 (A) -> now $20 (L)

; ----------------------------------------------------------------------------
; Factory-default options table (bank $06, mirrored at $86 for FastROM
; execution -- see "THE INITIALIZATION ROUTINE" above). Layout of the first
; six bytes, one per remappable function, in on-screen KEY CONFIG order:
;
;   $86F1F9  SHOT      ($40 = Y)        -- unchanged
;   $86F1FA  JUMP      ($80 = B)        -- unchanged
;   $86F1FB  DASH      ($20 = A) -> ($08 = L)
;   $86F1FC  SELECT_L  ($08 = L) -> ($20 = A)
;   $86F1FD  SELECT_R  ($04 = R)        -- unchanged
;   $86F1FE  MENU      ($01 = START)    -- unchanged
; ----------------------------------------------------------------------------

org $86F1FB
DefaultDash:
        db $08                   ; was $20 (A) -> now $08 (L)

org $86F1FC
DefaultSelectL:
        db $20                   ; was $08 (L) -> now $20 (A)

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
