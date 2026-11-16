# AXI4-Stream terms

## Beat

A **beat** is one word that crosses the interface on one clock edge: a rising `aclk` edge where `TVALID = '1'` and `TREADY = '1'` at the same time. The AXI spec calls it a **transfer**; engineers usually say beat. Everything that moves on that edge (`TDATA`, `TLAST`, and any other sideband signals) belongs to that one beat.

```
aclk     _|‾|_|‾|_|‾|_|‾|_|‾|_
tvalid   ___|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|__
tready   ‾‾‾‾‾‾‾‾|___|‾‾‾‾‾‾‾‾‾
tdata    ---< 0 >< 1     >< 2 >--
              ^   ^   ^   ^
            beat beat  no beat
              0   1  (stall)
```

- On the third edge `tvalid` is high but `tready` is low, so nothing transfers. The source must hold `1` stable until a later edge where both are high (here, the very next edge).
- Counting beats means counting edges where both signals are high, not clock cycles.

## Related terms

- **Packet / frame:** a group of beats. `TLAST = '1'` marks the last beat of the packet. In this repo, `TLAST` marks a frame (see [stream_contract.md](stream_contract.md)).
- **Burst:** the same idea in full AXI4 (memory-mapped). A burst of 16 beats means 16 data transfers for one address. It appears in stages 7 and 9.

## In the testbench

In `axis_reg_slice_tb`, `NUM_BEATS = 100` means the source must get 100 words through the handshake, and the checker must see 100 handshakes on the output side.
