#!/usr/bin/env bash
set -euo pipefail

SSH_PORT="10022"
SOURCE_USER="alma"
SOURCE_AUTH_KEYS="/home/${SOURCE_USER}/.ssh/authorized_keys"
LOGIN_DEFS="/etc/login.defs"
WEB_HOME_MODE="0711"
SKEL_DIR="/etc/skel"
SKEL_SSH_DIR="${SKEL_DIR}/.ssh"
SKEL_AUTH_KEYS="${SKEL_SSH_DIR}/authorized_keys"
SKEL_LOGS_DIR="${SKEL_DIR}/logs"
SKEL_HTTPD_LOG_DIR="${SKEL_LOGS_DIR}/httpd"
SKEL_PHP_LOG_DIR="${SKEL_LOGS_DIR}/php"
SKEL_HTTPD_ACCESS_LOG="${SKEL_HTTPD_LOG_DIR}/access.log"
SKEL_HTTPD_ERROR_LOG="${SKEL_HTTPD_LOG_DIR}/error.log"
SKEL_PHP_ERROR_LOG="${SKEL_PHP_LOG_DIR}/error.log"
ROOT_SSH_DIR="/root/.ssh"
ROOT_AUTH_KEYS="${ROOT_SSH_DIR}/authorized_keys"
SSHD_DROPIN="/etc/ssh/sshd_config.d/90-startup-root-login.conf"
WEBMIN_PORT="10001"
WEBMIN_USER="${SOURCE_USER}"
WEBMIN_REPO_SCRIPT_URL="https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh"
WEBMIN_REPO_SCRIPT="/tmp/webmin-setup-repo.sh"
WEBMIN_CONFIG_DIR="/etc/webmin"
WEBMIN_MINISERV_CONF="${WEBMIN_CONFIG_DIR}/miniserv.conf"
WEBMIN_USERS_FILE="${WEBMIN_CONFIG_DIR}/miniserv.users"
WEBMIN_ACL_FILE="${WEBMIN_CONFIG_DIR}/webmin.acl"
WEBMIN_LOGIN_FAILURES="5"
WEBMIN_LOCK_SECONDS="900"
POSTFIX_MYHOSTNAME="${POSTFIX_MYHOSTNAME:-}"
SWAPFILE_PATH="/swapfile"
SWAP_MIN_GIB="2"
SWAPPINESS="10"
SWAP_SYSCTL_CONF="/etc/sysctl.d/90-startup-swap.conf"
HTTPD_DEFAULT_DOCROOT="/var/www/html"
HTTPD_MAIN_CONF="/etc/httpd/conf/httpd.conf"
HTTPD_SECURITY_CONF="/etc/httpd/conf.d/00-security-and-tuning.conf"
HTTPD_MODSSL_CONF="/etc/httpd/conf.d/ssl.conf"
HTTPD_AUTOINDEX_CONF="/etc/httpd/conf.d/autoindex.conf"
HTTPD_WELCOME_CONF="/etc/httpd/conf.d/welcome.conf"
HTTPD_USERDIR_CONF="/etc/httpd/conf.d/userdir.conf"
HTTPD_SSL_CONF="/etc/httpd/conf.d/01-ssl-hardening.conf"
HTTPD_VHOSTS_DIR="/etc/httpd/vhosts.d"
HTTPD_VHOSTS_INCLUDE_CONF="/etc/httpd/conf.d/10-vhosts-include.conf"
HTTPD_VHOST_TEMPLATE="${HTTPD_VHOSTS_DIR}/00-template.conf"
HTTPD_PHP_FPM_CONF="/etc/httpd/conf.d/20-php-fpm.conf"
PHP_FPM_POOL_CONF="/etc/php-fpm.d/www.conf"
PHP_TUNING_INI="/etc/php.d/99-startup-tuning.ini"
MARIADB_TUNING_CONF="/etc/my.cnf.d/90-server-tuning.cnf"
APP_ROOT="/opt/apps"
NODE_MAJOR="24"
NODE_SERVICE_TEMPLATE="/etc/systemd/system/app-template-node.service.example"
PYTHON_SERVICE_TEMPLATE="/etc/systemd/system/app-template-python.service.example"
APP_APACHE_PROXY_TEMPLATE="${HTTPD_VHOSTS_DIR}/10-app-proxy-template.conf"
CERTBOT_RELOAD_HOOK="/etc/letsencrypt/renewal-hooks/deploy/reload-httpd.sh"
JOURNALD_RETENTION_CONF="/etc/systemd/journald.conf.d/90-startup-retention.conf"
FAIL2BAN_LOCAL_CONF="/etc/fail2ban/fail2ban.local"
FAIL2BAN_JAIL_LOCAL="/etc/fail2ban/jail.d/90-startup.local"
AUDIT_STARTUP_RULES="/etc/audit/rules.d/90-startup-security.rules"
AIDE_CONF="/etc/aide.conf"
AIDE_CHECK_SERVICE="/etc/systemd/system/aide-check.service"
AIDE_CHECK_TIMER="/etc/systemd/system/aide-check.timer"
LOGWATCH_SYSTEMD_CONF="/etc/logwatch/conf/systemd.conf"
LOGROTATE_RSYSLOG_CONF="/etc/logrotate.d/rsyslog"
LOGROTATE_HTTPD_CONF="/etc/logrotate.d/httpd"
LOGROTATE_PHP_FPM_CONF="/etc/logrotate.d/php-fpm"
LOGROTATE_WEBMIN_CONF="/etc/logrotate.d/webmin"
LOGROTATE_FAIL2BAN_CONF="/etc/logrotate.d/fail2ban"
LOGROTATE_AIDE_CONF="/etc/logrotate.d/aide"
LOGROTATE_MARIADB_SLOW_CONF="/etc/logrotate.d/mariadb-slow"
LOGROTATE_WTMP_CONF="/etc/logrotate.d/wtmp"
LOGROTATE_BTMP_CONF="/etc/logrotate.d/btmp"
HTTPD_USER_LOG_PERMS_HELPER="/usr/local/sbin/fix-user-httpd-log-perms"

COMMON_BASE_PACKAGES=(
  acl
  audit
  bind-utils
  bzip2
  ca-certificates
  chrony
  curl
  dnf-plugins-core
  firewalld
  git
  gzip
  iproute
  iputils
  jq
  less
  logrotate
  lsof
  nano
  net-tools
  openssh-clients
  openssl
  policycoreutils-python-utils
  rsync
  rsyslog
  strace
  tar
  tcpdump
  traceroute
  unzip
  vim-minimal
  wget
  which
  xz
  zip
)

REQUIRED_FIREWALL_PORTS=(
  "${SSH_PORT}/tcp"
  "${WEBMIN_PORT}/tcp"
  "80/tcp"
  "443/tcp"
)

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

set_config_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp

  tmp="$(mktemp)"
  awk -v key="${key}" -v value="${value}" '
    BEGIN { updated = 0 }
    $0 ~ "^[[:space:]]*" key "=" {
      print key "=" value
      updated = 1
      next
    }
    { print }
    END {
      if (!updated) {
        print key "=" value
      }
    }
  ' "${file}" > "${tmp}"
  install -m 600 -o root -g root "${tmp}" "${file}"
  rm -f "${tmp}"
}

ensure_webmin_unix_user() {
  local tmp

  if [[ ! -f "${WEBMIN_USERS_FILE}" ]]; then
    echo "ERROR: ${WEBMIN_USERS_FILE} が見つかりません。" >&2
    exit 1
  fi

  tmp="$(mktemp)"
  if grep -q "^${WEBMIN_USER}:" "${WEBMIN_USERS_FILE}"; then
    cp -a "${WEBMIN_USERS_FILE}" "${tmp}"
  else
    cp -a "${WEBMIN_USERS_FILE}" "${tmp}"
    printf '%s:x::::::::::::\n' "${WEBMIN_USER}" >> "${tmp}"
  fi
  install -m 600 -o root -g root "${tmp}" "${WEBMIN_USERS_FILE}"
  rm -f "${tmp}"
}

ensure_webmin_admin_acl() {
  local source_acl
  local tmp

  if [[ ! -f "${WEBMIN_ACL_FILE}" ]]; then
    echo "ERROR: ${WEBMIN_ACL_FILE} が見つかりません。" >&2
    exit 1
  fi

  source_acl="$(
    awk -F: '$1 == "root" || $1 == "admin" {
      sub(/^[^:]*:/, "")
      print
      exit
    }' "${WEBMIN_ACL_FILE}"
  )"

  if [[ -z "${source_acl}" ]]; then
    echo "ERROR: root/admin の Webmin ACL を取得できません。" >&2
    exit 1
  fi

  tmp="$(mktemp)"
  awk -F: -v user="${WEBMIN_USER}" -v acl="${source_acl}" '
    BEGIN { updated = 0 }
    $1 == user {
      print user ":" acl
      updated = 1
      next
    }
    { print }
    END {
      if (!updated) {
        print user ":" acl
      }
    }
  ' "${WEBMIN_ACL_FILE}" > "${tmp}"
  install -m 600 -o root -g root "${tmp}" "${WEBMIN_ACL_FILE}"
  rm -f "${tmp}"
}

open_firewall_port() {
  local port_proto="$1"

  if ! command -v firewall-cmd >/dev/null 2>&1; then
    dnf install -y firewalld
  fi

  if ! firewall-cmd --state >/dev/null 2>&1; then
    firewall-offline-cmd --add-port="${port_proto}" >/dev/null 2>&1 || true
    systemctl enable --now firewalld
  else
    systemctl enable firewalld
  fi

  firewall-cmd --permanent --add-port="${port_proto}"
  firewall-cmd --add-port="${port_proto}" >/dev/null 2>&1 || true
}

ensure_required_firewall_ports() {
  local port_proto

  for port_proto in "${REQUIRED_FIREWALL_PORTS[@]}"; do
    open_firewall_port "${port_proto}"
  done

  firewall-cmd --reload
}

close_default_ssh_firewall_access() {
  if ! firewall-cmd --state >/dev/null 2>&1; then
    return 0
  fi

  firewall-cmd --permanent --remove-service=ssh >/dev/null 2>&1 || true
  firewall-cmd --remove-service=ssh >/dev/null 2>&1 || true
  firewall-cmd --permanent --remove-service=cockpit >/dev/null 2>&1 || true
  firewall-cmd --remove-service=cockpit >/dev/null 2>&1 || true
  firewall-cmd --permanent --remove-port=22/tcp >/dev/null 2>&1 || true
  firewall-cmd --remove-port=22/tcp >/dev/null 2>&1 || true
  firewall-cmd --reload
}

run_initial_system_update() {
  local rc

  dnf makecache -y

  set +e
  dnf check-update
  rc=$?
  set -e

  if (( rc == 100 )); then
    dnf update -y
  elif (( rc != 0 )); then
    return "${rc}"
  fi
}

install_common_base_packages() {
  dnf install -y "${COMMON_BASE_PACKAGES[@]}"
}

detect_postfix_myhostname() {
  local detected

  if [[ -n "${POSTFIX_MYHOSTNAME}" ]]; then
    echo "${POSTFIX_MYHOSTNAME}"
    return 0
  fi

  detected="$(hostname -f 2>/dev/null || true)"
  if [[ -z "${detected}" || "${detected}" == "(none)" ]]; then
    detected="$(hostname 2>/dev/null || true)"
  fi

  if [[ -z "${detected}" || "${detected}" == "(none)" ]]; then
    echo "ERROR: Postfix の myhostname を自動判定できません。" >&2
    exit 1
  fi

  if [[ "${detected}" != *.* ]]; then
    echo "WARNING: Postfix myhostname '${detected}' はFQDNではありません。必要に応じてホスト名を設定してください。" >&2
  fi

  echo "${detected}"
}

print_reboot_notice() {
  local output rc

  if command -v needs-restarting >/dev/null 2>&1; then
    set +e
    output="$(needs-restarting -r 2>&1)"
    rc=$?
    set -e
  else
    set +e
    output="$(dnf needs-restarting -r 2>&1)"
    rc=$?
    set -e

    if (( rc != 0 )) && grep -Eqi 'no such command|unknown command|argument.*invalid' <<<"${output}"; then
      return 0
    fi
  fi

  if (( rc != 0 )); then
    echo "WARNING: OS更新後の再起動が必要な可能性があります。"
    printf '%s\n' "${output}"
  fi
}

calculate_swap_size_gib() {
  local mem_kb mem_gib swap_gib

  mem_kb="$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)"
  mem_gib="$(((mem_kb + 1048576 - 1) / 1048576))"
  swap_gib="$((mem_gib * 2))"

  if (( swap_gib < SWAP_MIN_GIB )); then
    swap_gib="${SWAP_MIN_GIB}"
  fi

  echo "${swap_gib}"
}

setup_swapfile() {
  local swap_gib desired_size_bytes current_size_bytes tmp

  swap_gib="$(calculate_swap_size_gib)"
  desired_size_bytes="$((swap_gib * 1024 * 1024 * 1024))"

  if [[ -f "${SWAPFILE_PATH}" ]]; then
    current_size_bytes="$(stat -c '%s' "${SWAPFILE_PATH}")"
    if (( current_size_bytes != desired_size_bytes )); then
      if swapon --show=NAME --noheadings | grep -qx "${SWAPFILE_PATH}"; then
        swapoff "${SWAPFILE_PATH}"
      fi
      rm -f "${SWAPFILE_PATH}"
    fi
  fi

  if [[ ! -f "${SWAPFILE_PATH}" ]]; then
    install -m 600 -o root -g root /dev/null "${SWAPFILE_PATH}"
    if ! fallocate -l "${swap_gib}G" "${SWAPFILE_PATH}"; then
      dd if=/dev/zero of="${SWAPFILE_PATH}" bs=1M count="$((swap_gib * 1024))" status=progress
    fi
    chmod 600 "${SWAPFILE_PATH}"
    mkswap "${SWAPFILE_PATH}"
  fi

  if ! swapon --show=NAME --noheadings | grep -qx "${SWAPFILE_PATH}"; then
    swapon "${SWAPFILE_PATH}"
  fi

  tmp="$(mktemp)"
  awk -v path="${SWAPFILE_PATH}" '
    BEGIN { updated = 0 }
    $1 == path && $3 == "swap" {
      if (!updated) {
        print path " none swap defaults 0 0"
        updated = 1
      }
      next
    }
    { print }
    END {
      if (!updated) {
        print path " none swap defaults 0 0"
      }
    }
  ' /etc/fstab > "${tmp}"
  install -m 644 -o root -g root "${tmp}" /etc/fstab
  rm -f "${tmp}"

  cat > "${SWAP_SYSCTL_CONF}" <<EOF
# Managed by startup_script.sh
vm.swappiness = ${SWAPPINESS}
EOF
  chmod 644 "${SWAP_SYSCTL_CONF}"
  chown root:root "${SWAP_SYSCTL_CONF}"
  sysctl -w "vm.swappiness=${SWAPPINESS}"
}

set_login_defs_home_mode() {
  local tmp mode owner group

  tmp="$(mktemp)"
  mode="$(stat -c '%a' "${LOGIN_DEFS}")"
  owner="$(stat -c '%u' "${LOGIN_DEFS}")"
  group="$(stat -c '%g' "${LOGIN_DEFS}")"

  awk -v value="${WEB_HOME_MODE}" '
    BEGIN { updated = 0 }
    /^[[:space:]]*HOME_MODE[[:space:]]+/ {
      if (!updated) {
        print "HOME_MODE\t\t" value
        updated = 1
      }
      next
    }
    { print }
    END {
      if (!updated) {
        print "HOME_MODE\t\t" value
      }
    }
  ' "${LOGIN_DEFS}" > "${tmp}"

  install -m "${mode}" -o "${owner}" -g "${group}" "${tmp}" "${LOGIN_DEFS}"
  rm -f "${tmp}"
}

set_apache_home_acl() {
  local home_dir="$1"

  if command -v setfacl >/dev/null 2>&1; then
    setfacl -m u:apache:--x "${home_dir}" || chmod o+x "${home_dir}"
  else
    chmod o+x "${home_dir}"
  fi
}

setup_default_user_skel() {
  set_login_defs_home_mode

  install -d -m 700 -o root -g root "${SKEL_SSH_DIR}"
  install -m 600 -o root -g root "${SOURCE_AUTH_KEYS}" "${SKEL_AUTH_KEYS}"

  install -d -m 755 -o root -g root "${SKEL_LOGS_DIR}"
  install -d -m 755 -o root -g root "${SKEL_HTTPD_LOG_DIR}" "${SKEL_PHP_LOG_DIR}"
  install -m 666 -o root -g root /dev/null "${SKEL_HTTPD_ACCESS_LOG}"
  install -m 666 -o root -g root /dev/null "${SKEL_HTTPD_ERROR_LOG}"
  install -m 666 -o root -g root /dev/null "${SKEL_PHP_ERROR_LOG}"

  restorecon -RFv "${SKEL_SSH_DIR}" "${SKEL_LOGS_DIR}" >/dev/null 2>&1 || true
}

ensure_web_home_access() {
  local home_dir

  set_login_defs_home_mode

  if ! id apache >/dev/null 2>&1; then
    return 0
  fi

  shopt -s nullglob
  for home_dir in /home/*; do
    [[ -d "${home_dir}" ]] || continue
    set_apache_home_acl "${home_dir}"
  done
}

calculate_stack_tuning() {
  local mem_kb mem_mb cpu_cores php_budget_mb

  mem_kb="$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)"
  mem_mb="$((mem_kb / 1024))"
  cpu_cores="$(nproc)"

  DB_BUFFER_POOL_MB="$((mem_mb * 30 / 100))"
  if (( DB_BUFFER_POOL_MB < 384 )); then
    DB_BUFFER_POOL_MB=384
  elif (( DB_BUFFER_POOL_MB > 8192 )); then
    DB_BUFFER_POOL_MB=8192
  fi

  DB_LOG_FILE_MB="$((DB_BUFFER_POOL_MB / 4))"
  if (( DB_LOG_FILE_MB < 128 )); then
    DB_LOG_FILE_MB=128
  elif (( DB_LOG_FILE_MB > 1024 )); then
    DB_LOG_FILE_MB=1024
  fi

  if (( mem_mb < 2048 )); then
    PHP_MEMORY_LIMIT_MB=192
    PHP_CHILD_ESTIMATE_MB=128
    PHP_TMP_TABLE_MB=32
  else
    PHP_MEMORY_LIMIT_MB=256
    PHP_CHILD_ESTIMATE_MB=160
    PHP_TMP_TABLE_MB=64
  fi

  php_budget_mb="$((mem_mb * 35 / 100))"
  PHP_PM_MAX_CHILDREN="$((php_budget_mb / PHP_CHILD_ESTIMATE_MB))"
  if (( PHP_PM_MAX_CHILDREN < 4 )); then
    PHP_PM_MAX_CHILDREN=4
  elif (( PHP_PM_MAX_CHILDREN > 80 )); then
    PHP_PM_MAX_CHILDREN=80
  fi

  PHP_PM_START_SERVERS="${cpu_cores}"
  if (( PHP_PM_START_SERVERS < 2 )); then
    PHP_PM_START_SERVERS=2
  elif (( PHP_PM_START_SERVERS > PHP_PM_MAX_CHILDREN )); then
    PHP_PM_START_SERVERS="${PHP_PM_MAX_CHILDREN}"
  fi

  PHP_PM_MIN_SPARE="$((PHP_PM_START_SERVERS / 2))"
  if (( PHP_PM_MIN_SPARE < 2 )); then
    PHP_PM_MIN_SPARE=2
  elif (( PHP_PM_MIN_SPARE > PHP_PM_MAX_CHILDREN )); then
    PHP_PM_MIN_SPARE="${PHP_PM_MAX_CHILDREN}"
  fi

  PHP_PM_MAX_SPARE="$((PHP_PM_START_SERVERS * 2))"
  if (( PHP_PM_MAX_SPARE < PHP_PM_MIN_SPARE )); then
    PHP_PM_MAX_SPARE="${PHP_PM_MIN_SPARE}"
  elif (( PHP_PM_MAX_SPARE > PHP_PM_MAX_CHILDREN )); then
    PHP_PM_MAX_SPARE="${PHP_PM_MAX_CHILDREN}"
  fi

  HTTPD_MAX_REQUEST_WORKERS="$((PHP_PM_MAX_CHILDREN * 4))"
  if (( HTTPD_MAX_REQUEST_WORKERS < 75 )); then
    HTTPD_MAX_REQUEST_WORKERS=75
  elif (( HTTPD_MAX_REQUEST_WORKERS > 300 )); then
    HTTPD_MAX_REQUEST_WORKERS=300
  fi

  DB_MAX_CONNECTIONS="$((PHP_PM_MAX_CHILDREN + 40))"
  if (( DB_MAX_CONNECTIONS < 60 )); then
    DB_MAX_CONNECTIONS=60
  elif (( DB_MAX_CONNECTIONS > 200 )); then
    DB_MAX_CONNECTIONS=200
  fi

  DB_THREAD_CACHE_SIZE="${DB_MAX_CONNECTIONS}"
  if (( DB_THREAD_CACHE_SIZE > 64 )); then
    DB_THREAD_CACHE_SIZE=64
  fi

  if (( mem_mb < 4096 )); then
    OPCACHE_MEMORY_MB=96
  elif (( mem_mb < 8192 )); then
    OPCACHE_MEMORY_MB=128
  else
    OPCACHE_MEMORY_MB=192
  fi
}

write_systemd_resilience_dropin() {
  local service_name="$1"
  local oom_score_adjust="$2"
  local extra_directive="${3:-}"
  local dropin_dir="/etc/systemd/system/${service_name}.d"

  install -d -m 755 -o root -g root "${dropin_dir}"
  cat > "${dropin_dir}/10-startup-resilience.conf" <<EOF
# Managed by startup_script.sh
[Service]
Restart=on-failure
RestartSec=5s
OOMScoreAdjust=${oom_score_adjust}
EOF
  if [[ -n "${extra_directive}" ]]; then
    printf '%s\n' "${extra_directive}" >> "${dropin_dir}/10-startup-resilience.conf"
  fi
  chmod 644 "${dropin_dir}/10-startup-resilience.conf"
  chown root:root "${dropin_dir}/10-startup-resilience.conf"
}

ensure_httpd_selinux_for_home_vhosts() {
  if ! command -v selinuxenabled >/dev/null 2>&1 || ! selinuxenabled; then
    return 0
  fi

  if ! command -v semanage >/dev/null 2>&1; then
    dnf install -y policycoreutils-python-utils
  fi

  setsebool -P httpd_enable_homedirs on
  setsebool -P httpd_can_network_connect on
  semanage fcontext -a -t httpd_sys_content_t '/home/[^/]+/public_html(/.*)?' \
    || semanage fcontext -m -t httpd_sys_content_t '/home/[^/]+/public_html(/.*)?'
  semanage fcontext -a -t httpd_log_t '/home/[^/]+/logs/httpd(/.*)?' \
    || semanage fcontext -m -t httpd_log_t '/home/[^/]+/logs/httpd(/.*)?'
  semanage fcontext -a -t httpd_log_t '/home/[^/]+/logs/php(/.*)?' \
    || semanage fcontext -m -t httpd_log_t '/home/[^/]+/logs/php(/.*)?'
  restorecon -RFv /home/*/public_html >/dev/null 2>&1 || true
  restorecon -RFv /home/*/logs/httpd /home/*/logs/php >/dev/null 2>&1 || true
}

write_apache_common_config() {
  calculate_stack_tuning

  install -d -m 755 -o root -g root "${HTTPD_VHOSTS_DIR}"
  install -d -m 755 -o root -g root "${HTTPD_DEFAULT_DOCROOT}"
  install -m 644 -o root -g root /dev/null "${HTTPD_DEFAULT_DOCROOT}/index.html"

  cat > "${HTTPD_SECURITY_CONF}" <<EOF
# Managed by startup_script.sh

ServerName localhost
ServerSignature Off
ServerTokens Prod
TraceEnable Off
FileETag None
HttpProtocolOptions Strict RegisteredMethods
LimitRequestBody 67108864
LimitRequestFields 64
LimitRequestLine 8190
MaxRanges 5
MaxRangeOverlaps none
MaxRangeReversals none

Timeout 60
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5

<IfModule mpm_event_module>
    StartServers 2
    MinSpareThreads 25
    MaxSpareThreads 75
    ThreadsPerChild 25
    MaxRequestWorkers ${HTTPD_MAX_REQUEST_WORKERS}
    MaxConnectionsPerChild 10000
</IfModule>

<IfModule reqtimeout_module>
    RequestReadTimeout header=20-40,MinRate=500 body=20,MinRate=500
</IfModule>

<IfModule headers_module>
    RequestHeader unset Proxy early
    Header always unset X-Powered-By
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    Header always set Permissions-Policy "geolocation=(), microphone=(), camera=()"
</IfModule>

<Directory />
    AllowOverride None
    Require all denied
</Directory>

<Directory "/var/www/html">
    Options -Indexes +FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

<DirectoryMatch "/(\.git|\.svn|\.hg|\.bzr|\.vscode)(/|$)">
    Require all denied
</DirectoryMatch>

<FilesMatch "^(\.ht|\.user\.ini|\.env|composer\.(json|lock)|package(-lock)?\.json|yarn\.lock|.*\.(?:bak|config|dist|fla|inc|ini|log|orig|psd|sh|sql|swp))$">
    Require all denied
</FilesMatch>

<LocationMatch "^/\.well-known/acme-challenge/">
    Require all granted
</LocationMatch>

SetEnvIfNoCase Request_URI "\.(?:avif|bmp|css|eot|gif|ico|jpe?g|js|map|mp4|ogg|otf|pdf|png|svg|ttf|webm|webp|woff2?)(?:\?.*)?$" dontlog_static

<IfModule deflate_module>
    AddOutputFilterByType DEFLATE text/plain text/html text/css text/xml text/javascript application/javascript application/json application/xml application/rss+xml image/svg+xml
    DeflateCompressionLevel 5
    SetEnvIfNoCase Request_URI "\.(?:gif|jpe?g|png|webp|avif|zip|gz|bz2|xz|7z|rar|mp4|mov|pdf)$" no-gzip
    <IfModule headers_module>
        Header append Vary Accept-Encoding env=!dont-vary
    </IfModule>
</IfModule>
EOF

  cat > "${HTTPD_PHP_FPM_CONF}" <<'EOF'
# Managed by startup_script.sh
DirectoryIndex index.php index.html

<IfModule proxy_fcgi_module>
    <FilesMatch "\.php$">
        SetHandler "proxy:unix:/run/php-fpm/www.sock|fcgi://localhost/"
    </FilesMatch>
</IfModule>
EOF

  cat > "${HTTPD_SSL_CONF}" <<'EOF'
# Managed by startup_script.sh
<IfModule ssl_module>
    SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite PROFILE=SYSTEM
    SSLProxyCipherSuite PROFILE=SYSTEM
    SSLHonorCipherOrder on
    SSLCompression off
    SSLSessionTickets off
    SSLUseStapling on
    SSLStaplingCache "shmcb:/run/httpd/ssl_stapling(32768)"
</IfModule>
EOF

  cat > "${HTTPD_AUTOINDEX_CONF}" <<'EOF'
# Managed by startup_script.sh
# Disabled intentionally.
# Directory indexes and the packaged /icons/ alias are not used.
EOF

  cat > "${HTTPD_WELCOME_CONF}" <<'EOF'
# Managed by startup_script.sh
# Disabled intentionally.
# The packaged welcome/noindex page and related aliases are not used.
EOF

  cat > "${HTTPD_USERDIR_CONF}" <<'EOF'
# Managed by startup_script.sh
# Disabled intentionally.
# Per-user public_html hosting is handled by explicit vHost definitions.
<IfModule mod_userdir.c>
    UserDir disabled
</IfModule>
EOF

  cat > "${HTTPD_VHOSTS_INCLUDE_CONF}" <<'EOF'
# Managed by startup_script.sh
IncludeOptional /etc/httpd/vhosts.d/*.conf
EOF

  cat > "${HTTPD_VHOST_TEMPLATE}" <<'EOF'
# Managed by startup_script.sh
# Copy this file to another .conf file, uncomment it, and replace example values.
# Let's Encrypt certificate paths are expected after issuing the certificate.
#
# <VirtualHost *:80>
#     ServerName example.com
#     ServerAlias www.example.com
#     DocumentRoot /home/example/public_html
#     # Prepare logs before enabling:
#     # install -d -m 750 -o example -g apache /home/example/logs/httpd /home/example/logs/php
#     # touch /home/example/logs/httpd/access.log /home/example/logs/httpd/error.log /home/example/logs/php/error.log
#     # chown example:apache /home/example/logs/httpd/*.log /home/example/logs/php/*.log
#     # chmod 664 /home/example/logs/httpd/*.log /home/example/logs/php/*.log
#
#     <Directory /home/example/public_html>
#         Options -Indexes +FollowSymLinks
#         AllowOverride FileInfo AuthConfig Limit
#         Require all granted
#     </Directory>
#
#     RewriteEngine On
#     RewriteCond %{REQUEST_URI} !^/\.well-known/acme-challenge/
#     RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L,NE]
#
#     ErrorLog /home/example/logs/httpd/error.log
#     CustomLog /home/example/logs/httpd/access.log combined env=!dontlog_static
# </VirtualHost>
#
# <IfModule ssl_module>
# <VirtualHost *:443>
#     ServerName example.com
#     ServerAlias www.example.com
#     DocumentRoot /home/example/public_html
#     ProxyFCGISetEnvIf "true" PHP_VALUE "error_log=/home/example/logs/php/error.log"
#
#     <Directory /home/example/public_html>
#         Options -Indexes +FollowSymLinks
#         AllowOverride FileInfo AuthConfig Limit
#         Require all granted
#     </Directory>
#
#     SSLEngine on
#     SSLCertificateFile /etc/letsencrypt/live/example.com/fullchain.pem
#     SSLCertificateKeyFile /etc/letsencrypt/live/example.com/privkey.pem
#     IncludeOptional /etc/letsencrypt/options-ssl-apache.conf
#
#     <IfModule http2_module>
#         Protocols h2 http/1.1
#     </IfModule>
#
#     Header always set Strict-Transport-Security "max-age=15552000"
#
#     ErrorLog /home/example/logs/httpd/error.log
#     CustomLog /home/example/logs/httpd/access.log combined env=!dontlog_static
# </VirtualHost>
# </IfModule>
EOF

  chmod 644 "${HTTPD_SECURITY_CONF}" "${HTTPD_PHP_FPM_CONF}" "${HTTPD_SSL_CONF}" \
    "${HTTPD_AUTOINDEX_CONF}" "${HTTPD_WELCOME_CONF}" "${HTTPD_USERDIR_CONF}" \
    "${HTTPD_VHOSTS_INCLUDE_CONF}" "${HTTPD_VHOST_TEMPLATE}"
  chown root:root "${HTTPD_SECURITY_CONF}" "${HTTPD_PHP_FPM_CONF}" "${HTTPD_SSL_CONF}" \
    "${HTTPD_AUTOINDEX_CONF}" "${HTTPD_WELCOME_CONF}" "${HTTPD_USERDIR_CONF}" \
    "${HTTPD_VHOSTS_INCLUDE_CONF}" "${HTTPD_VHOST_TEMPLATE}"
}

ensure_default_ssl_certificate() {
  if [[ -s /etc/pki/tls/certs/localhost.crt && -s /etc/pki/tls/private/localhost.key ]]; then
    return 0
  fi

  install -d -m 755 -o root -g root /etc/pki/tls/certs
  install -d -m 700 -o root -g root /etc/pki/tls/private
  openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 3650 \
    -subj "/CN=localhost" \
    -keyout /etc/pki/tls/private/localhost.key \
    -out /etc/pki/tls/certs/localhost.crt
  chmod 600 /etc/pki/tls/private/localhost.key
  chmod 644 /etc/pki/tls/certs/localhost.crt
  chown root:root /etc/pki/tls/private/localhost.key /etc/pki/tls/certs/localhost.crt
}

write_php_fpm_config() {
  calculate_stack_tuning

  install -d -m 755 -o root -g root /var/log/php-fpm
  install -m 664 -o root -g apache /dev/null /var/log/php-fpm/www-error.log
  install -m 664 -o root -g apache /dev/null /var/log/php-fpm/www-slow.log

  cat > "${PHP_FPM_POOL_CONF}" <<EOF
; Managed by startup_script.sh
[www]
user = apache
group = apache

listen = /run/php-fpm/www.sock
listen.owner = apache
listen.group = apache
listen.mode = 0660

pm = dynamic
pm.max_children = ${PHP_PM_MAX_CHILDREN}
pm.start_servers = ${PHP_PM_START_SERVERS}
pm.min_spare_servers = ${PHP_PM_MIN_SPARE}
pm.max_spare_servers = ${PHP_PM_MAX_SPARE}
pm.max_requests = 500
pm.status_path = /fpm-status
ping.path = /fpm-ping

request_terminate_timeout = 120s
request_slowlog_timeout = 10s
slowlog = /var/log/php-fpm/www-slow.log
catch_workers_output = yes
decorate_workers_output = no

php_admin_flag[log_errors] = on
php_value[error_log] = /var/log/php-fpm/www-error.log
php_admin_value[memory_limit] = ${PHP_MEMORY_LIMIT_MB}M
EOF

  cat > "${PHP_TUNING_INI}" <<EOF
; Managed by startup_script.sh
expose_php = Off
memory_limit = ${PHP_MEMORY_LIMIT_MB}M
max_execution_time = 60
max_input_time = 60
max_input_vars = 3000
post_max_size = 64M
upload_max_filesize = 64M
max_file_uploads = 20
realpath_cache_size = 4096K
realpath_cache_ttl = 600

session.cookie_httponly = 1
session.cookie_samesite = Lax

opcache.enable = 1
opcache.enable_cli = 0
opcache.memory_consumption = ${OPCACHE_MEMORY_MB}
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 20000
opcache.validate_timestamps = 1
opcache.revalidate_freq = 2
opcache.save_comments = 1
opcache.jit = 0
opcache.jit_buffer_size = 0
EOF

  chmod 644 "${PHP_FPM_POOL_CONF}" "${PHP_TUNING_INI}"
  chown root:root "${PHP_FPM_POOL_CONF}" "${PHP_TUNING_INI}"
}

write_mariadb_tuning_config() {
  calculate_stack_tuning

  cat > "${MARIADB_TUNING_CONF}" <<EOF
# Managed by startup_script.sh
[mariadb]
bind-address=127.0.0.1
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci

skip_name_resolve=ON
max_connections=${DB_MAX_CONNECTIONS}
thread_cache_size=${DB_THREAD_CACHE_SIZE}
table_open_cache=2000
table_definition_cache=1000
max_allowed_packet=64M
tmp_table_size=${PHP_TMP_TABLE_MB}M
max_heap_table_size=${PHP_TMP_TABLE_MB}M
sort_buffer_size=2M
join_buffer_size=1M
read_buffer_size=256K
read_rnd_buffer_size=512K

innodb_file_per_table=ON
innodb_buffer_pool_size=${DB_BUFFER_POOL_MB}M
innodb_log_file_size=${DB_LOG_FILE_MB}M
innodb_log_buffer_size=64M
innodb_flush_method=O_DIRECT
innodb_flush_log_at_trx_commit=1
innodb_read_io_threads=4
innodb_write_io_threads=4
innodb_io_capacity=1000
innodb_io_capacity_max=2000
innodb_flush_neighbors=0
innodb_undo_log_truncate=ON

aria_pagecache_buffer_size=64M

slow_query_log=ON
slow_query_log_file=/var/log/mariadb/slow.log
long_query_time=2
EOF

  chmod 644 "${MARIADB_TUNING_CONF}"
  chown root:root "${MARIADB_TUNING_CONF}"
}

secure_mariadb_initial_state() {
  if mariadb -uroot -NBe "SHOW TABLES FROM mysql LIKE 'global_priv'" | grep -qx "global_priv"; then
    mariadb -uroot <<'SQL'
DELETE FROM mysql.global_priv WHERE User='';
DELETE FROM mysql.global_priv WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db LIKE 'test\_%';
FLUSH PRIVILEGES;
SQL
  else
    mariadb -uroot <<'SQL'
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db LIKE 'test\_%';
FLUSH PRIVILEGES;
SQL
  fi
}

setup_mta_stack() {
  local postfix_myhostname

  postfix_myhostname="$(detect_postfix_myhostname)"

  dnf install -y postfix s-nail

  systemctl disable --now exim >/dev/null 2>&1 || true

  if [[ -x /usr/sbin/sendmail.postfix ]]; then
    alternatives --set mta /usr/sbin/sendmail.postfix >/dev/null 2>&1 || true
  fi

  postconf -e "myhostname = ${postfix_myhostname}"
  postconf -e 'myorigin = $myhostname'
  postconf -e 'mydestination = $myhostname, localhost.$mydomain, localhost'
  postconf -e 'relayhost ='
  postconf -e 'inet_interfaces = loopback-only'
  postconf -e 'inet_protocols = ipv4'
  postconf -e 'mynetworks = 127.0.0.0/8'
  postconf -e 'smtpd_relay_restrictions = permit_mynetworks, reject_unauth_destination'
  postconf -e 'disable_vrfy_command = yes'
  postconf -e 'smtp_tls_security_level = may'
  postconf -e 'smtp_address_preference = ipv4'
  postconf -e 'alias_maps = lmdb:/etc/aliases'
  postconf -e 'alias_database = lmdb:/etc/aliases'

  newaliases
  postfix check

  systemctl enable --now postfix
  systemctl restart postfix
}

write_node_python_templates() {
  install -d -m 755 -o root -g root "${APP_ROOT}"

  cat > "${NODE_SERVICE_TEMPLATE}" <<'EOF'
# Managed by startup_script.sh
# Copy to /etc/systemd/system/<app>.service and replace example values.
[Unit]
Description=Node.js application example
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=example
Group=example
WorkingDirectory=/opt/apps/example/current
Environment=NODE_ENV=production
Environment=PORT=3000
EnvironmentFile=-/etc/sysconfig/example
ExecStart=/usr/local/bin/node /opt/apps/example/current/server.js
Restart=on-failure
RestartSec=5s
OOMScoreAdjust=150

[Install]
WantedBy=multi-user.target
EOF

  cat > "${PYTHON_SERVICE_TEMPLATE}" <<'EOF'
# Managed by startup_script.sh
# Copy to /etc/systemd/system/<app>.service and replace example values.
[Unit]
Description=Python application example
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=example
Group=example
WorkingDirectory=/opt/apps/example/current
Environment=PYTHONUNBUFFERED=1
EnvironmentFile=-/etc/sysconfig/example
ExecStart=/opt/apps/example/venv/bin/gunicorn --bind 127.0.0.1:8000 app:app
Restart=on-failure
RestartSec=5s
OOMScoreAdjust=150

[Install]
WantedBy=multi-user.target
EOF

  cat > "${APP_APACHE_PROXY_TEMPLATE}" <<'EOF'
# Managed by startup_script.sh
# Copy this file to another .conf file, uncomment it, and replace example values.
#
# <VirtualHost *:80>
#     ServerName app.example.com
#     # Prepare logs before enabling:
#     # install -d -m 750 -o example -g apache /home/example/logs/httpd
#     # touch /home/example/logs/httpd/access.log /home/example/logs/httpd/error.log
#     # chown example:apache /home/example/logs/httpd/*.log
#     # chmod 664 /home/example/logs/httpd/*.log
#
#     RewriteEngine On
#     RewriteCond %{REQUEST_URI} !^/\.well-known/acme-challenge/
#     RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L,NE]
#
#     ErrorLog /home/example/logs/httpd/error.log
#     CustomLog /home/example/logs/httpd/access.log combined env=!dontlog_static
# </VirtualHost>
#
# <IfModule ssl_module>
# <VirtualHost *:443>
#     ServerName app.example.com
#
#     SSLEngine on
#     SSLCertificateFile /etc/letsencrypt/live/app.example.com/fullchain.pem
#     SSLCertificateKeyFile /etc/letsencrypt/live/app.example.com/privkey.pem
#     IncludeOptional /etc/letsencrypt/options-ssl-apache.conf
#
#     ProxyPreserveHost On
#     ProxyPass / http://127.0.0.1:3000/
#     ProxyPassReverse / http://127.0.0.1:3000/
#
#     <IfModule http2_module>
#         Protocols h2 http/1.1
#     </IfModule>
#
#     Header always set Strict-Transport-Security "max-age=15552000"
#
#     ErrorLog /home/example/logs/httpd/error.log
#     CustomLog /home/example/logs/httpd/access.log combined env=!dontlog_static
# </VirtualHost>
# </IfModule>
EOF

  chmod 644 "${NODE_SERVICE_TEMPLATE}" "${PYTHON_SERVICE_TEMPLATE}" "${APP_APACHE_PROXY_TEMPLATE}"
  chown root:root "${NODE_SERVICE_TEMPLATE}" "${PYTHON_SERVICE_TEMPLATE}" "${APP_APACHE_PROXY_TEMPLATE}"
}

setup_node_python_stack() {
  install -d -m 755 -o root -g root /usr/local/bin

  ln -sf /usr/bin/node-${NODE_MAJOR} /usr/local/bin/node
  ln -sf /usr/bin/npm-${NODE_MAJOR} /usr/local/bin/npm
  ln -sf /usr/bin/npx-${NODE_MAJOR} /usr/local/bin/npx

  /usr/bin/npm-${NODE_MAJOR} install -g n

  if /usr/local/bin/node -v >/dev/null 2>&1 && /usr/local/bin/npm -v >/dev/null 2>&1; then
    /usr/local/bin/npm config set fund false
    /usr/local/bin/npm config set audit false
  fi

  write_node_python_templates
}

setup_certbot_stack() {
  install -d -m 755 -o root -g root /etc/letsencrypt/renewal-hooks/deploy

  cat > "${CERTBOT_RELOAD_HOOK}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if systemctl is-active --quiet httpd; then
  systemctl reload httpd
fi
EOF

  chmod 755 "${CERTBOT_RELOAD_HOOK}"
  chown root:root "${CERTBOT_RELOAD_HOOK}"

  if systemctl list-unit-files certbot-renew.timer >/dev/null 2>&1; then
    systemctl enable --now certbot-renew.timer
  elif systemctl list-unit-files certbot.timer >/dev/null 2>&1; then
    systemctl enable --now certbot.timer
  fi
}

set_spaced_config_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp mode owner group

  tmp="$(mktemp)"
  mode="$(stat -c '%a' "${file}")"
  owner="$(stat -c '%u' "${file}")"
  group="$(stat -c '%g' "${file}")"

  awk -v key="${key}" -v value="${value}" '
    BEGIN { updated = 0 }
    $0 ~ "^[[:space:]]*#?[[:space:]]*" key "[[:space:]]*=" {
      print key " = " value
      updated = 1
      next
    }
    { print }
    END {
      if (!updated) {
        print key " = " value
      }
    }
  ' "${file}" > "${tmp}"

  install -m "${mode}" -o "${owner}" -g "${group}" "${tmp}" "${file}"
  rm -f "${tmp}"
}

tune_httpd_packaged_logging() {
  if [[ -f "${HTTPD_MAIN_CONF}" ]]; then
    sed -i \
      's#^[[:space:]]*CustomLog "logs/access_log" combined$#    CustomLog "logs/access_log" combined env=!dontlog_static#' \
      "${HTTPD_MAIN_CONF}"
  fi

  if [[ -f "${HTTPD_MODSSL_CONF}" ]]; then
    sed -i \
      's#^[[:space:]]*TransferLog logs/ssl_access_log$#CustomLog logs/ssl_access_log combined env=!dontlog_static#' \
      "${HTTPD_MODSSL_CONF}"
    perl -0pi -e 's#(CustomLog logs/ssl_request_log \\\n[[:space:]]*"%t %h %\{SSL_PROTOCOL\}x %\{SSL_CIPHER\}x \\"%r\\" %b")(?: env=!dontlog_static)?#$1 env=!dontlog_static#' \
      "${HTTPD_MODSSL_CONF}"
  fi
}

write_audit_watch_rule() {
  local path="$1"
  local perms="$2"
  local key="$3"

  if [[ -e "${path}" ]]; then
    printf -- '-w %s -p %s -k %s\n' "${path}" "${perms}" "${key}" >> "${AUDIT_STARTUP_RULES}"
  fi
}

ensure_aide_excludes() {
  local tmp

  if [[ ! -f "${AIDE_CONF}" ]]; then
    return 0
  fi

  tmp="$(mktemp)"
  awk '
    BEGIN {
      shm = "!/usr/lib/sysimage/rpm/rpmdb\\.sqlite-shm$"
      wal = "!/usr/lib/sysimage/rpm/rpmdb\\.sqlite-wal$"
    }
    $0 == shm { seen_shm = 1 }
    $0 == wal { seen_wal = 1 }
    { print }
    END {
      if (!seen_shm || !seen_wal) {
        print ""
        print "# Managed by startup_script.sh"
        print "# RPM SQLite shared-memory files are volatile after dnf/rpm operations."
        if (!seen_shm) {
          print shm
        }
        if (!seen_wal) {
          print wal
        }
      }
    }
  ' "${AIDE_CONF}" > "${tmp}"

  install -m 600 -o root -g root "${tmp}" "${AIDE_CONF}"
  rm -f "${tmp}"
}

write_logging_security_configs() {
  install -d -m 755 -o root -g root /etc/systemd/journald.conf.d
  install -d -m 755 -o root -g root /etc/fail2ban/jail.d
  install -d -m 755 -o root -g root /etc/logwatch/conf
  install -d -m 755 -o root -g root /usr/local/sbin

  cat > "${JOURNALD_RETENTION_CONF}" <<'EOF'
# Managed by startup_script.sh
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=8G
SystemKeepFree=5G
MaxRetentionSec=548day
MaxFileSec=1month
EOF

  cat > "${FAIL2BAN_LOCAL_CONF}" <<'EOF'
# Managed by startup_script.sh
[DEFAULT]
loglevel = INFO
logtarget = /var/log/fail2ban.log
dbpurgeage = 47347200
EOF

  cat > "${FAIL2BAN_JAIL_LOCAL}" <<EOF
# Managed by startup_script.sh
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
banaction = nftables-multiport
banaction_allports = nftables-allports
bantime = 1h
findtime = 10m
maxretry = 5
bantime.increment = true
bantime.factor = 2
bantime.maxtime = 30d

[sshd]
enabled = true
mode = aggressive
port = ${SSH_PORT}
backend = systemd
findtime = 10m
bantime = 1h
maxretry = 3

[webmin-auth]
enabled = true
port = ${WEBMIN_PORT}
logpath = /var/log/secure
          /var/webmin/miniserv.error
backend = auto
findtime = 15m
bantime = 2h
maxretry = 5

[apache-auth]
enabled = true
port = http,https
logpath = /var/log/httpd/*error_log
          /var/log/httpd/*error.log
          /home/*/logs/httpd/*error.log
backend = auto
findtime = 10m
bantime = 1h
maxretry = 5

[apache-botsearch]
enabled = true
port = http,https
logpath = /var/log/httpd/*error_log
          /var/log/httpd/*error.log
          /home/*/logs/httpd/*error.log
backend = auto
findtime = 1h
bantime = 6h
maxretry = 4

[apache-badbots]
enabled = true
port = http,https
logpath = /var/log/httpd/*access_log
          /var/log/httpd/*access.log
          /home/*/logs/httpd/*access.log
backend = auto
findtime = 1d
bantime = 2d
maxretry = 2

[recidive]
enabled = true
logpath = /var/log/fail2ban.log
banaction = nftables-allports
findtime = 7d
bantime = 30d
maxretry = 5
EOF

  cat > "${HTTPD_USER_LOG_PERMS_HELPER}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

shopt -s nullglob
for dir in /home/*/logs/httpd; do
  user="$(basename "$(dirname "$(dirname "${dir}")")")"
  if ! id "${user}" >/dev/null 2>&1; then
    continue
  fi
  chown "${user}:apache" "${dir}" || true
  chmod 755 "${dir}" || true
  for log in "${dir}"/*.log; do
    chown "${user}:apache" "${log}" || true
    chmod 664 "${log}" || true
  done
done

for dir in /home/*/logs/php; do
  user="$(basename "$(dirname "$(dirname "${dir}")")")"
  if ! id "${user}" >/dev/null 2>&1; then
    continue
  fi
  chown "${user}:apache" "${dir}" || true
  chmod 755 "${dir}" || true
  for log in "${dir}"/*.log; do
    chown "${user}:apache" "${log}" || true
    chmod 664 "${log}" || true
  done
done
EOF

  cat > "${LOGROTATE_RSYSLOG_CONF}" <<'EOF'
# Managed by startup_script.sh
/var/log/cron
/var/log/maillog
/var/log/messages
/var/log/secure
/var/log/spooler
{
    weekly
    rotate 78
    missingok
    notifempty
    compress
    delaycompress
    dateext
    create 0600 root root
    sharedscripts
    postrotate
        /usr/bin/systemctl reload rsyslog.service >/dev/null 2>&1 || true
    endscript
}
EOF

  cat > "${LOGROTATE_HTTPD_CONF}" <<EOF
# Managed by startup_script.sh
/var/log/httpd/*log
/var/log/httpd/*.log
{
    weekly
    rotate 26
    maxsize 100M
    missingok
    notifempty
    compress
    delaycompress
    dateext
    create 0640 root root
    sharedscripts
    postrotate
        /bin/systemctl reload httpd.service >/dev/null 2>&1 || true
    endscript
}

/home/*/logs/httpd/*.log
{
    weekly
    rotate 26
    maxsize 100M
    missingok
    notifempty
    compress
    delaycompress
    dateext
    create 0640 root root
    sharedscripts
    prerotate
        ${HTTPD_USER_LOG_PERMS_HELPER} >/dev/null 2>&1 || true
    endscript
    postrotate
        /bin/systemctl reload httpd.service >/dev/null 2>&1 || true
        ${HTTPD_USER_LOG_PERMS_HELPER} >/dev/null 2>&1 || true
    endscript
}
EOF

  cat > "${LOGROTATE_PHP_FPM_CONF}" <<EOF
# Managed by startup_script.sh
/var/log/php-fpm/*log {
    weekly
    rotate 26
    maxsize 100M
    missingok
    notifempty
    compress
    delaycompress
    dateext
    create 0664 root apache
    sharedscripts
    postrotate
        /bin/kill -SIGUSR1 \`cat /run/php-fpm/php-fpm.pid 2>/dev/null\` 2>/dev/null || true
    endscript
}

/home/*/logs/php/*.log
{
    weekly
    rotate 26
    maxsize 100M
    missingok
    notifempty
    compress
    delaycompress
    dateext
    create 0640 apache apache
    sharedscripts
    prerotate
        ${HTTPD_USER_LOG_PERMS_HELPER} >/dev/null 2>&1 || true
    endscript
    postrotate
        ${HTTPD_USER_LOG_PERMS_HELPER} >/dev/null 2>&1 || true
    endscript
}
EOF

  cat > "${LOGROTATE_WEBMIN_CONF}" <<'EOF'
# Managed by startup_script.sh
/var/webmin/miniserv.log
/var/webmin/miniserv.error
/var/webmin/webmin.log
{
    weekly
    rotate 78
    missingok
    notifempty
    compress
    delaycompress
    dateext
    copytruncate
    create 0600 root root
}
EOF

  cat > "${LOGROTATE_FAIL2BAN_CONF}" <<'EOF'
# Managed by startup_script.sh
/var/log/fail2ban.log {
    weekly
    rotate 78
    missingok
    notifempty
    compress
    delaycompress
    dateext
    create 0640 root root
    postrotate
        /usr/bin/fail2ban-client flushlogs >/dev/null 2>&1 || true
    endscript
}
EOF

  cat > "${LOGROTATE_AIDE_CONF}" <<'EOF'
# Managed by startup_script.sh
/var/log/aide/*.log {
    weekly
    rotate 78
    missingok
    notifempty
    compress
    delaycompress
    dateext
    copytruncate
}
EOF

  cat > "${LOGROTATE_MARIADB_SLOW_CONF}" <<'EOF'
# Managed by startup_script.sh
/var/log/mariadb/slow.log {
    su mysql mysql
    weekly
    rotate 12
    maxsize 256M
    missingok
    notifempty
    compress
    delaycompress
    dateext
    create 0640 mysql mysql
    sharedscripts
    postrotate
        if test -x /usr/bin/mariadb-admin; then
            /usr/bin/mariadb-admin --local flush-slow-log >/dev/null 2>&1 || true
        fi
    endscript
}
EOF

  cat > "${LOGROTATE_WTMP_CONF}" <<'EOF'
# Managed by startup_script.sh
/var/log/wtmp {
    monthly
    rotate 18
    missingok
    minsize 1M
    compress
    delaycompress
    dateext
    create 0664 root utmp
}
EOF

  cat > "${LOGROTATE_BTMP_CONF}" <<'EOF'
# Managed by startup_script.sh
/var/log/btmp {
    monthly
    rotate 18
    missingok
    compress
    delaycompress
    dateext
    create 0660 root utmp
}
EOF

  cat > "${LOGWATCH_SYSTEMD_CONF}" <<'EOF'
# Managed by startup_script.sh
LOGWATCH_OPTIONS="--output stdout --format text --range yesterday --detail med"
EOF

  cat > "${AIDE_CHECK_SERVICE}" <<'EOF'
# Managed by startup_script.sh
[Unit]
Description=AIDE file integrity check
Documentation=man:aide(1)

[Service]
Type=oneshot
ExecStart=/usr/sbin/aide --check
EOF

  cat > "${AIDE_CHECK_TIMER}" <<'EOF'
# Managed by startup_script.sh
[Unit]
Description=Weekly AIDE file integrity check

[Timer]
OnCalendar=Sun 03:30
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOF

  chmod 644 "${JOURNALD_RETENTION_CONF}" "${FAIL2BAN_LOCAL_CONF}" "${FAIL2BAN_JAIL_LOCAL}" \
    "${LOGROTATE_RSYSLOG_CONF}" "${LOGROTATE_HTTPD_CONF}" "${LOGROTATE_PHP_FPM_CONF}" \
    "${LOGROTATE_WEBMIN_CONF}" "${LOGROTATE_FAIL2BAN_CONF}" "${LOGROTATE_AIDE_CONF}" \
    "${LOGROTATE_MARIADB_SLOW_CONF}" "${LOGROTATE_WTMP_CONF}" "${LOGROTATE_BTMP_CONF}" \
    "${LOGWATCH_SYSTEMD_CONF}" "${AIDE_CHECK_SERVICE}" "${AIDE_CHECK_TIMER}"
  chmod 755 "${HTTPD_USER_LOG_PERMS_HELPER}"
  chown root:root "${JOURNALD_RETENTION_CONF}" "${FAIL2BAN_LOCAL_CONF}" "${FAIL2BAN_JAIL_LOCAL}" \
    "${LOGROTATE_RSYSLOG_CONF}" "${LOGROTATE_HTTPD_CONF}" "${LOGROTATE_PHP_FPM_CONF}" \
    "${LOGROTATE_WEBMIN_CONF}" "${LOGROTATE_FAIL2BAN_CONF}" "${LOGROTATE_AIDE_CONF}" \
    "${LOGROTATE_MARIADB_SLOW_CONF}" "${LOGROTATE_WTMP_CONF}" "${LOGROTATE_BTMP_CONF}" \
    "${LOGWATCH_SYSTEMD_CONF}" "${AIDE_CHECK_SERVICE}" "${AIDE_CHECK_TIMER}" \
    "${HTTPD_USER_LOG_PERMS_HELPER}"

  : > "${AUDIT_STARTUP_RULES}"
  cat > "${AUDIT_STARTUP_RULES}" <<'EOF'
## Managed by startup_script.sh
-b 8192
--backlog_wait_time 60000
-f 1
EOF

  write_audit_watch_rule /etc/passwd wa identity
  write_audit_watch_rule /etc/group wa identity
  write_audit_watch_rule /etc/shadow wa identity
  write_audit_watch_rule /etc/gshadow wa identity
  write_audit_watch_rule /etc/sudoers wa privilege-config
  write_audit_watch_rule /etc/sudoers.d wa privilege-config
  write_audit_watch_rule /etc/ssh wa ssh-config
  write_audit_watch_rule /etc/httpd wa web-config
  write_audit_watch_rule /etc/php.d wa web-config
  write_audit_watch_rule /etc/php-fpm.d wa web-config
  write_audit_watch_rule /etc/my.cnf wa db-config
  write_audit_watch_rule /etc/my.cnf.d wa db-config
  write_audit_watch_rule /etc/webmin wa webmin-config
  write_audit_watch_rule /etc/letsencrypt wa tls-config
  write_audit_watch_rule /etc/systemd/system wa systemd-config
  write_audit_watch_rule /etc/cron.d wa scheduler-config
  write_audit_watch_rule /var/spool/cron wa scheduler-config
  write_audit_watch_rule /usr/bin/sudo x privilege-exec
  write_audit_watch_rule /usr/bin/su x privilege-exec
  write_audit_watch_rule /usr/bin/passwd x identity-exec
  write_audit_watch_rule /usr/sbin/useradd x identity-exec
  write_audit_watch_rule /usr/sbin/userdel x identity-exec
  write_audit_watch_rule /usr/sbin/usermod x identity-exec
  write_audit_watch_rule /usr/bin/dnf x package-management
  write_audit_watch_rule /usr/bin/rpm x package-management
  write_audit_watch_rule /usr/bin/systemctl x service-management
  write_audit_watch_rule /usr/bin/mariadb x db-admin
  chmod 640 "${AUDIT_STARTUP_RULES}"
  chown root:root "${AUDIT_STARTUP_RULES}"
}

setup_logging_security_stack() {
  write_logging_security_configs
  ensure_aide_excludes
  tune_httpd_packaged_logging
  set_spaced_config_value /etc/audit/auditd.conf max_log_file 128
  set_spaced_config_value /etc/audit/auditd.conf num_logs 96
  set_spaced_config_value /etc/audit/auditd.conf max_log_file_action ROTATE
  set_spaced_config_value /etc/audit/auditd.conf space_left 2048
  set_spaced_config_value /etc/audit/auditd.conf admin_space_left 1024
  set_spaced_config_value /etc/audit/auditd.conf space_left_action SYSLOG
  set_spaced_config_value /etc/audit/auditd.conf admin_space_left_action SYSLOG
  set_spaced_config_value /etc/audit/auditd.conf disk_full_action SYSLOG
  set_spaced_config_value /etc/audit/auditd.conf disk_error_action SYSLOG

  systemctl daemon-reload
  systemctl enable --now auditd
  systemctl enable --now rsyslog
  augenrules --load || true
  systemctl restart systemd-journald
  systemctl enable --now fail2ban
  systemctl restart fail2ban
  systemctl disable --now exim >/dev/null 2>&1 || true
  systemctl enable --now logwatch.timer
  systemctl enable --now aide-check.timer

  "${HTTPD_USER_LOG_PERMS_HELPER}" || true
}

initialize_aide_database() {
  if [[ ! -s /var/lib/aide/aide.db.gz ]]; then
    /usr/sbin/aide --init
    install -m 600 -o root -g root /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
  fi
}

if [[ ! -s "${SOURCE_AUTH_KEYS}" ]]; then
  echo "ERROR: ${SOURCE_AUTH_KEYS} が存在しない、または空です。" >&2
  exit 1
fi

if ! id "${WEBMIN_USER}" >/dev/null 2>&1; then
  echo "ERROR: Webmin 初期ユーザー ${WEBMIN_USER} が存在しません。" >&2
  exit 1
fi

run_initial_system_update
install_common_base_packages
ensure_required_firewall_ports
setup_swapfile

setup_default_user_skel

install -d -m 700 -o root -g root "${ROOT_SSH_DIR}"
install -m 600 -o root -g root "${SOURCE_AUTH_KEYS}" "${ROOT_AUTH_KEYS}"
restorecon -RFv "${ROOT_SSH_DIR}" >/dev/null 2>&1 || true

cat > "${SSHD_DROPIN}" <<EOF
# Managed by /home/alma/startup_script.sh
Port ${SSH_PORT}
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
AuthenticationMethods publickey
MaxAuthTries 3
LoginGraceTime 30s
AuthorizedKeysFile .ssh/authorized_keys
EOF
chmod 600 "${SSHD_DROPIN}"
chown root:root "${SSHD_DROPIN}"

if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled; then
  if ! command -v semanage >/dev/null 2>&1; then
    dnf install -y policycoreutils-python-utils
  fi

  if ! semanage port -l | awk '$1 == "ssh_port_t" && $2 == "tcp" { print }' | grep -qw "${SSH_PORT}"; then
    semanage port -a -t ssh_port_t -p tcp "${SSH_PORT}" \
      || semanage port -m -t ssh_port_t -p tcp "${SSH_PORT}"
  fi
fi

open_firewall_port "${SSH_PORT}/tcp"

/usr/sbin/sshd -t
systemctl reload sshd || systemctl restart sshd
close_default_ssh_firewall_access

echo "SSH 設定を反映しました。新しい接続先: root@<server> -p ${SSH_PORT}"

if ! rpm -q webmin >/dev/null 2>&1; then
  if ! command -v curl >/dev/null 2>&1; then
    dnf install -y curl
  fi

  curl -fsSL -o "${WEBMIN_REPO_SCRIPT}" "${WEBMIN_REPO_SCRIPT_URL}"
  sh "${WEBMIN_REPO_SCRIPT}" --force
  dnf install -y webmin
fi

if [[ ! -f "${WEBMIN_MINISERV_CONF}" ]]; then
  echo "ERROR: ${WEBMIN_MINISERV_CONF} が見つかりません。" >&2
  exit 1
fi

set_config_value "${WEBMIN_MINISERV_CONF}" "port" "${WEBMIN_PORT}"
set_config_value "${WEBMIN_MINISERV_CONF}" "listen" "${WEBMIN_PORT}"
set_config_value "${WEBMIN_MINISERV_CONF}" "ssl" "1"
set_config_value "${WEBMIN_MINISERV_CONF}" "session" "1"
set_config_value "${WEBMIN_MINISERV_CONF}" "syslog" "1"
set_config_value "${WEBMIN_MINISERV_CONF}" "passdelay" "1"
set_config_value "${WEBMIN_MINISERV_CONF}" "blockhost_failures" "${WEBMIN_LOGIN_FAILURES}"
set_config_value "${WEBMIN_MINISERV_CONF}" "blockhost_time" "${WEBMIN_LOCK_SECONDS}"
set_config_value "${WEBMIN_MINISERV_CONF}" "blockuser_failures" "${WEBMIN_LOGIN_FAILURES}"
set_config_value "${WEBMIN_MINISERV_CONF}" "blockuser_time" "${WEBMIN_LOCK_SECONDS}"
set_config_value "${WEBMIN_MINISERV_CONF}" "blocklock" "0"

ensure_webmin_unix_user
ensure_webmin_admin_acl

open_firewall_port "${WEBMIN_PORT}/tcp"

systemctl enable --now webmin
systemctl restart webmin

echo "Webmin 設定を反映しました。接続先: https://<server>:${WEBMIN_PORT}/  ユーザー: ${WEBMIN_USER}"

setup_mta_stack

echo "MTA(Postfix) 設定を反映しました。ローカル投入専用で外向き送信のみ行います。"

dnf install -y httpd mod_ssl mod_http2 mariadb-server acl \
  php-fpm php-cli php-mysqlnd php-opcache php-gd php-mbstring php-xml \
  php-intl php-bcmath php-ldap php-soap php-process php-gmp php-dba \
  php-enchant php-snmp php-pecl-zip php-pecl-apcu php-pecl-redis6

ensure_web_home_access
write_apache_common_config
write_php_fpm_config
write_mariadb_tuning_config
ensure_default_ssl_certificate
write_systemd_resilience_dropin "mariadb.service" "-800"
write_systemd_resilience_dropin "php-fpm.service" "100"
write_systemd_resilience_dropin "httpd.service" "200" "ProtectHome=false"
systemctl daemon-reload

ensure_httpd_selinux_for_home_vhosts
open_firewall_port "80/tcp"
open_firewall_port "443/tcp"

/usr/sbin/httpd -t
php-fpm -t
systemctl enable --now php-fpm
systemctl restart php-fpm
systemctl enable --now httpd
systemctl restart httpd

install -d -m 750 -o mysql -g mysql /var/log/mariadb
systemctl enable --now mariadb
systemctl restart mariadb
secure_mariadb_initial_state

echo "Apache/MariaDB 設定を反映しました。vHost テンプレート: ${HTTPD_VHOST_TEMPLATE}"

dnf install -y epel-release
dnf install -y certbot python3-certbot-apache

setup_certbot_stack

echo "Certbot 設定を反映しました。Apache プラグイン: python3-certbot-apache"

dnf install -y fail2ban fail2ban-systemd aide logwatch audit rsyslog logrotate

setup_logging_security_stack

/usr/sbin/httpd -t
systemctl reload httpd

echo "ログ・監査・fail2ban 設定を反映しました。vHost ログは /home/<user>/logs/httpd/ と /home/<user>/logs/php/ を使用してください。"

dnf install -y nodejs24 nodejs24-npm python3-pip python3-devel \
  gcc gcc-c++ make openssl-devel libffi-devel zlib-ng-compat-devel \
  bzip2-devel xz-devel sqlite-devel readline-devel

setup_node_python_stack

echo "Node/Python 設定を反映しました。アプリ配置先: ${APP_ROOT}"

initialize_aide_database

echo "AIDE ベースラインを初期化しました。"

print_reboot_notice
