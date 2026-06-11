  -- Base
import XMonad
import System.Directory
import System.IO (hPutStrLn)
import System.Exit (exitSuccess)
import qualified XMonad.StackSet as W

    -- Actions
import XMonad.Actions.CopyWindow (kill1)
import XMonad.Actions.CycleWS (Direction1D(..), moveTo, shiftTo, WSType(..), nextScreen, prevScreen, nextWS, prevWS, toggleWS)
import XMonad.Actions.GridSelect
import XMonad.Actions.MouseResize
import XMonad.Actions.Promote
import XMonad.Actions.RotSlaves (rotSlavesDown, rotAllDown)
import XMonad.Actions.WindowGo (runOrRaise)
import XMonad.Actions.WithAll (sinkAll, killAll)
import qualified XMonad.Actions.Search as S
import XMonad.Actions.CopyWindow (copyToAll)
import XMonad.Util.WorkspaceCompare

    -- Data
import Data.Char (isSpace, toUpper)
import Data.Maybe (fromJust)
import Data.Monoid
import Data.Maybe (isJust)
import Data.Tree
import qualified Data.Map as M
import Data.Ratio

    -- Hooks
import XMonad.Hooks.DynamicLog (dynamicLogWithPP, wrap, xmobarPP, xmobarColor, shorten, PP(..))
import XMonad.Hooks.EwmhDesktops  -- for some fullscreen events, also for xcomposite in obs.
import XMonad.Hooks.ManageDocks (avoidStruts, manageDocks, ToggleStruts(..))
import XMonad.Hooks.ManageDocks
import XMonad.Hooks.ManageHelpers (isFullscreen, doFullFloat, doCenterFloat, doRectFloat)
import XMonad.Hooks.InsertPosition (insertPosition, Position(..), Focus(..))
import XMonad.Hooks.ServerMode
import XMonad.Hooks.SetWMName
import XMonad.Hooks.WorkspaceHistory
import XMonad.Hooks.StatusBar
import XMonad.Hooks.StatusBar.PP (filterOutWsPP)

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
import Colors.Fathom
import Colors.FathomColors (qinghai, bermejo, baikal)  -- raw palette: green / red / blue

myHiddenWorkspace = filterOutWs ["NSP"]

myFont :: String
myFont = "xft:SauceCodePro Nerd Font:regular:size=9:antialias=true:hinting=true"
myGridFont :: String
myGridFont = "xft:SauceCodePro Nerd Font:regular:size=18:antialias=true:hinting=true"

myModMask :: KeyMask
myModMask = mod4Mask        -- Sets modkey to super/windows key

myTerminal :: String
myTerminal = "alacritty"    -- Sets default terminal

myBrowser :: String
myBrowser = "firefox -P default-release"  -- Sets firefox as browser

myEditor :: String
myEditor = myTerminal ++ " -e vim "    -- Sets vim as editor

myMusic :: String
myMusic = "spotify-launcher"

myBorderWidth :: Dimension
myBorderWidth = 2           -- Sets border width for windows

myNormColor :: String       -- Border color of normal windows
myNormColor   = colorBack   -- This variable is imported from Colors.THEME

myFocusColor :: String      -- Border color of focused windows
myFocusColor  = colorFore   -- This variable is imported from Colors.THEME

-- i3lock-color themed lock screen.  Background = colorBack; the indicator
-- ring/text uses the Fathom green (qinghai) / red (bermejo) / blue (baikal),
-- following the default i3lock-color state scheme:
--   idle ring = blue, keypress + verifying = green, wrong + backspace = red.
-- Color flags want RRGGBBAA, so strip the '#' and append "ff" (opaque).
myLockOpaque :: String -> String
myLockOpaque c = drop 1 c ++ "ff"

-- NOTE: the i3lock-color (Raymo111) fork installs its binary as `i3lock` and
-- uses hyphenated flag names (--ring-color, not --ringcolor).  --blur is
-- built in: it captures and blurs the screen itself, so no compositor needed.
myLockCmd :: String
myLockCmd = unwords
    [ "i3lock"
    , "--blur=12"                                           -- built-in gaussian blur (sigma); no compositor
    , "--inside-color="      ++ myLockOpaque colorBack
    , "--ring-color="        ++ myLockOpaque baikal        -- idle ring: blue
    , "--insidever-color="   ++ myLockOpaque colorBack
    , "--ringver-color="     ++ myLockOpaque qinghai       -- verifying: green
    , "--insidewrong-color=" ++ myLockOpaque colorBack
    , "--ringwrong-color="   ++ myLockOpaque bermejo       -- wrong: red
    , "--keyhl-color="       ++ myLockOpaque qinghai       -- keypress highlight: green
    , "--bshl-color="        ++ myLockOpaque bermejo       -- backspace highlight: red
    , "--separator-color="   ++ myLockOpaque colorBack
    , "--verif-color="       ++ myLockOpaque qinghai       -- "verifying" text: green
    , "--wrong-color="       ++ myLockOpaque bermejo       -- "wrong" text: red
    , "--verif-text=''"                                  -- hide verifying text to avoid clock overlap
    , "--wrong-text=''"                                  -- hide wrong text to avoid clock overlap
    , "--line-uses-inside"
    , "--radius=120"                                       -- bigger indicator ring
    , "--ring-width=8"
    , "--force-clock"                                      -- always show clock + indicator
    , "--time-str=%H:%M"
    , "--date-str='%A %d %B'"                              -- quoted: contains spaces
    , "--time-color="        ++ myLockOpaque colorFore
    , "--date-color="        ++ myLockOpaque colorFore
    , "--pass-media-keys"                                  -- Spotify keys work while locked
    , "--pass-volume-keys"                                 -- volume keys work while locked
    ]

windowCount :: X (Maybe String)
windowCount = gets $ Just . show . length . W.integrate' . W.stack . W.workspace . W.current . windowset

-- setting colors for tabs layout and tabs sublayout.
myTabTheme = def { XMonad.Layout.Tabbed.fontName            = "xft:Ubuntu:bold:size=9:antialias=true:hinting=true"
                 , XMonad.Layout.Tabbed.activeColor         = colorFore
                 , XMonad.Layout.Tabbed.inactiveColor       = colorBack
                 , XMonad.Layout.Tabbed.activeBorderColor   = colorFore
                 , XMonad.Layout.Tabbed.inactiveBorderColor = colorBack
                 , XMonad.Layout.Tabbed.activeTextColor     = colorBack
                 , XMonad.Layout.Tabbed.inactiveTextColor   = colorInactiveText
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
    spawn "/usr/bin/prime-offload"
    -- spawn "killall conky"   -- kill current conky on each restart
    -- spawn "killall trayer"  -- kill current trayer on each restart

    spawnOnce "lxsession"
    -- spawnOnce "picom"
    spawnOnce "dunst"
    spawnOnce "greenclip daemon"   -- Clipboard history daemon (M-C-v to browse)

    setWMName "LG3D"
    setDefaultCursor xC_left_ptr

    -- killall first so each xmonad restart REPLACES trayer instead of stacking
    -- another copy (trayer uses spawn, not spawnOnce, so it runs every restart).
    spawn ("killall trayer; trayer --edge top --align right --widthtype request --padding 6 --SetDockType true --SetPartialStrut true --expand true --monitor primary --transparent true --alpha 0 " ++ colorTrayer ++ " --height 30 --distance 1") -- Effective height is height + 2*distance
    -- spawn ("conky -c $HOME/.config/.conkyrc")

    spawnOnce "nm-applet"
    -- spawnOnce "blueman-applet"
    spawnOnce "retrovol"
    spawnOnce "xsettingsd"

    -- spawnOnce "xargs xwallpaper --stretch < ~/.cache/wall"
    -- spawnOnce "~/.fehbg &"  -- set last saved feh wallpaper
    -- spawnOnce "feh --randomize --bg-fill ~/wallpapers/*"  -- feh set random wallpaper
    -- spawnOnce "nitrogen --restore &"   -- if you prefer nitrogen to feh
    --spawnOnce "optimus-manager-qt"

    spawnOnce "eval $(gnome-keyring-daemon --start)"
    spawnOnce "export SSH_AUTH_SOCK"

    spawnOnce "xset r rate 200 50"
    spawnOnce "xinput --set-prop 'TPPS/2 Elan TrackPoint' 'libinput Accel Speed' -0.5"
    spawnOnce "xrandr --output 'eDP-1' --primary"

    spawnOnce "feh --bg-fill $HOME/.wallpapers/trees.webp"

    spawn "killall skippy-xd; skippy-xd --start-daemon &"

    -- Spawn workspace-specific apps
    -- spawnOn "mail" "evolution"

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
    { gs_cellheight   = 90
    , gs_cellwidth    = 600
    , gs_cellpadding  = 6
    , gs_originFractX = 0.1
    , gs_originFractY = 0.5
    , gs_font         = myGridFont
    }

spawnSelected' :: [(String, String)] -> X ()
spawnSelected' lst = gridselect conf lst >>= flip whenJust spawn
    where conf = def
                   { gs_cellheight   = 90
                   , gs_cellwidth    = 600
                   , gs_cellpadding  = 6
                   , gs_originFractX = 0.1
                   , gs_originFractY = 0.5
                   , gs_font         = myGridFont
                   }

myAppGrid = [ ("Nemo", "nemo")
                 , ("Firefox", "firefox -P default-release")
                 , ("Okular", "okular")
                 , ("Spotify", myMusic)
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
                , NS "reader" spawnReader findReader manageReader
                , NS "ai" spawnAI findAI manageAI
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
    spawnMus  = myMusic
    findMus   = className =? "Spotify"
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
    spawnBrowser  = "firefox -P scratchpad --class browserscratchpad --no-remote --new-window"
    findBrowser   = className =? "browserscratchpad"
    manageBrowser = customFloating $ W.RationalRect l t w h
               where
                 h = 0.9
                 w = 0.9
                 t = 0.95 -h
                 l = 0.95 -w
    spawnAI  = "chromium --app=https://claude.ai/code --profile-directory=AI"
    findAI  = appName =? "claude.ai__code"
    manageAI = customFloating $ W.RationalRect l t w h
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
    spawnFiles   = "nemo" -- --name=filescratchpad --class=filescratchpad"
    findFiles    = className =? "Nemo" --"filescratchpad"
    manageFiles  = customFloating $ W.RationalRect l t w h
               where
                 h = 0.9
                 w = 0.9
                 t = 0.95 -h
                 l = 0.95 -w
    spawnReader   = "okular --qwindowtitle reader-scratchpad"
    findReader    = className =? "okular"
    manageReader  = customFloating $ W.RationalRect l t w h
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
myWorkspaces = [" chat ", " mail ", " www ", " dev", " note ", " read ", " write ", " sys ", " misc "]
myWorkspaceIndices = M.fromList $ zipWith (,) myWorkspaces [1..] -- (,) == \x y -> (x,y)

clickable ws = "<action=xdotool key super+"++show i++">"++ws++"</action>"
    where i = fromJust $ M.lookup ws myWorkspaceIndices

-- New *tiled* windows go to the bottom of the stack (Below Newer), preserving
-- the master pane.  New *floating* windows instead open on top (Above Newer) so
-- dialogs/floats/scratchpads don't appear behind already-open windows.  This runs
-- after myManageHook so doFloat/doCenterFloat/etc. have already registered the
-- window in the floating map, which is what we test here.
myInsertPosition :: ManageHook
myInsertPosition = do
    w         <- ask
    floatEndo <- insertPosition Master Newer  -- head of W.index => top of the float stack
    tileEndo  <- insertPosition Below Newer
    -- Decide against the *threaded* windowset (which earlier hooks have already
    -- mutated with doFloat/customFloating), NOT the live X state -- at manage
    -- time the X state still holds the pre-manage windowset, so a `gets
    -- windowset` here would never see the new window as floating.
    pure $ Endo $ \ws ->
        appEndo (if w `M.member` W.floating ws then floatEndo else tileEndo) ws

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
     , className =? "GLWindow"           --> doFloat
    --  , className =? "ksnip"             --> doCenterFloat
     , className =? "Yad"             --> doCenterFloat
     , title =? "CairoMakie"          --> doFloat
     , title =? "'downloadbibinfo'"     --> doCenterFloat
     , title =? "Oracle VM VirtualBox Manager"  --> doFloat
    --  , title =? "Mozilla Firefox"     --> doShift ( myWorkspaces !! 2 )
     -- , className =? "Brave-browser"   --> doShift ( myWorkspaces !! 1 )
     --, className =? "mpv"             --> doShift ( myWorkspaces !! 7 )
     -- , className =? "Gimp"            --> doShift ( myWorkspaces !! 8 )
     --, className =? "VirtualBox Manager" --> doShift  ( myWorkspaces !! 4 )
     , (className =? "firefox" <&&> resource =? "Dialog") --> doFloat  -- Float Firefox Dialog
     , isFullscreen -->  doFullFloat
     , title =? "Picture-in-Picture" --> doFloat
     , title=? "Picture-in-Picture" --> doF copyToAll
     ] <+> namedScratchpadManageHook myScratchPads

-- Index keybindings
indexKeys :: [(String, X ())]
indexKeys = concatMap
        (\n ->
            [ ("M-c " ++ show n, spawn $ "xdotool key ctrl+c && cb copy" ++ show n ++ " $(xclip -selection clipboard -o)")
            , ("M-S-c " ++ show n, spawn $ "xdotool key ctrl+shift+c && cb copy" ++ show n ++ " $(xclip -selection clipboard -o)")
            , ("M-x " ++ show n, spawn $ "xdotool key ctrl+x && cb copy" ++ show n ++ " $(xclip -selection clipboard -o)")
            , ("M-v " ++ show n, spawn $ "cb copy0 $(cb paste" ++ show n ++ ") && xdotool key --clearmodifiers ctrl+shift+v")
            , ("M-S-v " ++ show n, spawn $ "cb copy0 $(cb paste" ++ show n ++ ") && xdotool key --clearmodifiers ctrl+v")
            ]
        ) [1..9]

-- START_KEYS
singleKeys :: [(String, X ())]
singleKeys =
    -- KB_GROUP Xmonad
        [ ("M-C-r", spawn "xmonad --recompile")       -- Recompiles xmonad
        , ("M-S-r", spawn "xmonad --restart; feh --recursive --randomize --bg-fill $HOME/.wallpapers/")         -- Restarts xmonad
        , ("M-S-q", io exitSuccess)                   -- Quits xmonad
        , ("M-S-p t", spawn "~/.local/bin/transparenton") -- Set picom to transparent
        , ("M-S-p o", spawn "~/.local/bin/transparentoff") -- Set picom to opaque
        , ("M-S-b", spawn "feh --recursive --randomize --bg-fill $HOME/.wallpapers/") -- Changes backgroundB
        , ("M-C-1", spawn "~/.local/bin/docked")
        , ("M-C-2", spawn "~/.local/bin/doubledocked")
        , ("M-C-3", spawn "~/.local/bin/doubledockedmixed")

    -- KB_GROUP Get Help
        , ("M-S-/", spawn "~/.xmonad/xmonad_keys.sh") -- Get list of keybindings

    -- KB_GROUP Lock & Clipboard
        , ("M-S-l", spawn myLockCmd)  -- Lock screen, themed via i3lock-color (password to unlock; processes keep running)
        , ("M-C-v", spawn "rofi -modi 'clipboard:greenclip print' -show clipboard -run-command '{cmd}'") -- Clipboard history

    -- KB_GROUP Run Prompt
        --, ("M-S-<Return>", spawn "dmenu_run -i -fn 'Ubuntu:weight=bold:pixelsize=26:antialias=true:hinting=true' -p \"Run: \"") -- Dmenu
        , ("M-<Return>", spawn "rofi -drun-show-actions -drun-match-fields name,keywords,generic -show drun") -- Dmenu
        , ("C-S-<Return>", spawn "rofi -drun-show-actions -drun-match-fields name,keywords,generic -show drun") -- Dmenu

    -- KB_GROUP Useful programs to have a keybinding for launch
        , ("M-S-<Return>", spawn (myTerminal))
        , ("M-b", spawn (myBrowser)) -- , ("M-b", spawn (myBrowser) >> moveTo Prev (WSIs $ return (('w' `elem`) . W.tag)))
        , ("M-S-f", spawn "nemo --name=files --class=files")
        , ("M-<Print>", spawn "flameshot gui")
        , ("M-S-<Print>", spawn "TMPFILE=/tmp/$RANDOM.png; flameshot gui -p $TMPFILE; pix2tex $TMPFILE | xclip; notify-send 'Copied LaTeX to clipboard'")
        , ("M-d", spawn "downloadbibinfo")
        , ("M-S-d", spawn "downloadpaper")

    -- KB_GROUP Kill windows
        , ("M-S-x", kill)     -- Kill the currently focused client
        , ("M-S-a", killAll)   -- Kill all windows on current workspace

    -- KB_GROUP Workspaces<Return>
        , ("M-<Left>", prevWS)
        , ("M-<Right>", nextWS)
        , ("M-<Delete>", toggleWS)
        , ("M-0", toggleWS)
        , ("M-.", nextScreen)  -- Switch focus to next monitor
        , ("M-,", prevScreen)  -- Switch focus to prev monitor
        , ("M-S-<Left>", shiftTo Prev nonNSP >> moveTo Prev nonNSP)  -- Shifts focused window to prev ws
        , ("M-S-<Right>", shiftTo Next nonNSP >> moveTo Next nonNSP) -- Shifts focused window to next ws

    -- KB_GROUP Skippy-xd workspace switching
        , ("M-w", spawn "skippy-xd --expose")  -- Page windows
        , ("M-S-w", spawn "skippy-xd --paging")  -- Page windows

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
        , ("M-s r", namedScratchpadAction myScratchPads "reader")
        , ("M-s l", namedScratchpadAction myScratchPads "ai")
        -- Arbitrary scratchpad with XMonad.Util.WindowState?

    -- Dunst (notification) controls
        , ("M-M1-n", spawn "dunstctl history-pop") -- Return the most recent notification
        , ("M-n", spawn "dunstctl close") -- Close the oldest notification
        , ("M-S-n", spawn "dunstctl close-all") -- Close all notifications

    -- -- KB_GROUP Controls for music player (SUPER-m followed by a key)
        , ("M-m k", spawn "dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.Next")
        , ("M-m .", spawn "dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.Next")
        , ("M-m j", spawn "dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.Previous")
        , ("M-m ,", spawn "dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.Previous")
        , ("M-m <Space>", spawn "dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.PlayPause")
        , ("M-m p", spawn "dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.PlayPause")
        , ("M-m s", spawn "mpc stop")
        -- , ("M-m <Backspace>", spawn "mpc stop && dbus-sends --print-reply --dest=org.mpris.MediaPlayer2.spotify /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.Play")
        -- , ("M-m <Delete>", spawn "mpc del 0")
        , ("M-m f", spawn "mpc seek +10%")
        , ("M-m b", spawn "mpc seek -10%")
        , ("M-m u", spawn "mpc volume +20")
        , ("M-m d", spawn "mpc volume -20")
        , ("<XF86AudioStop>", spawn "dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.PlayPause")
        , ("<XF86AudioPause>", spawn "dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.PlayPause")
        , ("<XF86AudioToggle>", spawn "dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.PlayPause")

    -- KB_GROUP Multimedia Keys
        , ("<XF86AudioPlay>", spawn "dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.Play")
        , ("<XF86AudioPrev>", spawn "dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.Previous")
        , ("<XF86AudioNext>", spawn "dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.Next")
        , ("<XF86AudioMute>", spawn "pactl set-sink-mute @DEFAULT_SINK@ toggle")
        , ("<XF86AudioMicMute>", spawn "pactl set-source-mute @DEFAULT_SOURCE@ toggle")
        , ("<XF86AudioLowerVolume>", spawn "pactl set-sink-volume @DEFAULT_SINK@ -2%")
        , ("<XF86AudioRaiseVolume>", spawn "pactl set-sink-volume @DEFAULT_SINK@ +2%")
        , ("<XF86HomePage>", spawn "firefox -P default-release https://www.google.com/")
        , ("<XF86Search>", spawn "qutebrowser")
        , ("<XF86Mail>", runOrRaise "evolution" (resource =? "evolution"))
        , ("<XF86Calculator>", runOrRaise "qalculate-gtk" (resource =? "qalculate-gtk"))
        , ("<XF86Eject>", spawn "toggleeject")



    -- Function keys
        , ("<XF86MonBrightnessDown>", spawn "xbacklight -ctrl amdgpu_bl1 -dec 10") -- Backlight down for AMD graphics
        , ("<XF86MonBrightnessUp>", spawn "xbacklight -ctrl amdgpu_bl1 -inc 10") -- Backlight up for AMD graphics
        ]
    -- The following lines are needed for named scratchpads.
          where nonNSP          = WSIs (return (\ws -> W.tag ws /= "NSP"))
                nonEmptyNonNSP  = WSIs (return (\ws -> isJust (W.stack ws) && W.tag ws /= "NSP"))
-- END_KEYS

myKeys :: [(String, X ())]
myKeys = singleKeys ++ indexKeys

-- The pretty-printer that builds the workspace/layout string written to the
-- _XMONAD_LOG X property.  Note: no ppOutput here -- the StatusBar machinery
-- writes the property for us, so a wedged xmobar can never block xmonad.
myXmobarPP :: PP
myXmobarPP = filterOutWsPP [scratchpadWorkspaceTag] $ xmobarPP
      -- Current workspace
    { ppCurrent = xmobarColor colorCurrent "" . wrap
                  ("<box type=Bottom width=2 mb=2 color=" ++ colorCurrent ++ ">") "</box>"
      -- Visible but not current workspace
    , ppVisible = xmobarColor colorVisible "" . clickable
      -- Hidden workspace
    , ppHidden = xmobarColor colorHidden "" . wrap
                 ("<box type=Top width=2 mt=2 color=" ++ colorHidden ++ ">") "</box>" . clickable
      -- Hidden workspaces (no windows)
    , ppHiddenNoWindows = xmobarColor colorHidden "" . clickable
      -- Title of active window
    , ppTitle = const " "
      -- Separator character
    , ppSep =  "<fc=" ++ colorSeparator ++ "> <fn=1>|</fn> </fc>"
      -- Urgent workspace
    , ppUrgent = xmobarColor colorUrgent "" . wrap "!" "!"
      -- Adding # of windows on current workspace to the bar
    , ppExtras  = [windowCount]
      -- order of things in xmobar
    , ppOrder  = \(ws:l:t:ex) -> [ws,l]++ex++[t]
    }

-- One xmobar per physical screen, spawned/killed automatically as monitors
-- come and go.  All bars read the same _XMONAD_LOG property (Run XMonadLog).
barSpawner :: ScreenId -> X StatusBarConfig
barSpawner 0 = pure $ statusBarProp
                 "xmobar -x 0 $HOME/.config/xmobar/xmobarrc" (pure myXmobarPP)
barSpawner n = pure $ statusBarProp
                 ("xmobar -x " ++ show (fromIntegral n :: Int)
                                ++ " $HOME/.config/xmobar/dual_xmobarrc") (pure myXmobarPP)

main :: IO ()
main = xmonad
     . addEwmhWorkspaceSort (pure myHiddenWorkspace)
     . ewmh
     . docks
     . dynamicSBs barSpawner
     $ def
        { manageHook         = myInsertPosition <+> myManageHook <+> manageDocks
        , modMask            = myModMask
        , terminal           = myTerminal
        , startupHook        = myStartupHook
        , layoutHook         = myLayoutHook
        , workspaces         = myWorkspaces
        , borderWidth        = myBorderWidth
        , normalBorderColor  = myNormColor
        , focusedBorderColor = myFocusColor
        } `additionalKeysP` myKeys
