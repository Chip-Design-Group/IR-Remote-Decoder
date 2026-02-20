# Tapeout Checklist (IHP SG13G2)

## Run Commands

```bash
cd /home/maik/HM/Semester_5/IR-Remote-Decoder/librelane
nix-shell
cd /home/maik/HM/Semester_5/IR-Remote-Decoder/TopLevel/src
make librelane-tapeout
```

Quick iteration run (not final signoff):

```bash
make librelane-signoff-quick
```

## Required Pass Criteria

- `design__lint_error__count == 0`
- `openroad__psm__violations == 0`
- `route__drc_errors == 0`
- `design__critical_disconnected_pin__count == 0`
- `Checker.KLayoutDRC` passes
- `Checker.LVS` passes
- `Checker.SetupViolations` passes
- `Checker.HoldViolations` passes

## Notes on Magic-Based Errors

- `config_tapeout.yaml` disables hard-fail on `Magic.DRC` and `IllegalOverlap`.
- This is intentional for the current SG13G2 padframe+bondpad integration, where
  Magic commonly reports obstruction/slotting artifacts not reproduced by
  KLayout DRC + LVS.
- If your MPW/foundry explicitly requires Magic-clean signoff, use
  `config_signoff.yaml` and resolve all Magic errors before submission.
