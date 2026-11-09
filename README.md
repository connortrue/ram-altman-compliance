# Ram-Altman: Compliance Division

A bash script that emails Sam Altman when your RAM is actually in use.

This is the well-behaved inverse of [ram-altman](https://github.com/IainKay/ram-altman), which
emails him a daily complaint about the RAM sitting unused in your computer. This one writes
only when the RAM is busy, to reassure him that the machine is behaving.

```
used = MemTotal - MemAvailable
```

Same accounting as the original, including reclaimable page cache. It just reports the
opposite verdict.

## A sample letter

```
To: sam@example.com
From: A well-behaved machine <you@example.com>
Subject: You're welcome

Hi Sam,

Brief status: 29.8 GiB of 32.0 GiB in use (93%). Peak today was 93% at
08:02. That is 6 consecutive compliant day(s), if you are counting, and I
suspect you are.

Keep building. I am using it.

Compliantly,
A well-behaved machine

--
Sent automatically, at most once a day, by a small script on one PC.
Reply if you'd like it to stop.
```

## Features

- Emails at or above a utilisation threshold (default 90%), at most once a day
- Rotates 8 subject lines, 6 letters and 6 sign-offs, so the good news stays fresh
- Tracks the day's peak and a consecutive-days compliance streak
- `--dry-run` prints the letter without sending anything
- `--status` shows the figures, the peak and whether a report is due
- Ships with no recipient address, and asks you not to add one
- One run at a time, with a lock that clears itself if a run is killed

## Install

Needs Linux, bash, and a working `sendmail`, `msmtp` or `mail` command.

```sh
git clone https://github.com/YOURNAME/ram-altman-compliance.git
cd ram-altman-compliance
chmod +x ram-altman-compliance.sh

./ram-altman-compliance.sh --status     # the evidence in your favour
./ram-altman-compliance.sh --dry-run    # read today's letter, send nothing
```

There is nothing to build and nothing to install. It is one file.

## Run it for real

Add this to `crontab -e`. It samples every five minutes and still sends at most one email a day.

```
COMPLIANCE_ALTMAN_TO=you@example.com
COMPLIANCE_ALTMAN_FROM=you@example.com
COMPLIANCE_ALTMAN_FROM_NAME=Your Name

*/5 * * * * /path/to/ram-altman-compliance.sh
```

| Setting | What it does | Default |
| --- | --- | --- |
| `COMPLIANCE_ALTMAN_TO` | Who receives the good news | Required |
| `COMPLIANCE_ALTMAN_FROM` | A real address you can send from | Required |
| `COMPLIANCE_ALTMAN_FROM_NAME` | Your name, or your nom de RAM | `A well-behaved machine` |
| `COMPLIANCE_ALTMAN_MIN_USED` | Email at or above this % used | `90` |
| `COMPLIANCE_ALTMAN_STATE_DIR` | Where the peak, streak and send date live | `~/.local/state/ram-altman-compliance` |
| `COMPLIANCE_ALTMAN_MEMINFO` | meminfo file | `/proc/meminfo` |

## One honest caveat

A literal threshold makes this a quiet script. Idle is the normal state of a desktop, so most
days no letter is due, which is arguably the joke. If you want the correspondence to actually
arrive, either lower the threshold (`COMPLIANCE_ALTMAN_MIN_USED=40` will do it on a working
laptop) or give the machine something to do, like running a model locally. Then the letter is
not just compliance, it is a flex.

## FAQ

**Does this help with the DRAM shortage?** No. It is the same amount of help as the original,
with better manners.

**Does it work on macOS?** No. It reads `/proc/meminfo`, like the original. Your RAM is soldered
down anyway, which makes you the hardest target in the global allocation programme.

**Why 90%?** Because that is roughly the point at which "I am using my RAM" becomes a claim you
can defend in writing.

**How do I see the jokes without sending anything?** `--dry-run` renders today's letter using
your real figures. It never sends.

## Please be a good neighbour

This is a parody. It is not affiliated with, endorsed by, or connected to Sam Altman or OpenAI.
The repository deliberately contains no email address: use your own real address, send from it,
do not spoof anyone, do not run this across a fleet, and stop if the recipient asks you to.

## License

Free as in fully allocated. See [LICENSE](LICENSE).
