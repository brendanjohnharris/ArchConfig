  -- Base
import XMonad
import System.Directory
import System.IO (hPutStrLn)
import System.Exit (exitSuccess)
import qualified XMonad.StackSet as W

    -- Actions
import XMonad.Actions.CopyWindow (kill1)
import XMonad.Actions.CycleWS (Direction1D(..), moveTo, shiftTo, WSType(..), nextScreen, prevScreen, nextWS, prevWS)
import XMonad.Actions.GridSelect
import XMonad.Actions.MouseResize
import XMonad.Actions.Promote
import XMonad.Actions.RotSlaves (rotSlavesDown, rotAllDown)
import XMonad.Actions.WindowGo (runOrRaise)
import XMonad.Actions.WithAll (sinkAll, killAll)
import qualified XMonad.Actions.Search as S
import XMonad.Actions.CopyWindow (copyToAll)

    -- Data
import Data.Char (isSpace, toUpper)
import Data.Maybe (fromJust)
import Data.Monoid
import Data.Maybe (isJust)
import Data.Tree
import qualified Data.Map as M

    -- Hooks
import XMonad.Hooks.DynamicLog (dynamicLogWithPP, wrap, xmobarPP, xmobarColor, shorten, PP(..))
import XMonad.Hooks.EwmhDesktops  -- for some fullscreen events, also for xcomposite in obs.
import XMonad.Hooks.ManageDocks (avoidStruts, docksEventHook, manageDocks, ToggleStruts(..))
import XMonad.Hooks.ManageHelpers (isFullscreen, doFullFloat, doCenterFloat)
import XMonad.Hooks.ServerMode
import XMonad.Hooks.SetWMName
import XMonad.Hooks.WorkspaceHistory

    -- Layouts
import XMonad.Layout.Accordion
import XMonad.Layout.GridVariants (Grid(Grid))
import XMonad.Layout.SimplestFloat
import XMonad.Layout.Spiral
import XMonad.Layout.ResizableTile
import XMonad.Layout.Tabbed
import XMonad.Layout.ThreeColumns

    -- Layouts modifiers
import XMonad.Layout.LayoutModifier
import XMonad.Layout.LimitWindows (limitWindows, increaseLimit, decreaseLimit)
import XMonad.Layout.Magnifier
import XMonad.Layout.MultiToggle (mkToggle, single, EOT(EOT), (??))
import XMonad.Layout.MultiToggle.Instances (StdTransformers(NBFULL, MIRROR, NOBORDERS))
import XMonad.Layout.NoBorders
import XMonad.Layout.Renamed
import XMonad.Layout.ShowWName
import XMonad.Layout.Simplest
import XMonad.Layout.Spacing
import XMonad.Layout.SubLayouts
import XMonad.Layout.WindowArranger (windowArrange, WindowArrangerMsg(..))
import XMonad.Layout.WindowNavigation
import qualified XMonad.Layout.ToggleLayouts as T (toggleLayouts, ToggleLayout(Toggle))
import qualified XMonad.Layout.MultiToggle as MT (Toggle(..))
import XMonad.Layout.IndependentScreens (countScreens)

   -- Utilities
import XMonad.Util.Dmenu
import XMonad.Util.EZConfig (additionalKeysP)
import XMonad.Util.NamedScratchpad
import XMonad.Util.Run (runProcessWithInput, safeSpawn, spawnPipe)
import XMonad.Util.SpawnOnce
import XMonad.Util.Cursor


-- import XMonad.Actions.SpawnOn

   -- ColorScheme module (SET ONLY ONE!)
      -- Possible choice are:
      -- DoomOne
      -- Dracula
      -- GruvboxDark
      -- MonokaiPro
      -- Nord
      -- OceanicNext
      -- Palenight
      -- SolarizedDark
      -- SolarizedLight
      -- TomorrowNight
import Colors.DoomOne

myFont :: String
myFont = "xft:SauceCodePro Nerd Font:regular:size=9:antialias=true:hinting=true"

myModMask :: KeyMask
myModMask = mod4Mask        -- Sets modkey to super/windows key

myTerminal :: String
myTerminal = "alacritty"    -- Sets default terminal

myBrowser :: String
myBrowser = "firefox -P default-release"  -- Sets firefox as browser

myEditor :: String
myEditor = myTerminal ++ " -e vim "    -- Sets vim as editor

myBorderWidth :: Dimension
myBorderWidth = 2           -- Sets border width for windows

myNormColor :: String       -- Border color of normal windows
myNormColor   = colorBack   -- This variable is imported from Colors.THEME

myFocusColor :: String      -- Border color of focused windows
myFocusColor  = colorFore -- color15     -- This variable is imported from Colors.THEME

windowCount :: X (Maybe String)
windowCount = gets $ Just . show . length . W.integrate' . W.stack . W.workspace . W.current . windowset

-- setting colors for tabs layout and tabs sublayout.
myTabTheme = def { XMonad.Layout.Tabbed.fontName            = "xft:Ubuntu:bold:size=9:antialias=true:hinting=true"
                 , XMonad.Layout.Tabbed.activeColor         = colorFore
                 , XMonad.Layout.Tabbed.inactiveColor       = colorBack
                 , XMonad.Layout.Tabbed.activeBorderColor   = colorFore
                 , XMonad.Layout.Tabbed.inactiveBorderColor = colorBack
                 , XMonad.Layout.Tabbed.activeTextColor     = colorBack
                 , XMonad.Layout.Tabbed.inactiveTextColor   = color16
                 }

-- Theme for showWName which prints current workspace when you change workspaces.
myShowWNameTheme :: SWNConfig
myShowWNameTheme = def
    { swn_font              = "xft:Ubuntu:bold:size=60"
    , swn_fade              = 1.0
    , swn_bgcolor           = colorBack
    , swn_color             = colorFore
    }

myStartupHook :: X ()
myStartupHook = do
    -- spawn "/usr/bin/prime-offload"
    spawn "killall conky"   -- kill current conky on each restart
    spawn "killall trayer"  -- kill current trayer on each restart

    spawnOnce "lxsession"
    spawnOnce "picom"
    spawnOnce "dunst"

    spawn ("sleep 2 && conky -c $HOME/.config/.conkyrc")
    spawn ("sleep 2 && trayer --edge top --align right --widthtype request --padding 6 --SetDockType true --SetPartialStrut true --expand true --monitor 1 --transparent true --alpha 0 " ++ colorTrayer ++ " --height 30 --distance 1") -- Effective height is height + 2*distance

    spawnOnce "nm-applet"
    spawnOnce "blueman-applet"
    spawnOnce "volumeicon"
    spawnOnce "xsettingsd"

    -- spawnOnce "xargs xwallpaper --stretch < ~/.cache/wall"
    spawnOnce "$(watch -n 600 'feh --recursive --randomize --bg-fill $HOME/.wallpapers/')"
    -- spawnOnce "~/.fehbg &"  -- set last saved feh wallpaper
    -- spawnOnce "feh --randomize --bg-fill ~/wallpapers/*"  -- feh set random wallpaper
    -- spawnOnce "nitrogen --restore &"   -- if you prefer nitrogen to feh
    setWMName "LG3D"
    setDefaultCursor xC_left_ptr
    --spawnOnce "optimus-manager-qt"

    -- Spawn workspace-specific apps
    -- spawnOn "mail" "betterbird"

myColorizer :: Window -> Bool -> X (String, String)
myColorizer = colorRangeFromClassName
                  (0x28,0x2c,0x34) -- lowest inactive bg
                  (0x28,0x2c,0x34) -- highest inactive bg
                  (0xc7,0x92,0xea) -- active bg
                  (0xc0,0xa7,0x9a) -- inactive fg
                  (0x28,0x2c,0x34) -- active fg

-- gridSelect menu layout
mygridConfig :: p -> GSConfig Window
mygridConfig colorizer = (buildDefaultGSConfig myColorizer)
    { gs_cellheight   = 40
    , gs_cellwidth    = 200
    , gs_cellpadding  = 6
    , gs_originFractX = 0.5
    , gs_originFractY = 0.5
    , gs_font         = myFont
    }

spawnSelected' :: [(String, String)] -> X ()
spawnSelected' lst = gridselect conf lst >>= flip whenJust spawn
    where conf = def
                   { gs_cellheight   = 40
                   , gs_cellwidth    = 200
                   , gs_cellpadding  = 6
                   , gs_originFractX = 0.5
                   , gs_originFractY = 0.5
                   , gs_font         = myFont
                   }

myAppGrid = [ ("Nemo", "nemo")
                 , ("Firefox", "firefox -P default-release")
                 , ("Okular", "okular")
                 , ("Cantata", "cantata")
                 , ("Inkscape", "inkscape")
                 , ("Gimp", "gimp")
                 , ("Audacity", "audacity")
                 , ("Kdenlive", "kdenlive")
                 , ("LibreOffice Impress", "loimpress")
                 , ("LibreOffice Writer", "lowriter")
                 ]

myScratchPads :: [NamedScratchpad]
myScratchPads = [ NS "terminal" spawnTerm findTerm manageTerm
                , NS "notepad" spawnNote findNote manageNote
                , NS "music" spawnMus findMus manageMus
                , NS "calculator" spawnCalc findCalc manageCalc
                , NS "browser" spawnBrowser findBrowser manageBrowser
                , NS "emoji" spawnEmoji findEmoji manageEmoji
                , NS "peek" spawnPeek findPeek managePeek
                , NS "files" spawnFiles findFiles manageFiles
                ]
  where
    spawnTerm  = myTerminal ++ " -t scratchpad"
    findTerm   = title =? "scratchpad"
    manageTerm = customFloating $ W.RationalRect l t w h
               where
                 h = 0.9
                 w = 0.9
                 t = 0.95 -h
                 l = 0.95 -w
    spawnNote  = myTerminal ++ " -t notepad -e tnote -a"
    findNote   = title =? "notepad"
    manageNote = customFloating $ W.RationalRect l t w h
               where
                 h = 0.9
                 w = 0.9
                 t = 0.95 -h
                 l = 0.95 -w
    spawnMus  = "cantata"
    findMus   = className =? "cantata"
    manageMus = customFloating $ W.RationalRect l t w h
               where
                 h = 0.9
                 w = 0.9
                 t = 0.95 -h
                 l = 0.95 -w
    spawnCalc  = "qalculate-gtk"
    findCalc   = className =? "Qalculate-gtk"
    manageCalc = customFloating $ W.RationalRect l t w h
               where
                 h = 0.5
                 w = 0.4
                 t = 0.75 -h
                 l = 0.70 -w
    spawnBrowser  = "firefox --no-remotes -P scratchpad --class browserscratchpad"
    findBrowser   = className =? "browserscratchpad"
    manageBrowser = customFloating $ W.RationalRect l t w h
               where
                 h = 0.9
                 w = 0.9
                 t = 0.95 -h
                 l = 0.95 -w
    spawnEmoji  = "gnome-characters"
    findEmoji   = className =? "org.gnome.Characters" -- xprop | grep WM_CLASS to find the class name
    manageEmoji = customFloating $ W.RationalRect l t w h
               where
                 h = 0.9
                 w = 0.35
                 t = 0.95 -h
                 l = 0.99 -w
    spawnPeek   = "peek"
    findPeek    = className =? "Peek"
    managePeek  = customFloating $ W.RationalRect l t w h
               where
                 h = 1
                 w = 1
                 t = 1 -h
                 l = 1 -w
    spawnFiles   = "nemo --name=filescratchpad --class=filescratchpad"
    findFiles    = className =? "filescratchpad"
    manageFiles  = customFloating $ W.RationalRect l t w h
               where
                 h = 0.9
                 w = 0.9
                 t = 0.95 -h
                 l = 0.95 -w

--Makes setting the spacingRaw simpler to write. The spacingRaw module adds a configurable amount of space around windows.
mySpacing :: Integer -> l a -> XMonad.Layout.LayoutModifier.ModifiedLayout Spacing l a
mySpacing i = spacingRaw False (Border i i i i) True (Border i i i i) True

-- Below is a variation of the above except no borders are applied
-- if fewer than two windows. So a single window has no gaps.
mySpacing' :: Integer -> l a -> XMonad.Layout.LayoutModifier.ModifiedLayout Spacing l a
mySpacing' i = spacingRaw True (Border i i i i) True (Border i i i i) True

-- Defining a bunch of layouts, many that I don't use.
-- limitWindows n sets maximum number of windows displayed for layout.
-- mySpacing n sets the gap size around the windows.
tall     = renamed [Replace "tall"]
           $ smartBorders
           $ windowNavigation
           $ addTabsBottom shrinkText myTabTheme
           $ subLayout [] (smartBorders Simplest)
           $ limitWindows 12
           $ mySpacing 4
           $ ResizableTall 1 (3/100) (1/2) []
tabs     = renamed [Replace "tabs"]
           -- I cannot add spacing to this layout because it will
           -- add spacing between window and tabs which looks bad.
           $ tabbedBottom shrinkText myTabTheme
-- magnify  = renamed [Replace "magnify"]
--            $ smartBorders
--            $ windowNavigation
--            $ addTabsBottom shrinkText myTabTheme
--            $ subLayout [] (smartBorders Simplest)
--            $ magnifier
--            $ limitWindows 12
--            $ mySpacing 8
--            $ ResizableTall 1 (3/100) (1/2) []
-- monocle  = renamed [Replace "monocle"]
--            $ smartBorders
--            $ windowNavigation
--            $ addTabsBottom shrinkText myTabTheme
--            $ subLayout [] (smartBorders Simplest)
--            $ limitWindows 20 Full
floats   = renamed [Replace "floats"]
           $ smartBorders
           $ limitWindows 20 simplestFloat
grid     = renamed [Replace "grid"]
           $ smartBorders
           $ windowNavigation
           $ addTabsBottom shrinkText myTabTheme
           $ subLayout [] (smartBorders Simplest)
           $ limitWindows 12
           $ mySpacing 4
           $ mkToggle (single MIRROR)
           $ Grid (16/10)
-- spirals  = renamed [Replace "spirals"]
--            $ smartBorders
--            $ windowNavigation
--            $ addTabsBottom shrinkText myTabTheme
--            $ subLayout [] (smartBorders Simplest)
--            $ mySpacing' 8
--            $ spiral (6/7)
threeCol = renamed [Replace "threeCol"]
           $ smartBorders
           $ windowNavigation
           $ addTabsBottom shrinkText myTabTheme
           $ subLayout [] (smartBorders Simplest)
           $ limitWindows 7
           $ ThreeCol 1 (3/100) (1/2)
threeRow = renamed [Replace "threeRow"]
           $ smartBorders
           $ windowNavigation
           $ addTabsBottom shrinkText myTabTheme
           $ subLayout [] (smartBorders Simplest)
           $ limitWindows 7
           -- Mirror takes a layout and rotates it by 90 degrees.
           -- So we are applying Mirror to the ThreeCol layout.
           $ Mirror
           $ ThreeCol 1 (3/100) (1/2)
-- tallAccordion  = renamed [Replace "tallAccordion"]
--            $ Accordion
-- wideAccordion  = renamed [Replace "wideAccordion"]
--            $ Mirror Accordion

-- The layout hook
myLayoutHook = avoidStruts $ mouseResize $ windowArrange $ T.toggleLayouts floats
               $ mkToggle (NBFULL ?? NOBORDERS ?? EOT) myDefaultLayout
             where
               myDefaultLayout =     withBorder myBorderWidth tall
                                 ||| noBorders tabs
                                --  ||| magnify
                                --  ||| noBorders monocle
                                 ||| floats
                                 ||| grid
                                --  ||| spirals
                                 ||| threeCol
                                 ||| threeRow
                                --  ||| tallAccordion
                                --  ||| wideAccordion

-- myWorkspaces = [" 1 ", " 2 ", " 3 ", " 4 ", " 5 ", " 6 ", " 7 ", " 8 ", " 9 "]
myWorkspaces = [" chat ", " mail ", " www ", " dev", " note ", " read ", " sys ", " gfx ", " misc "]
myWorkspaceIndices = M.fromList $ zipWith (,) myWorkspaces [1..] -- (,) == \x y -> (x,y)

clickable ws = "<action=xdotool key super+"++show i++">"++ws++"</action>"
    where i = fromJust $ M.lookup ws myWorkspaceIndices

myManageHook :: XMonad.Query (Data.Monoid.Endo WindowSet)
myManageHook = composeAll
     -- 'doFloat' forces a window to float.  Useful for dialog boxes and such.
     -- using 'doShift ( myWorkspaces !! 7)' sends program to workspace 8!
     -- I'm doing it this way because otherwise I would have to write out the full
     -- name of my workspaces and the names would be very long if using clickable workspaces.
     [ className =? "confirm"         --> doFloat
     , className =? "file_progress"   --> doFloat
     , className =? "dialog"          --> doFloat
     , className =? "download"        --> doFloat
     , className =? "error"           --> doFloat
     , className =? "Gimp"            --> doFloat
     , className =? "notification"    --> doFloat
     , className =? "pinentry-gtk-2"  --> doFloat
     , className =? "splash"          --> doFloat
     , className =? "toolbar"         --> doFloat
     , className =? "Makie"           --> doFloat
     , className =? "Yad"             --> doCenterFloat
     , title =? "Oracle VM VirtualBox Manager"  --> doFloat
     -- , title =? "Mozilla Firefox"     --> doShift ( myWorkspaces !! 1 )
     -- , className =? "Brave-browser"   --> doShift ( myWorkspaces !! 1 )
     --, className =? "mpv"             --> doShift ( myWorkspaces !! 7 )
     -- , className =? "Gimp"            --> doShift ( myWorkspaces !! 8 )
     --, className =? "VirtualBox Manager" --> doShift  ( myWorkspaces !! 4 )
     , (className =? "firefox" <&&> resource =? "Dialog") --> doFloat  -- Float Firefox Dialog
     , isFullscreen -->  doFullFloat
     , title =? "Picture-in-Picture" --> doFloat
     , title=? "Picture-in-Picture" --> doF copyToAll
     ] <+> namedScratchpadManageHook myScratchPads

-- START_KEYS
myKeys :: [(String, X ())]
myKeys =
    -- KB_GROUP Xmonad
        [ ("M-C-r", spawn "xmonad --recompile")       -- Recompiles xmonad
        , ("M-S-r", spawn "xmonad --restart")         -- Restarts xmonad
        , ("M-S-q", io exitSuccess)                   -- Quits xmonad
        , ("M-S-p t", spawn "~/.local/bin/transparenton") -- Set picom to transparent
        , ("M-S-p o", spawn "~/.local/bin/transparentoff") -- Set picom to opaque
        , ("M-S-b", spawn "feh --recursive --randomize --bg-fill $HOME/.wallpapers/") -- Changes backgroundB

    -- KB_GROUP Get Help
        , ("M-S-/", spawn "~/.xmonad/xmonad_keys.sh") -- Get list of keybindings

    -- KB_GROUP Run Prompt
        --, ("M-S-<Return>", spawn "dmenu_run -i -fn 'Ubuntu:weight=bold:pixelsize=26:antialias=true:hinting=true' -p \"Run: \"") -- Dmenu
        , ("M-<Return>", spawn "rofi -show drun") -- Dmenu

    -- KB_GROUP Useful programs to have a keybinding for launch
        , ("M-S-<Return>", spawn (myTerminal))
        , ("M-b", spawn (myBrowser))
        , ("M-S-f", spawn "nemo")
        , ("M-<Print>", spawn "flameshot gui")

    -- KB_GROUP Kill windows
        , ("M-S-c", kill1)     -- Kill the currently focused client
        , ("M-S-a", killAll)   -- Kill all windows on current workspace

    -- KB_GROUP Workspaces<Return>
        , ("M-<Left>", prevWS)
        , ("M-<Right>", nextWS)
        , ("M-.", nextScreen)  -- Switch focus to next monitor
        , ("M-,", prevScreen)  -- Switch focus to prev monitor
        , ("M-S-<Left>", shiftTo Prev nonNSP >> moveTo Prev nonNSP)  -- Shifts focused window to prev ws
        , ("M-S-<Right>", shiftTo Next nonNSP >> moveTo Next nonNSP) -- Shifts focused window to next ws

    -- KB_GROUP Floating windows
        , ("M-f", sendMessage (T.Toggle "floats")) -- Toggles my 'floats' layout
        , ("M-t", withFocused $ windows . W.sink)  -- Push floating window back to tile
        , ("M-S-t", sinkAll)                       -- Push ALL floating windows to tile

    -- KB_GROUP Increase/decrease spacing (gaps)
        , ("C-M1-j", decWindowSpacing 2)         -- Decrease window spacing
        , ("C-M1-k", incWindowSpacing 2)         -- Increase window spacing
        , ("C-M1-h", decScreenSpacing 2)         -- Decrease screen spacing
        , ("C-M1-l", incScreenSpacing 2)         -- Increase screen spacing

    -- KB_GROUP Grid Select (CTR-g followed by a key)
        , ("C-g g", spawnSelected' myAppGrid)                 -- grid select favorite apps
        , ("C-g t", goToSelected $ mygridConfig myColorizer)  -- goto selected window
        , ("C-g b", bringSelected $ mygridConfig myColorizer) -- bring selected window

    -- KB_GROUP Windows navigation
        , ("M-i", windows W.focusMaster)  -- Move focus to the master window
        , ("M-k", windows W.focusDown)    -- Move focus to the next window
        , ("M1-<Tab>", windows W.focusDown)    -- Move focus to the next window
        , ("M-j", windows W.focusUp)      -- Move focus to the prev window
        , ("M1-S-<Tab>", windows W.focusDown)    -- Move focus to the prev window
        , ("M-S-m", windows W.swapMaster) -- Swap the focused window and the master window
        , ("M-S-j", windows W.swapUp)   -- Swap focused window with next window
        , ("M-S-k", windows W.swapDown)     -- Swap focused window with prev window
        , ("M-<Backspace>", promote)      -- Moves focused window to master, others maintain order
        , ("M-M1-<Tab>", rotSlavesDown)    -- Rotate all windows except master and keep focus in place
        , ("M-C-<Tab>", rotAllDown)       -- Rotate all the windows in the current stack

    -- KB_GROUP Layouts
        , ("M-<Tab>", sendMessage NextLayout)     -- Switch to next layout
        , ("M-S-<Tab>", sendMessage FirstLayout)        -- Switch to the first layout (Tall)
        , ("M-<Space>", sendMessage (MT.Toggle NBFULL) >> sendMessage ToggleStruts) -- Toggles noborder/full

    -- KB_GROUP Increase/decrease windows in the master pane or the stack
        , ("M-S-<Up>", sendMessage (IncMasterN 1))      -- Increase # of clients master pane
        , ("M-S-<Down>", sendMessage (IncMasterN (-1))) -- Decrease # of clients master pane
        , ("M-C-<Up>", increaseLimit)                   -- Increase # of windows
        , ("M-C-<Down>", decreaseLimit)                 -- Decrease # of windows

    -- KB_GROUP Window resizing
        , ("M-h", sendMessage Shrink)                   -- Shrink horiz window width
        , ("M-l", sendMessage Expand)                   -- Expand horiz window width
        , ("M-M1-l", sendMessage MirrorShrink)          -- Expand vert window width
        , ("M-M1-h", sendMessage MirrorExpand)          -- Shrink vert window width
        , ("M-M1-<Left>", sendMessage Shrink)         -- Shrink horiz window width
        , ("M-M1-<Right>", sendMessage Expand)         -- Expand horiz window width
        , ("M-M1-<Down>", sendMessage MirrorShrink)    -- Expand vert window width
        , ("M-M1-<Up>", sendMessage MirrorExpand)     -- Shrink vert window width

    -- KB_GROUP Sublayouts
    -- This is used to push windows to tabbed sublayouts, or pull them out of it.
        , ("M-C-h", sendMessage $ pullGroup L)
        , ("M-C-l", sendMessage $ pullGroup R)
        , ("M-C-k", sendMessage $ pullGroup U)
        , ("M-C-j", sendMessage $ pullGroup D)
        , ("M-C-<Left>", sendMessage $ pullGroup L)
        , ("M-C-<Right>", sendMessage $ pullGroup R)
        , ("M-C-<Up>", sendMessage $ pullGroup U)
        , ("M-C-<Down>", sendMessage $ pullGroup D)
        , ("M-C-m", withFocused (sendMessage . MergeAll))
        -- , ("M-C-u", withFocused (sendMessage . UnMerge))
        , ("M-C-t", withFocused (sendMessage . UnMergeAll))
        , ("M-C-.", onGroup W.focusUp')    -- Switch focus to next tab
        , ("M-C-,", onGroup W.focusDown')  -- Switch focus to prev tab

    -- KB_GROUP Scratchpads
    -- Toggle show/hide these programs.  They run on a hidden workspace.
    -- When you toggle them to show, it brings them to your current workspace.
    -- Toggle them to hide and it sends them back to hidden workspace (NSP).
        , ("M-s <Return>", namedScratchpadAction myScratchPads "terminal")
        , ("M-M1-t", namedScratchpadAction myScratchPads "terminal")
        , ("M-s n", namedScratchpadAction myScratchPads "notepad")
        , ("M-s m", namedScratchpadAction myScratchPads "music")
        , ("M-s c", namedScratchpadAction myScratchPads "calculator")
        , ("M-s b", namedScratchpadAction myScratchPads "browser")
        , ("M-s e", namedScratchpadAction myScratchPads "emoji")
        , ("M-s p", namedScratchpadAction myScratchPads "peek")
        , ("M-s f", namedScratchpadAction myScratchPads "files")

    -- Dunst (notification) controls
        , ("M-M1-n", spawn "dunstctl history-pop") -- Return the most recent notification
        , ("M-n", spawn "dunstctl close") -- Close the oldest notification
        , ("M-S-n", spawn "dunstctl close-all") -- Close all notifications

    -- -- KB_GROUP Controls for music player (SUPER-m followed by a key)
        , ("M-m k", spawn "mpc next")
        , ("M-m j", spawn "mpc prev")
        , ("M-m <Space>", spawn "mpc toggle")
        , ("<XF86AudioStop>", spawn "mpc toggle")
        , ("<XF86AudioPause>", spawn "mpc toggle")
        , ("<XF86AudioToggle>", spawn "mpc toggle")
        --, ("<XF86AudioPlay>", spawn "mpc toggle")

    -- KB_GROUP Multimedia Keys
        , ("<XF86AudioPlay>", spawn "mpc play")
        , ("<XF86AudioPrev>", spawn "mpc prev")
        , ("<XF86AudioNext>", spawn "mpc next")
        , ("<XF86AudioMute>", spawn "amixer set Master toggle")
        , ("<XF86AudioMicMute>", spawn "amixer set Capture toggle")
        , ("<XF86AudioLowerVolume>", spawn "amixer -M set Master 2%- unmute")
        , ("<XF86AudioRaiseVolume>", spawn "amixer -M set Master 2%+ unmute")
        , ("<XF86HomePage>", spawn "firefox -P default-release https://www.google.com/")
        , ("<XF86Search>", spawn "qutebrowser")
        , ("<XF86Mail>", runOrRaise "betterbird" (resource =? "betterbird"))
        , ("<XF86Calculator>", runOrRaise "qalculate-gtk" (resource =? "qalculate-gtk"))
        , ("<XF86Eject>", spawn "toggleeject")



    -- Function keys
        , ("<XF86MonBrightnessDown>", spawn "xbacklight -ctrl intel_backlight -dec 10 & xbacklight -ctrl nvidia_0 -dec 10") -- Backlight down for intel integrated graphics
        , ("<XF86MonBrightnessUp>", spawn "xbacklight -ctrl intel_backlight -inc 10 & xbacklight -ctrl nvidia_0 -inc 10") -- Backlight up for intel integrated graphics
        ]
    -- The following lines are needed for named scratchpads.
          where nonNSP          = WSIs (return (\ws -> W.tag ws /= "NSP"))
                nonEmptyNonNSP  = WSIs (return (\ws -> isJust (W.stack ws) && W.tag ws /= "NSP"))
-- END_KEYS

main :: IO ()
main = do
    nScreens <- countScreens
    -- Launching three instances of xmobar on their monitors.
    xmproc0 <- spawnPipe ("xmobar -x 0 $HOME/.config/xmobar/" ++ (if nScreens > 1 then "dual_xmobarrc" else "xmobarrc"))
    xmproc1 <- spawnPipe ("xmobar -x 1 $HOME/.config/xmobar/" ++ (if nScreens > 2 then "dual_xmobarrc" else "xmobarrc"))
    xmproc2 <- spawnPipe ("xmobar -x 1 $HOME/.config/xmobar/" ++ (if nScreens > 3 then "dual_xmobarrc" else "xmobarrc"))
    -- the xmonad, ya know...what the WM is named after!
    xmonad $ ewmh def
        { manageHook         = myManageHook <+> manageDocks
        , handleEventHook    = docksEventHook
                               -- Uncomment this line to enable fullscreen support on things like YouTube/Netflix.
                               -- This works perfect on SINGLE monitor systems. On multi-monitor systems,
                               -- it adds a border around the window if screen does not have focus. So, my solution
                               -- is to use a keybinding to toggle fullscreen noborders instead.  (M-<Space>)
                               -- <+> fullscreenEventHook
        , modMask            = myModMask
        , terminal           = myTerminal
        , startupHook        = myStartupHook
        , layoutHook         = showWName' myShowWNameTheme $ myLayoutHook
        , workspaces         = myWorkspaces
        , borderWidth        = myBorderWidth
        , normalBorderColor  = myNormColor
        , focusedBorderColor = myFocusColor
        , logHook = dynamicLogWithPP $ namedScratchpadFilterOutWorkspacePP $ xmobarPP
              -- XMOBAR SETTINGS
              { ppOutput = \x -> hPutStrLn xmproc0 x   -- xmobar on monitor 1
                              >> hPutStrLn xmproc1 x   -- xmobar on monitor 2
                              >> hPutStrLn xmproc2 x   -- xmobar on monitor 3
                -- Current workspace
              , ppCurrent = xmobarColor color06 "" . wrap
                            ("<box type=Bottom width=2 mb=2 color=" ++ color06 ++ ">") "</box>"
                -- Visible but not current workspace
              , ppVisible = xmobarColor color06 "" . clickable
                -- Hidden workspace
              , ppHidden = xmobarColor color05 "" . wrap
                           ("<box type=Top width=2 mt=2 color=" ++ color05 ++ ">") "</box>" . clickable
                -- Hidden workspaces (no windows)
              , ppHiddenNoWindows = xmobarColor color05 "" . clickable
                -- Title of active window
              , ppTitle = xmobarColor color16 "" . shorten 60
                -- Separator character
              , ppSep =  "<fc=" ++ color09 ++ "> <fn=1>|</fn> </fc>"
                -- Urgent workspace
              , ppUrgent = xmobarColor color02 "" . wrap "!" "!"
                -- Adding # of windows on current workspace to the bar
              , ppExtras  = [windowCount]
                -- order of things in xmobar
              , ppOrder  = \(ws:l:t:ex) -> [ws,l]++ex++[t]
              }

        } `additionalKeysP` myKeys
