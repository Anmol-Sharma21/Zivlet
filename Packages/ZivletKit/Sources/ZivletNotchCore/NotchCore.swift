// ZivletNotchCore (design/19 §3.1, D-N1): the pure half of the notch island. Display geometry, the notch housing,
// island frames, the island state machine and the arbiter that lets several clients share one island. No AppKit, no
// clock reads: every event carries its own monotonic time. Nothing here names jobs, batches or files.
