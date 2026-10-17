# QRC compatibility codec

The `des.c` and `des.h` implementation is from wangqr/QQMusicDES (MIT):
https://github.com/wangqr/QQMusicDES

Upstream blob identifiers: des.c 887e83b1d7a0f6cac00946a643d35ab3de0b6786;
des.h 1503772a2b5906b469f318d86d41742e090dfc7d.
The upstream source attributes its DES implementation to Brad Conte and
https://github.com/B-Con/crypto-algorithms. Preserve LICENSE with redistributions.
Local change: corrected the header guard spelling. The legacy, intentionally
nonstandard DES behavior is for public QQ lyric-format interoperability only;
it must not be used to protect passwords, user data or network traffic.

The app-specific bounded buffer wrapper is in windows/runner/qrc_codec.c.
No account cookie, user key, player patching or process-memory access is used.
