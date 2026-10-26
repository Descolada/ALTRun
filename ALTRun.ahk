#ErrorStdOut
;===============================================================================
; ALTRun - An effective launcher for Windows, in the spirit of Alfred for macOS
; https://github.com/zhugecaomao/ALTRun
;-------------------------------------------------------------------------------
; This file only lists the modules and starts the app - see Src\Core\App.ahk
; for the startup sequence.
;
; Project layout:
;   Lib\            General-purpose libraries, nothing ALTRun-specific
;   Src\Core\       App startup, settings + migration, search model, ranking, actions
;   Src\UI\         Search window, preferences window, large type, themes, icons
;   Src\Providers\  Search features: clipboard history, applications, custom commands,
;                   snippets, system commands, calculator, web search, file search, terminal
;   Src\Extensions\ Features outside the search window: snippet auto-expansion,
;                   dialog quick switch, Ctrl+D date, PT Tools, update checker
;   Resources\      Data files shipped with ALTRun (Kanji.txt, Pinyin.txt, built-in themes, Lang\ translations, Icons\, ALTRun.ico)
;   Themes\         Optional custom themes (<Name>.json)
;   Data\           Generated at runtime: app index, learned ranking, clipboard history
;===============================================================================
;@Ahk2Exe-SetName ALTRun
;@Ahk2Exe-SetDescription ALTRun
;@Ahk2Exe-Set Comments, An effective launcher for Windows
;@Ahk2Exe-SetVersion 2026.10.26.4
;@Ahk2Exe-SetCopyright Copyright (c) 2013-2026 zhugecaomao
;@Ahk2Exe-SetOrigFilename ALTRun.exe
;@Ahk2Exe-SetMainIcon Resources\ALTRun.ico
; (compiling: see .github/workflows/release.yml; SetVersion must match App.Version, which a test checks)

#Requires AutoHotkey v2.0
#SingleInstance Off                     ; when one is already running, hand over to it (see App.HandOff)
#NoTrayIcon
#Warn All, StdOut
#Warn Experimental, Off

#Include ALTRun.Modules.ahk

App.Start()
