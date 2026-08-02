-----------------------------------------------------------------------------
-- |
-- Module      :  LimboView
-- Description :  greedyView without the two-monitor workspace swap.
--
-- Plain 'W.greedyView' swaps workspaces between monitors when the target is
-- visible on another screen.  'limboView' instead lets that other screen
-- retreat to the first *empty* hidden workspace, so pulling a workspace onto
-- the focused monitor never shoves the focused monitor's old workspace onto
-- the other one.  When every hidden workspace has windows there is nowhere
-- empty to retreat to, so it falls back to the plain greedyView swap.
-----------------------------------------------------------------------------

module LimboView (limboView) where

import Data.Maybe (isNothing)
import XMonad (WindowSet, WorkspaceId)
import qualified XMonad.StackSet as W

-- | Like 'W.greedyView', but when the target workspace is visible on another
-- screen, that screen is parked on the first empty hidden workspace (never
-- NSP) instead of taking over the focused screen's old workspace.  Works by
-- first viewing the empty workspace HERE, so the subsequent greedyView swap
-- hands the empty one -- not our old workspace -- to the other screen.
limboView :: WorkspaceId -> WindowSet -> WindowSet
limboView tag ws
  | tag `elem` map (W.tag . W.workspace) (W.visible ws)
  , (e:_) <- [ W.tag w | w <- W.hidden ws
             , isNothing (W.stack w), W.tag w /= "NSP" ]
      = W.greedyView tag (W.view e ws)
  | otherwise = W.greedyView tag ws
