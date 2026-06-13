{-# LANGUAGE ScopedTypeVariables, GeneralizedNewtypeDeriving, FlexibleInstances, BangPatterns, ForeignFunctionInterface #-}
-- The xmonad build script compiles without optimisation; the per-pixel
-- backdrop tint in 'dimPixmap' is ~50x slower at -O0 (seconds, not ms), so
-- force optimisation for this module.
{-# OPTIONS_GHC -O2 #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  GridSelectColumns
-- Description :  A GridSelect variant that lays windows out one column per
--                workspace, so moving left/right changes workspace.
--
-- This is a trimmed, vendored copy of the *engine* of
-- "XMonad.Actions.GridSelect" (v0.18.1), kept here because the pieces it needs
-- (the @TwoDState@ constructor, @evalTwoD@, the drawing/event loop) are not
-- exported upstream.  The configuration type 'GSConfig' and the colorizers ARE
-- exported, so we import those rather than redefine them -- that avoids duplicate
-- 'HasColorizer' / 'Default' instances.
--
-- What this adds over the vendored engine:
--   * Column-major placement, one column per workspace (centred), with the
--     workspace name drawn as a header above each column.
--   * Type-to-search that keeps every column FIXED in place: non-matching
--     windows are dimmed and skipped by navigation; matching ones stay put.
--     Columns are never reflowed, so the spatial workspace layout is stable.
--   * left/right (and Tab) jump to the nearest *matching* cell in the adjacent
--     column that still has matches, with wrap-around; up/down move within a
--     column; Return selects, Escape cancels, Backspace edits the query.
--   * Flicker-free drawing: every frame is composed in an off-screen pixmap
--     and blitted to the window in a single copy, on top of a snapshot of the
--     desktop taken when the grid opens (pseudo-transparency, no compositor
--     required).  The snapshot is dimmed with a true per-pixel tint, cards
--     cast dithered drop-shadows, the cursor card is raised slightly, the
--     live search query floats in a pill near the bottom of the screen, and
--     the matched part of each title is highlighted in the column accent.
-----------------------------------------------------------------------------

module GridSelectColumns
    ( goToSelectedColumns
    , bringSelectedColumns
    , gridselectWindowColumns
    ) where

import Data.Bits
import Data.Char (isAlphaNum)
import Data.IORef (IORef, newIORef, readIORef, modifyIORef')
import Data.Ord (comparing)
import Data.Word (Word32)
import Data.Array.Unboxed (UArray, listArray, (!))
import qualified Data.ByteString as BS
import Foreign.C.Types (CLong, CULong, CUChar(..), CInt(..))
import Foreign.Marshal.Alloc (mallocBytes, alloca)
import Foreign.Marshal.Array (peekArray)
import Foreign.Ptr (Ptr, castPtr, nullPtr)
import Foreign.Storable (pokeElemOff)
import qualified Foreign.Storable as FS (peek)
import Numeric (readHex)
import Text.Printf (printf)
import Control.Exception (catch, bracket, SomeException)
import Control.Monad.State
import Data.List as L
import qualified Data.Map as M
import qualified Data.Set as S
import System.Directory (doesFileExist, getHomeDirectory, createDirectoryIfMissing)
import System.IO.Unsafe (unsafePerformIO)
import System.Posix.Signals (installHandler, sigCHLD, Handler(Default))
import System.Process (spawnCommand)
import Graphics.X11.Xlib.Extras (xGetWindowProperty, anyPropertyType, getClassHint, ClassHint(..))
import XMonad hiding (liftX)
import XMonad.Prelude
import XMonad.Util.Font
import XMonad.Prompt (mkUnmanagedWindow)
import XMonad.StackSet as W
import XMonad.Layout.Decoration
import XMonad.Util.NamedWindows (getName)
import XMonad.Actions.WindowBringer (bringWindow)
import XMonad.Actions.GridSelect (GSConfig(..), TwoDPosition)
import qualified Colors.FathomColors as C   -- auto-generated from the Fathom YAML

-- ---------------------------------------------------------------------------
-- Visual options -- each effect switches off with 0 / Nothing / False.
-- ---------------------------------------------------------------------------
-- | How to dim the desktop snapshot behind the grid.
data DimMethod
  = DimTint String Double -- ^ per-pixel blend toward a colour at the given
                          --   opacity in [0,1]: smooth and tintable, but costs
                          --   ~30-60 ms when the grid opens
  | DimShift Int          -- ^ server-side bit-plane shift: halves brightness n
                          --   times (1 = 50%, 2 = 25%, ...).  Effectively
                          --   instant, but darkens toward black only, in
                          --   power-of-two steps
  | DimNone               -- ^ leave the snapshot at full brightness

data Style = Style
  { sCellInset    :: Integer      -- inner gap inside each cell slot   (0 = none)
  , sCornerRadius :: Integer      -- rounded-corner radius, px         (0 = square)
  , sSelStroke    :: Integer      -- accent border on the cursor cell  (0 = none)
  , sScrim        :: Maybe String -- solid backdrop fill (Nothing = desktop snapshot)
  , sDim          :: DimMethod    -- how the desktop snapshot is dimmed
  , sShadow       :: Integer      -- card drop-shadow offset, px       (0 = none)
  , sRaise        :: Integer      -- cursor card grows by this much, px (0 = none)
  , sEdgeMargin   :: Integer      -- min gap kept between grid and screen edge:
                                  -- cells + fonts shrink together to honour it
  , sColWiden     :: Double       -- widen cards when few columns: this is the
                                  -- width multiplier at 1 column, tapering as
                                  -- 1 + (k-1)/ncols (1 = never widen)
  , sHeaderFont   :: Maybe String -- separate (bigger) header font     (Nothing = reuse)
  , sBevel        :: Bool         -- per-card top highlight + bottom shadow
  , sSoftCorners  :: Bool         -- dither-soften rounded corners (poor man's
                                  -- anti-aliasing; core X cannot alpha-blend)
  , sIcon         :: Maybe Integer -- draw each window's _NET_WM_ICON to the left
                                  -- of its title, with this gap px after it
                                  -- (Nothing = no icons)
  , sIconScale    :: Double       -- shrink/grow icons relative to the card-fit
                                  -- default (1 = fill the card height; 0.9 = 90%)
  , sIconMaxSrc   :: Int          -- skip a window's icon if its smallest source
                                  -- size exceeds this (px); keeps startup fast
                                  -- for apps that only ship huge 512-1024px icons
  , sNumLines     :: Int          -- max lines a title may wrap onto inside its
                                  -- box (1 = single line, as before)
  , sBreakWords   :: Bool         -- break over-long words mid-character when
                                  -- wrapping (False = only break at spaces)
  }

style :: Style
style = Style
  { sCellInset    = 6
  , sCornerRadius = 10
  , sSelStroke    = 3
  , sScrim        = Nothing
  , sDim          = DimShift 1 -- DimTint C.chernoe 0.6   -- or: DimShift 1 (instant, 50% darken)
  , sShadow       = 3
  , sRaise        = 2
  , sEdgeMargin   = 48
  , sColWiden     = 2.0
  , sHeaderFont   = Just "xft:Ubuntu:bold:size=20"
  , sBevel        = True
  , sSoftCorners  = False
  , sIcon         = Just 10
  , sIconScale    = 0.75
  , sIconMaxSrc   = 128
  , sNumLines     = 2
  , sBreakWords   = True
  }

-- Whole-grid outline + window-cell text.  Headers are drawn as bare centred text
-- in their column colour (see 'columnColors'), so they have no fixed bg/stroke.
gridBorder, cellText, grayedFg, headerBg :: String
gridBorder = C.chernoe_dark      -- outline around the whole selector
cellText   = C.abyad_lighter           -- normal window-cell text
grayedFg   = C.chernoe_lighter   -- dim text for search non-matches
headerBg   = C.chernoe           -- fill behind the centred header text

-- Padding (px) between the header text and the edge of its background pill.
headerMargin :: Integer
headerMargin = 8

-- | Multiply the @size=N@ / @pixelsize=N@ component of an Xft font string by
-- @k@ (floored at 6pt so titles stay legible); other components, and non-Xft
-- font strings, pass through untouched.
scaleFontSize :: Double -> String -> String
scaleFontSize k = intercalate ":" . map adj . splitOn ':'
  where
    splitOn c s = case break (== c) s of
                    (a, [])    -> [a]
                    (a, _ : b) -> a : splitOn c b
    adj part = case break (== '=') part of
                 (key, '=' : val)
                   | map toLower key `elem` ["size", "pixelsize"]
                   , [(n, "")] <- (reads val :: [(Double, String)])
                   -> key ++ "=" ++ show (max 6 (round (n * k) :: Int))
                 _ -> part

-- Per-column accent as (plain, lighter), cycling left-to-right in the Fathom
-- BASE_COLORS order (Fathom.jl, src/Colors.jl) and wrapping back to baikal.
-- chernoe is left out of the cycle: it is the backdrop/scrim colour here, so
-- it would have no contrast.  Plain = normal header text; lighter (the
-- _lighter palette variant) = selected text on both headers and window cells.
columnColors :: [(String, String)]
columnColors =
  [ (C.baikal,      C.baikal_lighter)
  , (C.bermejo,     C.bermejo_lighter)
  , (C.qinghai,     C.qinghai_lighter)
  , (C.seohae,      C.seohae_lighter)
  , (C.ianthina,    C.ianthina_lighter)
  , (C.abyad,       C.abyad_lighter)
  , (C.mesopelagic, C.mesopelagic_lighter)
  ]

-- Depth gradient: the ocean's pelagic zones, shallow (top of stack) -> deep.
-- (position, colour) where position in [0,1] is the point in the colourmap at
-- which the colour lands (0 = shallowest cell, 1 = deepest).  Edit positions
-- freely; they need not be evenly spaced, but should be ascending.
pelagicStops :: [(Double, String)]
pelagicStops =
  [ (0.00, C.epipelagic)     -- sunlight
  , (0.5, C.mesopelagic)    -- twilight
  , (0.66, C.bathypelagic)   -- midnight
  , (1.00, C.abyssopelagic)  -- abyss
  ]

-- Start sampling the gradient a little past the first stop, so the shallowest
-- cell is already a small blend of epipelagic and mesopelagic rather than pure
-- epipelagic.  The deepest cell still reaches the final stop.
gradientStart :: Double
gradientStart = 0.2


-- | The pelagic colour for a window at the given depth (0 = shallowest).
shadeFor :: Integer -> Integer -> String
shadeFor maxDepth depth =
    let r = fromIntegral depth / fromIntegral (max 1 maxDepth)
    in gradientAt pelagicStops (gradientStart + r * (1 - gradientStart))

-- | Sample a [0,1] ratio across colour stops placed at explicit positions
-- (piecewise linear; values outside the stop range clamp to the end colours).
gradientAt :: [(Double, String)] -> Double -> String
gradientAt stops r =
    case sortBy (comparing fst) stops of
      []      -> "#000000"
      [(_,c)] -> c
      sorted  -> seg sorted
  where
    seg ((p1, c1) : rest@((p2, c2) : more))
      | r <= p2 || null more =
          mixHex c1 c2 (if p2 == p1 then 0 else max 0 (min 1 ((r - p1) / (p2 - p1))))
      | otherwise = seg rest
    seg _ = "#000000"

mixHex :: String -> String -> Double -> String
mixHex c1 c2 r =
    let (r1, g1, b1) = parseHex c1
        (r2, g2, b2) = parseHex c2
        chan a b = round (fromIntegral a * (1 - r) + fromIntegral b * r) :: Int
    in printf "#%02x%02x%02x" (chan r1 r2) (chan g1 g2) (chan b1 b2)

parseHex :: String -> (Int, Int, Int)
parseHex ('#':a:b:c:d:e:f:_) = (h a b, h c d, h e f)
  where h x y = fst (head (readHex [x, y]))
parseHex _ = (0, 0, 0)

-- ---------------------------------------------------------------------------
-- Window icons (_NET_WM_ICON).  The property is a flat list of 32-bit values:
-- repeated (width, height, then width*height ARGB pixels).  We pick one source
-- size, scale it to fit the card, and composite it against the card fill at
-- draw time (core X has no alpha, but we know the exact fill colour).
-- ---------------------------------------------------------------------------

type RawIcon = (Int, Int, [Word32])              -- width, height, ARGB pixels

data IconImg = IconImg { iiW :: !Int, iiH :: !Int, iiPx :: !(UArray Int Word32) }

foreign import ccall unsafe "XFree" xFreePtr :: Ptr CUChar -> IO CInt

-- | Desired source size to grab when several are available: we draw at roughly
-- this, so a source at/just above it downscales crisply with minimal marshalling.
iconTargetPx :: Int
iconTargetPx = 64

-- | Read @len@ 32-bit words of a format-32 property starting at word @off@.
-- This is the key to fast startup: @_NET_WM_ICON@ bundles every icon size an app
-- ships -- some publish only 512-1024px variants -- and naively marshalling the
-- whole property is tens of MB per app.  By reading the 2-word (w,h) headers and
-- jumping over the pixel blocks, we transfer only the headers plus the one icon
-- we actually use.
getPropRange :: Display -> Atom -> Window -> CLong -> CLong -> IO [Word32]
getPropRange dpy atom win off len =
  alloca $ \aType -> alloca $ \aFmt -> alloca $ \aN ->
  alloca $ \aAfter -> alloca $ \aProp -> do
    st <- xGetWindowProperty dpy win atom off len False anyPropertyType
            aType aFmt aN aAfter aProp
    p <- FS.peek aProp
    if st /= 0 || p == nullPtr
      then return []
      else do
        fmt <- FS.peek aFmt
        n   <- FS.peek aN
        vals <- if fmt == (32 :: CInt) && n > (0 :: CULong)
                  then map fromIntegral
                         <$> peekArray (fromIntegral n) (castPtr p :: Ptr CLong)
                  else return []
        _ <- xFreePtr p
        return vals

-- | Read a window's icon cheaply: walk the size headers, choose the smallest
-- whose larger side is >= 'iconTargetPx' (else the largest) among those whose
-- larger side is <= @cap@, then fetch only that one icon's pixels.  Windows that
-- publish ONLY huge icons (> @cap@) are skipped (Nothing) rather than marshalled,
-- which is what keeps startup fast.
-- | Per-window cache of resolved raw icons, so reopening the grid never re-reads
-- (or re-renders) a window's icon during a session.
{-# NOINLINE rawIconCache #-}
rawIconCache :: IORef (M.Map Window (Maybe RawIcon))
rawIconCache = unsafePerformIO (newIORef M.empty)

readRawIcon :: Display -> Atom -> Int -> Window -> IO (Maybe RawIcon)
readRawIcon dpy atom cap win = do
    cache <- readIORef rawIconCache
    case M.lookup win cache of
      Just hit -> return hit
      Nothing  -> do
        (r, final) <- compute
        -- don't cache a "pending" theme render: retry (and pick it up) next open
        when final $ modifyIORef' rawIconCache (M.insert win r)
        return r
  where
    -- Prefer the window's OWN _NET_WM_ICON whenever it has any image: marshal the
    -- chosen size, downsample to iconTargetPx, and cache that (so the one big
    -- marshal of an oversized-only app happens once per session, then memory is
    -- tiny).  Only when there is no _NET_WM_ICON data at all do we fall back to
    -- the (async) freedesktop theme render.
    compute = do
      headers <- walk 0 []
      case choose headers of
        Just (off, w, h) -> do
          px <- getPropRange dpy atom win (off + 2) (fromIntegral (w * h))
          if length px == w * h
            then return (Just (resampleRaw iconTargetPx (w, h, px)), True)
            else themeIconRaw dpy win iconTargetPx     -- corrupt read: try theme
        Nothing -> themeIconRaw dpy win iconTargetPx   -- no _NET_WM_ICON at all
    -- collect (wordOffset, w, h) for every icon; header reads are ~20us each
    walk off acc = do
      hdr <- getPropRange dpy atom win off 2
      case hdr of
        (a : b : _) | a > 0, b > 0 ->
          let w = fromIntegral a; h = fromIntegral b
          in walk (off + 2 + fromIntegral (w * h)) ((off, w, h) : acc)
        _ -> return (reverse acc)
    md (_, w, h) = max w h
    -- which icon to marshal: the smallest at/above the draw target among those
    -- within @cap@ (cheap, crisp); if none are within cap, take the smallest
    -- oversized one (we still prefer the real icon over a theme substitute).
    choose []  = Nothing
    choose hs  = Just $
      let pool = case L.filter ((<= cap) . md) hs of { [] -> hs; ok -> ok }
      in case L.filter ((>= iconTargetPx) . md) pool of
           big@(_:_) -> minimumBy (comparing md) big
           []        -> maximumBy (comparing md) pool

-- | Classes whose background render we've already kicked off this session, to
-- avoid launching duplicate jobs for multiple windows of the same app.
{-# NOINLINE themeSpawned #-}
themeSpawned :: IORef (S.Set String)
themeSpawned = unsafePerformIO (newIORef S.empty)

-- | On-disk render cache: @~/.cache/gridselectcolumns-icons/<class>.rgba@ holds
-- a px*px*4 RGBA blob (or an empty 0-byte marker meaning "no themed icon").
iconCacheDir :: IO FilePath
iconCacheDir = do
    h <- getHomeDirectory
    let d = h ++ "/.cache/gridselectcolumns-icons"
    createDirectoryIfMissing True d
    return d

-- | Fallback icon source for Electron/Chromium apps (VSCode, ...) that ship only
-- huge or no _NET_WM_ICON but do have a normal themed icon by name.
--
-- ASYNCHRONOUS: resolving + rendering (find + magick) is slow, so we never block
-- the grid on it.  If the render cache already has the icon we load it; otherwise
-- we fire a detached background job to produce it and return Nothing for now --
-- the icon appears on the next grid open.  The Bool result says whether the
-- answer is final (safe to cache) or still pending (retry next open).
themeIconRaw :: Display -> Window -> Int -> IO (Maybe RawIcon, Bool)
themeIconRaw dpy win px = do
    ClassHint rn rc <- getClassHint dpy win
    let names = nub [ n | n <- map (map toLower) [rn, rc], not (null n), all safe n ]
        safe c = isAlphaNum c || c `elem` "-_+."
    case names of
      []        -> return (Nothing, True)
      (key : _) -> do
        dir <- iconCacheDir
        let cacheFile = dir ++ "/" ++ key ++ ".rgba"
        ready <- doesFileExist cacheFile
        if ready
          then (\r -> (r, True)) <$> loadRgba cacheFile px   -- icon or empty marker
          else do spawnThemeRender key names cacheFile px    -- kick off, show nothing yet
                  return (Nothing, False)

-- | Fire (once per class) a detached job that resolves @names@ to an icon file
-- and renders it to @cacheFile@ as px*px RGBA, atomically; if nothing resolves,
-- it writes an empty marker so we stop retrying.  Fire-and-forget via
-- 'spawnCommand' (no 'waitForProcess', so xmonad's SIGCHLD-ignore auto-reaps it).
spawnThemeRender :: String -> [String] -> FilePath -> Int -> IO ()
spawnThemeRender key names cacheFile px = do
    already <- readIORef themeSpawned
    unless (key `S.member` already) $ do
      modifyIORef' themeSpawned (S.insert key)
      -- xmonad keeps SIGCHLD = SIG_IGN; the render shell-out (and magick's own
      -- delegate, e.g. inkscape/rsvg) need waitpid to work, so fork the job with
      -- the default disposition restored.  The child inherits it; we put back
      -- xmonad's ignore (which auto-reaps the now-detached child).
      bracket (installHandler sigCHLD Default Nothing)
              (\old -> installHandler sigCHLD old Nothing)
              (const . void $ spawnCommand cmd)
  where
    sz   = show px ++ "x" ++ show px
    tmp  = cacheFile ++ ".tmp"
    pats = L.intercalate " -o " [ "-iname '" ++ n ++ e ++ "'" | n <- names, e <- [".png", ".svg"] ]
    -- pick scalable, then large raster sizes; render; move into place atomically
    cmd = "f=$(find \"$HOME/.local/share/icons\" /usr/share/icons /usr/share/pixmaps \\( "
       ++ pats ++ " \\) 2>/dev/null | awk '{s=9;"
       ++ "if($0 ~ /scalable/)s=0; else if($0 ~ /128/)s=2; else if($0 ~ /\\/64/)s=3;"
       ++ "else if($0 ~ /\\/48/)s=4} {print s\"\\t\"$0}' | sort -n | head -1 | cut -f2-); "
       ++ "if [ -n \"$f\" ]; then magick \"$f\" -background none -resize " ++ sz
       ++ " -gravity center -extent " ++ sz ++ " -depth 8 RGBA:'" ++ tmp ++ "' "
       ++ "&& mv '" ++ tmp ++ "' '" ++ cacheFile ++ "'; else : > '" ++ cacheFile ++ "'; fi"

-- | Load a px*px RGBA blob written by the render job (Nothing if it's the empty
-- marker or got truncated / removed mid-read).
loadRgba :: FilePath -> Int -> IO (Maybe RawIcon)
loadRgba file px = (decode <$> BS.readFile file) `catch` \(_ :: SomeException) -> return Nothing
  where
    n = px * px
    decode bs | BS.length bs == n * 4 = Just (px, px, [ pixAt bs i | i <- [0 .. n - 1] ])
              | otherwise             = Nothing
    -- ImageMagick RGBA: bytes are R,G,B,A per pixel; pack to A<<24|R<<16|G<<8|B
    pixAt bs i = let b j = fromIntegral (BS.index bs (4 * i + j)) :: Word32
                 in (b 3 `shiftL` 24) .|. (b 0 `shiftL` 16) .|. (b 1 `shiftL` 8) .|. b 2

-- | Nearest-neighbour resample a raw icon to fit a @target@ x @target@ box,
-- preserving aspect ratio.  No keying -- used both for the final draw size and
-- for downsampling an oversized _NET_WM_ICON before caching it.
resampleRaw :: Int -> RawIcon -> RawIcon
resampleRaw target (sw, sh, px) =
    (dw, dh, [ src ! (sy dy * sw + sx dx) | dy <- [0 .. dh-1], dx <- [0 .. dw-1] ])
  where
    sc = fromIntegral target / fromIntegral (max sw sh) :: Double
    dw = max 1 (round (fromIntegral sw * sc))
    dh = max 1 (round (fromIntegral sh * sc))
    src = listArray (0, sw * sh - 1) px :: UArray Int Word32
    sx dx = min (sw - 1) (dx * sw `div` dw)
    sy dy = min (sh - 1) (dy * sh `div` dh)

-- | Resample to the final draw box, ready to composite.
scaleIcon :: Integer -> RawIcon -> IconImg
scaleIcon target raw =
    let (dw, dh, ps) = resampleRaw (fromIntegral target) raw
    in IconImg dw dh (listArray (0, dw * dh - 1) ps)

-- | Composite an icon over a solid fill colour and blit it at (x, y).  Each
-- pixel is alpha-blended toward @fillC@: out = src*a + fill*(1-a).
drawIcon :: Display -> Drawable -> String -> Integer -> Integer -> IconImg -> IO ()
drawIcon dpy d fillC x y (IconImg w h px) = do
    let (fr, fg, fb) = parseHex fillC
        co s f a = (s * a + f * (255 - a)) `div` 255
        comp p = let a  = (p `shiftR` 24) .&. 0xff
                     sr = (p `shiftR` 16) .&. 0xff
                     sg = (p `shiftR`  8) .&. 0xff
                     sb =  p              .&. 0xff
                 in (co sr (fi fr) a `shiftL` 16)
                .|. (co sg (fi fg) a `shiftL`  8)
                .|.  co sb (fi fb) a
    buf <- mallocBytes (w * h * 4) :: IO (Ptr Word32)
    let go !i | i >= w * h = return ()
              | otherwise  = pokeElemOff buf i (comp (px ! i)) >> go (i + 1)
    go 0
    let scrn = defaultScreenOfDisplay dpy
    img <- createImage dpy (defaultVisualOfScreen scrn) (defaultDepthOfScreen scrn)
                       zPixmap 0 (castPtr buf) (fi w) (fi h) 32 0
    gc <- createGC dpy d
    putImage dpy d gc img 0 0 (fi x) (fi y) (fi w) (fi h)
    freeGC dpy gc
    destroyImage img   -- also frees buf (malloc'd)

-- | True per-pixel tint: blend every pixel of the pixmap toward @col@ at
-- @amt@ opacity (out = (1-amt)*pixel + amt*col).  Grain-free, unlike a
-- dithered stipple; costs ~50 ms for a 1080p screen, paid once at open.
dimPixmap :: Display -> Pixmap -> Dimension -> Dimension -> String -> Double -> IO ()
dimPixmap dpy pm w h col amt = do
    img <- getImage dpy pm 0 0 (fi w) (fi h) (complement 0) zPixmap
    let (tr, tg, tb) = parseHex col
        ka = round (amt * 256) :: Word32
        blend v t = (v * (256 - ka) + fromIntegral t * ka) `shiftR` 8
        tint p =     (p .&. 0xff000000)
             .|. (blend ((p `shiftR` 16) .&. 0xff) tr `shiftL` 16)
             .|. (blend ((p `shiftR`  8) .&. 0xff) tg `shiftL`  8)
             .|.  blend  (p              .&. 0xff) tb
        (wi, hi) = (fi w, fi h) :: (Int, Int)
    buf <- mallocBytes (wi * hi * 4) :: IO (Ptr Word32)
    let go !i !y !x
          | y >= hi   = return ()
          | x >= wi   = go i (y + 1) 0
          | otherwise = do
              pokeElemOff buf i (tint (fromIntegral (getPixel img (fi x) (fi y))))
              go (i + 1) y (x + 1)
    go 0 0 0
    let scrn = defaultScreenOfDisplay dpy
    img' <- createImage dpy (defaultVisualOfScreen scrn) (defaultDepthOfScreen scrn)
                        zPixmap 0 (castPtr buf) w h 32 0
    gc <- createGC dpy pm
    putImage dpy pm gc img' 0 0 0 0 w h
    freeGC dpy gc
    destroyImage img'   -- XDestroyImage also frees buf (malloc'd, so that's safe)
    destroyImage img

-- | Server-side dim: rebuild the snapshot with every channel shifted right by
-- @n@ bits (pixel -> pixel / 2^n), one 'copyPlane' per destination bit.  Bit i
-- of each channel is set from bit i+n of the source, and since each pass ORs
-- in a disjoint bit, the planes assemble the shifted value exactly.  No image
-- data ever crosses to the client, so this is effectively instant.
dimPixmapShift :: Display -> Pixmap -> Dimension -> Dimension -> Int -> IO ()
dimPixmapShift dpy pm w h n0 = do
    let n = max 1 (min 7 n0)
    tmp <- createPixmap dpy pm w h (defaultDepthOfScreen (defaultScreenOfDisplay dpy))
    gc <- createGC dpy tmp
    setForeground dpy gc 0
    fillRectangle dpy tmp gc 0 0 w h
    setBackground dpy gc 0
    setFunction dpy gc gXor
    forM_ [0, 8, 16] $ \c ->            -- blue, green, red channel base bits
      forM_ [0 .. 7 - n] $ \i -> do
        setForeground dpy gc (bit (c + i))
        copyPlane dpy pm tmp gc 0 0 w h 0 0 (bit (c + i + n))
    setFunction dpy gc gXcopy
    copyArea dpy tmp pm gc 0 0 w h 0 0
    freeGC dpy gc
    freePixmap dpy tmp

-- ---------------------------------------------------------------------------
-- Vendored engine (verbatim from XMonad.Actions.GridSelect, minus the diamond
-- layout, the colorizers and the config type we don't need here).
-- ---------------------------------------------------------------------------

type TwoDElementMap a = [(TwoDPosition, (String, a))]

data TwoDState a = TwoDState { td_curpos :: TwoDPosition
                             , td_gsconfig :: GSConfig a
                             , td_font :: XMonadFont
                             , td_headerFont :: XMonadFont
                             , td_paneX :: Integer
                             , td_paneY :: Integer
                             , td_drawingWin :: Window
                             , td_buffer :: Pixmap                 -- off-screen frame buffer
                             , td_backdrop :: Pixmap               -- desktop snapshot under the grid
                             , td_searchString :: String
                             , td_elementmap :: TwoDElementMap a   -- the FULL, fixed map (incl. headers)
                             , td_headerPos :: [TwoDPosition]      -- which cells are workspace headers
                             , td_icons :: M.Map TwoDPosition IconImg  -- per-cell window icons
                             , td_wrap :: M.Map TwoDPosition [String]  -- per-cell pre-wrapped title lines
                             , td_shadowGC :: GC                   -- shared black 50%-stipple GC for card shadows
                             , td_iconPm :: IORef (M.Map TwoDPosition Pixmap)
                               -- lazily-built icons pre-composited against their base shade,
                               -- reused (copyArea) for base-fill cells instead of recompositing
                             }

newtype TwoD a b = TwoD { unTwoD :: StateT (TwoDState a) X b }
    deriving (Functor, Applicative, Monad, MonadState (TwoDState a))

liftX :: X a1 -> TwoD a a1
liftX = TwoD . lift

evalTwoD :: TwoD a1 a -> TwoDState a1 -> X a
evalTwoD m s = flip evalStateT s $ unTwoD m

findInElementMap :: (Eq a) => a -> [(a, b)] -> Maybe (a, b)
findInElementMap pos = find ((== pos) . fst)

-- | Clamp a corner radius so the arcs fit inside the rectangle.
clampR :: Integer -> Integer -> Integer -> Integer
clampR w h r = max 0 (min r (min (w `div` 2) (h `div` 2)))

-- | The four corner-arc anchors (x, y, start angle in 1/64 deg) of a rounded
-- rectangle; each arc spans 90 degrees with diameter 2r.
corners :: Integer -> Integer -> Integer -> Integer -> Integer -> [(Integer, Integer, Integer)]
corners x y w h r =
  [ (x,           y,           90 * 64)
  , (x + w - 2*r, y,           0)
  , (x,           y + h - 2*r, 180 * 64)
  , (x + w - 2*r, y + h - 2*r, 270 * 64) ]

-- | Filled rounded rectangle (square when r <= 0).
fillRound :: Display -> Drawable -> GC -> Integer -> Integer -> Integer -> Integer -> Integer -> IO ()
fillRound dpy d gc x y w h r0
  | r <= 0    = fillRectangle dpy d gc (fi x) (fi y) (fi w) (fi h)
  | otherwise = do
      fillRectangle dpy d gc (fi x)         (fi (y + r))     (fi w)           (fi (h - 2*r))
      fillRectangle dpy d gc (fi (x + r))   (fi y)           (fi (w - 2*r))   (fi r)
      fillRectangle dpy d gc (fi (x + r))   (fi (y + h - r)) (fi (w - 2*r))   (fi r)
      forM_ (corners x y w h r) $ \(ax, ay, a) ->
        fillArc dpy d gc (fi ax) (fi ay) (fi (2*r)) (fi (2*r)) (fi a) (90*64)
  where r = clampR w h r0

-- | Rounded-rectangle outline (square when r <= 0).
drawRound :: Display -> Drawable -> GC -> Integer -> Integer -> Integer -> Integer -> Integer -> IO ()
drawRound dpy d gc x y w h r0
  | r <= 0    = drawRectangle dpy d gc (fi x) (fi y) (fi w) (fi h)
  | otherwise = do
      drawLine dpy d gc (fi (x + r)) (fi y)       (fi (x + w - r)) (fi y)
      drawLine dpy d gc (fi (x + r)) (fi (y + h)) (fi (x + w - r)) (fi (y + h))
      drawLine dpy d gc (fi x)       (fi (y + r)) (fi x)           (fi (y + h - r))
      drawLine dpy d gc (fi (x + w)) (fi (y + r)) (fi (x + w))     (fi (y + h - r))
      forM_ (corners x y w h r) $ \(ax, ay, a) ->
        drawArc dpy d gc (fi ax) (fi ay) (fi (2*r)) (fi (2*r)) (fi a) (90*64)
  where r = clampR w h r0

-- | Run a drawing action with a GC that paints @col@ through a 2x2
-- checkerboard stipple, laying the colour over the existing pixels at ~50%
-- coverage -- the closest core X gets to alpha blending.
withHalfTone :: Display -> Drawable -> String -> (GC -> IO ()) -> IO ()
withHalfTone dpy d col act = do
    stip <- createPixmap dpy d 2 2 1
    gc <- createGC dpy stip
    setForeground dpy gc 0
    fillRectangle dpy stip gc 0 0 2 2
    setForeground dpy gc 1
    drawPoint dpy stip gc 0 0
    drawPoint dpy stip gc 1 1
    freeGC dpy gc
    gc' <- createGC dpy d
    Just c <- initColor dpy col
    setForeground dpy gc' c
    setStipple dpy gc' stip
    setFillStyle dpy gc' fillStippled
    act gc'
    freeGC dpy gc'
    freePixmap dpy stip

-- | Build a reusable GC that paints solid black through a 2x2 checkerboard
-- stipple (~50% coverage), for every card's drop shadow.  Created once per grid
-- instead of allocating a pixmap+GC per card per frame.  Returns the GC and its
-- stipple pixmap (the GC references it, so both must outlive drawing and be
-- freed together).
mkShadowGC :: Display -> Drawable -> IO (GC, Pixmap)
mkShadowGC dpy d = do
    stip <- createPixmap dpy d 2 2 1
    g <- createGC dpy stip
    setForeground dpy g 0
    fillRectangle dpy stip g 0 0 2 2
    setForeground dpy g 1
    drawPoint dpy stip g 0 0
    drawPoint dpy stip g 1 1
    freeGC dpy g
    gc <- createGC dpy d
    Just black <- initColor dpy "#000000"
    setForeground dpy gc black
    setStipple dpy gc stip
    setFillStyle dpy gc fillStippled
    return (gc, stip)

-- | Poor man's anti-aliasing for rounded corners: stroke the corner arcs,
-- inflated by one pixel, in the shape's own colour at 50% dithered coverage.
-- This half-steps the luminance ramp at the stair-cased corners; straight
-- edges are left alone (they need no smoothing).
softenCorners :: Display -> Drawable -> String -> Integer -> Integer -> Integer -> Integer -> Integer -> IO ()
softenCorners dpy d col x y w h r0 =
    when (r > 0) $
      withHalfTone dpy d col $ \gc ->
        forM_ (corners (x - 1) (y - 1) (w + 2) (h + 2) (r + 1)) $ \(ax, ay, a) ->
          drawArc dpy d gc (fi ax) (fi ay) (fi (2*(r+1))) (fi (2*(r+1))) (fi a) (90*64)
  where r = clampR w h r0

-- | Index of the first case-insensitive occurrence of @q@ in @s@.
findCI :: String -> String -> Maybe Int
findCI q s = findIndex (map toUpper q `isPrefixOf`) (tails (map toUpper s))

-- | Greedy word-wrap @text@ into at most @maxLines@ lines that each fit @maxW@
-- pixels in @font@.  Anything beyond the budget is merged into the final line,
-- and every line is ellipsised if it still overruns (so a single over-long word
-- can't spill out).  With @maxLines == 1@ this reduces to the old single-line
-- shrink, so existing behaviour is unchanged.
wrapText :: Display -> XMonadFont -> Integer -> Int -> String -> X [String]
wrapText dpy font maxW maxLines text = do
    wrapped <- wrapWords "" (words text)
    let lns | length wrapped <= maxLines = wrapped
            | otherwise = take (maxLines - 1) wrapped
                       ++ [unwords (drop (maxLines - 1) wrapped)]
    mapM shrinkToFit lns
  where
    width s     = liftIO (textWidthXMF dpy font s)
    fits s      = (<= fromInteger maxW) <$> width s
    shrinkToFit = shrinkWhile (shrinkIt shrinkText)
                              (\n -> (> fromInteger maxW) <$> width n)
    -- Greedy wrap; @cur@ is the line being built ("" = empty).  A word that
    -- won't fit starts a fresh line; a word too wide even for an empty line is
    -- either hard-broken mid-character (sBreakWords) or left to be ellipsised.
    wrapWords cur []       = return [cur | not (null cur)]
    wrapWords cur (w : ws) = do
      let cand = if null cur then w else cur ++ " " ++ w
      f <- fits cand
      if f then wrapWords cand ws
      else if not (null cur)
             then (cur :) <$> wrapWords "" (w : ws)        -- close line, retry word
             else if sBreakWords style
                    then do                                -- word too wide: hard-break
                      (piece, rest) <- splitToWidth w
                      if null rest then wrapWords piece ws
                                   else (piece :) <$> wrapWords "" (rest : ws)
                    else (w :) <$> wrapWords "" ws          -- leave it; ellipsised later
    -- Longest character prefix of @s@ that fits @maxW@, plus the remainder;
    -- always takes at least one character so it can't loop.
    splitToWidth = go ""
      where go acc []       = return (acc, "")
            go acc (c : cs) = do
              f <- fits (acc ++ [c])
              if f then go (acc ++ [c]) cs
                   else return (if null acc then ([c], cs) else (acc, c : cs))

-- | A window cell: rounded fill, optional bevel (top highlight + bottom shadow),
-- optional accent border of width @bw@, an optional icon at the left, then the
-- left-aligned title.  First colour of the tuple is the FILL, second is the
-- TEXT.  When @hl@ is @Just (query, col)@, the first case-insensitive occurrence
-- of the query in the (shrunken) title is drawn in @col@.
drawWinBox :: Drawable -> GC -> XMonadFont -> (String, String) -> Maybe (String, String) -> Maybe IconImg -> Maybe Pixmap -> String -> Integer -> Integer -> Integer -> Integer -> [String] -> Integer -> Integer -> Integer -> X ()
drawWinBox d shadowGC font (fillC, textC) hl mico mpm bc bw rise ch cw lns x y cp =
  withDisplay $ \dpy -> do
  gc <- liftIO $ createGC dpy d
  -- The CARD is the content box grown by @rise@ on every side (a selected cell
  -- "lifts").  Crucially the text/icon layout below uses the *content* box
  -- (x, y, cw, ch), so it never reflows when a cell is selected -- only the card
  -- rectangle changes size.
  let rad = sCornerRadius style
      cx = x - rise; cy = y - rise
      ccw = cw + 2 * rise; cch = ch + 2 * rise
  liftIO $ do
    when (sShadow style > 0) $ do
      let o = sShadow style
      fillRound dpy d shadowGC (cx + o) (cy + o) ccw cch rad
    Just fillcolor <- initColor dpy fillC
    setForeground dpy gc fillcolor
    fillRound dpy d gc cx cy ccw cch rad
    when (sSoftCorners style) $ softenCorners dpy d fillC cx cy ccw cch rad
    when (sBevel style) $ do
      Just hiC <- initColor dpy (mixHex fillC "#ffffff" 0.16)
      Just loC <- initColor dpy (mixHex fillC "#000000" 0.32)
      let r = clampR ccw cch rad
      setForeground dpy gc hiC
      drawLine dpy d gc (fi (cx + r)) (fi (cy + 1))       (fi (cx + ccw - r)) (fi (cy + 1))
      setForeground dpy gc loC
      drawLine dpy d gc (fi (cx + r)) (fi (cy + cch - 2)) (fi (cx + ccw - r)) (fi (cy + cch - 2))
    when (bw > 0) $ do
      Just bordercolor <- initColor dpy bc
      setForeground dpy gc bordercolor
      setLineAttributes dpy gc (fi bw) lineSolid capButt joinMiter
      drawRound dpy d gc cx cy ccw cch rad
      setLineAttributes dpy gc 1 lineSolid capButt joinMiter
    -- icon at the left, vertically centred.  A pre-composited pixmap (@mpm@,
    -- for base-fill cells) is just blitted; otherwise composite live.
    forM_ mico $ \ii ->
      let iy = y + (ch - fi (iiH ii)) `div` 2
      in case mpm of
           Just pm -> copyArea dpy pm d gc 0 0 (fi (iiW ii)) (fi (iiH ii))
                               (fi (x + cp)) (fi iy)
           Nothing -> drawIcon dpy d fillC (x + cp) iy ii
  -- reserve the icon's width + the configured gap before the title; @lns@ is
  -- pre-wrapped (computed once at open) so no per-frame text measurement happens
  let iconAdv = maybe 0 (\ii -> fi (iiW ii) + fromMaybe 0 (sIcon style)) mico
  (asc, desc) <- liftIO $ textExtentsXMF font (if null lns then "Ag" else head lns)
  let n      = fromIntegral (length lns)
      lineH  = fromIntegral (asc + desc)            -- per-line advance
      lead   = if length lns > 1 then 2 else 0      -- small inter-line leading
      blockH = n * lineH + (n - 1) * lead
      top    = y + (ch - blockH) `div` 2            -- top of the centred block
      tx     = fromInteger (x + cp + iconAdv)
      -- print one line at baseline @ty@, with the matched substring (if any)
      -- in the highlight colour
      printLine ty ln = case hl of
        Just (q, hlC) | not (null q), Just i <- findCI q ln -> do
            let (pre, rest) = splitAt i ln
                (mid, post) = splitAt (length q) rest
            wPre <- liftIO $ textWidthXMF dpy font pre
            wMid <- liftIO $ textWidthXMF dpy font mid
            printStringXMF dpy d font gc textC fillC tx ty pre
            printStringXMF dpy d font gc hlC   fillC (tx + fromIntegral wPre) ty mid
            printStringXMF dpy d font gc textC fillC (tx + fromIntegral (wPre + wMid)) ty post
        _ -> printStringXMF dpy d font gc textC fillC tx ty ln
  forM_ (zip [0 ..] lns) $ \(i, ln) ->
    printLine (fromInteger (top + i * (lineH + lead) + fromIntegral asc)) ln
  liftIO $ freeGC dpy gc

-- | Draw text horizontally+vertically centred in a cell-sized region, with NO
-- fill and NO border (used for headers).  With an Xft font the glyphs are drawn
-- over whatever is already there, so the header has a transparent background.
drawCenteredText :: Drawable -> XMonadFont -> (String, String) -> String -> Integer -> Integer -> Integer -> Integer -> X ()
drawCenteredText d font (fg, bg) text cw ch x y =
  withDisplay $ \dpy -> do
  gc <- liftIO $ createGC dpy d
  stext <- shrinkWhile (shrinkIt shrinkText)
           (\n -> do size <- liftIO $ textWidthXMF dpy font n
                     return $ size > fromInteger cw)
           text
  tw <- liftIO $ textWidthXMF dpy font stext
  (asc, desc) <- liftIO $ textExtentsXMF font stext
  let m  = headerMargin
      tx = x + (cw - fromIntegral tw) `div` 2
      ty = y + ((ch - fromIntegral (asc + desc)) `div` 2) + fromIntegral asc
      rx = tx - m
      ry = ty - fromIntegral asc - m
      rw = fromIntegral tw + 2 * m
      rh = fromIntegral (asc + desc) + 2 * m
  -- draw the padded (rounded) background pill, then the text on top
  liftIO $ do
    let prad = min (sCornerRadius style) (rh `div` 2)
    Just bgcolor <- initColor dpy bg
    setForeground dpy gc bgcolor
    fillRound dpy d gc rx ry rw rh prad
    when (sSoftCorners style) $ softenCorners dpy d bg rx ry rw rh prad
  printStringXMF dpy d font gc fg bg (fromInteger tx) (fromInteger ty) stext
  liftIO $ freeGC dpy gc

-- | Pixel offset that centres the element-map bounding box on screen.  Centring
-- the box (rather than pinning cell x=0 to the middle) keeps the grid centred even
-- when the column/row count is even and the centred indices are asymmetric.
paneOffsets :: TwoDState a -> (Integer, Integer)
paneOffsets s = ( off (td_paneX s) (gs_cellwidth gsconfig)  (map (fst . fst) emap)
                , off (td_paneY s) (gs_cellheight gsconfig) (map (snd . fst) emap) )
  where
    gsconfig = td_gsconfig s
    emap = td_elementmap s
    off pane cell vs
      | null vs   = div (pane - cell) 2
      | otherwise = div (pane - (maximum vs - minimum vs + 1) * cell) 2 - minimum vs * cell

-- | Draw the given cells.  Matching cells are shaded by stack depth (shallow/top
-- light, deep/bottom dark); the cursor cell uses the accent; cells that don't
-- match the current search are greyed out.  Depth is read from the FULL map so it
-- stays stable while searching.
updateElements :: TwoDElementMap a -> TwoD a ()
updateElements toDraw = do
    s <- get
    let gsconfig = td_gsconfig s
        cw = gs_cellwidth gsconfig
        ch = gs_cellheight gsconfig
        (paneX', paneY') = paneOffsets s
        curpos = td_curpos s
        buf = td_buffer s
        font = td_font s
        hfont = td_headerFont s
        q = td_searchString s
        headers = td_headerPos s
        -- depth is measured among window cells only (headers excluded)
        colsY = M.fromListWith (++) [ (x, [y]) | ((x, y), _) <- td_elementmap s
                                               , (x, y) `notElem` headers ]
        maxDepth = maximum (1 : [ maximum ys - minimum ys | ys <- M.elems colsY ])
        -- left-to-right column order, for per-column accent colours
        colXs = sort . nub $ map (fst . fst) (td_elementmap s)
        colColor x = columnColors !! (fromMaybe 0 (elemIndex x colXs) `mod` length columnColors)
        -- returns (fg, bg); the header bg is unused (headers draw their own pill)
        styleFor pos@(x, y) label
          | pos `elem` headers =
              let (plain, lighter) = colColor x
                  fg | pos == curpos    = lighter    -- selected header: brighter column colour
                     | matchesQ q label = plain      -- normal header: column colour
                     | otherwise        = grayedFg   -- non-matching header: dim, like other cells
              in (fg, plain)
          | otherwise =
              let base = shadeFor maxDepth (y - minimum (M.findWithDefault [y] x colsY))
                  (fg, bg)
                    -- selection: lighter accent text on an accent-tinted fill
                    | pos == curpos    = (snd (colColor x), mixHex base (fst (colColor x)) 0.18)
                    | matchesQ q label = (cellText, base)
                    -- search non-match: dim text on a darkened fill
                    | otherwise        = (grayedFg, mixHex base "#000000" 0.40)
              in (fg, bg)
        icons = td_icons s
        sgc = td_shadowGC s
        -- a cell whose fill is exactly its base shade (matching, not cursor) can
        -- reuse the pre-composited icon pixmap; build+cache it on first use
        cachedIconPm pos bg ii = liftX $ withDisplay $ \dpy -> liftIO $ do
          cache <- readIORef (td_iconPm s)
          case M.lookup pos cache of
            Just pm -> return pm
            Nothing -> do
              let depth = defaultDepthOfScreen (defaultScreenOfDisplay dpy)
              pm <- createPixmap dpy (td_buffer s) (fi (iiW ii)) (fi (iiH ii)) depth
              drawIcon dpy pm bg 0 0 ii
              modifyIORef' (td_iconPm s) (M.insert pos pm)
              return pm
        draw ((x, y), (text, _)) =
            let (fg, bg) = styleFor (x, y) text
                px = paneX' + x * cw
                py = paneY' + y * ch
            in if (x, y) `elem` headers
                 -- headers: centred text on a rounded pill
                 then liftX $ drawCenteredText buf hfont (fg, headerBg) text cw ch px py
                 -- windows: inset rounded card; the cursor cell gets an accent
                 -- stroke and a slightly larger ("raised") card.  The content
                 -- box is ALWAYS the base inset, so the title never reflows on
                 -- selection; only the card grows, by @rise@.
                 else do
                   let g = sCellInset style
                       rise | (x, y) == curpos = sRaise style
                            | otherwise        = 0
                       (bcol, bw) | (x, y) == curpos = (fst (colColor x), sSelStroke style)
                                  | otherwise        = ("#000000", 0)
                       -- highlight the matched part of the title.  On the cursor
                       -- cell the rest of the text is the lighter accent, so draw
                       -- the match in the SAME hue but a darker shade.
                       hl | null q || not (matchesQ q text) = Nothing
                          | (x, y) == curpos = Just (q, mixHex (snd (colColor x)) "#000000" 0.35)
                          | otherwise        = Just (q, fst (colColor x))
                       mico = M.lookup (x, y) icons
                       lns  = M.findWithDefault [text] (x, y) (td_wrap s)
                       usePre = matchesQ q text && (x, y) /= curpos   -- fill == base shade
                   mpm <- case mico of
                            Just ii | usePre -> Just <$> cachedIconPm (x, y) bg ii
                            _                -> return Nothing
                   liftX $ drawWinBox buf sgc font (bg, fg) hl mico mpm bcol bw rise
                                      (ch - 2*g) (cw - 2*g) lns (px + g) (py + g)
                                      (gs_cellpadding gsconfig)
    mapM_ draw toDraw

makeXEventhandler :: ((KeySym, String, KeyMask) -> TwoD a (Maybe a)) -> TwoD a (Maybe a)
makeXEventhandler keyhandler = fix $ \me -> join $ liftX $ withDisplay $ \d -> liftIO $ allocaXEvent $ \e -> do
                             maskEvent d (exposureMask .|. keyPressMask .|. buttonReleaseMask) e
                             ev <- getEvent e
                             if ev_event_type ev == keyPress
                               then do
                                  (_, s) <- lookupString $ asKeyEvent e
                                  ks <- keycodeToKeysym d (ev_keycode ev) 0
                                  return $ do
                                      mask <- liftX $ cleanKeyMask <*> pure (ev_state ev)
                                      keyhandler (ks, s, mask)
                               else
                                  return $ stdHandle ev me

shadowWithKeymap :: M.Map (KeyMask, KeySym) a -> ((KeySym, String, KeyMask) -> a) -> (KeySym, String, KeyMask) -> a
shadowWithKeymap keymap dflt keyEvent@(ks, _, m') = fromMaybe (dflt keyEvent) (M.lookup (m', ks) keymap)

select :: TwoD a (Maybe a)
select = do
  s <- get
  -- Only the active (matching) cells are selectable.
  return $ snd . snd <$> findInElementMap (td_curpos s) (activeMap s)

cancel :: TwoD a (Maybe a)
cancel = return Nothing

-- | Sets the absolute position of the cursor, redrawing ONLY the old and new
-- cells (not the whole grid), so navigation stays cheap even with many windows.
setPos :: (Integer, Integer) -> TwoD a ()
setPos newPos = do
  s <- get
  let amap = activeMap s
      newSelectedEl = findInElementMap newPos amap
      oldPos = td_curpos s
  when (isJust newSelectedEl && newPos /= oldPos) $ do
    put s { td_curpos = newPos }
    redrawCells [oldPos, newPos]

-- | Restore the backdrop under the given cell slots, redraw just those cells,
-- refresh the search pill, and blit.  Each slot fully contains its card, raise
-- and shadow (since sCellInset >= sRaise + sShadow), so neighbours are untouched.
redrawCells :: [TwoDPosition] -> TwoD a ()
redrawCells ps = do
  s <- get
  let gsconfig = td_gsconfig s
      cw = gs_cellwidth gsconfig
      ch = gs_cellheight gsconfig
      (ox, oy) = paneOffsets s
      m   = min (sCellInset style) (sRaise style + sShadow style) + 1
      buf = td_buffer s
      cells = [ e | e@(p, _) <- td_elementmap s, p `elem` ps ]
  liftX $ withDisplay $ \dpy -> liftIO $ do
    gc <- createGC dpy buf
    forM_ ps $ \(x, y) ->
      copyArea dpy (td_backdrop s) buf gc
               (fi (ox + x * cw - m)) (fi (oy + y * ch - m))
               (fi (cw + 2 * m)) (fi (ch + 2 * m))
               (fi (ox + x * cw - m)) (fi (oy + y * ch - m))
    freeGC dpy gc
  updateElements cells
  drawQuery
  blitBuffer

-- | Mouse click / expose handling.
stdHandle :: Event -> TwoD a (Maybe a) -> TwoD a (Maybe a)
stdHandle ButtonEvent{ ev_event_type = t, ev_x = x, ev_y = y } contEventloop
    | t == buttonRelease = do
        s@TwoDState{ td_paneX = px
                   , td_paneY = py
                   , td_gsconfig = GSConfig{ gs_cellheight = ch
                                           , gs_cellwidth = cw
                                           , gs_cancelOnEmptyClick = cancelOnEmptyClick
                                           }
                   } <- get
        let (paneX', paneY') = paneOffsets s
            gridX = (fi x - paneX') `div` cw
            gridY = (fi y - paneY') `div` ch
        case lookup (gridX, gridY) (activeMap s) of   -- only matching cells are clickable
             Just (_, el) -> return (Just el)
             Nothing      -> if cancelOnEmptyClick
                             then return Nothing
                             else contEventloop
    | otherwise = contEventloop
stdHandle ExposeEvent{} contEventloop = blitBuffer >> contEventloop
stdHandle _ contEventloop = contEventloop

-- ---------------------------------------------------------------------------
-- Search filtering: the element map never changes; we just compute which cells
-- currently match and draw/navigate only those.
-- ---------------------------------------------------------------------------

-- | Case-insensitive substring test ("" matches everything).
matchesQ :: String -> String -> Bool
matchesQ q label = map toUpper q `isInfixOf` map toUpper label

-- | Cells that are currently selectable/navigable: any cell (window OR workspace
-- header) whose label matches the search string.
activeMap :: TwoDState a -> TwoDElementMap a
activeMap s = L.filter (matchesQ (td_searchString s) . fst . snd) (td_elementmap s)

-- | Compose the full frame into the off-screen buffer -- backdrop (scrim or
-- desktop snapshot), every cell (matches shaded by depth, non-matches dimmed),
-- the column headers, the outer border -- then blit it to the window in one
-- copy, so nothing ever flickers.  Columns never move; only colours change as
-- you search.
redrawAll :: TwoD a ()
redrawAll = do
  s <- get
  let buf = td_buffer s
  liftX $ withDisplay $ \dpy -> liftIO $ do
    gc <- createGC dpy buf
    case sScrim style of
      Just col -> do                       -- solid backdrop fill
        Just c <- initColor dpy col
        setForeground dpy gc c
        fillRectangle dpy buf gc 0 0 (fi (td_paneX s)) (fi (td_paneY s))
      Nothing ->                           -- the desktop snapshot shows through
        copyArea dpy (td_backdrop s) buf gc 0 0
                 (fi (td_paneX s)) (fi (td_paneY s)) 0 0
    freeGC dpy gc
  updateElements (td_elementmap s)
  drawBorder
  drawQuery
  blitBuffer

-- | While searching, float the current query in a pill near the bottom of the
-- screen (drawn after the cells, so it sits on top of the grid).
drawQuery :: TwoD a ()
drawQuery = do
  s <- get
  let q  = td_searchString s
      ch = gs_cellheight (td_gsconfig s)
  unless (null q) $ liftX $
    drawCenteredText (td_buffer s) (td_headerFont s) (cellText, headerBg) q
                     (td_paneX s) ch 0 (td_paneY s - 2 * ch)

-- | Copy the finished frame to the visible window in a single X request.
blitBuffer :: TwoD a ()
blitBuffer = do
  s <- get
  liftX $ withDisplay $ \dpy -> liftIO $ do
    gc <- createGC dpy (td_drawingWin s)
    copyArea dpy (td_buffer s) (td_drawingWin s) gc 0 0
             (fi (td_paneX s)) (fi (td_paneY s)) 0 0
    freeGC dpy gc

-- | A chernoe_dark outline a few pixels thick around the whole selector.  Only
-- drawn over a solid scrim; with the desktop snapshot a screen-edge frame would
-- just look like a stuck border.
drawBorder :: TwoD a ()
drawBorder = do
  s <- get
  when (isJust (sScrim style)) $ do
    let buf = td_buffer s
        pw  = td_paneX s
        phh = td_paneY s
    liftX $ withDisplay $ \dpy -> liftIO $ do
      gc <- createGC dpy buf
      Just c <- initColor dpy gridBorder
      setForeground dpy gc c
      forM_ [0, 1, 2 :: Integer] $ \i ->
        drawRectangle dpy buf gc (fromIntegral i) (fromIntegral i)
                      (fromIntegral (pw - 1 - 2 * i)) (fromIntegral (phh - 1 - 2 * i))
      freeGC dpy gc

-- | Append to / edit the search string, fix up the cursor if it landed on a
-- now-blanked cell, and redraw.
columnSearch :: (String -> String) -> TwoD a ()
columnSearch f = do
  s <- get
  let old = td_searchString s
      new = f old
  when (new /= old) $ do
    let s'  = s { td_searchString = new }
        act = activeMap s'
        cur | isJust (findInElementMap (td_curpos s') act) = td_curpos s'
            | null act  = td_curpos s'
            | otherwise = centralPos act
    put s' { td_curpos = cur }
    redrawAll

-- ---------------------------------------------------------------------------
-- Column-aware navigation (operates only on matching cells).
-- ---------------------------------------------------------------------------

-- | Move up/down to the nearest matching cell in the current column.
moveVert :: Integer -> TwoD a ()
moveVert dir = do
  s <- get
  let act = activeMap s
      (cx, cy) = td_curpos s
      -- active cells in column x that lie in the press direction from the cursor
      inDir x = [ y | ((x', y), _) <- act, x' == x
                    , (dir > 0 && y > cy) || (dir < 0 && y < cy) ]
      pick x ys = setPos (x, if dir > 0 then minimum ys else maximum ys)
  case inDir cx of
    ys@(_:_) -> pick cx ys   -- normal: a cell exists in this direction in the column
    []       ->              -- none here: hop to the nearest column that has one
      let cands = sortBy (comparing (\x -> (abs (x - cx), x)))
                         [ x | x <- nub (map (fst . fst) act)
                             , x /= cx, not (null (inDir x)) ]
      in case cands of
           (x:_) -> pick x (inDir x)
           []    -> return ()

-- | Jump to the nearest matching cell (by row) in the adjacent column that still
-- has matches, wrapping around at the ends.
moveCol :: Integer -> TwoD a ()
moveCol dir = do
  s <- get
  let act = activeMap s
      (cx, cy) = td_curpos s
      xs = sort . nub $ map (fst . fst) act
  unless (null xs) $ do
    let targetX
          | dir > 0   = fromMaybe (head xs) (find (> cx) xs)
          | otherwise = fromMaybe (last xs) (find (< cx) (reverse xs))
        ys = [ y | ((x, y), _) <- act, x == targetX ]
    unless (null ys) $
      setPos (targetX, minimumBy (comparing (\y -> abs (y - cy))) ys)

-- | Arrows navigate; Tab selects; typed characters filter; Backspace edits;
-- Return selects; Escape cancels.  As a one-handed alternative to the arrows,
-- the bare modifier keys also navigate (these bindings live only here, so they
-- have no effect outside the grid): Ctrl/Alt = left/right, Shift/Super =
-- up/down.  Pressed alone a modifier emits a KeyPress whose state is the
-- pre-press state, hence mask 0.
columnNavigation :: TwoD a (Maybe a)
columnNavigation = makeXEventhandler $ shadowWithKeymap navKeyMap navDefault
  where
    nav act = act >> columnNavigation
    navKeyMap = M.fromList $
      [ ((0, xK_Escape),     cancel)
      , ((0, xK_Return),     select)
      , ((0, xK_Tab),        select)
      , ((0, xK_Up),         nav (moveVert (-1)))
      , ((0, xK_Down),       nav (moveVert 1))
      , ((0, xK_Left),       nav (moveCol (-1)))
      , ((0, xK_Right),      nav (moveCol 1))
      , ((0, xK_BackSpace),  nav (columnSearch (\q -> if null q then q else init q)))
      ] ++
      -- bare modifier keys as navigation (both L/R variants where they exist)
      [ ((0, k), nav (moveCol (-1)))  | k <- [xK_Control_L, xK_Control_R] ] ++
      [ ((0, k), nav (moveCol 1))     | k <- [xK_Alt_L, xK_Alt_R, xK_Meta_L, xK_Meta_R] ] ++
      [ ((0, k), nav (moveVert (-1))) | k <- [xK_Shift_L, xK_Shift_R] ] ++
      [ ((0, k), nav (moveVert 1))    | k <- [xK_Super_L, xK_Super_R] ]
    navDefault (_, str, _) = do
      unless (null str) $ columnSearch (++ str)
      columnNavigation

-- ---------------------------------------------------------------------------
-- Placement and entry points.
-- ---------------------------------------------------------------------------

-- | Integer indices centred on the origin: centred 3 = [-1,0,1].
centred :: Int -> [Integer]
centred n = [ fromIntegral (i - (n - 1) `div` 2) | i <- [0 .. n - 1] ]

-- | Columns left-to-right (x centred), each column TOP-ALIGNED: every column
-- starts at the same top row, so the workspace-name headers line up in a single
-- row, and rows below increase with stack depth.  The whole block is centred
-- vertically on the tallest column.
columnsToElementMap :: [[(String, a)]] -> TwoDElementMap a
columnsToElementMap cols =
    [ ((x, topY + fromIntegral r), cell)
    | (x, col) <- zip (centred (length cols)) cols
    , (r, cell) <- zip [0 :: Int ..] col ]
  where
    maxRows = maximum (1 : map length cols)
    topY    = negate (fromIntegral ((maxRows - 1) `div` 2)) :: Integer

-- | Most central existing cell (fallback start / post-filter cursor).
centralPos :: TwoDElementMap a -> TwoDPosition
centralPos = fst . minimumBy (comparing (\((x, y), _) -> abs x + abs y))

-- | The engine setup, like upstream 'gridselect' but with a prebuilt element map
-- (which positions are headers is given separately), a start position, a map of
-- raw per-cell icons (scaled here, once the final cell size is known), and
-- 'columnNavigation'.
gridselectColumns :: GSConfig a -> [TwoDPosition] -> TwoDPosition -> M.Map TwoDPosition RawIcon -> TwoDElementMap a -> X (Maybe a)
gridselectColumns gsconfig headerPos startPos rawIcons emap
  | null emap = return Nothing
  | otherwise =
 withDisplay $ \dpy -> do
    rootw <- asks theRoot
    scr <- gets $ screenRect . W.screenDetail . W.current . windowset
    win <- liftIO $ mkUnmanagedWindow dpy (defaultScreenOfDisplay dpy) rootw
                    (rect_x scr) (rect_y scr) (rect_width scr) (rect_height scr)
    -- Snapshot the screen BEFORE mapping our window (pseudo-transparent
    -- backdrop, no compositor needed) and allocate the off-screen frame buffer.
    (backdrop, buffer) <- liftIO $ do
        let depth = defaultDepthOfScreen (defaultScreenOfDisplay dpy)
        bd <- createPixmap dpy rootw (rect_width scr) (rect_height scr) depth
        bf <- createPixmap dpy rootw (rect_width scr) (rect_height scr) depth
        gc <- createGC dpy bd
        setSubwindowMode dpy gc includeInferiors   -- capture client windows too
        copyArea dpy rootw bd gc (fi (rect_x scr)) (fi (rect_y scr))
                 (rect_width scr) (rect_height scr) 0 0
        freeGC dpy gc
        -- dim the snapshot once, here, so per-frame redraws pay nothing
        case sDim style of
          DimTint col opacity ->
            dimPixmap dpy bd (rect_width scr) (rect_height scr) col opacity
          DimShift n ->
            dimPixmapShift dpy bd (rect_width scr) (rect_height scr) n
          DimNone -> return ()
        return (bd, bf)
    liftIO $ mapWindow dpy win
    liftIO $ selectInput dpy win (exposureMask .|. keyPressMask .|. buttonReleaseMask)
    status <- io $ grabKeyboard dpy win True grabModeAsync grabModeAsync currentTime
    void $ io $ grabPointer dpy win True buttonReleaseMask grabModeAsync grabModeAsync none none currentTime
    -- measure the (unscaled) base font's line height so we can grow the cell
    -- to fit sNumLines before any fit-to-screen scaling happens
    font0 <- initXMF (gs_font gsconfig)
    (basc, bdesc) <- liftIO $ textExtentsXMF font0 "Ag"
    releaseXMF font0
    let screenWidth = toInteger $ rect_width scr
        screenHeight = toInteger $ rect_height scr
        -- treat the configured gs_cellheight as the single-line height and add
        -- one font line-height (plus leading) per extra wrapped line
        nLines = max 1 (sNumLines style)
        lineH  = fromIntegral (basc + bdesc)
        lead   = if nLines > 1 then 2 else 0
        baseCH = gs_cellheight gsconfig + fromIntegral (nLines - 1) * (lineH + lead)
        -- widen the cards when there are few columns (k at 1 col, tapering as
        -- 1 + (k-1)/ncols); fit-to-screen below still shrinks if it overflows
        widen  = max 1 (1 + (sColWiden style - 1) / fromIntegral ncols)
        baseCW = round (fromIntegral (gs_cellwidth gsconfig) * widen)
        baseConf = gsconfig { gs_cellheight = baseCH, gs_cellwidth = baseCW }
        -- Fit-to-screen: if the grid would run past the screen edge (minus
        -- sEdgeMargin on each side), shrink the cells and the fonts together
        -- by one uniform factor, so the layout always fits with a margin.
        ncols = maximum (map (fst . fst) emap) - minimum (map (fst . fst) emap) + 1
        nrows = maximum (map (snd . fst) emap) - minimum (map (snd . fst) emap) + 1
        avail d = fromIntegral (d - 2 * sEdgeMargin style) :: Double
        scale = minimum
          [ 1
          , avail screenWidth  / fromIntegral (ncols * gs_cellwidth baseConf)
          , avail screenHeight / fromIntegral (nrows * gs_cellheight baseConf) ]
        scaleI n = max 1 (floor (fromIntegral n * scale))
        gsconfig' = baseConf { gs_cellwidth   = scaleI (gs_cellwidth baseConf)
                             , gs_cellheight  = scaleI (gs_cellheight baseConf)
                             , gs_cellpadding = scaleI (gs_cellpadding baseConf) }
        -- scale icons to fit the (now final) card height, leaving inset + a
        -- little breathing room above and below, then apply sIconScale
        iconBox = floor (sIconScale style
                         * fromIntegral (gs_cellheight gsconfig' - 2 * sCellInset style - 6))
        icons | isJust (sIcon style) && iconBox >= 8 = M.map (scaleIcon iconBox) rawIcons
              | otherwise                            = M.empty
    font <- initXMF (scaleFontSize scale (gs_font gsconfig))
    hfont <- initXMF (scaleFontSize scale (fromMaybe (gs_font gsconfig) (sHeaderFont style)))
    -- Pre-wrap every window title ONCE (the wrap width is selection-independent),
    -- so per-frame redraws do no text measurement.
    let g'  = sCellInset style
        cp' = gs_cellpadding gsconfig'
        availOf pos = (gs_cellwidth gsconfig' - 2 * g') - 2 * cp'
                    - maybe 0 (\ii -> fromIntegral (iiW ii) + fromMaybe 0 (sIcon style))
                              (M.lookup pos icons)
    wrapMap <- fmap M.fromList $ forM [ (p, t) | (p, (t, _)) <- emap, p `notElem` headerPos ] $
                 \(p, t) -> (,) p <$> wrapText dpy font (availOf p) nLines t
    -- one shared black-stipple GC for all card shadows (vs a pixmap+GC per card)
    (shadowGC, shadowStip) <- liftIO (mkShadowGC dpy buffer)
    iconPmRef <- liftIO (newIORef M.empty)
    selected <- if status == grabSuccess
                  then do
                    let validStart = if isJust (findInElementMap startPos emap)
                                       then startPos else fst (head emap)
                        s = TwoDState { td_curpos = validStart
                                      , td_gsconfig = gsconfig'
                                      , td_font = font
                                      , td_headerFont = hfont
                                      , td_paneX = screenWidth
                                      , td_paneY = screenHeight
                                      , td_drawingWin = win
                                      , td_buffer = buffer
                                      , td_backdrop = backdrop
                                      , td_searchString = ""
                                      , td_elementmap = emap
                                      , td_headerPos = headerPos
                                      , td_icons = icons
                                      , td_wrap = wrapMap
                                      , td_shadowGC = shadowGC
                                      , td_iconPm = iconPmRef }
                    evalTwoD (redrawAll >> columnNavigation) s
                  else return Nothing
    liftIO $ do
      unmapWindow dpy win
      destroyWindow dpy win
      freeGC dpy shadowGC
      freePixmap dpy shadowStip
      readIORef iconPmRef >>= mapM_ (freePixmap dpy) . M.elems
      freePixmap dpy buffer
      freePixmap dpy backdrop
      ungrabPointer dpy currentTime
      sync dpy False
    releaseXMF font
    releaseXMF hfont
    return selected

-- | One column per (non-empty, non-NSP) workspace, in the given tag order, rows =
-- that workspace's windows, with a selectable workspace-name header above each
-- column.  A header's value is that workspace's master window, so selecting a
-- header focuses it -- i.e. switches to that workspace.  Opens on the currently
-- focused window when present.
gridselectWindowColumns :: GSConfig Window -> [WorkspaceId] -> X (Maybe Window)
gridselectWindowColumns conf order = do
    wset <- gets windowset
    let wsByTag t = find ((== t) . W.tag) (W.workspaces wset)
        winsOf t  = maybe [] (W.integrate' . W.stack) (wsByTag t)
        tags      = [ t | t <- order, t /= "NSP", not (null (winsOf t)) ]
    named <- forM tags $ \t -> do
               cells <- forM (winsOf t) $ \w -> do
                          name <- show <$> getName w
                          return (name, w)
               return (cleanTag t, cells)
    let windowCols = map snd named
        wEmap      = columnsToElementMap windowCols
        -- header cell sits one row above the (top-aligned) columns; its value is
        -- the column's master window (head of the stack list).
        topRow     = minimum (0 : map (snd . fst) wEmap)
        headerCells = [ ((x, topRow - 1), (name, snd (head col)))
                      | (x, (name, col)) <- zip (centred (length named)) named
                      , not (null col) ]
        headerPos = map fst headerCells
        emap      = headerCells ++ wEmap
    if null wEmap
      then return Nothing
      else do
        let focused  = W.peek wset
            -- start on the focused *window* cell (not a header), if present
            startPos = focused >>= \fw -> listToMaybe [ p | (p, (_, w)) <- wEmap, w == fw ]
        -- read each window's icon now (only the window cells, never headers);
        -- 64px is a safe ceiling for the source we ever downscale from.
        rawIcons <- if isJust (sIcon style)
                      then withDisplay $ \dpy -> do
                             atom <- liftIO $ internAtom dpy "_NET_WM_ICON" False
                             pairs <- forM wEmap $ \(pos, (_, w)) -> liftIO $
                                        fmap (\ri -> (pos, ri)) <$> readRawIcon dpy atom (sIconMaxSrc style) w
                             return (M.fromList (catMaybes pairs))
                      else return M.empty
        gridselectColumns conf headerPos (fromMaybe (centralPos wEmap) startPos) rawIcons emap
  where cleanTag = unwords . words   -- " chat " -> "chat" for the header

-- | Switch to the selected window's workspace and focus it.
goToSelectedColumns :: GSConfig Window -> [WorkspaceId] -> X ()
goToSelectedColumns conf order =
    gridselectWindowColumns conf order >>= flip whenJust (windows . W.focusWindow)

-- | Bring the selected window to the current workspace and focus it.
bringSelectedColumns :: GSConfig Window -> [WorkspaceId] -> X ()
bringSelectedColumns conf order =
    gridselectWindowColumns conf order >>= flip whenJust bring
  where bring w = do windows (bringWindow w)
                     XMonad.focus w
                     windows W.shiftMaster
