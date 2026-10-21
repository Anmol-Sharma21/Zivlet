// ZivletNotch (design/19 §3.1, D-N1): the AppKit half of the notch island. The panel above the menu bar, the screen
// geometry reader, one host per display and the hosts' owner. Clients (the Notch HUD now, the tray later) give it a
// SwiftUI view per surface and a request; it never names jobs, batches or files.
