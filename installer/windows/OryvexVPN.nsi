; OryvexVPN Setup, custom design: the app's black canvas and one blue, a dark welcome and finish,
; and one "Make it yours" page instead of the usual wizard steps.
;
; Build: installer\windows\build-installer.ps1   (or makensis /DSOURCE_DIR=... OryvexVPN.nsi)

!include "common.nsh"
!include "MUI2.nsh"

; App palette (apps/shared/lib/src/ui/theme.dart)
!define OX_INK   "06080C"
!define OX_TILE  "0E1218"
!define OX_TEXT  "F4F6FA"
!define OX_MUTED "A7B0BF"
!define OX_ICE   "8CC2FF"

ShowInstDetails nevershow
ShowUninstDetails nevershow

; --- Modern UI, recoloured --------------------------------------------------------------------
!define MUI_ICON "assets\app.ico"
!define MUI_UNICON "assets\app.ico"
!define MUI_BGCOLOR "${OX_INK}"
!define MUI_TEXTCOLOR "${OX_TEXT}"
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_RIGHT
!define MUI_HEADERIMAGE_BITMAP "assets\header.bmp"
!define MUI_HEADERIMAGE_UNBITMAP "assets\header.bmp"
!define MUI_HEADER_TRANSPARENT_TEXT
!define MUI_WELCOMEFINISHPAGE_BITMAP "assets\welcome.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "assets\welcome.bmp"
!define MUI_INSTFILESPAGE_COLORS "${OX_TEXT} ${OX_TILE}"
!define MUI_INSTFILESPAGE_PROGRESSBAR "colored"
!define MUI_ABORTWARNING
!define MUI_ABORTWARNING_TEXT "Stop installing OryvexVPN?"
!define MUI_UNABORTWARNING
!define MUI_CUSTOMFUNCTION_GUIINIT OxGuiInit
!define MUI_CUSTOMFUNCTION_UNGUIINIT un.OxGuiInit

Var OxDlg
Var OxDirField
Var OxDesktopCb
Var OxStartCb
Var OxLoginCb
Var OxTrayCb
Var OxFontLabel
Var OxFontBody

; --- Pages ----------------------------------------------------------------------------------
!define MUI_WELCOMEPAGE_TITLE "Welcome to OryvexVPN"
!define MUI_WELCOMEPAGE_TEXT "A way out of filtered networks: WireGuard, MASQUE and Tor, with the exit country you choose.$\r$\n$\r$\nSetup installs OryvexVPN into Program Files and puts it on your desktop. It takes about a minute.$\r$\n$\r$\nClick Next to make it yours."
!insertmacro MUI_PAGE_WELCOME

Page custom OxOptionsPage OxOptionsLeave

!define MUI_PAGE_HEADER_TEXT "Installing OryvexVPN"
!define MUI_PAGE_HEADER_SUBTEXT "Copying the app, the core and Tor. Hang tight."
!define MUI_PAGE_CUSTOMFUNCTION_SHOW OxDarkInner
!insertmacro MUI_PAGE_INSTFILES

!define MUI_FINISHPAGE_TITLE "You're all set."
!define MUI_FINISHPAGE_TEXT "OryvexVPN is installed.$\r$\n$\r$\nOpen it and press the big button to connect. Auto finds a route that works on your network."
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "Open OryvexVPN now"
!define MUI_FINISHPAGE_RUN_FUNCTION OxLaunchApp
!define MUI_FINISHPAGE_NOREBOOTSUPPORT
!define MUI_PAGE_CUSTOMFUNCTION_SHOW OxFinishShow
!insertmacro MUI_PAGE_FINISH

!define MUI_PAGE_CUSTOMFUNCTION_SHOW un.OxConfirmShow
!insertmacro MUI_UNPAGE_CONFIRM
!define MUI_PAGE_CUSTOMFUNCTION_SHOW un.OxDarkInner
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

VIAddVersionKey "ProductName" "OryvexVPN"
VIAddVersionKey "CompanyName" "Muvixo"
VIAddVersionKey "FileDescription" "OryvexVPN Setup"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Created by Muvixo. AGPL-3.0."

; --- Look ------------------------------------------------------------------------------------

; Windows draws themed checkboxes with black text whatever colour is asked for; the classic
; style honours SetCtlColors, so dark pages turn the theme off for their checkboxes.
!macro OX_DARK_CHECKBOX HWND
  System::Call 'uxtheme::SetWindowTheme(p ${HWND}, w " ", w " ")'
  SetCtlColors ${HWND} ${OX_TEXT} ${OX_INK}
!macroend

!macro OX_GUI_INIT UN
Function ${UN}OxGuiInit
  SetCtlColors $HWNDPARENT ${OX_TEXT} ${OX_INK}
  ; Hide the etched line and the empty branding text along the bottom.
  GetDlgItem $0 $HWNDPARENT 1035
  ShowWindow $0 ${SW_HIDE}
  GetDlgItem $0 $HWNDPARENT 1036
  ShowWindow $0 ${SW_HIDE}
  GetDlgItem $0 $HWNDPARENT 1028
  ShowWindow $0 ${SW_HIDE}
  ; Header title in the app's ice blue.
  GetDlgItem $0 $HWNDPARENT 1037
  SetCtlColors $0 ${OX_TEXT} transparent
  GetDlgItem $0 $HWNDPARENT 1038
  SetCtlColors $0 ${OX_MUTED} transparent
  CreateFont $OxFontLabel "Segoe UI" 8 700
  CreateFont $OxFontBody "Segoe UI" 10 400
FunctionEnd

; The inner page area of the stock pages (progress, uninstall confirm).
Function ${UN}OxDarkInner
  FindWindow $0 "#32770" "" $HWNDPARENT
  SetCtlColors $0 ${OX_TEXT} ${OX_INK}
  GetDlgItem $1 $0 1006
  ${If} $1 <> 0
    SetCtlColors $1 ${OX_TEXT} transparent
  ${EndIf}
FunctionEnd
!macroend
!insertmacro OX_GUI_INIT ""
!insertmacro OX_GUI_INIT "un."

Function OxFinishShow
  !insertmacro OX_DARK_CHECKBOX $mui.FinishPage.Run
FunctionEnd

Function un.OxConfirmShow
  Call un.OxDarkInner
  FindWindow $0 "#32770" "" $HWNDPARENT
  ${ForEach} $2 1000 1029 + 1
    GetDlgItem $1 $0 $2
    ${If} $1 <> 0
      SetCtlColors $1 ${OX_TEXT} transparent
    ${EndIf}
  ${Next}
  GetDlgItem $1 $0 1019
  ${If} $1 <> 0
    SetCtlColors $1 ${OX_TEXT} ${OX_TILE}
  ${EndIf}
FunctionEnd

; --- "Make it yours": folder, shortcuts and startup on one page -------------------------------

!macro OX_SECTION_LABEL TOP TEXT
  ${NSD_CreateLabel} 0 ${TOP} 100% 10u "${TEXT}"
  Pop $0
  SetCtlColors $0 ${OX_ICE} transparent
  SendMessage $0 ${WM_SETFONT} $OxFontLabel 1
!macroend

!macro OX_CHECK VAR TOP LEFT TEXT STATE
  ${NSD_CreateCheckbox} ${LEFT} ${TOP} 280u 12u "${TEXT}"
  Pop ${VAR}
  SendMessage ${VAR} ${WM_SETFONT} $OxFontBody 1
  !insertmacro OX_DARK_CHECKBOX ${VAR}
  ${If} ${STATE} == 1
    ${NSD_Check} ${VAR}
  ${EndIf}
!macroend

Function OxOptionsPage
  !insertmacro MUI_HEADER_TEXT "Make it yours" "Where OryvexVPN goes and how it starts."
  nsDialogs::Create 1018
  Pop $OxDlg
  ${If} $OxDlg == error
    Abort
  ${EndIf}
  SetCtlColors $OxDlg ${OX_TEXT} ${OX_INK}

  !insertmacro OX_SECTION_LABEL 0u "INSTALL TO"
  ${NSD_CreateText} 0 12u 232u 14u "$INSTDIR"
  Pop $OxDirField
  SetCtlColors $OxDirField ${OX_TEXT} ${OX_TILE}
  SendMessage $OxDirField ${WM_SETFONT} $OxFontBody 1
  ${NSD_CreateButton} 238u 11u 62u 16u "Browse..."
  Pop $0
  ${NSD_OnClick} $0 OxBrowse

  !insertmacro OX_SECTION_LABEL 36u "SHORTCUTS"
  !insertmacro OX_CHECK $OxDesktopCb 48u 0 "Put an OryvexVPN icon on the desktop" $OxWantDesktop
  !insertmacro OX_CHECK $OxStartCb 62u 0 "Add OryvexVPN to the Start menu" $OxWantStartMenu

  !insertmacro OX_SECTION_LABEL 84u "STARTUP"
  !insertmacro OX_CHECK $OxLoginCb 96u 0 "Launch OryvexVPN when I sign in to Windows" $OxWantLogin
  ${NSD_OnClick} $OxLoginCb OxLoginToggled
  !insertmacro OX_CHECK $OxTrayCb 110u 12u "Start quietly in the tray" $OxWantTray
  Call OxLoginToggled

  ${NSD_CreateLabel} 0 128u 100% 12u "Free software under the AGPL-3.0. You can change all of this later in Settings."
  Pop $0
  SetCtlColors $0 ${OX_MUTED} transparent

  ; The next click installs, so say so.
  GetDlgItem $0 $HWNDPARENT 1
  SendMessage $0 ${WM_SETTEXT} 0 "STR:Install"

  nsDialogs::Show
FunctionEnd

Function OxLoginToggled
  ${NSD_GetState} $OxLoginCb $0
  ${If} $0 == ${BST_CHECKED}
    EnableWindow $OxTrayCb 1
  ${Else}
    EnableWindow $OxTrayCb 0
  ${EndIf}
FunctionEnd

Function OxBrowse
  ${NSD_GetText} $OxDirField $0
  nsDialogs::SelectFolderDialog "Choose where to install OryvexVPN" "$0"
  Pop $0
  ${If} $0 != error
    StrCpy $INSTDIR $0
    Call OxNormalizeInstDir
    ${NSD_SetText} $OxDirField "$INSTDIR"
  ${EndIf}
FunctionEnd

Function OxOptionsLeave
  ${NSD_GetText} $OxDirField $0
  StrCpy $1 $0 2 1
  ${If} $0 == ""
  ${OrIf} $1 != ":\"
    MessageBox MB_ICONEXCLAMATION "Pick a full folder path, for example C:\Program Files\OryvexVPN."
    Abort
  ${EndIf}
  StrCpy $INSTDIR $0
  Call OxNormalizeInstDir
  ${NSD_SetText} $OxDirField "$INSTDIR"
  ${NSD_GetState} $OxDesktopCb $OxWantDesktop
  ${NSD_GetState} $OxStartCb $OxWantStartMenu
  ${NSD_GetState} $OxLoginCb $OxWantLogin
  ${NSD_GetState} $OxTrayCb $OxWantTray
FunctionEnd

; --- Sections (all hidden: the page above makes the choices) -----------------------------------

Section "-OryvexVPN" SecMain
  !insertmacro OX_INSTALL_FILES
SectionEnd

Section "-Shortcuts" SecShortcuts
  ${If} $OxWantDesktop == ${BST_CHECKED}
    !insertmacro OX_INSTALL_DESKTOP
  ${EndIf}
  ${If} $OxWantStartMenu == ${BST_CHECKED}
    !insertmacro OX_INSTALL_STARTMENU
  ${EndIf}
  ${If} $OxWantLogin == ${BST_CHECKED}
    !insertmacro OX_INSTALL_LOGIN $OxWantTray
  ${Else}
    DeleteRegValue HKCU "${OX_RUN_KEY}" "${OX_APP}"
  ${EndIf}
SectionEnd

Function .onInit
  Call OxInit
FunctionEnd

Function un.onInit
  Call un.OxInit
  Call un.OxAskRemoveSettings
FunctionEnd

Section "Uninstall"
  !insertmacro OX_UNINSTALL
SectionEnd
