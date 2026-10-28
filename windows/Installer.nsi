Unicode true
RequestExecutionLevel user
!include MUI2.nsh
!include nsDialogs.nsh
!include LogicLib.nsh
!include x64.nsh
!include WinVer.nsh
!include "${PAYLOAD_DIR}\payload-files.nsh"

Name "Cool Clock"
Caption "Cool Clock"
UninstallCaption "Cool Clock"
OutFile "${OUTPUT_FILE}"
InstallDir "$LOCALAPPDATA\Cool Clock"
; Videos are already compressed; solid LZMA saved under 0.5% in this package.
SetCompressor zlib
!define MUI_ICON "${PAYLOAD_DIR}\ClockIcon.ico"
!define MUI_UNICON "${PAYLOAD_DIR}\ClockIcon.ico"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TEXT "$(ClockWelcome)"
!insertmacro MUI_PAGE_WELCOME
Page custom SoundPage SoundLeave
!insertmacro MUI_PAGE_INSTFILES
Page custom SelectGuidePage
Page custom IntervalGuidePage
Page custom PowerGuidePage
Page custom CheckGuidePage
!define MUI_FINISHPAGE_TEXT "$(ClockFinish)"
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "$(ClockOpenSaver)"
!define MUI_FINISHPAGE_RUN_FUNCTION OpenSettings
!define MUI_FINISHPAGE_RUN_NOTCHECKED
!define MUI_FINISHPAGE_SHOWREADME
!define MUI_FINISHPAGE_SHOWREADME_TEXT "$(ClockPreview)"
!define MUI_FINISHPAGE_SHOWREADME_FUNCTION Preview
!define MUI_FINISHPAGE_SHOWREADME_NOTCHECKED
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Russian"

Var NativeArch
Var Sound
Var SoundCheckbox
Var StageDir
Var BackupDir
Var Mutex
Var RegChanged
Var RegRestoreFailed
Var Old0
Var Present0
Var Old1
Var Present1
Var Old2
Var Present2
Var Old3
Var Present3
Var Old4
Var Present4
Var Old5
Var Present5
Var Old6
Var Present6
Var Old7
Var Present7


LangString ClockWelcome ${LANG_ENGLISH} "This installer adds Cool Clock for the current user.$\r$\n$\r$\nThis is a Windows preview release. Automatic activation and behavior after locking still need testing.$\r$\n$\r$\nClick Next to continue."
LangString ClockWelcome ${LANG_RUSSIAN} "Установщик добавит Cool Clock для текущего пользователя.$\r$\n$\r$\nЭто предварительная Windows-версия. Автозапуск по таймеру и работа с блокировкой ещё требуют проверки.$\r$\n$\r$\nДля продолжения нажмите Далее."
LangString ClockFinish ${LANG_ENGLISH} "Cool Clock is installed.$\r$\n$\r$\nTo start the clock automatically, select Cool Clock in Windows screen saver settings, set the wait time, and click Apply.$\r$\n$\r$\nThe wizard does not verify automatic activation or change Windows sign-in settings."
LangString ClockFinish ${LANG_RUSSIAN} "Файлы Cool Clock установлены.$\r$\n$\r$\nЧтобы часы запускались автоматически, выберите Cool Clock в параметрах заставки Windows, задайте интервал и нажмите «Применить».$\r$\n$\r$\nМастер не проверяет автоматический запуск и не меняет параметры входа в Windows."
LangString ClockOpenSaver ${LANG_ENGLISH} "Open Windows screen saver settings"
LangString ClockOpenSaver ${LANG_RUSSIAN} "Открыть выбор заставки Windows"
LangString ClockPreview ${LANG_ENGLISH} "Preview Cool Clock"
LangString ClockPreview ${LANG_RUSSIAN} "Посмотреть Cool Clock"
LangString ClockCannotClose ${LANG_ENGLISH} "Could not close Cool Clock. Close the screensaver and its preview, then try again."
LangString ClockCannotClose ${LANG_RUSSIAN} "Не удалось закрыть работающий Cool Clock. Закройте заставку и её предпросмотр, затем повторите попытку."
LangString ClockSoundTitle ${LANG_ENGLISH} "Screensaver sound"
LangString ClockSoundTitle ${LANG_RUSSIAN} "Звук заставки"
LangString ClockSoundDescription ${LANG_ENGLISH} "You can change this later in Cool Clock settings."
LangString ClockSoundDescription ${LANG_RUSSIAN} "Эту настройку можно изменить в параметрах Cool Clock."
LangString ClockSoundCheckbox ${LANG_ENGLISH} "Enable sound and minute beeps"
LangString ClockSoundCheckbox ${LANG_RUSSIAN} "Включить звук и минутные сигналы"
LangString ClockRuntimeDownload ${LANG_ENGLISH} "If Microsoft Edge WebView2 Runtime is missing, the installer will download it from Microsoft. This requires an internet connection."
LangString ClockRuntimeDownload ${LANG_RUSSIAN} "Если Microsoft Edge WebView2 Runtime отсутствует, установщик загрузит его с сайта Microsoft. Для этого потребуется интернет."
LangString ClockGuideSubtitle ${LANG_ENGLISH} "Make the change in Windows, then return to the wizard."
LangString ClockGuideSubtitle ${LANG_RUSSIAN} "Выполните действие в Windows и вернитесь к мастеру."
LangString ClockSelectTitle ${LANG_ENGLISH} "Step 1 of 4. Select Cool Clock"
LangString ClockSelectTitle ${LANG_RUSSIAN} "Шаг 1 из 4. Выберите Cool Clock"
LangString ClockSelectBody ${LANG_ENGLISH} "The button below replaces the current screensaver with Cool Clock and opens Windows settings. Check the Screen saver field. Click Settings… to change the sound setting."
LangString ClockSelectBody ${LANG_RUSSIAN} "Кнопка ниже выберет установленный Cool Clock вместо текущей заставки и откроет окно Windows. Проверьте поле «Заставка / Screen saver». Для звука нажмите «Параметры… / Settings…»."
LangString ClockSelectTarget ${LANG_ENGLISH} "  In Windows: Screen saver → Cool Clock"
LangString ClockSelectTarget ${LANG_RUSSIAN} "  В окне Windows: Заставка / Screen saver → Cool Clock"
LangString ClockSelectNote ${LANG_ENGLISH} "If the window does not open: Start → Settings → Personalization → Lock screen → Screen saver. If your organization blocks this setting, contact your administrator."
LangString ClockSelectNote ${LANG_RUSSIAN} "Если окно не открылось: Пуск → Параметры → Персонализация → Экран блокировки → Заставка. Если выбор запрещён организацией, обратитесь к администратору."
LangString ClockSelectButton ${LANG_ENGLISH} "Select Cool Clock in Windows"
LangString ClockSelectButton ${LANG_RUSSIAN} "Выбрать Cool Clock в Windows"
LangString ClockIntervalTitle ${LANG_ENGLISH} "Step 2 of 4. Set the wait time"
LangString ClockIntervalTitle ${LANG_RUSSIAN} "Шаг 2 из 4. Задайте интервал"
LangString ClockIntervalBody ${LANG_ENGLISH} "In screen saver settings, set Wait to a suitable interval, such as 2 minutes. Click Apply, then OK. Keep your preferred sign-in requirement; you do not need to disable it to use the clock."
LangString ClockIntervalBody ${LANG_RUSSIAN} "В параметрах заставки задайте «Интервал / Wait»: например, 2 минуты. Нажмите «Применить / Apply», затем OK. Флажок запроса входа оставьте в нужном вам состоянии: отключать защиту для работы часов не требуется."
LangString ClockIntervalTarget ${LANG_ENGLISH} "  Wait → 2 minutes (example)$\r$\n  Save → Apply → OK"
LangString ClockIntervalTarget ${LANG_RUSSIAN} "  Интервал / Wait → 2 минуты (пример)$\r$\n  Сохранение → Применить / Apply → OK"
LangString ClockIntervalNote ${LANG_ENGLISH} "You choose the settings. Next in this wizard does not save Windows settings or verify your changes."
LangString ClockIntervalNote ${LANG_RUSSIAN} "Параметры выбираете вы. Кнопка «Далее» в мастере не сохраняет изменения в Windows и не подтверждает их проверку."
LangString ClockSettingsButton ${LANG_ENGLISH} "Open screen saver settings"
LangString ClockSettingsButton ${LANG_RUSSIAN} "Открыть параметры заставки"
LangString ClockPowerTitle ${LANG_ENGLISH} "Step 3 of 4. Check the screen timer"
LangString ClockPowerTitle ${LANG_RUSSIAN} "Шаг 3 из 4. Проверьте таймер экрана"
LangString ClockPowerBody ${LANG_ENGLISH} "In power settings, find the screen-off and sleep timers. Both must be longer than the screensaver wait time. On a laptop, check battery and plugged-in settings separately."
LangString ClockPowerBody ${LANG_RUSSIAN} "В параметрах питания найдите отключение экрана и переход в спящий режим. Оба таймера должны быть больше интервала заставки. На ноутбуке проверьте отдельно питание от батареи и от сети."
LangString ClockPowerTarget ${LANG_ENGLISH} "  Example: screensaver → 2 min; screen and sleep → 10 min"
LangString ClockPowerTarget ${LANG_RUSSIAN} "  Пример: заставка → 2 мин; экран и сон → 10 мин"
LangString ClockPowerNote ${LANG_ENGLISH} "Windows 11: System → Power & battery (or Power). Windows 10: System → Power & sleep. If the screen turns off first, you will not see the screensaver."
LangString ClockPowerNote ${LANG_RUSSIAN} "Windows 11: Система → Питание и батарея (или Питание). Windows 10: Система → Питание и спящий режим. Если экран гаснет раньше, заставку не будет видно."
LangString ClockPowerButton ${LANG_ENGLISH} "Open power settings"
LangString ClockPowerButton ${LANG_RUSSIAN} "Открыть параметры питания"
LangString ClockCheckTitle ${LANG_ENGLISH} "Step 4 of 4. Test the screensaver"
LangString ClockCheckTitle ${LANG_RUSSIAN} "Шаг 4 из 4. Проверьте запуск"
LangString ClockCheckBody ${LANG_ENGLISH} "In Windows settings, click Preview: the clock and clouds should move. Moving the mouse ends the preview. Then click Apply, OK, and leave the computer idle for the selected wait time."
LangString ClockCheckBody ${LANG_RUSSIAN} "В окне Windows нажмите «Просмотр / Preview»: часы и облака должны двигаться. Движение мыши завершит просмотр. Затем нажмите «Применить», OK и не трогайте компьютер в течение выбранного интервала."
LangString ClockCheckTarget ${LANG_ENGLISH} "  Preview → Apply → OK$\r$\n  Test automatic activation → leave the computer idle"
LangString ClockCheckTarget ${LANG_RUSSIAN} "  Просмотр / Preview → Применить / Apply → OK$\r$\n  Проверка автозапуска → дождаться интервала без действий"
LangString ClockCheckNote ${LANG_ENGLISH} "Preview and automatic activation are separate checks. If the screensaver does not start on its own, check that Cool Clock is selected, the wait time is saved, and the screen and sleep timers are set correctly."
LangString ClockCheckNote ${LANG_RUSSIAN} "Просмотр и автозапуск — отдельные проверки. Если заставка не запустилась сама, проверьте выбранный Cool Clock, сохранённый интервал и таймеры экрана и сна."
LangString ClockInstallingRuntime ${LANG_ENGLISH} "Installing Microsoft Edge WebView2 Runtime (internet connection required)…"
LangString ClockInstallingRuntime ${LANG_RUSSIAN} "Установка Microsoft Edge WebView2 Runtime (потребуется интернет)…"
LangString ClockPreservedFiles ${LANG_ENGLISH} "Additional files preserved: $BackupDir"
LangString ClockPreservedFiles ${LANG_RUSSIAN} "Дополнительные файлы сохранены: $BackupDir"
LangString ClockCannotRegister ${LANG_ENGLISH} "Could not save the sound setting or register the application. Installation will be rolled back."
LangString ClockCannotRegister ${LANG_RUSSIAN} "Не удалось сохранить выбранный звук или регистрацию программы. Установка будет отменена."
LangString ClockCannotRestoreSettings ${LANG_ENGLISH} "Could not fully restore the previous registry settings. Check the sound setting in Cool Clock after restoring it."
LangString ClockCannotRestoreSettings ${LANG_RUSSIAN} "Не удалось полностью восстановить прежние настройки реестра. Проверьте звук в параметрах Cool Clock после восстановления."
LangString ClockCannotRollback ${LANG_ENGLISH} "Could not remove the new version for rollback. The previous version is saved in $BackupDir. Installation is incomplete."
LangString ClockCannotRollback ${LANG_RUSSIAN} "Не удалось убрать новую версию для отката. Предыдущая версия сохранена в $BackupDir. Установка не завершена."
LangString ClockCannotRestoreVersion ${LANG_ENGLISH} "Could not restore the previous version. Its files are saved in $BackupDir."
LangString ClockCannotRestoreVersion ${LANG_RUSSIAN} "Не удалось восстановить предыдущую версию. Её файлы сохранены в $BackupDir."
LangString ClockRuntimeUnavailable ${LANG_ENGLISH} "WebView2 Runtime is unavailable. Check your internet connection and try installing again. The previous Cool Clock version is unchanged."
LangString ClockRuntimeUnavailable ${LANG_RUSSIAN} "WebView2 Runtime недоступен. Проверьте подключение к интернету и повторите установку. Предыдущая версия Cool Clock не изменена."
LangString ClockInstallIncomplete ${LANG_ENGLISH} "Installation is incomplete. Check free disk space and access to $LOCALAPPDATA."
LangString ClockInstallIncomplete ${LANG_RUSSIAN} "Установка не завершена. Проверьте свободное место и доступ к папке $LOCALAPPDATA."
LangString ClockOpenSettingsFailed ${LANG_ENGLISH} "Open Start → Settings → Personalization → Lock screen → Screen saver. Select Cool Clock, set the wait time, and click Apply."
LangString ClockOpenSettingsFailed ${LANG_RUSSIAN} "Откройте Пуск → Параметры → Персонализация → Экран блокировки → Заставка. Выберите Cool Clock, задайте интервал и нажмите «Применить»."
LangString ClockSelectFailed ${LANG_ENGLISH} "Could not open the Cool Clock selection. Check that $INSTDIR\Cool Clock.scr exists and reinstall if needed."
LangString ClockSelectFailed ${LANG_RUSSIAN} "Не удалось открыть выбор Cool Clock. Проверьте, что файл $INSTDIR\Cool Clock.scr существует, и повторите установку при необходимости."
LangString ClockOpenPowerFailed ${LANG_ENGLISH} "Open Start → Settings → System → Power. Set screen-off and sleep times longer than the screensaver wait time."
LangString ClockOpenPowerFailed ${LANG_RUSSIAN} "Откройте Пуск → Параметры → Система → Питание. Выберите время отключения экрана и сна больше интервала заставки."
LangString ClockUninstallIncomplete ${LANG_ENGLISH} "Uninstallation is incomplete: some files or registry entries could not be accessed. Close Cool Clock and try uninstalling again."
LangString ClockUninstallIncomplete ${LANG_RUSSIAN} "Удаление не завершено: часть файлов или записей реестра недоступна. Закройте Cool Clock и повторите удаление."

; Default to English; regional formats do not determine the interface language.
!macro SelectLanguage
  System::Call 'kernel32::GetUserDefaultUILanguage() i .r0'
  !ifdef COOL_CLOCK_TEST_UI_LANGUAGE
    ; Test-only builds exercise both language branches without changing Windows settings.
    StrCpy $0 ${COOL_CLOCK_TEST_UI_LANGUAGE}
  !endif
  IntOp $0 $0 & 0x3FF
  StrCpy $LANGUAGE ${LANG_ENGLISH}
  ; IntOp returns decimal text; compare numerically with the hex language ID.
  ${If} $0 = 0x19
    StrCpy $LANGUAGE ${LANG_RUSSIAN}
  ${EndIf}
!macroend

; LangString selection is not refreshed until .onInit returns.
!macro InitError EN RU
  ${If} $LANGUAGE == ${LANG_RUSSIAN}
    MessageBox MB_ICONSTOP "${RU}" /SD IDOK
  ${Else}
    MessageBox MB_ICONSTOP "${EN}" /SD IDOK
  ${EndIf}
!macroend

!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\CoolClock"
!macro RegisterValue INDEX MASK TYPE KEY NAME VALUE
  ClearErrors
  ReadReg${TYPE} $Old${INDEX} HKCU "${KEY}" "${NAME}"
  StrCpy $Present${INDEX} 1
  IfErrors 0 +2
    StrCpy $Present${INDEX} 0
  ClearErrors
  WriteReg${TYPE} HKCU "${KEY}" "${NAME}" "${VALUE}"
  IfErrors registry_failed
  IntOp $RegChanged $RegChanged | ${MASK}
!macroend

!macro RestoreValue INDEX MASK TYPE KEY NAME
  IntOp $0 $RegChanged & ${MASK}
  ${If} $0 != 0
    ClearErrors
    ${If} $Present${INDEX} == 1
      WriteReg${TYPE} HKCU "${KEY}" "${NAME}" "$Old${INDEX}"
    ${Else}
      DeleteRegValue HKCU "${KEY}" "${NAME}"
    ${EndIf}
    ${If} ${Errors}
      StrCpy $RegRestoreFailed 1
    ${EndIf}
  ${EndIf}
!macroend

!macro RemoveOwned ROOT
  !insertmacro RemoveCommon "${ROOT}"
  Delete "${ROOT}\Cool Clock.scr"
  Delete "${ROOT}\WebView2Loader.dll"
  Delete "${ROOT}\ClockIcon.ico"
  Delete "${ROOT}\Uninstall.exe"
  Delete "${ROOT}\.cool-clock-install"
  RMDir "${ROOT}"
!macroend

; Initialization exit codes: 10 OS, 11 CPU, 12 mutex, 13 concurrent setup, 14 unsafe folder, 15 foreign folder, 16 uninstall path.
!macro Ownership PREFIX
Function ${PREFIX}DetectPlatform
  ${IfNot} ${AtLeastWin10}
    !insertmacro InitError "Cool Clock requires Windows 10 or Windows 11 (x64 or ARM64)." "Для Cool Clock требуется Windows 10 или Windows 11 (x64 или ARM64)."
    SetErrorLevel 10
    Abort
  ${EndIf}
  ${If} ${IsNativeARM64}
    StrCpy $NativeArch "arm64"
  ${ElseIf} ${IsNativeAMD64}
    StrCpy $NativeArch "x64"
  ${Else}
    !insertmacro InitError "Cool Clock supports only 64-bit Windows: Intel/AMD (x64) or ARM64." "Cool Clock поддерживает только 64-разрядную Windows: Intel/AMD (x64) или ARM64."
    SetErrorLevel 11
    Abort
  ${EndIf}
FunctionEnd

Function ${PREFIX}LockInstaller
  System::Call 'kernel32::CreateMutexW(p 0, i 0, w "Local\CoolClockInstaller") p .r0 ?e'
  Pop $1
  StrCpy $Mutex $0
  ${If} $Mutex == 0
    !insertmacro InitError "Could not start the Cool Clock installer. Please try again." "Не удалось запустить установщик Cool Clock. Повторите попытку."
    SetErrorLevel 12
    Abort
  ${EndIf}
  ${If} $1 == 183
    !insertmacro InitError "The Cool Clock installer is already running." "Установщик Cool Clock уже запущен."
    SetErrorLevel 13
    Abort
  ${EndIf}
FunctionEnd

Function ${PREFIX}CheckOwnership
  ; A marker identifies an installation; a junction must never be traversed.
  System::Call 'kernel32::GetFileAttributesW(w "$INSTDIR") i .r0'
  ${If} $0 == -1
    Return
  ${EndIf}
  IntOp $1 $0 & 0x410
  ${If} $1 != 16
    !insertmacro InitError "The folder $INSTDIR is not a regular Cool Clock folder. Installation stopped." "Папка $INSTDIR не является обычной папкой Cool Clock. Установка остановлена."
    SetErrorLevel 14
    Abort
  ${EndIf}
  ClearErrors
  FileOpen $0 "$INSTDIR\.cool-clock-install" r
  IfErrors foreign
  FileRead $0 $1
  FileClose $0
  ${If} $1 == "CoolClockInstaller-v1"
    Return
  ${EndIf}
foreign:
  !insertmacro InitError "The folder $INSTDIR already exists and does not belong to this installer. Back up its contents and rename it before installing." "Папка $INSTDIR уже существует и не принадлежит этому установщику. Сохраните её содержимое и переименуйте папку перед установкой."
  SetErrorLevel 15
  Abort
FunctionEnd

Function ${PREFIX}CloseClock
  IfFileExists "$INSTDIR\Cool Clock.scr" 0 close_done
  ; Only execute our embedded helper, never the previously installed binary.
  InitPluginsDir
  ClearErrors
  SetOutPath "$PLUGINSDIR"
  ${If} $NativeArch == "arm64"
    File /oname=CloseClock.exe "${PAYLOAD_DIR}\arm64\Cool Clock.scr"
  ${Else}
    File /oname=CloseClock.exe "${PAYLOAD_DIR}\x64\Cool Clock.scr"
  ${EndIf}
  IfErrors close_failed
  ExecWait '"$PLUGINSDIR\CloseClock.exe" --close-existing "$INSTDIR\Cool Clock.scr"' $0
  IfErrors close_failed
  ${If} $0 == 0
    Return
  ${EndIf}
close_failed:
  MessageBox MB_ICONSTOP "$(ClockCannotClose)" /SD IDOK
  SetErrorLevel 1
  Abort
close_done:
FunctionEnd
!macroend
!insertmacro Ownership ""
!insertmacro Ownership "un."

Function .onInit
  !insertmacro SelectLanguage
  SetShellVarContext current
  SetRegView 64
  StrCpy $INSTDIR "$LOCALAPPDATA\Cool Clock"
  Call LockInstaller
  Call DetectPlatform
  Call CheckOwnership
  StrCpy $Sound 0
  ReadRegDWORD $Sound HKCU "Software\CoolClock" "SoundEnabled"
  ${If} $Sound != 1
    StrCpy $Sound 0
  ${EndIf}
FunctionEnd

Function SoundPage
  !insertmacro MUI_HEADER_TEXT "$(ClockSoundTitle)" "$(ClockSoundDescription)"
  nsDialogs::Create 1018
  Pop $0
  ${NSD_CreateCheckbox} 0 8u 100% 20u "$(ClockSoundCheckbox)"
  Pop $SoundCheckbox
  ${NSD_SetState} $SoundCheckbox $Sound
  ${NSD_CreateLabel} 0 40u 100% 50u "$(ClockRuntimeDownload)"
  Pop $0
  nsDialogs::Show
FunctionEnd

Function SoundLeave
  ${NSD_GetState} $SoundCheckbox $Sound
FunctionEnd

; These pages guide the user; silent installation never opens Settings or changes desktop policy.
!macro GuidePage FUNCTION TITLE BODY TARGET NOTE BUTTON ACTION
Function ${FUNCTION}
  !insertmacro MUI_HEADER_TEXT "${TITLE}" "$(ClockGuideSubtitle)"
  nsDialogs::Create 1018
  Pop $0
  ${NSD_CreateLabel} 0 0 100% 44u "${BODY}"
  Pop $0
  ${NSD_CreateLabel} 0 49u 100% 25u "${TARGET}"
  Pop $0
  SetCtlColors $0 "005ECC" "EAF3FF"
  ${NSD_CreateButton} 0 82u 100% 22u "${BUTTON}"
  Pop $0
  ${NSD_OnClick} $0 ${FUNCTION}Open
  ${NSD_CreateLabel} 0 111u 100% 29u "${NOTE}"
  Pop $0
  !if "${FUNCTION}" == "SelectGuidePage"
    GetDlgItem $0 $HWNDPARENT 3
    EnableWindow $0 0
  !endif
  nsDialogs::Show
FunctionEnd
Function ${FUNCTION}Open
  Pop $0
  Call ${ACTION}
FunctionEnd
!macroend

!insertmacro GuidePage SelectGuidePage "$(ClockSelectTitle)" \
  "$(ClockSelectBody)" \
  "$(ClockSelectTarget)" \
  "$(ClockSelectNote)" \
  "$(ClockSelectButton)" SelectSaver

!insertmacro GuidePage IntervalGuidePage "$(ClockIntervalTitle)" \
  "$(ClockIntervalBody)" \
  "$(ClockIntervalTarget)" \
  "$(ClockIntervalNote)" \
  "$(ClockSettingsButton)" OpenSettings

!insertmacro GuidePage PowerGuidePage "$(ClockPowerTitle)" \
  "$(ClockPowerBody)" \
  "$(ClockPowerTarget)" \
  "$(ClockPowerNote)" \
  "$(ClockPowerButton)" OpenPowerSettings

!insertmacro GuidePage CheckGuidePage "$(ClockCheckTitle)" \
  "$(ClockCheckBody)" \
  "$(ClockCheckTarget)" \
  "$(ClockCheckNote)" \
  "$(ClockSettingsButton)" OpenSettings

Section "Cool Clock"
  Call CheckOwnership
  Call CloseClock
  ; Stage on the same volume so publication is a directory rename.
  ClearErrors
  GetTempFileName $StageDir "$LOCALAPPDATA"
  IfErrors failed
  Delete "$StageDir"
  CreateDirectory "$StageDir"
  IfErrors failed
  SetOutPath "$StageDir"
  ${If} $NativeArch == "arm64"
    File "${PAYLOAD_DIR}\arm64\Cool Clock.scr"
    File "${PAYLOAD_DIR}\arm64\WebView2Loader.dll"
  ${Else}
    File "${PAYLOAD_DIR}\x64\Cool Clock.scr"
    File "${PAYLOAD_DIR}\x64\WebView2Loader.dll"
  ${EndIf}
  IfErrors stage_failed
  ExecWait '"$StageDir\Cool Clock.scr" --check-runtime' $0
  IfErrors runtime_install
  ${If} $0 == 0
    Goto runtime_ready
  ${EndIf}
runtime_install:
  DetailPrint "$(ClockInstallingRuntime)"
  InitPluginsDir
  SetOutPath "$PLUGINSDIR"
  ClearErrors
  File "${PAYLOAD_DIR}\MicrosoftEdgeWebview2Setup.exe"
  IfErrors stage_failed
  ExecWait '"$PLUGINSDIR\MicrosoftEdgeWebview2Setup.exe" /silent /install' $0
  ClearErrors
  ExecWait '"$StageDir\Cool Clock.scr" --check-runtime' $0
  IfErrors runtime_failed
  ${If} $0 != 0
    Goto runtime_failed
  ${EndIf}
runtime_ready:
  ClearErrors
  !insertmacro InstallCommon "$StageDir"
  SetOutPath "$StageDir"
  File "${PAYLOAD_DIR}\ClockIcon.ico"
  WriteUninstaller "$StageDir\Uninstall.exe"
  FileOpen $0 "$StageDir\.cool-clock-install" w
  FileWrite $0 "CoolClockInstaller-v1"
  FileClose $0
  IfErrors stage_failed
  Call CloseClock
  Call CheckOwnership
  ; Never retain a current working directory inside a directory being renamed.
  SetOutPath "$TEMP"
  IfFileExists "$INSTDIR\*" 0 publish
  ClearErrors
  GetTempFileName $BackupDir "$LOCALAPPDATA"
  IfErrors stage_failed
  Delete "$BackupDir"
  Rename "$INSTDIR" "$BackupDir"
  IfErrors stage_failed
publish:
  ClearErrors
  Rename "$StageDir" "$INSTDIR"
  IfErrors rollback
  StrCpy $RegChanged 0
  !insertmacro RegisterValue 0 1 DWORD "Software\CoolClock" "SoundEnabled" '$Sound'
  !insertmacro RegisterValue 1 2 Str "${UNINSTALL_KEY}" "DisplayName" 'Cool Clock'
  !insertmacro RegisterValue 2 4 Str "${UNINSTALL_KEY}" "DisplayVersion" '${VERSION}'
  !insertmacro RegisterValue 3 8 Str "${UNINSTALL_KEY}" "InstallLocation" '$INSTDIR'
  !insertmacro RegisterValue 4 16 Str "${UNINSTALL_KEY}" "DisplayIcon" '$INSTDIR\ClockIcon.ico'
  !insertmacro RegisterValue 5 32 Str "${UNINSTALL_KEY}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  !insertmacro RegisterValue 6 64 DWORD "${UNINSTALL_KEY}" "NoModify" '1'
  !insertmacro RegisterValue 7 128 DWORD "${UNINSTALL_KEY}" "NoRepair" '1'
  ${If} $BackupDir != ""
    !insertmacro RemoveOwned "$BackupDir"
    IfFileExists "$BackupDir\*" 0 +2
      DetailPrint "$(ClockPreservedFiles)"
  ${EndIf}
  Goto done
registry_failed:
  MessageBox MB_ICONSTOP "$(ClockCannotRegister)" /SD IDOK
  StrCpy $RegRestoreFailed 0
  !insertmacro RestoreValue 0 1 DWORD "Software\CoolClock" "SoundEnabled"
  !insertmacro RestoreValue 1 2 Str "${UNINSTALL_KEY}" "DisplayName"
  !insertmacro RestoreValue 2 4 Str "${UNINSTALL_KEY}" "DisplayVersion"
  !insertmacro RestoreValue 3 8 Str "${UNINSTALL_KEY}" "InstallLocation"
  !insertmacro RestoreValue 4 16 Str "${UNINSTALL_KEY}" "DisplayIcon"
  !insertmacro RestoreValue 5 32 Str "${UNINSTALL_KEY}" "UninstallString"
  !insertmacro RestoreValue 6 64 DWORD "${UNINSTALL_KEY}" "NoModify"
  !insertmacro RestoreValue 7 128 DWORD "${UNINSTALL_KEY}" "NoRepair"
  DeleteRegKey /ifempty HKCU "${UNINSTALL_KEY}"
  DeleteRegKey /ifempty HKCU "Software\CoolClock"
  ${If} $RegRestoreFailed == 1
    MessageBox MB_ICONSTOP "$(ClockCannotRestoreSettings)" /SD IDOK
  ${EndIf}
  ClearErrors
  Rename "$INSTDIR" "$StageDir"
  ${If} ${Errors}
    MessageBox MB_ICONSTOP "$(ClockCannotRollback)" /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
rollback:
  ${If} $BackupDir != ""
    ClearErrors
    Rename "$BackupDir" "$INSTDIR"
    ${If} ${Errors}
      MessageBox MB_ICONSTOP "$(ClockCannotRestoreVersion)" /SD IDOK
    ${EndIf}
  ${EndIf}
  Goto stage_failed
runtime_failed:
  MessageBox MB_ICONSTOP "$(ClockRuntimeUnavailable)" /SD IDOK
stage_failed:
  SetOutPath "$TEMP"
  !insertmacro RemoveOwned "$StageDir"
failed:
  MessageBox MB_ICONSTOP "$(ClockInstallIncomplete)" /SD IDOK
  SetErrorLevel 1
  Abort
done:
SectionEnd

Function Preview
  Exec '"$INSTDIR\Cool Clock.scr" --preview'
FunctionEnd

Function OpenSettings
  ClearErrors
  ${DisableX64FSRedirection}
  Exec '"$SYSDIR\control.exe" desk.cpl,screensaver,@screensaver'
  ${EnableX64FSRedirection}
  ${If} ${Errors}
    MessageBox MB_ICONEXCLAMATION "$(ClockOpenSettingsFailed)"
  ${EndIf}
FunctionEnd

Function SelectSaver
  ClearErrors
  ${DisableX64FSRedirection}
  Exec '"$SYSDIR\rundll32.exe" desk.cpl,InstallScreenSaver "$INSTDIR\Cool Clock.scr"'
  ${EnableX64FSRedirection}
  ${If} ${Errors}
    MessageBox MB_ICONEXCLAMATION "$(ClockSelectFailed)"
  ${EndIf}
FunctionEnd

Function OpenPowerSettings
  ClearErrors
  ExecShell "open" "ms-settings:powersleep"
  ${If} ${Errors}
    MessageBox MB_ICONEXCLAMATION "$(ClockOpenPowerFailed)"
  ${EndIf}
FunctionEnd

Function un.onInit
  !insertmacro SelectLanguage
  SetShellVarContext current
  SetRegView 64
  Call un.LockInstaller
  Call un.DetectPlatform
  ; Never trust a manually overridden uninstaller directory.
  StrCmp $INSTDIR "$LOCALAPPDATA\Cool Clock" uninstall_path_valid
    SetErrorLevel 16
    !insertmacro InitError "Cool Clock can only be uninstalled from its installation folder." "Удаление возможно только из папки установленного Cool Clock."
    Abort
uninstall_path_valid:
  Call un.CheckOwnership
FunctionEnd

Section "Uninstall"
  Call un.CheckOwnership
  Call un.CloseClock
  SetOutPath "$TEMP"
  ClearErrors
  Delete "$INSTDIR\Cool Clock.scr"
  Delete "$INSTDIR\WebView2Loader.dll"
  IfErrors uninstall_failed
  !insertmacro RemoveCommon "$INSTDIR"
  Delete "$INSTDIR\ClockIcon.ico"
  IfErrors uninstall_failed
  StrCpy $0 ""
  ReadRegStr $0 HKCU "Control Panel\Desktop" "SCRNSAVE.EXE"
  ClearErrors
  ; StrCmp is case-insensitive; never alter another screensaver or security policy.
  StrCmp $0 "$INSTDIR\Cool Clock.scr" 0 +2
    DeleteRegValue HKCU "Control Panel\Desktop" "SCRNSAVE.EXE"
  IfErrors uninstall_failed
  ; Missing registration is valid when retrying a partially completed removal.
  System::Call 'advapi32::RegOpenKeyExW(p 0x80000001, w "${UNINSTALL_KEY}", i 0, i 0x20119, *p .r1) i .r0'
  ${If} $0 == 0
    System::Call 'advapi32::RegCloseKey(p r1)'
    DeleteRegKey HKCU "${UNINSTALL_KEY}"
    IfErrors uninstall_failed
  ${ElseIf} $0 != 2
    Goto uninstall_failed
  ${EndIf}
  Delete "$INSTDIR\Uninstall.exe"
  IfErrors uninstall_failed
  Delete "$INSTDIR\.cool-clock-install"
  IfErrors uninstall_failed
  ; Preserve any additional files and directories the user placed here.
  RMDir "$INSTDIR"
  ClearErrors
  Goto uninstall_done
uninstall_failed:
  MessageBox MB_ICONSTOP "$(ClockUninstallIncomplete)" /SD IDOK
  SetErrorLevel 1
  Abort
uninstall_done:
  ; Keep user sound preferences and the shared WebView2 Runtime.
SectionEnd
