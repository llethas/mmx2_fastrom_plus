; ============================================================================
;  Mega Man X2 (SNES, USA) [FastROM v4.0 patch] -- Boss Intro START Skip
;  Apply after: Megaman X2 (U) - Fastrom v4.0.ips
; ============================================================================
;
;  ASSEMBLER
;    Written for Asar (https://github.com/RPGHacker/asar), LoROM, no header.
;    Build with checksum-fixing disabled:
;
;        asar --fix-checksum=off skip_boss_intro_for_mmx2fastrom.asm rom.sfc
;
;  WHAT IT DOES
;    Allows a newly-pressed START during the boss introduction to enter the
;    game's existing terminal intro state with a one-frame transition delay.
;    The selected boss ID is carried into the normal stage-transition path
;    before the state change, so the existing cleanup and stage-load code is
;    reused.
; ============================================================================

lorom

; ----------------------------------------------------------------------------
; How the boss intro works
; ----------------------------------------------------------------------------
;
; The boss introduction is controlled by the routine beginning at $80:B9D6.
; The current intro state is stored at $00D3 and is used as an index into the
; state table at $80:B9EF.  There are 9 states, at byte offsets $00, $02, $04,
; ..., $10 into that table.
;
; The original dispatch performed at $80:B9DB is:
;
;     LDX $00D3
;     JSR ($B9EF,X)
;
; State $10 is the normal final boss-intro state.  Its code begins at
; $80:BC3C and uses the direct-page timer at $34 (dp, relative to D=$0D18,
; i.e. physical $0D4C).  The preceding intro state loads $5A into that timer,
; so the normal transition waits 90 frames before continuing into the
; existing stage-transition code at $80:BC40.
;
; By changing the state to $10 and the timer to 1, the patch can use this
; existing transition path instead of jumping directly into stage code.
;
; State 0 ($80:BA01) also carries the boss the player selected forward into
; the rest of the cutscene:
;
;     $80:BA4E   LDA $1FAD        ; $1FAD = selected boss ID, set by the
;     $80:BA51   STA $0D4B        ;         boss-select screen
;     ...
;     $80:BA58   LDA #$0D         ; $1FAD is then reused as scratch/placeholder
;     $80:BA5A   STA $1FAD        ; for the duration of the cutscene
;
; and the terminal state reads it back here:
;
;     $80:BC50   LDA $0D4B
;     $80:BC53   STA $1FAD        ; $1FAD is restored just before stage load
;
; Forcing state $10 directly, as this patch does, can land on a frame where
; state 0 has not run yet, i.e. before it has copied $1FAD into $0D4B.  If
; that copy is skipped, $0D4B still holds whatever it last contained, and
; the terminal state loads the wrong stage -- the intro stage, if $0D4B has
; never been written this session, since stage index $00 is the intro stage.
; To prevent this, the patch performs that copy itself whenever it's needed
; (see the routine below) before forcing the jump to state $10, so the
; terminal state always reads back the boss the player actually selected.
;
; ----------------------------------------------------------------------------
; Controller input
; ----------------------------------------------------------------------------
;
; The newly-pressed controller buttons are available through $7E:25C0 and
; mirrored in the zero-page input variables.  The high byte is at $00AD.
; START is $1000 in the SNES controller word, therefore it is bit $10 in
; $00AD.
;
; Only the newly-pressed START bit is checked, so holding START does not
; cause the skip handler to retrigger every frame.
;
; ----------------------------------------------------------------------------
; Patch behavior
; ----------------------------------------------------------------------------
;
; 1. Replace the original state dispatch at $80:B9DB with a JSR to our
;    START-check routine at $80:FE77.
;
; 2. If START was not newly pressed, execute the original state dispatch.
;
; 3. If START was newly pressed:
;      - if $1FAD does not yet hold the placeholder $0D (i.e. state 0 has
;        not yet copied it this session), save the real selected boss ID
;        from $1FAD into $0D4B ourselves, so the wrong-stage bug described
;        above can't happen;
;      - force boss-intro state $10 at $00D3;
;      - set the transition timer at $34 to 1 frame;
;      - execute the original state-$10 dispatch.
;
; 4. The game's existing $80:BC3C-$80:BC49 transition code then performs the
;    normal cleanup and sends X into the correctly selected stage.
;
; ----------------------------------------------------------------------------
; Code locations
; ----------------------------------------------------------------------------
;
;   $80:B9DB  Original boss-intro state dispatch.
;   $80:FE77  Free space used by the START-check routine.
;
; The code cave at $80:FE77-$80:FE96 (32 bytes) is unused by the game and by
; the other patches in this set; $80:FE97 onward is claimed by later patches
; (extra_options_for_mmx2fastrom, sram_save_for_mmx2fastrom,
; option_mode_exit_to_menu_for_mmx2fastrom) and must not be touched here.
;
; ----------------------------------------------------------------------------
; Original bytes / replacement
; ----------------------------------------------------------------------------
;
;   $80:B9DB original:
;       AE D3 00 FC EF B9
;
;   $80:B9DB patched:
;       20 77 FE EA EA EA
;
;   $80:FE77:
;       AD AD 00 29 10 F0 12 AD AD 1F C9 0D F0 02 85 33
;       A9 10 8D D3 00 A9 01 85 34 AE D3 00 FC EF B9 60
;
; These are the exact bytes emitted by the companion IPS patch.
;
; ============================================================================

; ----------------------------------------------------------------------------
; Boss-intro dispatch hook
; ----------------------------------------------------------------------------

org $80B9DB

        JSR BossIntroStartSkip
        NOP
        NOP
        NOP

; ----------------------------------------------------------------------------
; START skip routine
; ----------------------------------------------------------------------------

org $80FE77

BossIntroStartSkip:
        LDA.W $00AD              ; Newly-pressed controller high byte.
        AND #$10                 ; START ($1000) = bit $10 here.
        BEQ .dispatch            ; No new START: keep the original state.

; Carry the selected boss ID forward ourselves so the wrong-stage bug
; doesn't happen: state 0 normally copies $1FAD (the boss the player
; selected) into $0D4B, then overwrites $1FAD with the placeholder $0D
; for the rest of the cutscene. If we're forcing the skip before state 0
; has run, $1FAD still holds the real boss ID (never $0D), so save it to
; $0D4B here before forcing the terminal state.
        LDA.W $1FAD
        CMP #$0D                 ; Already the placeholder -> state 0 already
        BEQ .force               ; ran and already made the copy; nothing to do.
        STA $33                  ; dp, D=$0D18 -> physical $0D4B.

.force:
        LDA #$10                 ; Force the normal terminal intro state.
        STA.W $00D3

        LDA #$01                 ; Reduce the transition delay to 1 frame.
        STA $34

.dispatch:
        LDX.W $00D3              ; Original state lookup.
        JSR ($B9EF,X)            ; Original state dispatch.
        RTS

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
