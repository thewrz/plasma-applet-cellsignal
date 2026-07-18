# xmm7360 feeder

For Intel XMM7360 modems driven by the in-tree `iosm` module. Metrics come
from the modem's AT command port (`/dev/wwan0at1`): `AT+XCESQ?` for live
RSRP/RSRQ/SINR and `AT+XMCI=1` for the serving cell's EARFCN (band and
frequency are derived from it). Root required (the wwan AT nodes are 0600).
No RPC userspace tooling is needed.

Install, from this directory (`feeders/xmm7360/`):

    cd feeders/xmm7360
    sudo install -Dm755 cellsignal-feeder-xmm7360 /usr/local/bin/cellsignal-feeder-xmm7360
    sudo install -Dm755 xmm7360_decode.py /usr/local/bin/xmm7360_decode.py
    sudo install -Dm644 cellsignal-xmm7360.service /etc/systemd/system/cellsignal-xmm7360.service
    sudo install -Dm644 cellsignal-xmm7360.timer   /etc/systemd/system/cellsignal-xmm7360.timer
    sudo systemctl daemon-reload && sudo systemctl enable --now cellsignal-xmm7360.timer

Run it once so the feed file exists right away, then check it:

    sudo systemctl start --wait cellsignal-xmm7360.service
    cat /run/cellsignal.json

Coexistence: the feeder shares the host's modem lock (`/run/lte-at.lock`) with other
modem tooling; a held lock skips that tick and the last published document stays
in place. Disable any other periodic publisher that takes the same lock, or the
skipped ticks age the feed.

Privacy: publishes signal metrics only — never IMEI/ICCID/IMSI or cell identifiers.
