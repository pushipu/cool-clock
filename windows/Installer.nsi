Unicode true
RequestExecutionLevel user
!include MUI2.nsh
!include nsDialogs.nsh
!include LogicLib.nsh
!include x64.nsh
!include WinVer.nsh
!include "${PAYLOAD_DIR}\payload-files.nsh"

Name "Cool Clock"
OutFile "${OUTPUT_FILE}"
InstallDir "$LOCALAPPDATA\Cool Clock"
SetCompressor /SOLID lzma
!define MUI_ICON "${PAYLOAD_DIR}\ClockIcon.ico"
!define MUI_UNICON "${PAYLOAD_DIR}\ClockIcon.ico"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TEXT "Установщик добавит Cool Clock для текущего пользователя.$\r$\n$\r$\nРабота и предпросмотр на настоящем Windows-компьютере ещё не проверены.$\r$\n$\r$\nДля продолжения нажмите Далее."
!insertmacro MUI_PAGE_WELCOME
Page custom SoundPage SoundLeave
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "Открыть выбор заставки Windows"
!define MUI_FINISHPAGE_RUN_FUNCTION OpenSettings
!define MUI_FINISHPAGE_RUN_NOTCHECKED
!define MUI_FINISHPAGE_SHOWREADME
!define MUI_FINISHPAGE_SHOWREADME_TEXT "Посмотреть Cool Clock"
!define MUI_FINISHPAGE_SHOWREADME_FUNCTION Preview
!define MUI_FINISHPAGE_SHOWREADME_NOTCHECKED
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
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
    MessageBox MB_ICONSTOP "Для Cool Clock требуется Windows 10 или Windows 11 (x64 или ARM64)." /SD IDOK
    SetErrorLevel 10
    Abort
  ${EndIf}
  ${If} ${IsNativeARM64}
    StrCpy $NativeArch "arm64"
  ${ElseIf} ${IsNativeAMD64}
    StrCpy $NativeArch "x64"
  ${Else}
    MessageBox MB_ICONSTOP "Cool Clock поддерживает только 64-разрядную Windows: Intel/AMD (x64) или ARM64." /SD IDOK
    SetErrorLevel 11
    Abort
  ${EndIf}
FunctionEnd

Function ${PREFIX}LockInstaller
  System::Call 'kernel32::CreateMutexW(p 0, i 0, w "Local\CoolClockInstaller") p .r0 ?e'
  Pop $1
  StrCpy $Mutex $0
  ${If} $Mutex == 0
    MessageBox MB_ICONSTOP "Не удалось запустить установщик Cool Clock. Повторите попытку." /SD IDOK
    SetErrorLevel 12
    Abort
  ${EndIf}
  ${If} $1 == 183
    MessageBox MB_ICONSTOP "Установщик Cool Clock уже запущен." /SD IDOK
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
  ${If} $1 != 0x10
    MessageBox MB_ICONSTOP "Папка $INSTDIR не является обычной папкой Cool Clock. Установка остановлена." /SD IDOK
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
  MessageBox MB_ICONSTOP "Папка $INSTDIR уже существует и не принадлежит этому установщику. Сохраните её содержимое и переименуйте папку перед установкой." /SD IDOK
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
  MessageBox MB_ICONSTOP "Не удалось закрыть работающий Cool Clock. Закройте заставку и её предпросмотр, затем повторите попытку." /SD IDOK
  SetErrorLevel 1
  Abort
close_done:
FunctionEnd
!macroend
!insertmacro Ownership ""
!insertmacro Ownership "un."

Function .onInit
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
  !insertmacro MUI_HEADER_TEXT "Звук заставки" "Эту настройку можно изменить в параметрах Cool Clock."
  nsDialogs::Create 1018
  Pop $0
  ${NSD_CreateCheckbox} 0 8u 100% 20u "Включить звук и минутные сигналы"
  Pop $SoundCheckbox
  ${NSD_SetState} $SoundCheckbox $Sound
  ${NSD_CreateLabel} 0 40u 100% 50u "Если Microsoft Edge WebView2 Runtime отсутствует, установщик загрузит его с сайта Microsoft. Для этого потребуется интернет."
  Pop $0
  nsDialogs::Show
FunctionEnd

Function SoundLeave
  ${NSD_GetState} $SoundCheckbox $Sound
FunctionEnd

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
  DetailPrint "Установка Microsoft Edge WebView2 Runtime (потребуется интернет)…"
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
      DetailPrint "Дополнительные файлы сохранены: $BackupDir"
  ${EndIf}
  Goto done
registry_failed:
  MessageBox MB_ICONSTOP "Не удалось сохранить выбранный звук или регистрацию программы. Установка будет отменена." /SD IDOK
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
    MessageBox MB_ICONSTOP "Не удалось полностью восстановить прежние настройки реестра. Проверьте звук в параметрах Cool Clock после восстановления." /SD IDOK
  ${EndIf}
  ClearErrors
  Rename "$INSTDIR" "$StageDir"
  ${If} ${Errors}
    MessageBox MB_ICONSTOP "Не удалось убрать новую версию для отката. Предыдущая версия сохранена в $BackupDir. Установка не завершена." /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
rollback:
  ${If} $BackupDir != ""
    ClearErrors
    Rename "$BackupDir" "$INSTDIR"
    ${If} ${Errors}
      MessageBox MB_ICONSTOP "Не удалось восстановить предыдущую версию. Её файлы сохранены в $BackupDir." /SD IDOK
    ${EndIf}
  ${EndIf}
  Goto stage_failed
runtime_failed:
  MessageBox MB_ICONSTOP "WebView2 Runtime недоступен. Проверьте подключение к интернету и повторите установку. Предыдущая версия Cool Clock не изменена." /SD IDOK
stage_failed:
  SetOutPath "$TEMP"
  !insertmacro RemoveOwned "$StageDir"
failed:
  MessageBox MB_ICONSTOP "Установка не завершена. Проверьте свободное место и доступ к папке $LOCALAPPDATA." /SD IDOK
  SetErrorLevel 1
  Abort
done:
SectionEnd

Function Preview
  Exec '"$INSTDIR\Cool Clock.scr" --preview'
FunctionEnd

Function OpenSettings
  ${DisableX64FSRedirection}
  Exec '"$SYSDIR\rundll32.exe" desk.cpl,InstallScreenSaver "$INSTDIR\Cool Clock.scr"'
  ${EnableX64FSRedirection}
FunctionEnd

Function un.onInit
  SetShellVarContext current
  SetRegView 64
  Call un.LockInstaller
  Call un.DetectPlatform
  ; Never trust a manually overridden uninstaller directory.
  StrCmp $INSTDIR "$LOCALAPPDATA\Cool Clock" uninstall_path_valid
    SetErrorLevel 16
    MessageBox MB_ICONSTOP "Удаление возможно только из папки установленного Cool Clock." /SD IDOK
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
  MessageBox MB_ICONSTOP "Удаление не завершено: часть файлов или записей реестра недоступна. Закройте Cool Clock и повторите удаление." /SD IDOK
  SetErrorLevel 1
  Abort
uninstall_done:
  ; Keep user sound preferences and the shared WebView2 Runtime.
SectionEnd
