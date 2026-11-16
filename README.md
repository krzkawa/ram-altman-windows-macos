# Ram-Altman

**A tiny cross-platform RAM monitor that writes to Sam Altman when your computer has memory to spare.**

This fork keeps the original Linux Bash implementation and adds native macOS and Windows runners. The joke is the email; the memory readings are real estimates.

## Platforms

| Platform | Entry point | Memory source | Scheduler |
| --- | --- | --- | --- |
| Linux | ./ram-altman.sh | /proc/meminfo (MemAvailable) | cron |
| macOS | ./ram-altman-macos.sh | vm_stat + sysctl hw.memsize | launchd |
| Windows 10/11 | ram-altman.bat | CIM + standby cache counters when available | Task Scheduler |

All implementations support --status, --dry-run and --help. Linux remains the upstream script.

## macOS

Requirements: macOS, Bash, vm_stat/sysctl (included with macOS), and either msmtp or sendmail configured for outgoing mail.

~~~sh
chmod +x ram-altman-macos.sh
./ram-altman-macos.sh --status
./ram-altman-macos.sh --dry-run
~~~

The macOS available-memory figure is an estimate: free + inactive + speculative + purgeable VM pages. This is useful for a rough comparison but is **not equivalent to Linux MemAvailable** and does not fully model memory pressure, compression or every reclaimability detail.

Configure the recipient/sender variables before running:

~~~sh
export RAM_ALTMAN_TO="recipient@example.com"
export RAM_ALTMAN_FROM="you@example.com"
export RAM_ALTMAN_FROM_NAME="Your Name"
export RAM_ALTMAN_THRESHOLD="10"
~~~

Install and configure msmtp (recommended) or a compatible sendmail command. The script does not configure your mail provider or store credentials.

### Run every five minutes with launchd

1. Copy com.ram-altman.monitor.plist to ~/Library/LaunchAgents/.
2. Replace /ABSOLUTE/PATH/TO/ram-altman-macos.sh with the full path to the script.
3. Set the required environment variables for the user launchd session, for example with launchctl setenv RAM_ALTMAN_TO recipient@example.com (repeat for RAM_ALTMAN_FROM and optional settings).
4. Load it:

~~~sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.ram-altman.monitor.plist
launchctl kickstart -k gui/$(id -u)/lol.ram-altman.monitor
~~~

To stop and unload:

~~~sh
launchctl bootout gui/$(id -u)/lol.ram-altman.monitor
~~~

launchctl setenv values are session-scoped. For a permanent setup, use a carefully permissioned wrapper/config rather than putting mail credentials in a world-readable plist.

## Windows 10/11

Requirements: Windows PowerShell 5.1 (included with Windows) and an SMTP account/provider. The .bat file is a small launcher for the PowerShell implementation.

~~~bat
ram-altman.bat --status
ram-altman.bat --dry-run
~~~

Set the required environment variables in the same session before sending:

~~~powershell
$env:RAM_ALTMAN_TO = "recipient@example.com"
$env:RAM_ALTMAN_FROM = "you@example.com"
$env:RAM_ALTMAN_FROM_NAME = "Your Name"
$env:RAM_ALTMAN_SMTP_SERVER = "smtp.example.com"
$env:RAM_ALTMAN_SMTP_PORT = "587"
$env:RAM_ALTMAN_SMTP_USERNAME = "you@example.com"
$env:RAM_ALTMAN_SMTP_PASSWORD = "your-app-password"
$env:RAM_ALTMAN_SMTP_SSL = "true"
$env:RAM_ALTMAN_THRESHOLD = "10"
~~~

Run ram-altman.bat --dry-run before allowing a real send. Use an app password if your provider requires one; do not commit credentials or paste them into issue reports. RAM_ALTMAN_SMTP_PASSWORD is read from the environment and is never written to the repository or log.

The Windows available-memory estimate adds FreePhysicalMemory to standby cache counters when available. Windows counter names are localized, so on non-English installations the lookup may fail and the script falls back to free physical memory only. Treat this as an estimate, not an exact equivalent of Linux MemAvailable.

### Schedule with Task Scheduler

Create a task in Task Scheduler with a five-minute repetition interval. Set:

- **Program/script:** the full path to ram-altman.bat
- **Start in:** the repository directory
- **Trigger:** daily, repeat every 5 minutes, indefinitely
- **Environment:** make the RAM_ALTMAN_* values available to the task's account before running it

Task Scheduler does not inherit variables from an interactive PowerShell window. Configure them for the task's account or use a private wrapper script protected with Windows file permissions. Do not put SMTP passwords in a shared/public script.

## Linux

The original upstream Bash implementation is retained:

~~~sh
chmod +x ram-altman.sh test-ram-altman.sh
./ram-altman.sh --status
./ram-altman.sh --dry-run
~~~

Requires Linux, Bash and a working sendmail, msmtp or mail command. Add the following to your crontab with crontab -e:

~~~cron
RAM_ALTMAN_TO=recipient@example.com
RAM_ALTMAN_FROM=you@example.com
RAM_ALTMAN_FROM_NAME=Your Name
*/5 * * * * /path/to/ram-altman.sh
~~~

Linux uses the kernel's MemAvailable estimate (or a fallback estimate on older kernels).

## Shared settings

| Variable | Meaning | Default |
| --- | --- | --- |
| RAM_ALTMAN_TO | Recipient address | Required for sending |
| RAM_ALTMAN_FROM | Sender address | Required for sending |
| RAM_ALTMAN_FROM_NAME | Sender display name | Optional |
| RAM_ALTMAN_THRESHOLD | Send when available RAM is strictly above this percentage | 10 |
| RAM_ALTMAN_STATE_DIR | State/log directory | Platform-specific |
| RAM_ALTMAN_SMTP_SERVER | Windows SMTP hostname | Required on Windows |
| RAM_ALTMAN_SMTP_PORT | Windows SMTP port | 587 |
| RAM_ALTMAN_SMTP_USERNAME | Windows SMTP username | Optional |
| RAM_ALTMAN_SMTP_PASSWORD | Windows SMTP password/app password | Required when username is set |
| RAM_ALTMAN_SMTP_SSL | Enable Windows SMTP TLS | true |

Each platform keeps its own CSV usage log and last-send date. A successful run sends at most one email per day. Failed sends are not recorded as successful, so a later run can retry. --dry-run never sends mail or changes the daily-send state.

## Please be a good neighbour

One email a day from one person is a joke. Ten thousand of them is a denial-of-service attack with better material.

- **Use --dry-run first.** It costs nothing and lets you inspect the message.
- Use an address you control and a legitimate sender account. No spoofing.
- Do not deploy this across a server fleet or use it to spam anyone.
- If anyone asks you to stop, stop.

## License

See LICENSE.