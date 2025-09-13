# Reliable migration to user‑session PipeWire under `mediabridge` (headless)

## Summary
Migrate all audio to a standard user‑session PipeWire stack running under the `mediabridge` user, replacing system‑mode services and ad‑hoc `/run/pipewire` workarounds. This issue consolidates learnings from #133 and #136 into a concrete, verifiable plan that works on headless appliances without pulling in a full desktop, with a minimal, explicit fallback only if strictly necessary.

## Context
- Prior attempt (#133) implemented user mode with bind‑mounts and environment overrides; it introduced dbus/session and service ordering problems, plus fragile scripts that depended on system services being present.
- Findings in #136 show why user sessions failed in a fully headless setup (dbus deadlocks, circular deps, missing session manager), and propose a desktop‑based workaround.
- Our goal is to make user‑session PipeWire reliable on a headless system using the supported systemd user model, only considering a minimal desktop fallback if truly unavoidable.

## Goals
- PipeWire, PipeWire‑Pulse, and WirePlumber run as `mediabridge` user units (systemd --user).
- Project services (intercom, ndi‑display, ndi‑capture) run as `mediabridge` user units; no XDG overrides to `/run/pipewire`.
- WirePlumber policies enforce Chrome isolation; virtual devices `intercom-speaker` and `intercom-microphone` exist and are default.
- HDMI audio output remains functional for display; all tests pass on hardware.

## Non‑Goals
- No full desktop environment; no long‑term `/run/pipewire` bind‑mount hacks.
- Do not reintroduce root‑mode audio.

---

## Target Architecture (headless user session)
- User: `mediabridge` with UID ≥ 1000; groups: `audio,video,render,input` (+ others as needed).
- Lingering enabled: `loginctl enable-linger mediabridge` so user services start at boot.
- `dbus-user-session` installed; systemd user instance owns the environment (sets `XDG_RUNTIME_DIR=/run/user/<uid>`).
- Services:
  - `pipewire.service`, `pipewire-pulse.service`, `wireplumber.service` — enabled under user.
  - Project units (intercom/display/capture) — enabled under user; depend on PipeWire user units.
- Config:
  - WirePlumber isolation config placed under `$XDG_CONFIG_HOME/wireplumber/*.conf.d` for `mediabridge`.
  - Virtual devices created by WP scripts/config at user scope.

---

## Implementation Plan

### Phase 0 — Preflight and Detection
- Detect and disable any `pipewire-system*` / `wireplumber-system*` services.
- Remove `/run/pipewire` env overrides and socket bind‑mount logic from scripts.
- Verify presence of `dbus-user-session` and `systemd --user` availability.

Checklist
- [ ] `systemctl disable --now pipewire-system.service pipewire-pulse-system.service wireplumber-system.service` (ignore if absent)
- [ ] Remove exports of `XDG_RUNTIME_DIR=/run/pipewire`, `PIPEWIRE_RUNTIME_DIR`, `PULSE_RUNTIME_PATH` in helper scripts
- [ ] Replace `PULSE_SERVER=unix:/run/pipewire/pulse/native` with `PULSE_SERVER=unix:${XDG_RUNTIME_DIR}/pulse/native` or omit entirely

### Phase 1 — User, Groups, Limits
- Ensure user exists with desktop‑style UID: `useradd -m -u 1001 -G audio,video,render,input mediabridge` (idempotent in migration script).
- Limits in `/etc/security/limits.d/99-mediabridge-limits.conf`: `rtprio 95`, `nice -19`, `memlock unlimited` (already present; verify).

Checklist
- [ ] `id mediabridge` shows UID ≥ 1000 and correct groups
- [ ] Limits file exists and is effective (verify with `ulimit -r` under the user service)

### Phase 2 — User Session Bootstrap
- `apt-get install -y dbus-user-session`.
- `loginctl enable-linger mediabridge`.
- Verify session: `sudo -u mediabridge systemctl --user is-active default.target` and `loginctl user-status mediabridge`.

Checklist
- [ ] `/run/user/<uid>` exists after boot
- [ ] `systemctl --user` usable under `sudo -u mediabridge`

### Phase 3 — PipeWire as User Units
- Enable under mediabridge: `sudo -u mediabridge systemctl --user enable --now pipewire pipewire-pulse wireplumber`.
- Ensure no system units remain enabled; sockets resolve to `/run/user/<uid>/pulse/native`.

Checklist
- [ ] `sudo -u mediabridge wpctl status` works
- [ ] `sudo -u mediabridge pactl info` shows `Server String: unix:/run/user/<uid>/pulse/native`

### Phase 4 — WirePlumber Policies + Virtual Devices
- Move `scripts/helper-scripts/50-chrome-isolation.conf` → `/var/lib/mediabridge/.config/wireplumber/50-chrome-isolation.conf` (or `wireplumber.conf.d/` as required by WP 0.5).
- Define virtual sink/source (`intercom-speaker`, `intercom-microphone`) via WP config or PipeWire modules in user scope.
- Reload WirePlumber.

Checklist
- [ ] `pactl list sinks|sources` shows `intercom-speaker` and `intercom-microphone`
- [ ] Chrome sees only virtual devices (policy enforced)

### Phase 5 — Convert Project Services to User Units
- Move system service `media-bridge-intercom.service` to a user unit in `/etc/systemd/user/media-bridge-intercom.service`:

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

- Do NOT set `XDG_RUNTIME_DIR` manually in user units; systemd user session provides it.
- Repeat for `ndi-display@.service` and `ndi-capture.service` as applicable (user units, After/Wants on PipeWire services if they use audio).
- Enable: `sudo -u mediabridge systemctl --user enable --now media-bridge-intercom`.

Checklist
- [ ] `sudo -u mediabridge systemctl --user status media-bridge-intercom` active
- [ ] No system unit with `User=mediabridge` remains for these services

### Phase 6 — Migration Script (Idempotent)
Create `/usr/local/bin/migrate-pipewire-user.sh` that:
1. Detects current mode (system vs user).
2. Creates/updates `mediabridge` user, groups, limits, lingering.
3. Installs user WP configs and virtual devices.
4. Disables system PipeWire/WP units; enables user PipeWire/WP units.
5. Moves project services to user units and enables them.
6. Validates sockets and devices; outputs a summary.
7. Supports `--rollback` to re‑enable previous system units if required.

### Phase 7 — Tests & Verification
- Update tests to execute user checks:
  - `sudo -u mediabridge systemctl --user is-active pipewire`
  - `sudo -u mediabridge wpctl status`
  - `sudo -u mediabridge pactl info` and device enumeration
- Intercom E2E: Chrome connects, `intercom-*` devices as default, audio round‑trip.
- HDMI audio present for `ndi-display`.

Acceptance
- [ ] All audio/intercom tests pass on target hardware
- [ ] Reboot persistence confirmed
- [ ] No references to `/run/pipewire` remain in scripts/services

### Phase 8 — Fallback (Only if Headless Session Fails)
- If user session cannot be made reliable on a specific image, implement a minimal fallback from #136:
  - Install only the minimal components required to satisfy systemd user/dbus assumptions (avoid full desktop), or enable tty1 autologin for `mediabridge` to seed the session.
  - Ensure no GUI daemons remain active. Document clearly and gate behind a build flag.

---

## Changes Required in Repo (high‑signal list)
- `scripts/helper-scripts/media-bridge-intercom.service`: convert to user unit; drop runtime env overrides.
- `scripts/helper-scripts/media-bridge-intercom-pipewire`: remove system‑service checks (`pipewire-system.service`), rely on user session; drop `/run/pipewire` exports; prefer `$XDG_RUNTIME_DIR`.
- `scripts/helper-scripts/50-chrome-isolation.conf`: relocate under mediabridge’s `$XDG_CONFIG_HOME/wireplumber/` and validate syntax for WirePlumber 0.5.
- Ensure `99-mediabridge-limits.conf` remains and is effective.
- Add `migrate-pipewire-user.sh` with rollback.
- Update docs: `docs/PIPEWIRE.md`, `docs/INTERCOM.md` to reflect user‑session architecture.

## Debugging & Validation Commands
```bash
# Session & units
loginctl user-status mediabridge
sudo -u mediabridge systemctl --user status pipewire wireplumber pipewire-pulse

# Audio state
sudo -u mediabridge wpctl status
sudo -u mediabridge pactl info
sudo -u mediabridge pactl list sinks short
sudo -u mediabridge pactl list sources short

# Device visibility from Chrome (should show only intercom-*)
# Validate via app logs and test suite
```

## Risk Management
- Circular deps: All project services `After/Wants` user PipeWire units; no calls to `systemctl` from ExecStartPost.
- Permissions: verify group membership grants `/dev/snd`/`/dev/dri` access; add udev rules if needed.
- Reboot readiness: rely on lingering user session; avoid bind‑mounts.
- Rollback path provided.

## Deliverables
- Migration script + converted units/configs.
- Updated tests and docs.
- Final report with test logs demonstrating 100% pass on hardware.

