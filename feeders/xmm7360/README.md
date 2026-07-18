# xmm7360 feeder

For Intel XMM7360 modems driven by the in-tree `iosm` module + the
`xmm7360-pci-spat` userspace RPC tooling (expected at
`/usr/lib/xmm7360-pci-spat/rpc/`). Root required (the wwan RPC node is 0600).

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

Privacy: publishes signal metrics only — never IMEI/ICCID/IMSI or cell identifiers.
