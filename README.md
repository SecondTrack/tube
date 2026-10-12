# Tube

**YouTube on an iPod touch 4 with iOS 6 – search, watch in 360p, or just listen with the screen off.**

The built-in YouTube app on iOS 6 stopped working long ago, and the website no longer plays on old Safari. Tube asks YouTube for the plain 360p stream (H.264 + AAC, itag 18) – the one format the iPod's hardware decoder can play natively – and hands it to the system player.

## What it can do

- **Search** with thumbnails, channel, views and length.
- **360p playback** with the native player, fullscreen when you turn the iPod.
- **Double-tap** the left or right side of the video to jump 10 seconds back or forward.
- **Mini player:** go back while a video is playing and it keeps running in a small window in the corner. Tap it to make it big again, drag it away or tap ✕ to close it.
- **Audio only:** play just the sound – it keeps going with the screen locked or in another app.
- **Comments** and video details, no account needed.
- German and English.

## Under the hood

- Stream URLs come from YouTube's internal player API using the Android client profiles, which still return direct 360p URLs without extra tokens. Search and comments use the web client.
- iOS 6 cannot do the TLS that YouTube's video servers require. Tube runs a tiny HTTP proxy on `127.0.0.1` that fetches the video over modern TLS with the bundled [mbedTLS](https://github.com/Mbed-TLS/mbedtls) and streams it to the system player.
- If YouTube changes its client versions, `src/YTApi.m` is the one place to update.

## Runs on

iOS 6.1.6 · jailbroken iPod touch 4

## Install

Easiest via the **[Reboot App Store](https://github.com/SecondTrack/reboot)** right on the iPod. By hand: `.deb` from the [latest release](https://github.com/SecondTrack/tube/releases/latest), `dpkg -i`, then `uicache`.

Build it yourself with [Theos](https://theos.dev): `make package`.

## License

GPL-3.0 – see [LICENSE](LICENSE). Libraries under `vendor/` keep their own licenses.
Not affiliated with YouTube, Google or Apple.
