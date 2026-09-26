AI was used to assist in the creation of this project.

Patch order:

  1. Megaman X2 (U) - Fastrom v4.0.ips
  2. skip_boss_intro_for_mmx2fastrom.ips
  3. faster_dialog_box_for_mmx2fastrom.ips
  4. dash_L_for_mmx2fastrom.ips
  5. extra_options_for_mmx2fastrom.ips
  6. option_mode_exit_to_menu_for_mmx2fastrom.ips
  7. sram_save_for_mmx2fastrom.ips

"fastrom_plus.ips" contains all of the patches merged into one. You can pick and choose which patches to apply, however, Megaman X2 (U) - Fastrom v4.0 is required for all of them, and if you're applying the sram_save_for_mmx2fastrom patch, it requires extra_options_for_mmx2fastrom and option_mode_exit_to_menu_for_mmx2fastrom to be applied beforehand.


Individual changes breakdown:

  skip_boss_intro_for_mmx2fastrom:
      - Pressing START skips the boss intro

  faster_dialog_box_for_mmx2fastrom:
      - Dialogue boxes open, close, and scroll faster

  dash_L_for_mmx2fastrom:
      - Assigns dash to L by default (and changes the armor upgrades scripted demonstration input assignments too, since changing the default DASH and SELECT_L breaks them)

  extra_options_for_mmx2fastrom:
      - Implements the EXTRA OPTIONS menu with the following toggles (also implements their gameplay gates alongside the UI elements):
          - D-TAP DASH (OFF by default, toggles double-tap dash)
          - BETTER SUB-TANK (ON by default, stops sub-tanks from depleting once health is full)

  option_mode_exit_to_menu_for_mmx2fastrom:
      - Exiting OPTION MODE now goes back directly to the main menu, instead of restarting the intro

  sram_save_for_mmx2fastrom:
      - Adds SRAM saving for in-game passwords, control scheme, and option toggles from OPTION MODE and EXTRA OPTIONS


See the .asm files for more information about each patch.
