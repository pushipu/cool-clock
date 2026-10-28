param([Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string]$ExpectedArchitecture)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$evidence = Join-Path $root 'output/windows-ci'
New-Item -ItemType Directory -Force $evidence | Out-Null
$proof = [ordered]@{ schema = 1; expectedArchitecture = $ExpectedArchitecture; stages = @(); errors = @(); automaticIdleStartTested = $false; secureLockTested = $false }
$ownedProcesses = [Collections.Generic.List[Diagnostics.Process]]::new()
$installDir = Join-Path $env:LOCALAPPDATA 'Cool Clock'
$saver = Join-Path $installDir 'Cool Clock.scr'
$uninstaller = Join-Path $installDir 'Uninstall.exe'
$ownsInstall = $false
$parentWindow = [IntPtr]::Zero

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Start-Native([string]$File, [string[]]$Arguments = @()) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $File
    $info.UseShellExecute = $false
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($info)
    $ownedProcesses.Add($process)
    return $process
}
function Start-Uninstall([string]$File) {
    # The ephemeral runner cleans this copy; Windows may retain its image lock after exit.
    $copy = Join-Path ([IO.Path]::GetTempPath()) ("CoolClock-uninstall-" + [Guid]::NewGuid().ToString('N') + '.exe')
    Copy-Item $File $copy
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $copy
    $info.UseShellExecute = $false
    # NSIS requires _?= to be last and unquoted, including spaces in its path.
    $info.Arguments = '/S _?=' + $installDir
    $process = [Diagnostics.Process]::Start($info)
    $ownedProcesses.Add($process)
    return $process
}
function Wait-Native([Diagnostics.Process]$Process, [int]$Seconds = 30) {
    $command = $Process.StartInfo.FileName + ' ' + $Process.StartInfo.Arguments + ' ' + ($Process.StartInfo.ArgumentList -join ' ')
    if (-not $Process.WaitForExit($Seconds * 1000)) {
        $Process.Kill($true)
        throw "Process $($Process.Id) exceeded $Seconds seconds: $command"
    }
    Assert-True ($Process.ExitCode -eq 0) "Process $($Process.Id) exited $($Process.ExitCode): $command"
}
function Desktop-Policy {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Control Panel\Desktop')
    try {
        $result = [ordered]@{}
        foreach ($name in @('SCRNSAVE.EXE', 'ScreenSaveTimeOut', 'ScreenSaverIsSecure', 'ScreenSaveActive')) {
            $result[$name] = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
        return $result | ConvertTo-Json -Compress
    } finally { if ($key) { $key.Dispose() } }
}
function Assert-Machine([string]$File, [int]$Machine) {
    $bytes = [IO.File]::ReadAllBytes($File)
    Assert-True ($bytes.Length -gt 256 -and $bytes[0] -eq 77 -and $bytes[1] -eq 90) "Invalid PE: $File"
    $offset = [BitConverter]::ToInt32($bytes, 0x3c)
    Assert-True ($offset -gt 0 -and $offset + 6 -le $bytes.Length) "Invalid PE offset: $File"
    Assert-True ([BitConverter]::ToUInt32($bytes, $offset) -eq 0x4550) "Invalid PE signature: $File"
    Assert-True ([BitConverter]::ToUInt16($bytes, $offset + 4) -eq $Machine) "Wrong installed architecture: $File"
}
function Check-Render([string]$Name, [string]$Mode = '--preview') {
    $report = Join-Path $evidence "$Name.json"
    # Allow the host's 30-second cold-start limit plus at least 15 seconds of playback.
    Wait-Native (Start-Native $saver @($Mode, '--smoke-report', $report, '--seconds', '45')) 75
    $data = Get-Content -Raw $report | ConvertFrom-Json
    Assert-True ($data.exitCode -eq 0 -and $data.views -ge 1 -and $data.readyViews -eq $data.views -and $data.errorCount -eq 0) "Render proof failed: $Name"
    $proof.stages += $Name
}
function Wait-SetupPage([Diagnostics.Process]$Process, [string]$Title, [string[]]$Required = @(), [int]$Seconds = 30, [switch]$MessageBox) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    $nextDiagnostic = [DateTime]::UtcNow
    $matchText = if ($MessageBox) { '' } else { $Title }
    do {
        Assert-True (-not $Process.HasExited) "Installer exited before page: $Title"
        $window = [SmokeWindow]::InstallerWindow($Process.Id, $matchText, [bool]$MessageBox)
        $text = if ($window -eq [IntPtr]::Zero) { '' }
            elseif ($MessageBox) { [SmokeWindow]::MessageBoxBody($window) }
            else { [SmokeWindow]::VisibleText($window) }
        $proof.lastInstallerPage = $text
        if ($MessageBox -and -not [string]::IsNullOrWhiteSpace($text)) {
            Assert-True ($text.Trim() -ceq $Title) "Wrong initialization error language. Expected: $Title. Actual: $text"
        }
        $complete = $text.Contains($Title)
        foreach ($expected in $Required) { $complete = $complete -and $text.Contains($expected) }
        if ($complete -and ($MessageBox -or [SmokeWindow]::ButtonEnabled($window, 1))) {
            $proof.installerPages += [ordered]@{ title = $Title; visibleText = $text }
            return $window
        }
        if ([DateTime]::UtcNow -ge $nextDiagnostic) {
            $Process.Refresh()
            $proof.lastInstallerWindowState = [ordered]@{
                expectedTitle = $Title; pid = $Process.Id
                mainWindow = $Process.MainWindowHandle.ToInt64()
                windows = [SmokeWindow]::DescribeWindows($Process.Id)
            }
            Write-Host ("Waiting for installer page: " + ($proof.lastInstallerWindowState | ConvertTo-Json -Compress))
            $nextDiagnostic = [DateTime]::UtcNow.AddSeconds(10)
        }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Installer page timed out: $Title. Last visible text: $text"
}


function Check-SetupGuide([string]$SetupFile, [bool]$Russian, [string]$ConcurrentSetup = '', [bool]$ConcurrentRussian = $false, [switch]$CheckUpdate) {
    $text = if ($Russian) {
        @{
            welcome = 'Вас приветствует мастер установки'; sound = 'Звук заставки'
            enableSound = 'Включить звук и минутные сигналы'; select = 'Шаг 1 из 4. Выберите Cool Clock'
            selectButton = 'Выбрать Cool Clock в Windows'; interval = 'Шаг 2 из 4. Задайте интервал'
            settings = 'Открыть параметры заставки'; apply = 'Применить'; power = 'Шаг 3 из 4. Проверьте таймер экрана'
            powerButton = 'Открыть параметры питания'; check = 'Шаг 4 из 4. Проверьте запуск'
            preview = 'Просмотр'; finish = 'Завершение работы мастера установки'
        }
    } else {
        @{
            welcome = 'Welcome to Cool Clock Setup'; sound = 'Screensaver sound'
            enableSound = 'Enable sound and minute beeps'; select = 'Step 1 of 4. Select Cool Clock'
            selectButton = 'Select Cool Clock in Windows'; interval = 'Step 2 of 4. Set the wait time'
            settings = 'Open screen saver settings'; apply = 'Apply'; power = 'Step 3 of 4. Check the screen timer'
            powerButton = 'Open power settings'; check = 'Step 4 of 4. Test the screensaver'
            preview = 'Preview'; finish = 'Completing Cool Clock Setup'
        }
    }
    $setup = Start-Native $SetupFile
    $wizard = Wait-SetupPage $setup $text.welcome
    if ($ConcurrentSetup) {
        # .onInit runs before NSIS refreshes LangString selection; check its error in the opposite language.
        $other = Start-Native $ConcurrentSetup
        $message = if ($ConcurrentRussian) { 'Установщик Cool Clock уже запущен.' } else { 'The Cool Clock installer is already running.' }
        # The first launch of this newly built EXE can delay readable dialog text.
        $dialog = Wait-SetupPage $other $message -Seconds 120 -MessageBox
        $proof.initializationErrorWindow = [SmokeWindow]::DescribeWindows($other.Id)
        [SmokeWindow]::ClickOnlyDialogButton($dialog)
        Assert-True ($other.WaitForExit(10000)) 'Concurrent setup did not close after its error was dismissed'
        Assert-True ($other.ExitCode -eq 13) "Concurrent setup exited $($other.ExitCode), expected 13"
        $proof.stages += 'localized-initialization-error'
    }
    [SmokeWindow]::ClickInstallerButton($wizard, 1)
    $wizard = Wait-SetupPage $setup $text.sound @($text.enableSound)
    $activePreviews = @()
    if ($CheckUpdate) {
        $embedded = Start-Native $saver @('/p', $parentWindow.ToInt64().ToString(), '--smoke-report', (Join-Path $evidence 'embedded-update.json'))
        $active = Start-Native $saver @('--preview', '--smoke-report', (Join-Path $evidence 'update-preview.json'))
        $deadline = [DateTime]::UtcNow.AddSeconds(20)
        do {
            Start-Sleep -Milliseconds 200
            Assert-True (-not $embedded.HasExited -and -not $active.HasExited) 'Preview exited before update'
            $hasChild = [SmokeWindow]::HasClockChild($parentWindow, $embedded.Id)
            $active.Refresh()
        } until (($hasChild -and $active.MainWindowHandle -ne 0) -or [DateTime]::UtcNow -gt $deadline)
        Assert-True $hasChild 'No embedded CoolClock child HWND appeared'
        Assert-True ($active.MainWindowHandle -ne 0) 'No active preview window appeared'
        $activePreviews = @($embedded, $active)
    }
    foreach ($preview in $activePreviews) {
        Assert-True (-not $preview.HasExited) 'Update test requires running previews immediately before installation'
    }
    [SmokeWindow]::ClickInstallerButton($wizard, 1)
    $wizard = Wait-SetupPage $setup $text.select @($text.selectButton) 240
    foreach ($preview in $activePreviews) { Wait-Native $preview 10 }
    Assert-True (-not [SmokeWindow]::ButtonEnabled($wizard, 3)) 'The first guide page must not return to the installation section'
    [SmokeWindow]::ClickInstallerButton($wizard, 1)
    $wizard = Wait-SetupPage $setup $text.interval @($text.settings, $text.apply)
    [SmokeWindow]::ClickInstallerButton($wizard, 3)
    $wizard = Wait-SetupPage $setup $text.select @($text.selectButton)
    [SmokeWindow]::ClickInstallerButton($wizard, 1)
    $wizard = Wait-SetupPage $setup $text.interval @($text.settings, $text.apply)
    [SmokeWindow]::ClickInstallerButton($wizard, 1)
    $wizard = Wait-SetupPage $setup $text.power @($text.powerButton)
    [SmokeWindow]::ClickInstallerButton($wizard, 1)
    $wizard = Wait-SetupPage $setup $text.check @($text.settings, $text.preview)
    [SmokeWindow]::ClickInstallerButton($wizard, 1)
    $wizard = Wait-SetupPage $setup $text.finish
    [SmokeWindow]::ClickInstallerButton($wizard, 1)
    Wait-Native $setup 30
    $proof.stages += if ($Russian) { 'russian-installer-guide' } else { 'english-installer-guide' }
}

try {
    Assert-True $IsWindows 'This smoke test requires Windows and PowerShell 7'
    $proof.os = [Runtime.InteropServices.RuntimeInformation]::OSDescription
    $proof.nativeArchitecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
    $proof.isSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
    Assert-True (-not $proof.isSystem) 'WebView2 must run as an interactive user, not SYSTEM'
    Assert-True ($proof.nativeArchitecture -eq $ExpectedArchitecture) 'Runner architecture differs from test target'
    Assert-True (-not (Test-Path $installDir)) 'Refusing to modify an existing Cool Clock installation'
    $beforePolicy = Desktop-Policy
    $proof.desktopPolicyBefore = $beforePolicy | ConvertFrom-Json
    $machine = if ($ExpectedArchitecture -eq 'arm64') { 0xaa64 } else { 0x8664 }
    $builtSaver = Join-Path $root "build/windows/$ExpectedArchitecture/Cool Clock.scr"
    Assert-Machine $builtSaver $machine
    Wait-Native (Start-Native $builtSaver @('--self-test'))
    $runtime = Start-Native $builtSaver @('--check-runtime')
    Assert-True ($runtime.WaitForExit(30000)) 'Runtime check timed out'
    if ($runtime.ExitCode -ne 0) {
        Wait-Native (Start-Native (Join-Path $root 'build/windows/MicrosoftEdgeWebview2Setup.exe') @('/silent', '/install')) 240
        Wait-Native (Start-Native $builtSaver @('--check-runtime'))
    }
    $proof.stages += 'native-self-test-and-runtime'
    $setups = @(Get-ChildItem (Join-Path $root 'dist/*Windows-Setup.exe'))
    Assert-True ($setups.Count -eq 1) 'Expected exactly one setup executable'
    $ownsInstall = $true
    Wait-Native (Start-Native $setups[0].FullName @('/S')) 240
    Assert-Machine $saver $machine
    Assert-Machine (Join-Path $installDir 'WebView2Loader.dll') $machine
    Assert-True ((Desktop-Policy) -eq $beforePolicy) 'Silent install changed desktop policy'
    $proof.stages += 'silent-install-native-architecture'
    Check-Render 'installed-render'
    Check-Render 'fullscreen-render' '/s'

    # A real child HWND tests /p shutdown without sending input to the desktop.
    Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class SmokeWindow {
    [DllImport("kernel32.dll")] public static extern ushort GetUserDefaultUILanguage();
    [StructLayout(LayoutKind.Sequential)] public struct Message { public IntPtr hwnd; public uint msg; public UIntPtr wp; public IntPtr lp; public uint time; public int x, y; public uint extra; }
    [DllImport("user32.dll")] static extern int GetMessageW(out Message message, IntPtr window, uint min, uint max);
    [DllImport("user32.dll")] static extern bool TranslateMessage(ref Message message);
    [DllImport("user32.dll")] static extern IntPtr DispatchMessageW(ref Message message);
    [DllImport("user32.dll")] static extern bool PostThreadMessageW(uint id, uint message, UIntPtr wp, IntPtr lp);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    static Thread thread;
    static uint threadId;
    public static IntPtr Start() {
        IntPtr window = IntPtr.Zero;
        using(var ready = new ManualResetEventSlim()) {
            thread = new Thread(() => {
                threadId = GetCurrentThreadId();
                window = CreateWindowExW(0, "STATIC", "Cool Clock CI preview parent", 0x10000000, 0, 0, 640, 480, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
                ready.Set();
                Message message;
                while(GetMessageW(out message, IntPtr.Zero, 0, 0) > 0) { TranslateMessage(ref message); DispatchMessageW(ref message); }
                if(window != IntPtr.Zero) DestroyWindow(window);
            });
            thread.IsBackground = true;
            thread.Start();
            if(!ready.Wait(10000)) throw new TimeoutException("Preview parent creation timed out");
        }
        return window;
    }
    public static void Stop() { PostThreadMessageW(threadId, 0x12, UIntPtr.Zero, IntPtr.Zero); thread.Join(5000); }

    public delegate bool EnumProc(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr CreateWindowExW(uint exStyle, string cls, string title, uint style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);
    [DllImport("user32.dll")] public static extern bool DestroyWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc callback, IntPtr param);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr window, StringBuilder text, int count);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback, IntPtr param);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetDlgItem(IntPtr window, int id);
    [DllImport("user32.dll")] static extern int GetDlgCtrlID(IntPtr window);
    [DllImport("user32.dll")] static extern bool PostMessageW(IntPtr window, uint message, UIntPtr wp, IntPtr lp);
    [DllImport("user32.dll", EntryPoint="SendMessageTimeoutW", CharSet=CharSet.Unicode)]
    static extern IntPtr ReadText(IntPtr window, uint message, UIntPtr wp, StringBuilder text, uint flags, uint timeout, out UIntPtr result);
    static string Text(IntPtr window) {
        var text = new StringBuilder(4096); UIntPtr result;
        return ReadText(window, 0xD, (UIntPtr)text.Capacity, text, 2, 200, out result) != IntPtr.Zero ? text.ToString() : "";
    }
    public static IntPtr InstallerWindow(uint expectedPid, string expectedText, bool messageBox) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((window, unused) => {
            uint pid; GetWindowThreadProcessId(window, out pid);
            if(pid == expectedPid && IsWindowVisible(window)
                && (messageBox ? OnlyDialogButton(window) != IntPtr.Zero : ButtonEnabled(window, 1))
                && VisibleText(window).Contains(expectedText)) { found = window; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }
    static IntPtr OnlyDialogButton(IntPtr parent) {
        IntPtr found = IntPtr.Zero;
        int count = 0;
        EnumChildWindows(parent, (child, unused) => {
            var cls = new StringBuilder(128); GetClassNameW(child, cls, 128);
            if(cls.ToString() == "Button" && IsWindowVisible(child) && IsWindowEnabled(child)) {
                found = child; count++;
            }
            return true;
        }, IntPtr.Zero);
        return count == 1 ? found : IntPtr.Zero;
    }
    public static void ClickOnlyDialogButton(IntPtr parent) {
        IntPtr button = OnlyDialogButton(parent);
        if(button == IntPtr.Zero)
            throw new InvalidOperationException("Expected one enabled message box button");
        ClickInstallerButton(parent, GetDlgCtrlID(button));
    }
    public static string MessageBoxBody(IntPtr parent) {
        var body = new StringBuilder();
        EnumChildWindows(parent, (child, unused) => {
            var cls = new StringBuilder(128); GetClassNameW(child, cls, 128);
            if(cls.ToString() == "Static" && IsWindowVisible(child)) {
                string text = Text(child);
                if(!String.IsNullOrWhiteSpace(text)) body.AppendLine(text);
            }
            return true;
        }, IntPtr.Zero);
        return body.ToString();
    }
    public static string DescribeWindows(uint expectedPid) {
        var all = new StringBuilder();
        EnumWindows((window, unused) => {
            uint pid; GetWindowThreadProcessId(window, out pid);
            if(pid == expectedPid) {
                var cls = new StringBuilder(128); GetClassNameW(window, cls, 128);
                all.AppendLine("HWND=" + window.ToInt64() + " class=" + cls + " visible=" + IsWindowVisible(window)
                    + " enabled=" + IsWindowEnabled(window) + " button1=" + GetDlgItem(window, 1).ToInt64()
                    + " title=" + Text(window));
                EnumChildWindows(window, (child, ignored) => {
                    GetClassNameW(child, cls, 128);
                    all.AppendLine("  child=" + child.ToInt64() + " id=" + GetDlgCtrlID(child) + " class=" + cls + " visible=" + IsWindowVisible(child)
                        + " enabled=" + IsWindowEnabled(child) + " text=" + Text(child));
                    return true;
                }, IntPtr.Zero);
            }
            return true;
        }, IntPtr.Zero);
        return all.ToString();
    }
    public static string VisibleText(IntPtr parent) {
        var all = new StringBuilder();
        EnumChildWindows(parent, (window, unused) => {
            if(IsWindowVisible(window)) { string text = Text(window); if(text.Length > 0) all.AppendLine(text); }
            return true;
        }, IntPtr.Zero);
        return all.ToString();
    }
    public static bool ButtonEnabled(IntPtr parent, int id) {
        IntPtr button = GetDlgItem(parent, id);
        return button != IntPtr.Zero && IsWindowVisible(button) && IsWindowEnabled(button);
    }
    public static void ClickInstallerButton(IntPtr parent, int id) {
        if(!ButtonEnabled(parent, id) || !PostMessageW(parent, 0x111, (UIntPtr)id, GetDlgItem(parent, id)))
            throw new InvalidOperationException("Installer button unavailable: " + id);
    }
    public static bool HasClockChild(IntPtr parent, uint expectedPid) {
        bool found = false;
        EnumChildWindows(parent, (window, unused) => {
            uint pid; GetWindowThreadProcessId(window, out pid);
            var cls = new StringBuilder(128); GetClassNameW(window, cls, 128);
            if(pid == expectedPid && cls.ToString() == "CoolClock") found = true;
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
'@
    $parentWindow = [SmokeWindow]::Start()
    Assert-True ($parentWindow -ne [IntPtr]::Zero) 'Cannot create embedded preview parent'
    Check-Render 'embedded-render' ("/p:" + $parentWindow.ToInt64().ToString())
    $systemRussian = ([SmokeWindow]::GetUserDefaultUILanguage() -band 0x3ff) -eq 0x19
    $proof.systemUILanguage = [SmokeWindow]::GetUserDefaultUILanguage()
    $dependencies = Get-Content -Raw (Join-Path $root 'windows/dependencies.json') | ConvertFrom-Json
    $hostTools = $dependencies.hosts.('Windows-' + $ExpectedArchitecture)
    $nsis = $dependencies.($hostTools.nsis)
    $nsisRoot = Join-Path (Join-Path $root 'build/windows-tools') $nsis.directory
    $makensis = Join-Path $nsisRoot $nsis.executable
    # The ephemeral runner cleans this image; ARM emulation may keep it locked after exit.
    $languageSetup = Join-Path ([IO.Path]::GetTempPath()) ("CoolClock-language-" + [Guid]::NewGuid().ToString('N') + '.exe')
    # German exercises the English fallback when the runner itself uses Russian.
    $testLanguage = if ($systemRussian) { 1031 } else { 1049 }
    $version = ([Diagnostics.FileVersionInfo]::GetVersionInfo($builtSaver)).ProductVersion
    $oldNSIS = $env:NSISDIR
    try {
        $env:NSISDIR = $nsisRoot
        & $makensis '-V3' '-NOCD' '-INPUTCHARSET' 'UTF8' "-DPAYLOAD_DIR=$(Join-Path $root 'build/windows')" "-DOUTPUT_FILE=$languageSetup" "-DVERSION=$version" "-DCOOL_CLOCK_TEST_UI_LANGUAGE=$testLanguage" (Join-Path $root 'windows/Installer.nsi') 2>&1 | Tee-Object (Join-Path $evidence 'language-installer-build.log')
        Assert-True ($LASTEXITCODE -eq 0) 'Could not build the test-only installer language variant'
    } finally { $env:NSISDIR = $oldNSIS }
    # Exercise the installed UI flow on the disposable runner without selecting a saver or changing its timer.
    $proof.installerPages = @()
    Check-SetupGuide $setups[0].FullName $systemRussian $languageSetup (-not $systemRussian) -CheckUpdate
    Check-SetupGuide $languageSetup (-not $systemRussian)
    Assert-Machine $saver $machine
    Assert-True ((Desktop-Policy) -eq $beforePolicy) 'Interactive update or guide changed desktop policy without a settings action'
    $proof.stages += 'interactive-guide-four-steps-and-back-navigation'
    $proof.stages += 'update-closes-top-level-and-embedded-previews'
    Check-Render 'updated-render'

    $sentinel = Join-Path $installDir 'user-added-preserve.txt'
    $sentinelContent = [Guid]::NewGuid().ToString()
    [IO.File]::WriteAllText($sentinel, $sentinelContent)
    $knownFiles = @(Get-ChildItem $installDir -File -Recurse | Where-Object FullName -ne $sentinel | ForEach-Object FullName)
    # Run a copy with _?= so the real uninstall exit is observed and its installed EXE can be deleted.
    Wait-Native (Start-Uninstall $uninstaller) 120
    foreach ($file in $knownFiles) {
        Assert-True (-not (Test-Path $file)) "Uninstall left package file: $file"
    }
    Assert-True ([IO.File]::ReadAllText($sentinel) -eq $sentinelContent) 'Uninstall changed a user-added file'
    Assert-True ((Desktop-Policy) -eq $beforePolicy) 'Silent uninstall changed desktop policy'
    $proof.desktopPolicyAfter = (Desktop-Policy) | ConvertFrom-Json
    $proof.stages += 'uninstall-preserves-user-files-and-desktop-policy'
    Remove-Item $sentinel
    # Only remove the empty test directory, never recursively remove user files.
    [IO.Directory]::Delete($installDir)
    $ownsInstall = $false
    $proof.passed = $true
} catch {
    $proof.passed = $false
    $proof.errors += $_.ToString()
    $proof.scriptStackTrace = $_.ScriptStackTrace
    try {
        $marker = Join-Path $installDir '.cool-clock-install'
        $proof.installAtFailure = [ordered]@{
            directory = $installDir
            attributes = if (Test-Path $installDir) { (Get-Item -Force $installDir).Attributes.ToString() } else { $null }
            markerBase64 = if (Test-Path $marker) { [Convert]::ToBase64String([IO.File]::ReadAllBytes($marker)) } else { $null }
        }
    } catch { $proof.errors += "Failure diagnostics: $_" }
    Write-Warning ($proof.errors[0])
} finally {
    foreach ($process in $ownedProcesses) {
        if (-not $process.HasExited) { $process.Kill($true); $process.WaitForExit(5000) | Out-Null }
    }
    if ($parentWindow -ne [IntPtr]::Zero) { [SmokeWindow]::Stop() }
    if ($ownsInstall -and (Test-Path $uninstaller)) {
        try {
            Wait-Native (Start-Uninstall $uninstaller) 120
        }
        catch { $proof.errors += "Cleanup: $_"; $proof.cleanupStackTrace = $_.ScriptStackTrace }
    }
    $proof | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 (Join-Path $evidence 'smoke-proof.json')
}
if (-not $proof.passed) { exit 1 }
