Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "x64.nsh"
!include "nsDialogs.nsh"

!define APP_VERSION "1.3.9"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\AppLimiter"

Name "App Limiter"
OutFile "..\dist\AppLimiter-Setup-${APP_VERSION}.exe"
InstallDir "$PROGRAMFILES64\AppLimiter"
RequestExecutionLevel user
SetCompressor /SOLID lzma
VIProductVersion "1.3.9.0"
VIAddVersionKey "ProductName" "App Limiter"
VIAddVersionKey "FileDescription" "App Limiter installer"
VIAddVersionKey "FileVersion" "${APP_VERSION}"
VIAddVersionKey "ProductVersion" "${APP_VERSION}"
VIAddVersionKey "LegalCopyright" ""

!define MUI_ABORTWARNING
!define MUI_ICON "..\assets\AppLimiter.ico"
!define MUI_UNICON "..\assets\AppLimiter.ico"
!define MUI_DIRECTORYPAGE_TEXT_TOP "Choose a dedicated folder directly under Program Files. The service files must be protected from standard users."
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
Page custom OptionsPageCreate OptionsPageLeave
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Var OwnerIdentity
Var PowerShell
Var DesktopShortcut
Var StartWithWindows
Var DesktopCheckbox
Var StartupCheckbox
Var InstallSucceeded
Var LaunchedByParent

Function LaunchPanel
  SetRegView 64
  ReadRegStr $0 HKLM "${UNINSTALL_KEY}" "InstallLocation"
  ${If} $0 != ""
    IfFileExists "$0\AppLimiter.exe" 0 launch_done
      Exec '"$0\AppLimiter.exe" --show'
      IfErrors 0 launch_done
        MessageBox MB_ICONEXCLAMATION "Setup completed, but App Limiter could not open. Launch it from the Start Menu."
  ${EndIf}
launch_done:
FunctionEnd

Function .onGUIEnd
  IfSilent gui_done
  ${If} $InstallSucceeded == 1
  ${AndIf} $LaunchedByParent != 1
    Call LaunchPanel
  ${EndIf}
gui_done:
FunctionEnd

Function OptionsPageCreate
  !insertmacro MUI_HEADER_TEXT "Installation options" "Choose how App Limiter starts for your Windows account."
  nsDialogs::Create 1018
  Pop $0
  ${If} $0 == error
    Abort
  ${EndIf}
  ${NSD_CreateCheckbox} 0 12u 100% 14u "Create a desktop shortcut"
  Pop $DesktopCheckbox
  ${If} $DesktopShortcut == 1
    ${NSD_Check} $DesktopCheckbox
  ${EndIf}
  ${NSD_CreateCheckbox} 0 38u 100% 14u "Start App Limiter when Windows starts"
  Pop $StartupCheckbox
  ${If} $StartWithWindows == 1
    ${NSD_Check} $StartupCheckbox
  ${EndIf}
  nsDialogs::Show
FunctionEnd

Function OptionsPageLeave
  ${NSD_GetState} $DesktopCheckbox $DesktopShortcut
  ${NSD_GetState} $StartupCheckbox $StartWithWindows
FunctionEnd

; ExecShellWait reports launch failures but does not expose the elevated
; process's exit code. Keep its process handle so silent deployment can fail
; when the actual installation or removal fails.
!macro ElevatedProcessWait executable arguments result
  System::Store S
  !if "${NSIS_PTR_SIZE}" > 4
    !define /ReDef APP_SHELLEXECUTEINFO_SIZE 14 * ${NSIS_PTR_SIZE}
  !else
    !define /ReDef APP_SHELLEXECUTEINFO_SIZE 60
  !endif
  System::Call '*(&i${APP_SHELLEXECUTEINFO_SIZE})i.r0'
  System::Call '*$0(i ${APP_SHELLEXECUTEINFO_SIZE},i 0x40,p $hwndparent,t "runas",t $\'${executable}$\',t $\'${arguments}$\',t "",i 1)p.r0'
  System::Call 'shell32::ShellExecuteEx(t)(pr0)i.r1'
  ${If} $1 == 0
    Push -1
  ${Else}
    System::Call '*$0(is,i,p,p,p,p,p,p,p,p,p,p,p,p,p.r1)'
    System::Call 'kernel32::WaitForSingleObject(pr1,i-1)'
    System::Call 'kernel32::GetExitCodeProcess(pr1,*i.s)'
    System::Call 'kernel32::CloseHandle(pr1)'
  ${EndIf}
  System::Free $0
  System::Store L
  Pop ${result}
  !undef APP_SHELLEXECUTEINFO_SIZE
!macroend

Function ReadOwnerIdentity
  InitPluginsDir
  SetOutPath "$PLUGINSDIR"
  File /oname=owner_identity.ps1 "owner_identity.ps1"
  nsExec::ExecToStack '"$PowerShell" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\owner_identity.ps1"'
  Pop $0
  Pop $OwnerIdentity
  ${If} $0 != "0"
    MessageBox MB_ICONSTOP "Could not identify the Windows account for this installation."
    Abort
  ${EndIf}
FunctionEnd

Function .onInit
  StrCpy $InstallSucceeded 0
  StrCpy $LaunchedByParent 0
  StrCpy $DesktopShortcut 1
  StrCpy $StartWithWindows 1
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "App Limiter requires Windows 11 x64 (Intel or AMD)."
    Abort
  ${EndIf}
  StrCpy $PowerShell "$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
  System::Call 'shell32::IsUserAnAdmin() i .r0'
  ${If} $0 == 0
    Call ReadOwnerIdentity
    StrCpy $1 ""
    IfSilent 0 +2
      StrCpy $1 "/S"
    !insertmacro ElevatedProcessWait "$EXEPATH" '/owner="$OwnerIdentity" /launchedByParent=1 $1' $2
    ${If} $2 != 0
      IfSilent install_elevation_failed 0
        MessageBox MB_ICONSTOP "Setup could not complete with administrator permissions."
    install_elevation_failed:
      SetErrorLevel 2
    ${Else}
      IfSilent install_parent_done
        Call LaunchPanel
    install_parent_done:
    ${EndIf}
    Quit
  ${EndIf}
  ${GetParameters} $0
  ${GetOptions} $0 "/owner=" $OwnerIdentity
  ${GetOptions} $0 "/launchedByParent=" $LaunchedByParent
  ${If} $OwnerIdentity == ""
    Call ReadOwnerIdentity
  ${EndIf}
  SetRegView 64
  ReadRegStr $0 HKLM "${UNINSTALL_KEY}" "InstallLocation"
  ${If} $0 != ""
    StrCpy $INSTDIR $0
  ${EndIf}
FunctionEnd

Section "Install"
  SetRegView 64
  InitPluginsDir
  SetOutPath "$PLUGINSDIR\stage"
  File "..\install.ps1"
  File "run_install.ps1"
  SetOutPath "$PLUGINSDIR\stage\dist\AppLimiter"
  File "..\dist\AppLimiter\AppLimiter.exe"
  File "..\dist\AppLimiter\app_limiter_service.exe"
  File "..\dist\AppLimiter\AppLimiter.ico"
  File "..\dist\AppLimiter\WinDivert.dll"
  File "..\dist\AppLimiter\WinDivert64.sys"
  File "..\dist\AppLimiter\LICENSE"

  DetailPrint "Installing files and configuring the App Limiter service..."
  nsExec::ExecToStack '"$PowerShell" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\stage\run_install.ps1" -Destination "$INSTDIR" -OwnerIdentity "$OwnerIdentity" -DesktopShortcut $DesktopShortcut -StartWithWindows $StartWithWindows'
  Pop $0
  Pop $1
  ${If} $0 != "0"
    DetailPrint "$1"
    IfSilent +2 0
      MessageBox MB_ICONSTOP "App Limiter installation failed: $1"
    SetErrorLevel 2
    Abort
  ${EndIf}

  SetOutPath "$INSTDIR"
  File "..\uninstall.ps1"
  File "run_uninstall.ps1"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayName" "App Limiter"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "OwnerIdentity" "$OwnerIdentity"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\AppLimiter.ico"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "${UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoRepair" 1
  StrCpy $InstallSucceeded 1
SectionEnd

Function un.onInit
  StrCpy $INSTDIR $EXEDIR
  SetRegView 64
  StrCpy $PowerShell "$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
  System::Call 'shell32::IsUserAnAdmin() i .r0'
  ${If} $0 == 0
    StrCpy $1 ""
    IfSilent 0 +2
      StrCpy $1 "/S"
    !insertmacro ElevatedProcessWait "$INSTDIR\Uninstall.exe" "$1" $2
    ${If} $2 != 0
      IfSilent uninstall_elevation_failed 0
        MessageBox MB_ICONSTOP "Removal could not complete with administrator permissions."
    uninstall_elevation_failed:
      SetErrorLevel 2
    ${Else}
      ReadRegStr $3 HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "AppLimiter"
      StrCpy $4 '"$INSTDIR\AppLimiter.exe" --startup'
      ${If} $3 == $4
        DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "AppLimiter"
      ${Else}
        StrCpy $4 '"$INSTDIR\AppLimiter.exe"'
        ${If} $3 == $4
          DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "AppLimiter"
        ${EndIf}
      ${EndIf}
    ${EndIf}
    Quit
  ${EndIf}
FunctionEnd

Section "Uninstall"
  StrCpy $INSTDIR $EXEDIR
  SetRegView 64
  DetailPrint "Stopping the App Limiter service and removing its files..."
  nsExec::ExecToStack '"$PowerShell" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$INSTDIR\run_uninstall.ps1" -Destination "$INSTDIR"'
  Pop $0
  Pop $1
  ${If} $0 != "0"
    DetailPrint "$1"
    IfSilent +2 0
      MessageBox MB_ICONSTOP "Could not stop and remove the App Limiter service: $1"
    SetErrorLevel 2
    Abort
  ${EndIf}
  Delete "$INSTDIR\AppLimiter.exe"
  Delete "$INSTDIR\app_limiter_service.exe"
  Delete "$INSTDIR\AppLimiter.ico"
  Delete "$INSTDIR\WinDivert.dll"
  Delete "$INSTDIR\WinDivert64.sys"
  Delete "$INSTDIR\LICENSE"
  Delete "$INSTDIR\install.log"
  Delete "$INSTDIR\uninstall.log"
  Delete "$INSTDIR\uninstall.ps1"
  Delete "$INSTDIR\run_uninstall.ps1"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKLM "${UNINSTALL_KEY}"
SectionEnd
