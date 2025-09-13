# Reliable migration to user‑session PipeWire under `mediabridge` (headless)

## Summary
Migrate all audio to a standard user‑session PipeWire stack running under the `mediabridge` user, replacing system‑mode services and ad‑hoc `/run/pipewire` workarounds. This issue consolidates lessons from the failed attempt in #133 and the unverified redesign proposal in #136 into a concrete, testable plan with explicit validation gates and rollback.

## Critical context (must read)
- #133 is a failed attempt. Do not reuse its system‑mode assumptions, bind‑mounts to `/run/pipewire`, or ExecStartPost calls to `systemctl`. Treat that implementation as non‑functional and a source of anti‑patterns to remove.
- #136 describes a desktop‑based workaround that is not verified. Treat it strictly as a fallback experiment behind a build flag, only after the headless user‑session approach is proven infeasible on target images.

## Goals (headless, standard user session)
- PipeWire, PipeWire‑Pulse, and WirePlumber run as `mediabridge` user units (systemd `--user`).
- Project audio services (intercom, ndi‑display, ndi‑capture) run as `mediabridge` user units; no overrides to `XDG_RUNTIME_DIR=/run/pipewire`.
- WirePlumber policies enforce Chrome isolation; virtual devices `intercom-speaker` and `intercom-microphone` exist and are default for the browser.
- HDMI audio output remains functional; all tests pass on hardware; changes persist across reboots.

## Non‑Goals
- No full desktop environment by default. No permanent bind‑mount hacks. Do not reintroduce root‑mode audio.

---

## Target Architecture (headless user session)
- User: `mediabridge` with UID ≥ 1000; groups: `audio,video,render,input` (+ others as needed).
- Lingering enabled: `loginctl enable-linger mediabridge` (starts user units at boot without login).
- `dbus-user-session` installed to support systemd user instances on a headless system.
- Services (enabled under user): `pipewire.service`, `pipewire-pulse.service`, `wireplumber.service`.
- Project user units: intercom/display/capture depend on the above and inherit correct env (`XDG_RUNTIME_DIR=/run/user/<uid>`).
- WirePlumber configs under `$XDG_CONFIG_HOME/wireplumber/*.conf.d` for `mediabridge` (Chrome isolation, virtual devices).

---

## Implementation Plan (with validation gates)

### Phase 0 — Preflight cleanup (BLOCKER for proceeding)
- Disable/remove any `pipewire-system*` / `wireplumber-system*` units.
- Remove `/run/pipewire` env exports and socket bind‑mount logic from helper scripts.
- Ensure `dbus-user-session` installed.

Gate 0 (must pass):
- `systemctl is-enabled pipewire-system.service` → disabled/not found.
- Grep shows no references to `/run/pipewire` in project services/scripts.

### Phase 1 — User, groups, limits
- Ensure `mediabridge` exists with UID ≥ 1000 and groups `audio,video,render,input`.
- Keep limits in `/etc/security/limits.d/99-mediabridge-limits.conf` (rtprio 95, nice -19, memlock unlimited).

Gate 1:
- `id mediabridge` shows correct UID/groups.
- Under a simple user service, `ulimit -r` = 95 and memlock unlimited.

### Phase 2 — Headless user session bootstrap
- `loginctl enable-linger mediabridge`.
- Verify `/run/user/<uid>` exists at boot; systemd user bus is available.

Gate 2:
- `sudo -u mediabridge systemctl --user is-active default.target` → active.
- `loginctl user-status mediabridge` shows a session, even headless.

### Phase 3 — PipeWire/WirePlumber as user units
- `sudo -u mediabridge systemctl --user enable --now pipewire pipewire-pulse wireplumber`.
- Confirm sockets resolve to `/run/user/<uid>/pulse/native`.

Gate 3:
- `sudo -u mediabridge wpctl status` works.
- `sudo -u mediabridge pactl info` shows `unix:/run/user/<uid>/pulse/native`.

### Phase 4 — WirePlumber policies + virtual devices
- Move `50-chrome-isolation.conf` into `$XDG_CONFIG_HOME/wireplumber/*.conf.d`.
- Define virtual devices (`intercom-speaker`, `intercom-microphone`) via WP config/modules under the user.

Gate 4:
- `pactl list sinks|sources` shows both virtual devices.
- Chrome only sees virtual devices (policy enforced).

### Phase 5 — Convert project audio services to user units
- Place `media-bridge-intercom.service` in `/etc/systemd/user/`:

```ini
[Unit]
Description=Media Bridge Intercom (user)
Wants=pipewire.service pipewire-pulse.service wireplumber.service
After=pipewire.service pipewire-pulse.service wireplumber.service

[Service]
Environment=VDO_ROOM=nl_interkom
ExecStart=/usr/local/bin/media-bridge-intercom-launcher
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
```

- Repeat where applicable for `ndi-display@.service` and `ndi-capture.service`.
- Do NOT export `XDG_RUNTIME_DIR`; rely on user session.

Gate 5:
- `sudo -u mediabridge systemctl --user status media-bridge-intercom` active; no system units with `User=` remain.

### Phase 6 — Migration script (idempotent, with rollback)
`/usr/local/bin/migrate-pipewire-user.sh` should:
1) Detect current mode.
2) Create/update user, groups, limits, lingering.
3) Install user WP configs + virtual devices.
4) Disable system PipeWire/WP; enable user PipeWire/WP.
5) Move project services to user units and enable them.
6) Validate (Gates 0–5); print a summary.
7) `--rollback` to restore prior state.

Gate 6:
- Re-running script is safe (no duplication); rollback returns to pre‑migration state.

### Phase 7 — Tests & verification (hardware)
- Add/adjust tests to assert user‑mode facts using `sudo -u mediabridge`:
  - `systemctl --user is-active pipewire`/`wireplumber`.
  - `wpctl status`, `pactl info`, and `pactl list sinks/sources`.
- Intercom E2E (Chrome, virtual devices, audio round‑trip).
- HDMI audio for `ndi-display`.

Gate 7 (exit criteria):
- All audio/intercom tests pass on hardware; reboot persistence proven.
- No `/run/pipewire` references remain. No ExecStartPost calls to `systemctl`.

### Phase 8 — Fallback experiment (only if headless fails)
- If gates fail due to upstream assumptions, add a guarded fallback build option:
  - Minimal session components (not full desktop) or tty1 autologin for `mediabridge`, to seed a stable user session.
  - Disable GUI daemons; document clearly. Only enable when headless user session is proven infeasible.

Gate F (fallback only):
- Same checks as Gates 0–7 must pass with the fallback; otherwise, revert.

---

## Repo changes required (high‑signal)
- Convert `media-bridge-intercom.service` (and any audio‑using units) to `/etc/systemd/user/` and enable via `--user`.
- Remove checks for `pipewire-system.service` from `media-bridge-intercom-pipewire` and drop `/run/pipewire` env exports; rely on `$XDG_RUNTIME_DIR`.
- Relocate `50-chrome-isolation.conf` to `~mediabridge/.config/wireplumber/` and validate syntax for WirePlumber 0.5.
- Keep `99-mediabridge-limits.conf`; verify effectiveness.
- Add `migrate-pipewire-user.sh` with `--rollback`.
- Update docs: `docs/PIPEWIRE.md`, `docs/INTERCOM.md` to reflect user‑session architecture.

## Observability & logs
- Enable debug for early iterations: `SYSTEMD_LOG_LEVEL=debug` on user units (temporary), WP verbose logs, `pw-dump` snapshots.
- Collect journald for `pipewire`, `wireplumber`, and project user units around boot and service restarts.

## Risk management
- DBus/session: Rely on systemd user instance + lingering; avoid `systemctl` in ExecStartPost.
- Permissions: Confirm access to `/dev/snd` and `/dev/dri` via groups; add udev rules if needed.
- Regression: Gate each phase; provide rollback.

## Deliverables
- Migration script + converted units/configs.
- Updated tests and docs.
- Final report with logs demonstrating Gate 0–7 success on hardware.

