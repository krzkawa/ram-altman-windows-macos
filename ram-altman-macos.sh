#!/usr/bin/env bash
set -euo pipefail
RECIPIENT="${RAM_ALTMAN_TO:-}"
SENDER="${RAM_ALTMAN_FROM:-}"
SENDER_NAME="${RAM_ALTMAN_FROM_NAME:-}"
THRESHOLD="${RAM_ALTMAN_THRESHOLD:-10}"
STATE_DIR="${RAM_ALTMAN_STATE_DIR:-$HOME/Library/Application Support/ram-altman}"
LOG="$STATE_DIR/usage.csv"; LAST="$STATE_DIR/last_sent"
die(){ echo "ram-altman: $1" >&2; exit 1; }
awk -v n="$THRESHOLD" 'BEGIN{exit !(n>=0 && n<=100)}' || die "threshold must be from 0 to 100"
read_memory(){
 local bytes vm page free inactive speculative purgeable
 bytes=$(sysctl -n hw.memsize) || die "cannot read hw.memsize"; vm=$(vm_stat) || die "vm_stat failed"
 page=$(echo "$vm"|awk '/page size of/{print $8;exit}'); [[ "$page" =~ ^[0-9]+$ ]] || die "cannot parse page size"
 free=$(echo "$vm"|awk '/Pages free:/{gsub("[.]","",$3);print $3+0}')
 inactive=$(echo "$vm"|awk '/Pages inactive:/{gsub("[.]","",$3);print $3+0}')
 speculative=$(echo "$vm"|awk '/Pages speculative:/{gsub("[.]","",$3);print $3+0}')
 purgeable=$(echo "$vm"|awk '/Pages purgeable:/{gsub("[.]","",$3);print $3+0}')
 total_kb=$((bytes/1024)); free_kb=$((free*page/1024)); cache_kb=$(((inactive+speculative+purgeable)*page/1024))
 available_kb=$((free_kb+cache_kb)); ((available_kb>total_kb)) && available_kb=$total_kb
 used_kb=$((total_kb-available_kb)); available_pct=$(awk -v a="$available_kb" -v t="$total_kb" 'BEGIN{printf "%.1f",a*100/t}')
}
gib(){ awk -v k="$1" 'BEGIN{printf "%.1f GiB",k/1048576}'; }
over(){ awk -v a="$available_kb" -v t="$total_kb" -v p="$THRESHOLD" 'BEGIN{exit !(a*100>p*t)}'; }
status(){ printf 'Total:      %s\nUsed:       %s\nAvailable:  %s (%s%%)\n  Free:     %s\n  Reclaimable estimate: %s\n' "$(gib "$total_kb")" "$(gib "$used_kb")" "$(gib "$available_kb")" "$available_pct" "$(gib "$free_kb")" "$(gib "$cache_kb")"; }
log_sample(){
 mkdir -p "$STATE_DIR"; [[ -f "$LOG" ]] || echo 'timestamp,total_kb,used_kb,available_kb,available_pct' > "$LOG"
 printf '%s,%s,%s,%s,%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$total_kb" "$used_kb" "$available_kb" "$available_pct" >> "$LOG"
 if (( $(wc -c < "$LOG") > 10485760 )); then { head -n 1 "$LOG"; tail -n 50000 "$LOG"; } > "$LOG.tmp"; mv "$LOG.tmp" "$LOG"; fi
}
compose(){
 email_subject="Unused RAM detected on my Mac"
 email_body="Hi Sam,

This Mac has $(gib "$total_kb") of RAM installed and $(gib "$available_kb") ($available_pct%) is currently available.

This is an estimate from free, inactive, speculative and purgeable vm_stat pages. It is not equivalent to Linux MemAvailable.

Hoarding responsibly,
${SENDER_NAME:-A concerned RAM owner}

--
Sent automatically, at most once a day, by a small script on one Mac.
Reply if you'd like it to stop."
}
render(){ local from="$SENDER"; [[ -n "$SENDER_NAME" ]] && from="$SENDER_NAME <$SENDER>"; printf 'From: %s\nTo: %s\nSubject: %s\nDate: %s\nMIME-Version: 1.0\nContent-Type: text/plain; charset=UTF-8\nAuto-Submitted: auto-generated\n\n%s\n' "$from" "$RECIPIENT" "$email_subject" "$(date '+%a, %d %b %Y %H:%M:%S %z')" "$email_body"; }
send(){ if command -v msmtp >/dev/null 2>&1; then render|msmtp -t; elif command -v sendmail >/dev/null 2>&1; then render|sendmail -t -i; else die "install and configure msmtp or sendmail before sending"; fi; }
case "${1:-}" in
 --help|-h) echo "Usage: ram-altman-macos.sh [--status|--dry-run|--help]"; exit 0 ;;
 --status) read_memory; status; exit 0 ;;
 --dry-run) read_memory; status; if over; then compose; RECIPIENT="${RECIPIENT:-recipient-not-set@example.com}"; SENDER="${SENDER:-sender-not-set@example.com}"; echo; render; else echo "No email: available RAM is not above ${THRESHOLD}%."; fi; exit 0 ;;
 "") ;;
 *) die "unknown option: $1 (try --help)" ;;
esac
[[ -n "$RECIPIENT" ]] || die "RAM_ALTMAN_TO is not set"; [[ -n "$SENDER" ]] || die "RAM_ALTMAN_FROM is not set"
mkdir -p "$STATE_DIR"
if ! mkdir "$STATE_DIR/lock" 2>/dev/null; then age=$(( $(date +%s)-$(stat -f %m "$STATE_DIR/lock" 2>/dev/null || echo 0) )); (( age>900 )) && rmdir "$STATE_DIR/lock" 2>/dev/null || exit 0; mkdir "$STATE_DIR/lock" 2>/dev/null || exit 0; fi
trap 'rmdir "$STATE_DIR/lock" 2>/dev/null || true' EXIT
read_memory; log_sample; over || exit 0
today=$(date +%F); [[ "$(cat "$LAST" 2>/dev/null || true)" != "$today" ]] || exit 0
compose; send; echo "$today" > "$LAST"
