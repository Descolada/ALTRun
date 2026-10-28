#Import Ks { Clr, A_OSType, A_DirSeparator, Clipboard, Image, Http, Crypt, Font }
#Include Lib/Platform.ahk
#Include Lib/ProcessRunner.ahk
#Include Lib/DesktopIntegration.ahk
#Include Lib/MacInputIntegration.ahk
#Include Lib/MacDesktop.ahk
#Include Lib/MacApp.ahk
#Include Lib/MacUpdate.ahk
#Include Lib/MacOcr.ahk
#Include Lib/MacSpotlight.ahk
; --- Lib ---
#Include Lib/JSON.ahk
#Include Lib/Logger.ahk
#Include Lib/Util.ahk
#Include Lib/TextTools.ahk
#Include Lib/DelimitedText.ahk
#Include Lib/Kanji.ahk
#Include Lib/Everything.ahk
#Include Lib/Units.ahk
#Include Lib/ClipboardData.ahk
#Include Lib/Dialogs.ahk
#Include Lib/HttpGet.ahk
#Include Lib/FolderWatcher.ahk
#Include Lib/WindowsRecent.ahk

; --- Src/Core ---
#Include Src/Core/App.ahk
#Include Src/Core/I18n.ahk
#Include Src/Core/AppSettings.ahk
#Include Src/Core/SchemaMigration.ahk
#Include Src/Core/SearchQuery.ahk
#Include Src/Core/ResultItem.ahk
#Include Src/Core/FuzzyMatcher.ahk
#Include Src/Core/BackgroundWork.ahk
#Include Src/Core/Knowledge.ahk
#Include Src/Core/Usage.ahk
#Include Src/Core/ActionCatalog.ahk
#Include Src/Core/ProviderRegistry.ahk
#Include Src/Core/FileIndex.ahk

; --- Src/UI ---
#Include Src/UI/ThemeManager.ahk
#if WINDOWS || OSX
#Include Src/UI/TypeAhead.ahk
#endif
#if WINDOWS
#Include Src/UI/SearchInputLanguage.ahk
#Include Src/UI/WindowFade.ahk
#endif
#Include Src/UI/Portable/IconCache.ahk
#Include Src/UI/Portable/LauncherCanvas.ahk
#Include Src/UI/Portable/SearchWindow.ahk
#Include Src/UI/Portable/LargeType.ahk
#Include Src/UI/Portable/Hud.ahk
#Include Src/UI/Portable/ItemEditor.ahk
#if WINDOWS
#Include Src/UI/HotkeyBox.ahk
#else
#Include Src/UI/Portable/HotkeyBox.ahk
#endif
#Include Src/UI/Portable/PreferencesWindow.ahk
#Include Src/UI/ResultActions.ahk

; --- Src/Providers ---
#Include Src/Providers/ClipboardProvider.ahk
#Include Src/Providers/ApplicationProvider.ahk
#Include Src/Providers/CustomCommandProvider.ahk
#Include Src/Providers/SnippetProvider.ahk
#Include Src/Providers/SystemProvider.ahk
#Include Src/Providers/CalculatorProvider.ahk
#Include Src/Providers/WebSearchProvider.ahk
#Include Src/Providers/BookmarkProvider.ahk
#Include Src/Providers/FileSearchProvider.ahk
#Include Src/Providers/TerminalProvider.ahk
#Include Src/Providers/WindowProvider.ahk
#Include Src/Providers/RecentProvider.ahk
#Include Src/Providers/ScriptProvider.ahk
#Include Src/Providers/HelpProvider.ahk
#Include Src/Providers/ShortcutsProvider.ahk

; --- Src/Extensions ---
#Include Src/Extensions/SnippetExpander.ahk
#Include Src/Extensions/QuickSwitch.ahk
#Include Src/Extensions/AutoDate.ahk
#Include Src/Extensions/CapsLockSwitch.ahk
#Include Src/Extensions/CapsLockHelper.ahk
#Include Src/Extensions/TendonProfile.ahk
#Include Src/Extensions/PTToolsWindow.ahk
#Include Src/Extensions/UpdateChecker.ahk
#Include Src/Extensions/CurrencyRates.ahk
#Include Src/Extensions/SelectionActions.ahk


