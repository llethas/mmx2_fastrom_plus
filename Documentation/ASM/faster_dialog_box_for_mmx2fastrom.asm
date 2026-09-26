; ============================================================================
;  Mega Man X2 (SNES, USA) [FastROM v4.0 patch] -- "Faster Dialog Box"
;  Apply after: Megaman X2 (U) - Fastrom v4.0.ips
; ============================================================================
;
;  ASSEMBLER
;    Written for Asar (https://github.com/RPGHacker/asar), LoROM, no header.
;    Build with checksum-fixing disabled so the result matches the shipped
;    IPS byte-for-byte:
;
;        asar --fix-checksum=off faster_dialog_box_for_mmx2fastrom.asm rom.sfc
;
;  WHAT IT DOES
;    Speeds up the dialog-box opening/closing animation and the scroll to the
;    next text page. The patch keeps the original targets and uses clamped
;    per-frame steps so the animation still reaches the game's intended states.
; ============================================================================

lorom

; ############################################################################
; # PART 1 - Box opening / closing
; ############################################################################
;
; When the dialog box opens, its black background grows from a point into
; a full-size box; when it closes, it shrinks back down. This is driven by
; two counters living on the dialog box object's direct page:
;
;   $1A (DP)  - primary box-size counter
;   $1B (DP)  - secondary box-size counter
;
; While opening, both counters are incremented by 1 every frame until they
; reach fixed targets stored at DP $07 and $08 (normally ~$58 and ~$30).
; While closing, the same two counters are decremented by 1 every frame
; until they reach 0. Whichever counter has the longer distance to travel
; determines how long the animation takes; at the original 1 unit/frame
; that's roughly 88 frames (~1.5s) each way.
;
; A shared "did anything move this frame?" flag at absolute address $0000
; is incremented by the same code whenever a counter is still short of its
; target; once a frame passes with the flag staying at 0, the box knows
; both counters are finished and advances to the next state (open -> idle,
; or close -> fully closed).
;
; This patch replaces the single-step INC/DEC on $1A and $1B with much
; larger per-frame steps, while keeping the original targets so the box
; still ends up exactly the right size:
;
;   Open  $1A : +7/frame  (reaches target $07 in ~12 frames)
;   Open  $1B : +4/frame  (reaches target $08 in exactly 12 frames)
;   Close $1A : -7/frame  (reaches 0 in ~12 frames)
;   Close $1B : -4/frame  (reaches 0 in ~12 frames)
;
; Since the original code only stops on exact equality (BEQ) against the
; target, a step that could overshoot needs to be clamped afterwards -
; clamped to the target when opening, clamped to 0 when closing - so the
; box always finishes exactly where it's supposed to instead of stalling
; past its target and never triggering the "finished" flag.
;
; Four spots in bank $82 are hijacked, each replacing a 5-byte
; "INC $0000 / INC-or-DEC $xx" sequence with a JSL to one of four small
; replacement routines living in free space at the end of the ROM. A fifth,
; separate 2-byte edit (see "THE SOFTLOCK BUG" above) fixes the close
; animation's "am I finished?" check so it can never stall regardless of
; step size.
; ----------------------------------------------------------------------------

!CNT_1A    = $1A                 ; primary box-size counter (DP-relative)
!CNT_1B    = $1B                 ; secondary box-size counter
!TGT_1A    = $07                 ; open target for $1A
!TGT_1B    = $08                 ; open target for $1B
!FLAG      = $0000               ; "still moving this frame?" flag

; ----------------------------------------------------------------------------
; Hijack points (bank $82)
; ----------------------------------------------------------------------------

; Open path - replace the 5-byte "INC $0000 / INC $xx" sequences
org $82E615
        JSL OpenStep_1A
        NOP

org $82E620
        JSL OpenStep_1B
        NOP

; Close path - replace the 5-byte "INC $0000 / DEC $xx" sequences
org $82E64E
        JSL CloseStep_1A
        NOP

org $82E657
        JSL CloseStep_1B
        NOP

; ----------------------------------------------------------------------------
; Close animation "am I finished?" gate adjustment
; Prevents the close sequence from stalling in a softlock state
;
; Original:  CMP #$01 / BNE $E6B2   (proceed to the $1F38 check only when
;                                    flag is EXACTLY 1)
; Fixed:     CMP #$02 / BEQ $E6B2   (skip the check only while BOTH counters
;                                    are still actively closing this frame;
;                                    same target, same instruction sizes)
; ----------------------------------------------------------------------------
; NOTE: BEQ/BNE only auto-compute their relative offset from a real Asar
; label -- a bare numeric literal (even one that looks like an absolute
; address, e.g. "BEQ $82E6B2") is instead truncated directly to its low
; byte and used as-is. Defining a label for the target below makes Asar
; compute the correct relative offset automatically.
CloseGate_Target = $82E6B2

org $82E65F
        CMP #$02                 ; was CMP #$01
        BEQ CloseGate_Target     ; was BNE $82E6B2

; ----------------------------------------------------------------------------
; OpenStep_1A  - $1A += 7, clamp to target $07
; DP is still the dialog-box object base when called.
; ----------------------------------------------------------------------------
org $AFFE00
OpenStep_1A:
        INC !FLAG
        LDA !CNT_1A
        CLC
        ADC #$07                 ; ~12 frames to reach the open target
        CMP !TGT_1A
        BCC .store
        LDA !TGT_1A              ; clamp
        .store
        STA !CNT_1A
        RTL

; ----------------------------------------------------------------------------
; OpenStep_1B  - $1B += 4, clamp to target $08
; ----------------------------------------------------------------------------
org $AFFE20
OpenStep_1B:
        INC !FLAG
        LDA !CNT_1B
        CLC
        ADC #$04                 ; exactly 12 frames to reach the open target
        CMP !TGT_1B
        BCC .store
        LDA !TGT_1B
        .store
        STA !CNT_1B
        RTL

; ----------------------------------------------------------------------------
; CloseStep_1A  - $1A -= 7, clamp to 0
; ----------------------------------------------------------------------------
org $AFFE40
CloseStep_1A:
        INC !FLAG
        LDA !CNT_1A
        SEC
        SBC #$07
        BCS .store               ; no borrow -> still >= 0
        LDA #$00                 ; clamp
        .store
        STA !CNT_1A
        RTL

; ----------------------------------------------------------------------------
; CloseStep_1B  - $1B -= 4, clamp to 0
; ----------------------------------------------------------------------------
org $AFFE60
CloseStep_1B:
        INC !FLAG
        LDA !CNT_1B
        SEC
        SBC #$04
        BCS .store
        LDA #$00
        .store
        STA !CNT_1B
        RTL

; ############################################################################
; # PART 2 - Scrolling up to the next text page
; ############################################################################
;
; When a text page finishes and the player presses the button, the box
; doesn't reopen or resize - the background layer the text is printed on
; (BG3, hardware scroll register $2112 / BG3VOFS) is smoothly scrolled
; upward to reveal the next page, then holds at the new position.
;
; This is driven by a small generic "scroll effect" system, separate from
; the box-size counters in Part 1:
;
;   $1F48 (RAM) - per-frame step added to the scroll position each frame
;                 (initialized to 2 by the shared setup routine)
;   (other fields in $1F46+ control the remaining distance / state)
;
; A shared setup routine at $80EA07 initializes this system - among
; other things it hardcodes the per-frame step to 2. At 2 pixels/frame,
; scrolling a typical 40-pixel page (five 8-pixel tile rows) takes
; 40/2 = 20 frames (~0.33s).
;
; $80EA07 is a *shared* utility - several different call sites across the ROM
; use it for other effects (menus, HUD reveals, etc.), and the step size
; is hardcoded inside the shared routine rather than passed in by the
; caller. Patching it directly would speed up every other effect that
; uses it too.
;
; This patch instead hijacks only the ONE call site used by the dialog
; text-scroll (bank $82, the box's per-frame state code). That call still
; runs the original setup exactly as before, then immediately overwrites
; just its own copy of the per-frame step from 2 to 4 before the first
; frame of scrolling happens. No other caller of $80EA07 is touched.
;
; At the new step of 4 pixels/frame, a typical 40-pixel page takes
; 40/4 = 10 frames; a taller page (up to 48px / six rows) takes exactly
; 12 frames; a shorter page takes fewer still.
;
; NOTE: $1F38, the flag involved in the softlock above, is not part of
; this scroll-effect system's fields ($1F46+); it is a separate, shared
; "busy" flag read by the close-animation check. This patch does not
; change how or when $1F38 itself gets set to 0 -- the fix above simply
; makes sure the game keeps checking it instead of giving up after one
; frame.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; Hijack point (bank $82) - the JSL that kicks off the page-scroll effect
; ----------------------------------------------------------------------------
; Original 4 bytes: JSL $80EA07   (runs the shared setup, step defaults to 2)
; Same size in, same size out - no NOP padding needed.
org $82E62C
        JSL ScrollSpeedOverride

; ----------------------------------------------------------------------------
; ScrollSpeedOverride
;   Runs the original scroll-effect setup, then overrides just the per-frame
;   step for this call site so only the dialog text-scroll speeds up.
;   The original $80EA07 restores the caller's P/DB/DP as needed.
; ----------------------------------------------------------------------------
org $AFFE80
ScrollSpeedOverride:
        JSL $80EA07              ; original setup (defaults: step=2, etc.)
        LDA #$04                 ; faster per-frame scroll step (was 2)
        STA $1F48
        RTL

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
