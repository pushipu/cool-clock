[RU](INSTALL.ru.md) / **EN**

# Install Cool Clock for Windows

[Download installer 0.9.4](https://github.com/pushipu/cool-clock/releases/download/v0.9.4/Cool-Clock-0.9.4-Windows-Setup.exe)

Requires Windows 10 or 11. One installer supports Intel/AMD x64 and ARM64.
This is a preview release; the installer is not yet digitally signed.

The installer and app use Russian when your Windows display language is Russian, and English otherwise.

## Installation

1. Run the downloaded installer and choose whether to enable sound and the minute beeps.
   Sound is off on first installation.
2. Wait for installation to finish. If Microsoft WebView2 Runtime is needed, the wizard
   downloads it from Microsoft; this requires an internet connection.
3. Follow the four setup steps. The wizard's buttons open Windows settings,
   and highlighted rows show what to select. **Next** does not save Windows
   settings or automatically check your changes.

## 1. Select Cool Clock

If Windows Screen Saver Settings is already open, save any changes you want to keep and close that window first.

Click **Select Cool Clock in Windows**. This button
replaces the currently selected screensaver with Cool Clock and opens its settings.
Check the **Screen saver** field. Click **Settings…** to change the sound setting.

The other wizard buttons only open settings. To open them manually, go to
**Start → Settings → Personalization → Lock screen → Screen saver**.
If your organization prevents you from changing the screensaver, contact your administrator.

## 2. Save the wait time

Set **Wait** to a suitable interval, such as **2 minutes**.
Click **Apply → OK**. Set **On resume, display logon screen** as you prefer;
the wizard does not change it.

## 3. Check screen and sleep timers

Click **Open power settings**. On Windows 11, this opens
**System → Power & battery** or **Power**; on Windows 10, **System → Power & sleep**.

The screen-off and sleep timers must be longer than the screensaver's wait time.
For example: screensaver after 2 minutes, screen off and sleep after 10. On a laptop,
check the timers separately for battery power and when plugged in.

## 4. Test the screensaver

Open **Screen Saver Settings** and click **Preview**. Check that the clock and clouds
are moving. Moving the mouse ends the preview.
Click **Apply → OK**, then leave the mouse and keyboard untouched for the selected
wait time to check that the screensaver starts automatically.

If the screen turns off first or the clock does not appear, check that Cool Clock is selected,
the wait time was saved, and the screen and sleep timers are set correctly. A working preview
does not confirm automatic activation; pressing Win+L does not replace this test either.

## Updating and uninstalling

To update, run the new installer. To uninstall, use the list of installed apps in Windows.
Cool Clock's files are in `%LOCALAPPDATA%\Cool Clock`. Uninstalling preserves any extra
files you have placed in that folder and the shared Microsoft WebView2 Runtime.

Automatic activation and behavior after locking a real PC have not yet been confirmed.
[Microsoft's screen saver setup guide](https://support.microsoft.com/en-us/windows/configure-a-screen-saver-in-windows-a9dc2a0c-dc8e-9161-d270-aaccc252082a).
