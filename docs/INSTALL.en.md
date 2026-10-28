[RU](INSTALL.md) / **EN**

# Install Cool Clock for macOS

[Download installer 0.9.2](https://github.com/pushipu/cool-clock/releases/download/v0.9.2/Cool-Clock-0.9.2-macOS.dmg)

Requires macOS 12 or later. One installer supports Apple Silicon and Intel.
This is a preview release; macOS may warn about an unidentified developer
the first time you open it.

The installer and app use Russian when your system interface language is Russian, and English otherwise.

## Installation

1. Open the downloaded DMG and launch **Cool Clock Installer.app**.
2. Click **Continue** and choose whether to enable sound.
   Sound is off on a first installation.
3. Click **Install** and follow the setup steps below.

The wizard's buttons open System Settings, and a floating guide shows you
what to select. Make the change in System Settings, then click **Next**
in the guide. The wizard does not select the screensaver or check your actions
automatically. The guide does not need Accessibility or Screen Recording
permission. Drag its title bar to move it.

If the screensaver is already installed, click
**Cool Clock is already installed: set up macOS…**
on the first screen. You do not need to reinstall it.

## Set up the screensaver

1. **Select Cool Clock.** On macOS 26–27, open **Wallpaper → Screen Saver… →
   Custom → Other → Show All → Cool Clock** and click **Done**.
   On macOS 13–15, use the separate **Screen Saver** section; on macOS 12,
   open **Desktop & Screen Saver**.
2. **Turn off the system clock.** On macOS 26–27, open **Wallpaper → Clock Appearance…**
   and set the large clock to **Never**. On macOS 14–15, **Show large clock** is under
   **Lock Screen**. On macOS 12–13, clear **Show with clock**.
   **On Lock Screen** still leaves the clock overlay visible when the Mac is locked;
   choose **Never** to turn off the large clock entirely.
3. **Set the start delay.** For example, after 2 minutes of inactivity. On macOS 26–27,
   the timer is in the **Screen Saver…** window; click **Done** after setting it.
   On macOS 13–15, open **Lock Screen** settings; on macOS 12,
   open **Desktop & Screen Saver**.
4. **Check the display timer.** The display should turn off after the screensaver starts:
   for example, the display after 10 minutes and the screensaver after 2.
   On a laptop, check both battery and power adapter settings.
   You do not need to change the password requirement.
5. **Check the result.** Launch the system **Preview**. Then lock your Mac
   (⌃⌘Q), wait for the screensaver, and check that the large macOS clock no longer
   covers it. Your avatar and login controls may remain visible.

## Sound

In System Settings, select Cool Clock, open its **Options**, change the sound
toggle, and click **Save**.

In the separate **Cool Clock Preview** app, click the clock to toggle sound
or open **Cool Clock → Settings…** (⌘,). The preview app and
system screensaver have separate sound settings. During installation,
your choice is applied to both.

## If macOS blocks the app

If you trust the downloaded release, open **System Settings → Privacy & Security**
and click **Open Anyway** for Cool Clock, if that button is available.
On older versions, the section is called **Security & Privacy**.
On a work Mac, your administrator may restrict these permissions.
[Read Apple's guidance](https://support.apple.com/102445).

## Updates and files

To update, run the new installer. You can eject the DMG after installation.
The screensaver is stored at `~/Library/Screen Savers/Cool Clock.saver`,
and the preview app at `~/Applications/Cool Clock Preview.app`.

To verify the download, save [SHA256SUMS](https://github.com/pushipu/cool-clock/releases/download/v0.9.2/SHA256SUMS)
beside the DMG and run this command in that folder:

```sh
shasum -a 256 -c SHA256SUMS
```

The wizard has been tested on Apple Silicon with macOS 27.0.1.
Intel Macs and the interfaces of older macOS versions have not been tested separately.
