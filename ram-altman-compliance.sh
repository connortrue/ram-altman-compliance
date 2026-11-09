#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Ram-Altman: Compliance Division
#
# The well-behaved inverse of ram-altman. Where that script complains to Sam
# Altman about RAM sitting idle, this one writes to him only when the RAM is
# actually in use, to reassure him that the machine is behaving.
#
#   used = MemTotal - MemAvailable   (same accounting as the original)
#   emails at most once a day, and only at or above the utilisation threshold
#
# This is a parody. It ships with no recipient address: set your own, use a
# real address you can send from, and stop if anyone asks you to.
# ---------------------------------------------------------------------------

set -u

VERSION="1.0.0"
PROG="ram-altman-compliance"

STATE_DIR="${COMPLIANCE_ALTMAN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/ram-altman-compliance}"
MEMINFO="${COMPLIANCE_ALTMAN_MEMINFO:-/proc/meminfo}"
MIN_USED="${COMPLIANCE_ALTMAN_MIN_USED:-90}"
MODE="run"

SUBJECTS=(
  "Compliance report: exemplary"
  "You're welcome"
  "No notes"
  "Utilisation update: we've been good"
  "Nothing to sit idle, nothing to report"
  "Fully allocated, as requested"
  "Your RAM is earning its keep"
  "Filed under: well behaved"
)

BODIES=(
"Hi Sam,

Good news for once. Of the {TOTAL} installed in this computer, {USED} ({PCT}%) were in use when I last checked. Nothing is sitting around unattended. The machine is earning its keep.

I know idle RAM has been on your mind, so take this as a routine all-clear."
"Dear Sam,

A short compliance note. This machine has been at {PEAK}% today, and it is still working. Your RAM is not sitting on my desk unused; it is on my desk, busy.

No action required. I will keep you posted."
"Hi Sam,

Reporting in, as requested. Utilisation is {PCT}%, comfortably above the level at which anyone could accuse me of hoarding. {USED} of the {TOTAL} are allocated; the remainder is cache the kernel will hand back the moment something asks.

You are welcome."
"Sam,

I have been good. {PCT}% of my RAM is in use. I did not buy it to look at it.

Please update your records accordingly."
"Hi Sam,

Brief status: {USED} of {TOTAL} in use ({PCT}%). Peak today was {PEAK}% at {PEAKTIME}. That is {STREAK} consecutive compliant day(s), if you are counting, and I suspect you are.

Keep building. I am using it."
"Dear Sam,

No idle capacity to report. The RAM is allocated, the machine is warm, and the fans are doing that thing they do. Utilisation: {PCT}%.

Apologies for the short letter. I am busy."
)

SIGNOFFS=(
  "Yours in full utilisation,"
  "Compliantly,"
  "With no idle time to speak of,"
  "Efficiently,"
  "Warmly, from a busy machine,"
  "Respectfully, and at {PCT}%,"
)

die() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit "${2:-1}"
}

usage() {
  cat <<'EOF'
Usage: ram-altman-compliance.sh [--status | --dry-run] [--help]

Reports to Sam Altman when your RAM is in use, not when it is idle.

Options:
  --status     Print the figures and today's peak, send nothing
  --dry-run    Print the letter it would send, send nothing
  --help       Show this help
  --version    Show the version

Configuration (environment):
  COMPLIANCE_ALTMAN_TO             Recipient. Required to actually send.
  COMPLIANCE_ALTMAN_FROM           Your real address. Required to actually send.
  COMPLIANCE_ALTMAN_FROM_NAME      Your name. Default: A well-behaved machine
  COMPLIANCE_ALTMAN_MIN_USED       Email at or above this % used. Default: 90
  COMPLIANCE_ALTMAN_STATE_DIR      Where state lives.
                                   Default: ~/.local/state/ram-altman-compliance
  COMPLIANCE_ALTMAN_MEMINFO        meminfo file. Default: /proc/meminfo

Cron (every five minutes; it still sends at most once a day):

  */5 * * * * COMPLIANCE_ALTMAN_TO=you@example.com \
              COMPLIANCE_ALTMAN_FROM=you@example.com \
              /path/to/ram-altman-compliance.sh

This is a parody. Not affiliated with Sam Altman or OpenAI. The repo ships with
no recipient address, and you should not add one.
EOF
}

# ---------------------------------------------------------------------------
# Figures
# ---------------------------------------------------------------------------

mem_kb() {
  awk -v key="$1:" '$1 == key { print $2; found = 1 } END { if (!found) print 0 }' "$MEMINFO"
}

has_memavailable() {
  awk '$1 == "MemAvailable:" { found = 1 } END { exit !found }' "$MEMINFO"
}

gib() {
  awk -v kb="$1" 'BEGIN { printf "%.1f GiB", kb / 1048576 }'
}

read_figures() {
  [ -r "$MEMINFO" ] || die "cannot read $MEMINFO (this script is Linux-only)"

  TOTAL_KB=$(mem_kb MemTotal)
  [ "${TOTAL_KB:-0}" -gt 0 ] || die "no MemTotal in $MEMINFO"

  if has_memavailable; then
    AVAIL_KB=$(mem_kb MemAvailable)
  else
    # Kernels before 3.14 have no MemAvailable; estimate like the original.
    local free buffers cached sreclaimable shmem
    free=$(mem_kb MemFree)
    buffers=$(mem_kb Buffers)
    cached=$(mem_kb Cached)
    sreclaimable=$(mem_kb SReclaimable)
    shmem=$(mem_kb Shmem)
    AVAIL_KB=$(( free + buffers + cached + sreclaimable - shmem ))
    [ "$AVAIL_KB" -lt 0 ] && AVAIL_KB=0
  fi

  [ "${AVAIL_KB:-0}" -ge 0 ] || AVAIL_KB=0
  [ "$AVAIL_KB" -le "$TOTAL_KB" ] || AVAIL_KB=$TOTAL_KB

  USED_KB=$(( TOTAL_KB - AVAIL_KB ))
  PCT=$(( USED_KB * 100 / TOTAL_KB ))
  TOTAL_GIB=$(gib "$TOTAL_KB")
  USED_GIB=$(gib "$USED_KB")
  AVAIL_GIB=$(gib "$AVAIL_KB")
}

# ---------------------------------------------------------------------------
# State: peak of the day, last send, compliance streak
# ---------------------------------------------------------------------------

PEAK_FILE="$STATE_DIR/peak"
SENT_FILE="$STATE_DIR/last_sent"
STREAK_FILE="$STATE_DIR/streak"

ensure_state() {
  mkdir -p "$STATE_DIR" 2>/dev/null || die "cannot create state dir $STATE_DIR"
}

load_peak() {
  PEAK_PCT=$PCT
  PEAK_TIME=$(date +%H:%M)
  local p_date="" p_time="" p_pct=""
  if [ -r "$PEAK_FILE" ]; then
    IFS=$'\t' read -r p_date p_time p_pct < "$PEAK_FILE" || true
    if [ "${p_date:-}" = "$TODAY" ] && [ "${p_pct:-}" -gt "$PEAK_PCT" ]; then
      PEAK_PCT=$p_pct
      PEAK_TIME=${p_time:-$PEAK_TIME}
    fi
  fi
}

save_peak() {
  ensure_state
  local p_date="" p_time="" p_pct=""
  if [ -r "$PEAK_FILE" ]; then
    IFS=$'\t' read -r p_date p_time p_pct < "$PEAK_FILE" || true
  fi
  if [ "${p_date:-}" != "$TODAY" ] || [ "${p_pct:-0}" -lt "$PEAK_PCT" ]; then
    printf '%s\t%s\t%s\n' "$TODAY" "$PEAK_TIME" "$PEAK_PCT" > "$PEAK_FILE"
  fi
}

already_sent_today() {
  [ -r "$SENT_FILE" ] && [ "$(cat "$SENT_FILE" 2>/dev/null)" = "$TODAY" ]
}

mark_sent() {
  printf '%s\n' "$TODAY" > "$SENT_FILE"
}

# Streak the report would claim, without changing anything.
streak_preview() {
  local s_date="" s_count=""
  if [ -r "$STREAK_FILE" ]; then
    IFS=$'\t' read -r s_date s_count < "$STREAK_FILE" || true
  fi
  if [ "${s_date:-}" = "$TODAY" ]; then
    printf '%s' "${s_count:-1}"
  elif [ "${s_date:-}" = "$YESTERDAY" ]; then
    printf '%s' "$(( ${s_count:-0} + 1 ))"
  else
    printf '1'
  fi
}

mark_streak() {
  local s_date="" s_count="" next
  if [ -r "$STREAK_FILE" ]; then
    IFS=$'\t' read -r s_date s_count < "$STREAK_FILE" || true
  fi
  if [ "${s_date:-}" = "$YESTERDAY" ]; then
    next=$(( ${s_count:-0} + 1 ))
  elif [ "${s_date:-}" = "$TODAY" ]; then
    next=${s_count:-1}
  else
    next=1
  fi
  printf '%s\t%s\n' "$TODAY" "$next" > "$STREAK_FILE"
}

# ---------------------------------------------------------------------------
# The letter
# ---------------------------------------------------------------------------

render() {
  local s=$1
  s=${s//\{TOTAL\}/$TOTAL_GIB}
  s=${s//\{USED\}/$USED_GIB}
  s=${s//\{AVAILABLE\}/$AVAIL_GIB}
  s=${s//\{PCT\}/$PCT}
  s=${s//\{PEAK\}/$PEAK_PCT}
  s=${s//\{PEAKTIME\}/$PEAK_TIME}
  s=${s//\{STREAK\}/$STREAK}
  printf '%s' "$s"
}

compose() {
  local doy subj_idx body_idx sign_idx template
  doy=$(( 10#$(date +%j) ))
  subj_idx=$(( doy % ${#SUBJECTS[@]} ))
  body_idx=$(( (doy * 3 + 1) % ${#BODIES[@]} ))
  sign_idx=$(( (doy * 5 + 2) % ${#SIGNOFFS[@]} ))

  SUBJECT=$(render "${SUBJECTS[$subj_idx]}")

  template=${BODIES[$body_idx]}$'\n\n'${SIGNOFFS[$sign_idx]}$'\n'${FROM_NAME}
  BODY=$(render "$template")
}

build_message() {
  local to from
  to=${TO:-recipient@example.com}
  from=${FROM:-you@example.com}
  cat <<EOF
To: $to
From: $FROM_NAME <$from>
Subject: $SUBJECT
Date: $(date -R)
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

$BODY

--
Sent automatically, at most once a day, by a small script on ${HOSTNAME:-one PC}.
Reply if you'd like it to stop.
EOF
}

sanitize() {
  printf '%s' "${1:-}" | tr -d '\r\n'
}

# ---------------------------------------------------------------------------
# Output modes
# ---------------------------------------------------------------------------

print_status() {
  load_peak
  printf 'Total:      %s\n' "$TOTAL_GIB"
  printf 'Used:       %s (%s%%)\n' "$USED_GIB" "$PCT"
  printf 'Available:  %s\n' "$AVAIL_GIB"
  printf 'Threshold:  %s%%\n' "$MIN_USED"
  printf 'Peak today: %s%% at %s\n' "$PEAK_PCT" "$PEAK_TIME"
  printf 'Streak:     %s compliant day(s)\n' "$(streak_preview)"
  if [ "$PCT" -ge "$MIN_USED" ]; then
    printf 'Verdict:    report due (if not already sent today)\n'
  else
    printf 'Verdict:    below threshold, no report\n'
  fi
}

print_dry_run() {
  load_peak
  STREAK=$(streak_preview)
  compose
  build_message
}

send_report() {
  local msg
  msg=$(build_message)

  if command -v sendmail >/dev/null 2>&1; then
    printf '%s\n' "$msg" | sendmail -t
  elif command -v msmtp >/dev/null 2>&1; then
    printf '%s\n' "$msg" | msmtp -t
  elif command -v mail >/dev/null 2>&1; then
    printf '%s\n' "$BODY" | mail -s "$SUBJECT" "$TO"
  else
    die "no sendmail, msmtp or mail found; nothing sent" 2
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

for arg in "$@"; do
  case "$arg" in
    --status)  MODE="status" ;;
    --dry-run) MODE="dry_run" ;;
    --help|-h) usage; exit 0 ;;
    --version) printf '%s %s\n' "$PROG" "$VERSION"; exit 0 ;;
    *) usage >&2; die "unknown option: $arg" 1 ;;
  esac
done

case "$MIN_USED" in
  ''|*[!0-9]*) die "COMPLIANCE_ALTMAN_MIN_USED must be a whole number 1-100" ;;
esac
[ "$MIN_USED" -ge 1 ] && [ "$MIN_USED" -le 100 ] \
  || die "COMPLIANCE_ALTMAN_MIN_USED must be between 1 and 100"

TODAY=$(date +%F)
YESTERDAY=$(date -d yesterday +%F 2>/dev/null || true)
[ -n "$YESTERDAY" ] || YESTERDAY=""

read_figures

TO=$(sanitize "${COMPLIANCE_ALTMAN_TO:-}")
FROM=$(sanitize "${COMPLIANCE_ALTMAN_FROM:-}")
FROM_NAME=$(sanitize "${COMPLIANCE_ALTMAN_FROM_NAME:-A well-behaved machine}")
[ -n "$FROM_NAME" ] || FROM_NAME="A well-behaved machine"

if [ "$MODE" = "status" ]; then
  print_status
  exit 0
fi

if [ "$MODE" = "dry_run" ]; then
  print_dry_run
  exit 0
fi

# Real run from cron.
if [ -z "$TO" ] || [ -z "$FROM" ]; then
  die "set COMPLIANCE_ALTMAN_TO and COMPLIANCE_ALTMAN_FROM (or use --dry-run)" 2
fi

if [ "$PCT" -lt "$MIN_USED" ]; then
  exit 0
fi

ensure_state

# One run at a time; clear a lock left behind by a killed run.
LOCK="$STATE_DIR/lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
    rmdir "$LOCK" 2>/dev/null || true
    mkdir "$LOCK" 2>/dev/null || exit 0
  else
    exit 0
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

load_peak
save_peak

if already_sent_today; then
  exit 0
fi

STREAK=$(streak_preview)
compose

if send_report; then
  mark_sent
  mark_streak
  printf '%s: compliance report sent (%s%% used)\n' "$PROG" "$PCT"
  exit 0
fi

die "send failed; will retry on the next run" 2
