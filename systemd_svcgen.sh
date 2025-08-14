#!/bin/bash
set -euo pipefail
VERSION="1.0.0"
PROG="${0##*/}"
usage() {
  cat <<EOF
${PROG} — generate a systemd service for a script/binary, enable it, and start it.

Usage:
  ${PROG} [options]

Required (if omitted, you'll be prompted interactively):
  -n, --name NAME              Unit name (without .service)
  -e, --exec PATH              Executable/script path (e.g., /home/jaden/actions-runner/run.sh)

Common:
  -d, --description TEXT       Description for the service
  -a, --args "ARG STRING"      Arguments passed to the executable
  -u, --user USER              Run as this user (default: SUDO_USER or current user)
  -w, --workdir DIR            WorkingDirectory (default: dirname of --exec)
      --env-file PATH          EnvironmentFile=PATH (optional)
      --restart MODE           always|on-failure|no (default: always)
      --restart-sec SEC        Seconds between restarts (default: 5)
      --after TARGETS          After= (default: network-online.target)
      --wants TARGETS          Wants= (default: network-online.target)
      --wantedby TARGET        WantedBy= (default: multi-user.target)
      --no-start               Do not start now (still enables at boot)

Info:
  -h, --help                   Show this help and exit
  -V, --version                Show version and exit

Example:
  ${PROG} \\
    --name gha-runner \\
    --description "GitHub Actions Runner" \\
    --exec /home/user/actions-runner/run.sh \\
    --user jaden \\
    --workdir /home/jaden/actions-runner

Effect:
  Writes /etc/systemd/system/NAME.service, daemon-reload, enable, and start (unless --no-start).
  View logs with: journalctl -u NAME.service -f
EOF
}
# --- defaults ---
NAME=""
DESC=""
EXEC=""
ARGS=""
RUN_AS="${SUDO_USER:-$(whoami)}"
WORKDIR=""
ENVFILE=""
RESTART="always"
RESTART_SEC="5"
AFTER="network-online.target"
WANTS="network-online.target"
WANTEDBY="multi-user.target"
AUTO_START=1
# --- args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    -V|--version) printf "%s %s\n" "$PROG" "$VERSION"; exit 0;;
    -n|--name)        NAME="$2"; shift 2;;
    -d|--description) DESC="$2"; shift 2;;
    -e|--exec)        EXEC="$2"; shift 2;;
    -a|--args)        ARGS="$2"; shift 2;;
    -u|--user)        RUN_AS="$2"; shift 2;;
    -w|--workdir)     WORKDIR="$2"; shift 2;;
    --env-file)       ENVFILE="$2"; shift 2;;
    --restart)        RESTART="$2"; shift 2;;
    --restart-sec)    RESTART_SEC="$2"; shift 2;;
    --after)          AFTER="$2"; shift 2;;
    --wants)          WANTS="$2"; shift 2;;
    --wantedby)       WANTEDBY="$2"; shift 2;;
    --no-start)       AUTO_START=0; shift 1;;
    *) echo "Unknown arg: $1"; echo; usage; exit 1;;
  esac
done
# --- interactive prompts if missing ---
read -rp "Service name [${NAME:-gha-runner}]: " _in; NAME="${_in:-${NAME:-gha-runner}}"
read -rp "Description [${DESC:-$NAME}]: " _in; DESC="${_in:-${DESC:-$NAME}}"
read -rp "Path to executable/script [${EXEC:-/path/to/run.sh}]: " _in; EXEC="${_in:-$EXEC}"
[[ -x "${EXEC}" ]] || chmod +x "${EXEC}" 2>/dev/null || true
read -rp "Args (optional) [${ARGS:-}]: " _in; ARGS="${_in:-$ARGS}"
read -rp "Run as user [${RUN_AS}]: " _in; RUN_AS="${_in:-$RUN_AS}"
if [[ -z "${WORKDIR}" ]]; then
  DEF_WD="$(cd "$(dirname "${EXEC:-.}")" 2>/dev/null && pwd || echo /)"
  read -rp "WorkingDirectory [${DEF_WD}]: " _in; WORKDIR="${_in:-$DEF_WD}"
fi
if [[ -z "${ENVFILE}" ]]; then
  read -rp "EnvironmentFile (optional) [/etc/${NAME}.env or blank]: " _in; ENVFILE="${_in:-}"
fi

# --- compose unit ---
SERVICE_PATH="/etc/systemd/system/${NAME}.service"
GROUP="$(id -gn "${RUN_AS}" 2>/dev/null || echo "${RUN_AS}")"

# Use bash -lc so profile paths (nvm/pyenv/etc.) are available
START_CMD="/usr/bin/env bash -lc '\"${EXEC}\" ${ARGS}'"

UNIT=$(cat <<EOF
[Unit]
Description=${DESC}
After=${AFTER}
Wants=${WANTS}

[Service]
Type=simple
User=${RUN_AS}
Group=${GROUP}
WorkingDirectory=${WORKDIR}
ExecStart=${START_CMD}
Restart=${RESTART}
RestartSec=${RESTART_SEC}
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${NAME}

[Install]

EOF
)

if [[ -n "${ENVFILE}" ]]; then
  UNIT="${UNIT}"$'\n'"EnvironmentFile=-${ENVFILE}"
fi

UNIT="${UNIT}"$'\n\n'"[Install]
WantedBy=${WANTEDBY}
"

# --- write, reload, enable ---
SUDO=""; [[ $EUID -ne 0 ]] && SUDO="sudo"
echo "Writing ${SERVICE_PATH} ..."
printf "%s" "${UNIT}" | ${SUDO} tee "${SERVICE_PATH}" >/dev/null
${SUDO} systemctl daemon-reload
${SUDO} systemctl enable "${NAME}.service"
if [[ ${AUTO_START} -eq 1 ]]; then
  ${SUDO} systemctl restart "${NAME}.service"
  ${SUDO} systemctl --no-pager --full status "${NAME}.service" || true
  echo "Logs: journalctl -u ${NAME}.service -f"
else
  echo "Created and enabled. Start with: sudo systemctl start ${NAME}.service"
fi
