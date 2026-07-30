# facelock Requirements Audit

**Date:** 2026-07-30 · **Scope:** `apps/face-unlock/` (Prototype phase, `security.phase = P`) · **Method:** read-only traceability of all 54 requirement IDs from `docs/pilot-face-unlock/requirements.md` against the 20 implementation modules in `apps/face-unlock/facelock/*.py` and the 22 test files in `apps/face-unlock/tests/*.py` (220 test functions). No daemon, `systemctl`, or camera was invoked.

Each requirement is classified into exactly one of: **CODE+TEST** (implemented and covered by a passing automated test), **CODE-ONLY** (implemented but only incidental / no automated test, or satisfied by construction / static inspection), **NEEDS-LIVE** (correctness requires a real webcam, X11 display, or graphical session — unit tests mock the camera and X, so recognition-accuracy, shield-visibility, and wall-clock/perf requirements land here even when the plumbing is unit-tested), or **GAP** (not implemented, partial, or a documented Hardening hook/stub). A note on the phase model: the pilot is the **Prototype**. Requirements tagged Hardening-only (`H`) that are intentionally deferred behind documented hooks are marked **GAP** with that deferral called out — they are honest gaps against the *full* spec, not defects of the prototype.

## Summary counts

| Status | Functional (F-01..27) | Non-functional (NF-01..27) | Total |
|---|---|---|---|
| CODE+TEST  | 15 | 8  | **23** |
| CODE-ONLY  | 4  | 11 | **15** |
| NEEDS-LIVE | 5  | 7  | **12** |
| GAP        | 3  | 1  | **4**  |
| **Total**  | 27 | 27 | **54** |

The four GAPs are all Hardening-phase items deferred by design: REQ-F-20 (PAM), REQ-F-21 (privileged helper), REQ-F-24 (OS-auth unlock), REQ-NF-11 (PAD to ISO/IEC 30107-3). The prototype's own contract (screensaver-only, fail-closed, password never touched) has no GAP.

---

## Traceability Matrix

| REQ-ID | Requirement (short) | Code location | Test(s) | Status | Notes |
|---|---|---|---|---|---|
| REQ-F-01 | Owner enrollment: capture ≥5 samples, build 0600 template + name | `enroll.py:EnrollmentTool.enroll` / `enroll.py:build_template` / `store.py:TemplateStore.save` | `test_enroll_core.py:test_build_template_produces_calibrated_template`, `test_pose_plan_*`; `test_store.py:test_roundtrip_and_permissions` | CODE+TEST | Template build/pose-plan/quality/0600 unit-tested; the interactive camera capture loop itself is exercised only live (owner is enrolled, τ≈0.363). |
| REQ-F-02 | Enrollment quality gate: reject 0/>1 face, too small/blurry/dark | `enroll.py:assess_quality` | `test_enroll_core.py:test_quality_no_face` / `_multiple_faces` / `_face_too_small` / `_too_blurry` / `_bad_brightness` / `_ok` | CODE+TEST | Pure gate fully covered with synthetic detections/metrics. |
| REQ-F-03 | Re-enroll / update (supersede or augment), logged | `enroll.py:EnrollmentTool.enroll` (augment) / `store.py:TemplateStore.save` (.bak rotate) / `store.py:rollback` | `test_store.py:test_rollback_restores_backup`, `test_roundtrip_and_permissions` | CODE+TEST | Supersede + backup + rollback tested; the augment-merge branch (camera) is code-only. |
| REQ-F-04 | Delete template / factory reset (secure) | `store.py:TemplateStore.delete` / `store.py:_secure_shred` / `enroll.py:EnrollmentTool.delete` | `test_store.py:test_secure_delete_removes_all` | CODE+TEST | Overwrite-then-unlink of template+bak+sig+key verified. |
| REQ-F-05 | Camera acquisition (V4L2, busy/backoff, no crash) | `capture.py:CameraCapture.open` / `.read` / `.reacquire` | — (no `test_capture.py`; camera object faked in `test_enroll_pause.py`) | NEEDS-LIVE | Real device open/fps/EBUSY-backoff has no unit coverage; requires the webcam. |
| REQ-F-06 | Face detection (0/1/many, confidence, local model) | `detect.py:FaceDetector.detect` | — (no detector unit test; needs cv2 model + frames) | NEEDS-LIVE | Fail-closed empty-list logic present but untested; detection is inherently live. |
| REQ-F-07 | Face verification 1:1 (embed + τ + accept/reject) | `embed.py:FaceEmbedder.embed` / `matcher.py:Matcher.verify` / `matcher.py:_score` | `test_matcher.py:*` (k-of-n, cosine, multiface/no-template never owner); `test_matcher_multipose.py:*` | NEEDS-LIVE | Matcher math + k-of-n heavily unit-tested; recognition of the real owner (SFace embedding) is live. |
| REQ-F-08 | Multiple-face policy — fail closed (no unlock >1 face) | `matcher.py:Matcher.verify` (`face_count==1` guard) / `fsm.py:_on_verifying` (>1 → `_count_fail`) | `test_matcher.py:test_multiface_never_owner`; `test_fsm.py:test_multiface_never_grants` | CODE+TEST | Deterministic guard fully covered. |
| REQ-F-09 | Owner presence monitoring (no lock while present) | `fsm.py:_on_unlocked` / `_on_unlocked_grace` | `test_fsm.py:test_owner_returns_in_grace`, `test_away_locks_after_dwell`; `test_no_owner.py:test_owner_present_away_locks_normally` | CODE+TEST | FSM presence logic tested with synthetic observations; live-confirm the camera keeps recognizing the seated owner (checklist B). |
| REQ-F-10 | Away/absence detection → auto-lock after dwell | `fsm.py:_on_unlocked_grace` (`away_dwell_s`) / `guardian.py:_cmd_lock` | `test_fsm.py:test_away_locks_after_dwell`; `test_relock.py:test_away_lock_uses_shield_not_os_backend` | CODE+TEST | Dwell logic (injected clock) tested; wall-clock latency is live (see NF-03). |
| REQ-F-11 | Stranger-present detection → lock + log | `fsm.py:_stranger_triggered` / `_on_unlocked`; `guardian.py:_cmd_lock`; `shield.py:set_denied` | `test_fsm.py:test_stranger_lenient_*` / `_strict_*`; `test_relock.py:test_stranger_lock_uses_shield_not_os_backend`; `test_feedback.py:test_shield_status_denied_shows_unauthorized` | CODE+TEST | Policy logic tested; real stranger recognition is live (checklist C). |
| REQ-F-12 | Owner-return re-acquire → start verification | `fsm.py:_on_locked` (face → VERIFYING); `daemon.py:_manage_camera` (reacquire); `shield.py:set_recognizing` | `test_fsm.py:test_locked_face_begins_verifying` | CODE+TEST | FSM re-acquire trigger tested; camera duty-cycle re-acquire + latency are live. |
| REQ-F-13 | Engage screen lock (abstract backend, verified) | `lock_backend.py:LockController.engage` / `select_backends` / `LoginctlBackend`/`GnomeDbusBackend`/`XdgScreensaverBackend`; `guardian.py:_escalate_os_lock` | `test_lock_controller.py:*` (confirmed / fallback / none-confirmed fail-closed / last-resort / no-backends) | CODE+TEST | Controller verify-engaged + fallback tested with fake backends; actual OS lock-screen display is live (checklist F). |
| REQ-F-14 | Face-verified unlock (release shield, no password) | `guardian.py:_cmd_unlock_grant`; `control.py:GrantAuthority.validate_grant`; `daemon.py:_handle_emits`; `fsm.py:_to_grant`; `shield.py:dismiss` | `test_control.py:test_valid_grant_consumes_and_unlocks`; `test_guardian_dispatch.py:test_valid_unlock_grant_dismisses`; `test_relock.py:test_relock_after_unlock_with_stale_grant_stays_locked` | NEEDS-LIVE | Nonce-bound grant + dismiss plumbing strongly unit-tested; the flagship "my face drops the shield" needs a live face + display (checklist B). |
| REQ-F-15 | Personalized "Welcome back, <name>" ≤3 s | `guardian.py:_cmd_unlock_grant` (greeter + welcome hold); `shield.py:Greeter.show` / `ShieldWindow.set_welcome`; `guardian.py:_maybe_finish_welcome` | `test_feedback.py:test_unlock_shows_welcome_splash_then_dismisses_after_hold`, `test_unlock_with_zero_hold_dismisses_immediately` | NEEDS-LIVE | Trigger/one-shot/≤3 s dismiss timing unit-tested; the on-screen splash + `notify-send` are live. |
| REQ-F-16 | Non-owner/spoof denied; OS password left working | `matcher.py:Matcher.verify` (reject); `fsm.py:_count_fail`; no-PAM architecture (`__init__.py`) | `test_matcher.py` (impostor rejected); `test_fsm.py:test_reject_then_cooldown_then_recover`; `test_matcher_multipose.py:test_stranger_still_rejected_with_pose_bank` | CODE+TEST | Rejection logic tested; password-path-untouched is by-construction (see F-18). Live-confirm the OS password field at the lock screen. |
| REQ-F-17 | Prototype spoof-limitation disclosure (README + first-run) | `__init__.py:PROTOTYPE_SPOOF_DISCLOSURE`; `cli.py:_maybe_show_disclosure` / `cmd_disclosure`; `README.md` §Safety notice | — (no test asserts the disclosure string or first-run marker) | CODE-ONLY | Disclosure present and wired to first-run + `facelock disclosure`; add a unit test asserting the text + `.disclosed` marker. |
| REQ-F-18 | Bounded scope: no PAM/sudo/login hooks in prototype | Absence — verified: no `pam`/`setuid`/`pkexec` in `facelock/`; `systemd/*.service` are `--user` + `NoNewPrivileges=true` | — (AC is static inspection; no guard test) | CODE-ONLY | Grep confirms zero PAM/sudo/login coupling. Recommend a CI test that greps the tree to prevent regression. |
| REQ-F-19 | Liveness/anti-spoofing (P: optional turn/blink; H: full PAD) | `liveness.py:LivenessEngine.check` / `_check_turn` / `_check_passive`; `estimate_yaw` | `test_liveness.py:test_turn_pass_with_motion`, `_turn_fails_for_static_photo`, `_off_mode_*`, `_passive_unavailable_fails_closed`, `_blink_hook_fails_without_model` | CODE+TEST | Prototype `turn` geometry + fail-closed hooks tested. **Caveat:** default is `off` (photo-spoofable by design); the Hardening `passive`/`full`/`blink` PAD are model-less fail-closed hooks — see REQ-NF-11 (GAP). Real spoof-resistance is live. |
| REQ-F-20 | Optional PAM integration (Hardening) | Not implemented (documented hook in `README.md`, design §13) | — | GAP | Intentionally absent in prototype (REQ-F-18); deferred to Hardening. |
| REQ-F-21 | Secure privileged helper (Hardening, if F-20) | Not implemented (prototype is user-space, no privileged surface) | — | GAP | N/A until F-20; deferred. |
| REQ-F-22 | Event logging (structured, image-free) | `logging_setup.py:get_logger` / `event` / `_JsonLineFormatter` (image-key redaction) | — (no `test_logging.py`; `event()` used across tests but never asserted) | CODE-ONLY | JSON-lines events + `_IMAGE_KEYS` redaction implemented; no automated assertion. Add a test for one-line-per-event + redaction. |
| REQ-F-23 | Configuration (typed, range-validated, fail-closed) | `config.py:load_config` / `SCHEMA` / validators / `_determine_phase` | `test_config.py:*` (defaults, phase aliases, security-refuse, cross-field, off-forbidden-in-H, persist-frames rejected, bad-TOML fail-closed, missing-file defaults) | CODE+TEST | Extensively covered incl. security-critical refuse semantics. |
| REQ-F-24 | OS-auth unlock path (Hardening, supersede F-14) | Not implemented (would route via PAM, F-20) | — | GAP | Deferred to Hardening. |
| REQ-F-25 | Manual override / panic-lock / disable / cooldown | `cli.py:cmd_lock`/`cmd_disable`/`cmd_enable`; `guardian.py:_cmd_lock`(panic)/`_cmd_disable`/`_cmd_enable`; `fsm.py:_count_fail`→COOLDOWN | `test_fsm.py:test_reject_then_cooldown_then_recover`, `test_disable_then_enable`, `test_panic_locks`; `test_guardian_dispatch.py:test_disable_blocks_unlock_and_hides_nonce`, `test_enable_restores`; `test_no_owner.py:test_no_owner_panic_still_locks` | CODE+TEST | Panic/disable/enable/cooldown logic fully covered. |
| REQ-F-26 | Service lifecycle + crash recovery (never auto-unlock) | `guardian.py:_check_watchdog` (heartbeat-miss → escalate); `daemon.py:_sd_notify`/`_heartbeat`; `systemd/*.service` (`Restart=always`, `WatchdogSec`, `Type=notify`) | `test_no_owner.py:test_watchdog_with_owner_escalates`, `_no_owner_does_not_escalate`; `test_relock.py:test_heartbeat_miss_still_escalates_and_keeps_screen_on` | CODE+TEST | Watchdog escalation logic tested; actual systemd restart-on-crash is live (checklist F). |
| REQ-F-27 | Camera in-use indicator (tray or hardware LED) | `capture.py:CameraCapture.open`/`.release` (UVC LED via device open/close); `config.py:228` `privacy.camera_indicator` | — | CODE-ONLY | Met only by the incidental UVC LED (camera open lights it, `release()` clears it). **No tray icon**, and the `privacy.camera_indicator` flag is **defined but never consumed**. SHOULD-level; observe LED live. |
| REQ-NF-01 | Active loop ≥5 fps (CPU) | `daemon.py:run` (period pacing) / `_target_fps`; `cli.py:cmd_test` (reports fps) | — (perf; needs camera) | NEEDS-LIVE | Run `facelock test`; measured fps only meaningful on the real CPU + camera. |
| REQ-NF-02 | Unlock latency P95 ≤2 s; per-frame ≤200 ms | `cli.py:cmd_test` (measures per-frame + p95); `config.py` `probe_frames` | — (perf) | NEEDS-LIVE | `facelock test` prints per-frame mean/p95 vs the 200 ms budget. |
| REQ-NF-03 | Away-lock within dwell + 2 s | `fsm.py:_on_unlocked_grace`; `guardian.py:run` loop cadence | `test_fsm.py:test_away_locks_after_dwell` (injected clock) | CODE+TEST | Dwell arithmetic tested; the +2 s wall-clock is live (checklist B). |
| REQ-NF-04 | Stranger-lock within 2 s | `fsm.py:_stranger_triggered` (`stranger_dwell_s`) | `test_fsm.py:test_stranger_lenient_locks_when_owner_absent`, `_strict_locks_even_with_owner_present` | CODE+TEST | Trigger logic tested; wall-clock latency live (checklist C). |
| REQ-NF-05 | Optional GPU; MUST stay functional on CPU | CPU-only by default (`opencv-python` CPU, `onnxruntime` optional extra) | — | CODE-ONLY | Satisfied by design — the only execution path is CPU; GPU is an unused optional accelerator (MAY). |
| REQ-NF-06 | Idle CPU ≤15% of one core | `daemon.py:_manage_camera` (idle throttle + long-absence release); `config.py` `fps_idle`; `systemd` `CPUQuota` | — (profiling) | NEEDS-LIVE | Profile with `top`/`pidstat` over 5 min idle. |
| REQ-NF-07 | Active CPU ≤ ~1 core sustained | `systemd/facelockd.service` `CPUQuota=100%`, `OMP_NUM_THREADS=4`; `config.py` `runtime.threads` | — (profiling) | NEEDS-LIVE | `CPUQuota` hard-caps it; confirm desktop stays responsive during an unlock burst. |
| REQ-NF-08 | Resident memory ≤500 MB | `systemd/*.service` `MemoryMax=500M` | — (profiling) | NEEDS-LIVE | Hard-capped by cgroup; observe RSS live. |
| REQ-NF-09 | Install ≤300 MB; logs rotated/capped | `logging_setup.py:get_logger` (`RotatingFileHandler`, `max_size_mb`×`rotate_count`) | — (rotation not directly asserted) | CODE-ONLY | Log rotation implemented + size-capped; install footprint (SFace 38.7 MB + YuNet 0.23 MB + venv) not measured by a test. Verify size live. |
| REQ-NF-10 | Accuracy operating point FMR≤1e-2, FNMR≤5% + CIs | `calibrate.py:calibrate` / `_tau_at_fmr_cosine` / `wilson_interval`; `store.py:generate_synthetic_impostors` | `test_calibrate.py:test_calibration_enforces_floor`, `_meets_target_for_tight_cluster`, `_never_relaxes_below_floor`, `_requires_min_samples`/`_impostors`, `test_wilson_interval_bounds` | NEEDS-LIVE | Calibration math + τ-floor + CIs strongly unit-tested, **but the prototype calibrates against a SYNTHETIC impostor null** (`generate_synthetic_impostors`) — real measured FMR/FNMR against genuine impostor faces has never been run. Needs a live eval protocol. |
| REQ-NF-11 | PAD APCER≤5% @ BPCER≤5% per ISO/IEC 30107-3 (H) | `liveness.py:_PassivePAD` / `_check_passive` (hook, fails closed w/o model) | `test_liveness.py:test_passive_unavailable_fails_closed` | GAP | Documented Hardening hook only; no PAD model, no 30107-3 evaluation. Deferred. |
| REQ-NF-12 | Local-only; zero network connections | `control.py` (AF_UNIX socket only, SO_PEERCRED); no `AF_INET`/`urllib`/`requests` anywhere in `facelock/` | — (no network-monitor test) | CODE-ONLY | Verified by construction (grep: no inet/http). Only network is `download_models.sh` provisioning. Add a static guard test; live-confirm with a network monitor (AC-NF-12). |
| REQ-NF-13 | No raw-frame persistence; embeddings only | `capture.py` (frames in memory only, no `imwrite`); `store.py` (npz embeddings, `allow_pickle=False`); `logging_setup.py:_JsonLineFormatter` (image-key redaction) | — (no FS-scan test) | CODE-ONLY | Verified by construction (grep: no `imwrite`/frame-pickling). Add a filesystem-scan test after a run. |
| REQ-NF-14 | Template at rest 0600 (P) / encrypted (H) | `store.py:TemplateStore.save`/`load` (0600 + HMAC sig, refuse non-0600); `paths.py:secure_write_bytes`/`is_mode` | `test_store.py:test_roundtrip_and_permissions`, `_unsafe_permissions_refused`, `_tamper_detected`, `_missing_sig_fails_closed`; `test_paths.py:test_secure_write_bytes_perms_and_content`, `test_is_mode` | CODE+TEST | Prototype 0600 + tamper-evidence fully covered. Encrypted-at-rest (H) is a documented hook (see NF-25 note). |
| REQ-NF-15 | Data minimization + complete erasure | `store.py:TemplateStore.delete` / `_secure_shred`; `paths.py` (only template/config/logs stored) | `test_store.py:test_secure_delete_removes_all` | CODE+TEST | Erasure verified; only required artefacts persisted. |
| REQ-NF-16 | Camera-use transparency; greeting name-only | `shield.py:Greeter.show` (message = "Welcome back, {name}"); camera LED (see F-27) | `test_feedback.py` (welcome splash content) | CODE-ONLY | Greeting is name-only by construction; the "indicator accurate" half inherits F-27's weakness (LED-only, dead config flag). |
| REQ-NF-17 | Usability: enroll ≤2 min; greeting ≤1 s; password recovery; safe defaults | `enroll.py:EnrollmentTool.enroll` (`timeout_s`); `guardian.py` `welcome_hold_s`; `config.py` safe defaults | — (human-timed) | NEEDS-LIVE | **Discrepancy:** `enroll.py:186` default `timeout_s=240.0` (4 min) exceeds the ≤2 min AC. Greeting-latency and password-recovery are human-observed. |
| REQ-NF-18 | Nuisance-lock bound (lenient: no lock while owner co-present) | `fsm.py:_stranger_triggered` (lenient branch) | `test_fsm.py:test_stranger_lenient_no_lock_when_owner_present` | CODE+TEST | Co-presence logic tested; live-confirm under a real colleague-behind-owner scene (checklist C). |
| REQ-NF-19 | Abstracted lock backend, swappable at runtime | `lock_backend.py:select_backends` / `_BACKEND_CLASSES` / `_AUTO_ORDER` | `test_lock_controller.py:test_select_backends_auto_returns_list`, `_fallback_to_next_backend` | CODE+TEST | Config-selectable backend chain tested. |
| REQ-NF-20 | Wayland-ready design (no X11-only core coupling) | `shield.py:has_display` (checks WAYLAND_DISPLAY); `display.py` (Wayland-degrade no-op); `lock_backend.py` (loginctl is session-agnostic) | — (AC is arch review) | CODE-ONLY | Core has no hard X11 coupling and documents the Wayland insertion points; a Wayland lock backend is not yet implemented (deferred, correct for phase). |
| REQ-NF-21 | Standard pinned dependency stack | `requirements.txt` / `pyproject.toml` (`numpy==2.2.6`, `opencv-python==4.12.0.88`, `tomllib` stdlib); no dlib/mediapipe | — (clean-env install AC) | CODE-ONLY | Pins present; reproduction effectively validated by the live editable install (220 tests pass on the pinned stack). Clean-machine repro is live. |
| REQ-NF-22 | Fail-closed guarantee (no fault yields unlock) | `fsm.py:step` (exception → LOCKED) / `_decide` (camera/suspend/panic); `matcher.py` (never owner on error, τ never lowered); `store.py:try_load` (corrupt → None); `config.py` (refuse) | `test_fsm.py:test_step_exception_forces_locked`, `_camera_error_grace_then_lock`, `_suspend_locks`; `test_matcher_multipose.py:test_tau_is_never_lowered_by_pose_mode`; `test_store.py:test_try_load_returns_none_on_corruption` | CODE+TEST | Many fault paths unit-tested; the full physical fault-injection matrix (kill camera/corrupt model/kill process) is live (checklist F). |
| REQ-NF-23 | Availability + watchdog auto-restart | `guardian.py:_check_watchdog` / `_write_health`; `systemd/*.service` (`Restart=always`, `WatchdogSec`) | `test_no_owner.py:test_watchdog_with_owner_escalates`; `test_relock.py:test_heartbeat_miss_still_escalates_and_keeps_screen_on` | CODE+TEST | Watchdog + lock-state-preservation logic tested; systemd auto-restart is live. |
| REQ-NF-24 | Observability (reconstruct any decision, no images) | `logging_setup.py:event` (score/tau/face_count/reason fields); `guardian.py:_write_health` (health.json); `guardian.py:_cmd_status` | — (no log-content test) | CODE-ONLY | Structured events + health snapshot implemented; no automated assertion of reconstructability. |
| REQ-NF-25 | Auditability: tamper-evident audit trail (H) | `logging_setup.py:AuditLog` (HMAC-chained, append-only, `verify`); enabled only when `security.audit` (H) | — (no AuditLog chain/verify test) | CODE-ONLY | Fully implemented (not a stub) but inert in the prototype and untested. Add a chain-append/verify/tamper test. |
| REQ-NF-26 | Reproducible one-command build (pinned env) | `scripts/install.sh` (venv + pinned deps + package + models + units); `scripts/download_models.sh` (SHA-pinned) | — (build AC) | CODE-ONLY | One-command installer + SHA-pinned models implemented; validated live by the working install. Clean-machine build is a live AC. |
| REQ-NF-27 | Least privilege (prototype non-root) | `scripts/install.sh` (refuses `id -u == 0`); `systemd/*.service` `NoNewPrivileges=true`, `--user`; no privileged surface | — (inspection AC) | CODE-ONLY | Non-root by construction; verified by inspection (install root-refusal + user units). |

---

## Gaps & Weak Coverage

Most important first. GAP items are Hardening-phase deferrals (expected); CODE-ONLY items are prototype behaviours lacking an automated guard.

**GAPs (not implemented — all Hardening, deferred by design):**

- **REQ-NF-11 — PAD to ISO/IEC 30107-3 (APCER≤5%@BPCER≤5%).** `liveness.py:_PassivePAD` is a runnable hook that fails closed with no model; no PAD model ships and no 30107-3 evaluation exists. **Action:** Hardening milestone — pin a MiniFASNet model, decode its output, and run a 30107-3-style print/replay/mask protocol. Until then the prototype is documentedly photo-spoofable (REQ-F-17).
- **REQ-F-20 — Optional PAM integration.** Intentionally absent (REQ-F-18 forbids it in the prototype). **Action:** Hardening — opt-in, liveness-gated PAM module that always falls through to the password.
- **REQ-F-24 — OS-auth unlock path (supersede F-14).** Not implemented; would route unlock through PAM (F-20). **Action:** implement with F-20; keep password fallback.
- **REQ-F-21 — Secure privileged helper.** Not implemented; only relevant once F-20 exists. **Action:** minimal least-privilege helper with input validation when PAM is added.

**CODE-ONLY (implemented but no / only-incidental automated test) — prototype-relevant, fix candidates:**

- **REQ-F-27 / REQ-NF-16 — Camera in-use indicator.** Only the incidental UVC LED satisfies this; there is **no tray icon** and `privacy.camera_indicator` (`config.py:228`) is **defined but never consumed** — a dead flag. **Action:** either wire the flag to a tray/indicator and add a test, or downgrade the requirement to "hardware LED only" and document it. (SHOULD-level.)
- **REQ-F-17 — Spoof-limitation disclosure.** Present in `__init__.py`/README/first-run, but **no test** asserts the text or the `.disclosed` first-run marker. **Action:** add a unit test on `PROTOTYPE_SPOOF_DISCLOSURE` content + `cli._maybe_show_disclosure` marker creation.
- **REQ-F-18 — No PAM/sudo/login hooks.** Satisfied (grep-confirmed) but only by inspection. **Action:** add a CI guard test that greps the tree for `pam`/`setuid`/`pkexec` to prevent regression.
- **REQ-F-22 / REQ-NF-24 — Event logging & observability.** `logging_setup.event` + `_JsonLineFormatter` image-redaction and `health.json` have no assertion. **Action:** test that one JSON line is emitted per event, that image keys are redacted, and that a decision (score/tau/face_count/reason) is reconstructable.
- **REQ-NF-25 — Audit trail (H).** `AuditLog` HMAC-chaining/`verify` is fully coded but untested and disabled in P. **Action:** add append→verify→tamper-detection tests (cheap, no hardware).
- **REQ-NF-12 — Local-only / no network.** By construction (no `AF_INET`/`urllib`). **Action:** add a static guard test (assert no inet sockets / no `urllib`/`requests` import in `facelock/`).
- **REQ-NF-13 — No raw-frame persistence.** By construction (no `imwrite`, embeddings-only). **Action:** add a filesystem-scan test after a mocked run asserting only the template exists.
- **REQ-NF-10 — Accuracy operating point.** Calibration math is tested, but the prototype uses a **synthetic** impostor null (`store.generate_synthetic_impostors`); real FMR/FNMR against genuine impostor faces is unmeasured. **Action:** run a live owner/impostor eval and report measured FMR/FNMR with CIs (also a NEEDS-LIVE item below).
- **REQ-NF-17 — Enrollment time budget.** `enroll.py:186` `timeout_s=240.0` (4 min) contradicts the ≤2 min AC. **Action:** lower the cap to 120 s (or document the coverage-based early-exit that normally finishes well under 2 min) and confirm live.
- **REQ-NF-05 / NF-09 / NF-20 / NF-21 / NF-26 / NF-27** — satisfied by design/inspection (CPU-only, log rotation, Wayland-ready, pinned deps, one-command build, non-root). Low risk; each would benefit from a small install/size/static test but none block the pilot.

---

## Live-Test Checklist

Ordered steps for the enrolled owner (Yash) at the physical machine. Each step lists the action, the exact expected result, and the REQ-ID(s) it validates. **Do step 0 first and keep the escape hatch ready throughout.** Config context: `stranger_policy=lenient`, `liveness.mode=off`, `security.phase=P` (screensaver-only, no PAM, photo-spoofable by design).

**0. ESCAPE HATCH (arm before anything else).** If the shield ever traps you or behaves wrongly: press **Ctrl+Alt+F3** to reach a text TTY, log in, and run `systemctl --user stop facelockd facelock-guardian`. Your **OS password lock always works** and is never touched — you can always log back in normally. Keep this TTY plan in mind for every step below.

**(A) Recognition sanity — no lock authority (`facelock test`, services may be stopped):**

1. Run `facelock status` (guardian running) — expect a JSON snapshot with `no_owner:false`, `face_unlock:true`. Validates the control path (REQ-F-25 plumbing, REQ-NF-24).
2. Run `facelock test --seconds 5` and read the output line-by-line:
   - "frames … fps …" with **fps ≥ 5** → validates **REQ-F-05** (camera acquires at fps) and **REQ-NF-01**.
   - "faces/frame ≈ 1.0" while you face the camera → validates **REQ-F-06** (detection).
   - "per-frame detect+embed: mean/p95 … (budget ≤200 ms)" with **p95 ≤ 200 ms** → validates **REQ-NF-02**.
   - "best score … vs tau … → OWNER" for your face → validates **REQ-F-07** and gives a live read on **REQ-NF-10** (score comfortably ≥ τ≈0.363).
3. Hold a **printed photo of yourself** to the camera during `facelock test` — expect it may still read OWNER (documented: prototype is photo-spoofable with `liveness.mode=off`). Confirms the **REQ-F-17** disclosure is accurate (this is expected, not a bug).

**(B) Sit → unlock / away → lock:**

4. Start both services: `systemctl --user start facelock-guardian facelockd`. Expect the shield to appear (locked) within ~1 s. Sit in front of the camera. **Expected:** within the latency budget the shield shows "Checking authorization" then drops to your desktop with a green **"Welcome back, Yash"** splash that auto-dismisses in ≤3 s. Validates **REQ-F-12, REQ-F-14, REQ-F-15, REQ-NF-02, REQ-NF-17** (greeting).
5. Stay seated and still for ~60 s. **Expected:** the screen does **not** lock while you remain present. Validates **REQ-F-09**.
6. Walk out of frame and start a timer. **Expected:** the screen locks (shield up, monitor blanks) within **dwell + 2 s** (default dwell 30 s → ≤32 s). Validates **REQ-F-10, REQ-NF-03**.
7. Return to frame. **Expected:** monitor wakes, "Checking authorization", unlock + greeting. Re-validates **REQ-F-12/14** and the reliable re-lock/re-unlock cycle.

**(C) Stranger / no-face:**

8. While unlocked and seated, have a colleague stand **behind you (you still in frame)**. **Expected (lenient):** **no lock** — a co-present colleague must not nuisance-lock. Validates **REQ-NF-18**.
9. Have the colleague take your seat **alone** (you out of frame) for >3 s. **Expected:** shield raises with a red "Unauthorized user" and locks within ~2 s; it does **not** unlock for them. Validates **REQ-F-11, REQ-F-16, REQ-NF-04**.
10. With the shield up, have **two faces** (you + colleague) both in frame. **Expected:** it does **not** unlock while >1 face is present; unlock only completes once you are the sole face. Validates **REQ-F-08**.
11. Cover the lens / close a privacy shutter while unlocked and step away. **Expected:** treated as no-face → locks; never unlocks on a dark frame. Validates **REQ-NF-22** (fail-closed, FM-09).

**(D) Pause / resume (video calls):**

12. Run `facelock pause --minutes 30`. **Expected:** "Perception paused; camera released. Auto-resumes in 30 min"; `facelock status` shows `perception_paused:true` and a `pause_resume_in_s` countdown; the camera is free for Zoom/Meet and the current lock state is held (fail-closed). Validates the pause path.
13. Run `facelock resume`. **Expected:** "Perception resumed; camera reacquired"; status `perception_paused:false`. (Or let the 30-min timer auto-resume.)

**(E) Panic / disable / enable:**

14. Run `facelock lock`. **Expected:** immediate lock — the **real OS password lock** engages (monitor stays lit) and only the password clears it. Validates **REQ-F-25** (panic) and **REQ-F-13** (verified OS-lock engage).
15. Run `facelock disable`, then sit in front of the camera. **Expected:** **no** face-unlock; the OS password is required; "Face-unlock disabled — use OS password". Validates **REQ-F-25** (disable) + password-fallback preserved.
16. Run `facelock enable`. **Expected:** face-unlock resumes on the next return. Validates **REQ-F-25** (enable).
17. Deliberately fail recognition 5× (e.g., partially obscure your face across attempts). **Expected:** after `max_fail_attempts` a cool-down engages and the **password remains available** (no lockout). Validates **REQ-F-25** (cooldown, no self-DoS).

**(F) Crash / watchdog & restart safety:**

18. While the session is **locked and you are away**, kill the daemon: `systemctl --user kill -s KILL facelockd` (or `kill -9` its PID). **Expected:** the guardian's watchdog trips within ~3× heartbeat, **keeps the shield up, and escalates to the real OS password lock** — it does **not** auto-unlock. Validates **REQ-F-26, REQ-NF-22, REQ-NF-23**.
19. Confirm `Restart=always` recovery: `systemctl --user status facelockd` should show it restarted; the session remains locked until a live owner verification (or password) succeeds. Validates **REQ-F-26/REQ-NF-23** (auto-restart, lock-state preserved).
20. Kill the **guardian** instead: `systemctl --user kill -s KILL facelock-guardian`. **Expected:** it restarts and comes up **LOCKED** (shield); no window of auto-unlock. Validates **REQ-NF-22/23**.
21. Press **Escape** on the shield at any lock. **Expected:** the shield drops to the **OS password screen** and your password logs you in — confirming the password path is always reachable (Safety Invariant). Re-validates **REQ-F-16**.

**Resource & privacy observation (run alongside B–F):**

22. During an idle-away period, watch `pidstat -p $(pgrep -f facelockd) 5` — **idle CPU ≤ ~15% of one core** (REQ-NF-06); during an unlock burst, **sustained CPU ≤ ~1 core** (REQ-NF-07); watch `systemctl --user status` / `ps` RSS — **≤ 500 MB** (REQ-NF-08, cgroup-capped).
23. Observe the **webcam LED**: lit while `facelockd` holds the camera, off after a long-absence release or `facelock pause`. Validates **REQ-F-27 / REQ-NF-16** (indicator = hardware LED). Optionally run a network monitor (e.g. `ss -tunp` / `nettop`) and confirm **zero outbound connections** from facelock (REQ-NF-12).

---

## Post-Audit Actions (2026-07-30)

Actions taken by the maintainer after reviewing this audit (verifying each finding before acting):

1. **REQ-F-18 / NF-12 / NF-13 promoted CODE-ONLY → CODE+TEST.** Added
   `tests/test_security_contract.py` (5 source-scanning regression guards): no
   `import pam` anywhere (F-18); no network-client imports and no `AF_INET`
   sockets, only `AF_UNIX` for the local control IPC (NF-12); no `cv2.imwrite`
   and no PIL image-save path (NF-13). Suite now **226 passing**. Ground truth
   confirmed before writing the tests: zero network calls and zero raw-frame
   writes in `facelock/` (the only `store.save()` calls persist the 128-D
   template, not images).

2. **REQ-NF-17 enrollment timeout — reviewed, NOT changed.** `enroll.py:186`
   `timeout_s=240.0` is a hard *ceiling* for the whole interactive multi-pose
   capture, not the expected completion time; the ≤2 min AC is a *SHOULD*
   usability target. Tightening the ceiling to 120 s would cause spurious
   enrollment failures for slower users — a net regression. Left as-is pending an
   explicit product decision.

3. **REQ-F-27 / NF-16 `privacy.camera_indicator` dead flag — acknowledged, open.**
   Confirmed defined at `config.py:228` with no consumer. In the prototype the
   in-use indicator is the hardware UVC LED (adequate for P). A software
   tray/indicator that reads this flag is deferred to Hardening (needs an X11
   tray); tracked as a known gap rather than silently leaving a live-looking
   config knob.

4. **The 4 GAPs (REQ-F-20 PAM, F-21 privileged helper, F-24 OS-auth unlock,
   NF-11 PAD) remain intentionally deferred to the Hardening phase** — they are
   out of the prototype's screensaver-only contract by design, not defects.
