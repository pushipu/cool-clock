# Media in Cool Clock

The macOS background uses two real camera recordings from Free Nature Stock:

- **Swift Moving Clouds**, 4096×2304. https://freenaturestock.com/video/swift-moving-clouds/
  Original: https://cdn.freenaturestock.com/videos/freenaturestock-swift-moving-clouds.mp4
- **Clouds and Sun Time-lapse**, 4096×2304. https://freenaturestock.com/video/clouds-and-sun-time-lapse/
  Original: https://cdn.freenaturestock.com/videos/freenaturestock-rotating-clouds-sun.mp4

License: **CC0 1.0**, https://creativecommons.org/publicdomain/zero/1.0/
Publisher's license and statement that footage is real camera capture:
https://freenaturestock.com/license/ (checked 2026-10-27).

Offline modifications: sky-only cropping, slowing with motion-compensated
interpolation to 60fps, crossfades for 29-second source loops, resizing to
1968×1436, H.264 encoding and removal of audio. The two prepared files are
bundled as CloudSwift.mp4 and CloudCirrus.mp4.

During playback, Metal applies monochrome blue/silver color grading and
animated rectangular windows. Three video streams reuse the two files at
offsets 0/7/13 seconds. Fourteen rectangular takeovers per 116-second scene
(about 8.286 seconds apart) promote window footage to the background.
Aspect-fill sampling adapts the clouds to the window without stretching them.

The Clouds and Sun crop starts at x=700, y=0 (1968×1436) so tree crowns
entering the original recording near its end stay outside the image.

These are replacement footage, not the lost original source clips. The geometry
of the clock and rectangular windows was measured from the user's old recording.
The user's recording itself is not included in the screensaver bundle.

The minute audio track is taken from the author’s original clock recording.
The project owner authorized its public distribution with this screensaver.
It is not covered by the cloud footage’s CC0 license; original code and media
remain subject to the repository’s LICENSE notice.
