# NetPulse — reconstructed source

This is a **clean-room, source-style reconstruction**, not the original source code. It is a small native SwiftUI project based on static evidence from the supplied `NetPulse` 2.1.2 iOS IPA. The original compiled app did not include its Xcode project, Swift files, debug symbols, or dSYM, so exact source recovery was not possible.

## What the IPA reveals

The app is a native arm64 Swift/SwiftUI iOS app (minimum iOS 17; bundle identifier `jcw.pong`). Readable Swift symbols and localization strings identify screens and components for speed tests, ping, DNS, HTTP timing, IPv4/IPv6 connection tests, app latency, LAN scanning, Bonjour/SSDP/NetBIOS discovery, port/service probes, camera detection, IP/device information, UDP/STUN quality, quick diagnosis, history, PDF reports, and subscriptions. The binary also contains Cloudflare speed-test URLs and several public DNS-over-HTTPS endpoints.

The reconstruction implements a reduced core: connection status, small Cloudflare download/upload samples, DNS-over-HTTPS lookup, HTTP GET timing, HTTPS reachability timing, combined DNS/HTTPS diagnosis, Cloudflare public-IP lookup, local Bonjour browsing, and on-device 14-day test history.

## Important differences and limits

- This is not a decompilation and does not reproduce the original app’s internal architecture, algorithms, UI details, database schema, feature limits, or StoreKit products.
- The screen called **Ping / Reachability** uses HTTPS `HEAD` timing. That includes DNS, TCP, TLS, and server response time; it is **not ICMP ping**.
- Local discovery browses five declared Bonjour service types only. It does not sweep the subnet, probe ports, use ARP/SSDP/NetBIOS, or find hidden cameras.
- UDP/STUN quality measurement, traceroute, packet capture/HTTPS interception, location/SSID lookup, subscriptions, and report export are not implemented.
- No API-like key recovered from the binary was copied into this project. Network requests in the sample go directly from the device to their named public endpoints.
- Testing a speed endpoint transfers approximately 8 MB down and 1 MB up. Use Wi-Fi or change the sample sizes if data usage matters.

## Build

Open `NetPulseReconstructed.xcodeproj` in Xcode 15+ and run the `NetPulseReconstructed` scheme on an iOS 17+ simulator or device. Local Bonjour discovery requires the Local Network permission prompt. The project could not be compiled or run in this Linux analysis environment, so treat the code as a starting point and verify it in Xcode before release.

## GitHub Actions unsigned IPA

When this source is published to a public GitHub repository, the `Build unsigned iOS IPA` workflow runs on pushes to `main` or can be started manually from the repository's Actions tab. It builds the app without code signing and uploads `NetPulseReconstructed-unsigned.ipa` as a workflow artifact for 14 days. The artifact is intended for workflows such as importing into LiveContainer; it is not an Apple-signed install package, and installation behavior depends on the device and LiveContainer version.

## Analysis limits

The bundle inventory and binary strings were inspected locally. The executable contains a Mach-O encryption-info command with `cryptid = 0`, and its Swift class/view symbols are readable. However, this environment has no configured Ghidra, Hopper, IDA, or Kuna provider and no macOS/Xcode tools, so there is no trustworthy function-level pseudocode or runtime behavior trace here. String and symbol presence establishes that names/features are embedded; it does not prove every code path is reachable or behaves as its label suggests.
