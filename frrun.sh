#!/bin/bash
#=====================================================================
# frrun.sh - entrypoint of the Forms container (frfmw).
#
# One `docker compose up -d` lands a running Forms server. Idempotent; on
# every start it:
#   1. Builds the WebLogic domain with crDomain.sh if it doesn't exist
#      (first start only, slow: RCU schemas + domain + OHS).
#   2. Starts NodeManager and AdminServer.
#   3. Adds the OHS routing of /forms to WLS_FORMS, which a fresh domain
#      lacks.
#   4. Starts WLS_FORMS (the Forms managed server), adds a [test] config
#      section for Oracle's test.fmx that the Forms Standalone Launcher can
#      open, and starts OHS.
#   5. Stays in the foreground while AdminServer is up.
#
# Applications (forms, config sections) are deployed separately, for
# example by forms-vaadin-hybrid-demo's deploy scripts.
#=====================================================================
set -u

DOMAIN_HOME=/opt/oracle/user_projects/domains/${DOMAIN_NAME:-FRDEMO}
BIN=$DOMAIN_HOME/bin
FMW=$DOMAIN_HOME/config/fmwconfig
OHS_CONF=$FMW/components/OHS/instances/${OHS_COMPONENTNAME:-ohs1}/moduleconf
APP=$FMW/servers/${FORMS_MS_NAME:-WLS_FORMS}/applications/formsapp_12.2.1/config
DB_HOST=${DB_HOST:-frdb}
DB_PORT=${DB_PORT:-1521}
# NodeManager binds to the container hostname (NM_LISTENADDRESS), not localhost.
NM_HOST=${NM_LISTENADDRESS:-$(hostname)}

log(){ echo "[frrun $(date '+%H:%M:%S')] $*"; }

# is_up <port> [host]: TCP connect test
is_up(){ timeout 2 bash -c "cat < /dev/null > /dev/tcp/${2:-localhost}/$1" 2>/dev/null; }

# wait_up <port> <label> <max_secs> [host]
wait_up(){
  local port=$1 label=$2 max=${3:-300} host=${4:-localhost} i=0
  while ! is_up "$port" "$host"; do
    i=$((i+5)); [ "$i" -ge "$max" ] && { log "TIMEOUT waiting for $label (:$port)"; return 1; }
    sleep 5
  done
  log "$label is up (:$port)"
}

#---------------------------------------------------------------------
# 1) Build the domain on first start. RCU needs the database, so wait
#    for it (compose also waits for its health check).
#---------------------------------------------------------------------
if [ ! -d "$DOMAIN_HOME" ]; then
  log "Waiting for database $DB_HOST:$DB_PORT..."
  wait_up "$DB_PORT" "database" 600 "$DB_HOST" || exit 1
  log "Domain not found - building it with crDomain.sh (first start only, slow)..."
  /opt/oracle/dockertools/crDomain.sh
fi

#---------------------------------------------------------------------
# 1b) A container that was killed instead of stopped cleanly leaves OHS's
#     httpd.pid behind. Before starting, OHS runs "httpd -k stop", which
#     signals that PID; in the new container it often belongs to
#     NodeManager, which dies and takes the OHS start with it. Remove the
#     file unless it points at a running httpd.
#---------------------------------------------------------------------
PIDFILE=$DOMAIN_HOME/servers/${OHS_COMPONENTNAME:-ohs1}/logs/httpd.pid
if [ -f "$PIDFILE" ] && ! ps -p "$(cat "$PIDFILE")" -o comm= 2>/dev/null | grep -q httpd; then
  rm -f "$PIDFILE"
  log "Removed stale $PIDFILE"
fi

#---------------------------------------------------------------------
# 2) NodeManager + AdminServer
#---------------------------------------------------------------------
if ! is_up 5556 "$NM_HOST"; then
  log "Starting NodeManager..."
  nohup "$BIN/startNodeManager.sh" >/tmp/nm.out 2>&1 &
  wait_up 5556 "NodeManager" 120 "$NM_HOST" || true
fi
if ! is_up 7001; then
  log "Starting AdminServer..."
  nohup "$DOMAIN_HOME/startWebLogic.sh" >/tmp/admin.out 2>&1 &
  wait_up 7001 "AdminServer" 300
fi

#---------------------------------------------------------------------
# 3) Runtime configuration (idempotent)
#---------------------------------------------------------------------
# 3a) OHS: route /forms to the Forms managed server. Without it, :7777
#     answers 404 for every Forms URL.
if [ ! -f "$OHS_CONF/forms.conf" ]; then
  cat > "$OHS_CONF/forms.conf" <<EOF
# Route Oracle Forms requests to the WLS_FORMS managed server.
<Location /forms>
    SetHandler weblogic-handler
    WebLogicHost localhost
    WebLogicPort ${FORMS12C_MS_PORT:-9001}
    DynamicServerList OFF
</Location>
EOF
  log "OHS: wrote moduleconf/forms.conf"
  OHS_RESTART=1   # crDomain.sh may already have started OHS without it
fi

#---------------------------------------------------------------------
# 4) WLS_FORMS managed server + OHS
#---------------------------------------------------------------------
if ! is_up "${FORMS12C_MS_PORT:-9001}"; then
  log "Starting ${FORMS_MS_NAME:-WLS_FORMS} managed server..."
  nohup "$BIN/startManagedWebLogic.sh" "${FORMS_MS_NAME:-WLS_FORMS}" >/tmp/wls_forms.out 2>&1 &
  wait_up "${FORMS12C_MS_PORT:-9001}" "${FORMS_MS_NAME:-WLS_FORMS}" 300 || true
fi
# 4b) [test] config: Oracle's test.fmx, openable by the Forms Standalone
#     Launcher, which needs baseSAAfile (FRM-93136 without it). formsweb.cfg
#     only exists once WLS_FORMS has started for the first time.
if [ -f "$APP/formsweb.cfg" ] && ! grep -q '^\[test\]' "$APP/formsweb.cfg"; then
  cat >> "$APP/formsweb.cfg" <<'EOF'

[test]
form=test.fmx
webstart=enabled
basejnlp=base.jnlp
baseSAAfile=basesaa.txt
separateFrame=true
EOF
  log "cfg: added [test] section to formsweb.cfg"
fi

if [ "${OHS_RESTART:-0}" = 1 ] && is_up "${OHS_LISTENPORT:-7777}"; then
  log "Restarting OHS to load forms.conf..."
  echo "${NM_PWD}" | "$BIN/stopComponent.sh" "${OHS_COMPONENTNAME:-ohs1}" >/tmp/ohs-stop.out 2>&1 || true
fi
if ! is_up "${OHS_LISTENPORT:-7777}"; then
  log "Starting OHS (${OHS_COMPONENTNAME:-ohs1})..."
  # startComponent.sh prompts for the NodeManager password, and there is no
  # TTY under compose: feed NM_PWD on stdin. storeUserConfig saves it, so
  # later starts don't prompt.
  echo "${NM_PWD}" | "$BIN/startComponent.sh" "${OHS_COMPONENTNAME:-ohs1}" storeUserConfig >/tmp/ohs.out 2>&1 \
    || log "WARN: OHS start reported an error (see /tmp/ohs.out)"
  wait_up "${OHS_LISTENPORT:-7777}" "OHS" 300 || true
fi

log "Startup complete. Test form: http://localhost:${OHS_LISTENPORT:-7777}/forms/frmservlet?config=test"

#---------------------------------------------------------------------
# 5) Keep the container alive while AdminServer is up.
#---------------------------------------------------------------------
while is_up 7001; do sleep 30; done
log "AdminServer is no longer reachable - exiting so Docker can react."
