DE0 Nano BitCoin Miner
======================

This project is a fork of https://github.com/kramble/DE0-Nano-BitCoin-Miner
with mixed code from http://www.makomk.com/gitweb/?p=Open-Source-FPGA-Bitcoin-Miner.git;a=shortlog;h=refs/heads/de0-nano-1hasher-afpgabm

Why ?
-----

For fun, you will not be rich or even return on investment, but that for
learning fpga programming.

What's the change ?
-------------------
This is specially optimized for a DE0 Nano without any modification and using
the usb 
So we have here 2 sha256 with 2 rounds, so at 40Mhz the DE0 Nano provide 10MH/s.

It s still use the usb to communicate. And project is configured at 30Mhz so
that's 7.5MH/s. I do not recommand using an unmodified DE0 Nano with higher
frequency as the power regulator will go too high in temperature.

Donation : [bitcoin:1Khertan7mpfbabM531QTsnDXBdK7sDYxLbitcoin:1Khertan7mpfbabM531QTsnDXBdK7sDYxL](bitcoin:1Khertan7mpfbabM531QTsnDXBdK7sDYxL)


