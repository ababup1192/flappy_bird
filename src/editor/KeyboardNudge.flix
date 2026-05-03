// KeyboardNudge — 矢印キーで選択ノードを 1px / 10px 単位で動かす
//
// マウスドラッグでは 1px 精度の調整が辛いため、選択中ノードを矢印キーで
// 微調整できるようにする。Shift 押下中は 10px ステップ。
// JSON 書き戻しは押下毎に発生し、HotReload が次フレームでシーンを再構築する
// （選択 NodePath は維持されるため選択状態は保持される）。
//
// 押しっぱなしのオートリピートは未実装。1 タップ = 1 移動

mod KeyboardNudge {

    /// 矢印キー（4 方向）の押下状態スナップ。
    /// 前フレームと比較して「今フレームに押下したエッジ」を求めるのに使う
    pub type alias ArrowKeys = {
        up = Bool,
        down = Bool,
        left = Bool,
        right = Bool
    }

    /// 全部 false の初期値（エディタ未起動状態用）
    pub def initialPrev(): ArrowKeys =
        {up = false, down = false, left = false, right = false}

    /// 現在の矢印キー押下状態を読む
    pub def readArrows(): ArrowKeys \ GameEngine.Game = {
        up    = GameEngine.Game.isKeyPressed(GameEngine.Key.Up),
        down  = GameEngine.Game.isKeyPressed(GameEngine.Key.Down),
        left  = GameEngine.Game.isKeyPressed(GameEngine.Key.Left),
        right = GameEngine.Game.isKeyPressed(GameEngine.Key.Right)
    }

    /// 押下エッジ（前フレーム未押下 → 今フレーム押下）。
    /// 純粋関数なので単体テストしやすい
    pub def pressEdges(prev: ArrowKeys, cur: ArrowKeys): ArrowKeys = {
        up    = cur#up    and not prev#up,
        down  = cur#down  and not prev#down,
        left  = cur#left  and not prev#left,
        right = cur#right and not prev#right
    }

    /// 押下エッジから移動量を計算する。step は 1px か 10px を渡す
    pub def nudgeDelta(edges: ArrowKeys, step: Float64): Vec2.Vec2 =
        let dx = (if (edges#right) step else 0.0) - (if (edges#left) step else 0.0);
        let dy = (if (edges#down)  step else 0.0) - (if (edges#up)   step else 0.0);
        {x = dx, y = dy}

    /// 押下エッジに応じて選択ノードを動かし JSON に書き戻す。
    /// Shift 押下中は 10px、それ以外は 1px ステップ。
    /// 選択ノードがない / 動きがない場合は何もしない（ファイル書き込みも発生しない）。
    /// 動いたときは EditHistory.Rewind に nudge 直前の位置を save する
    pub def applyNudge(stateData: Editor.EditorStateData,
                       curArrows: ArrowKeys,
                       scene: Scene[NodeTag]):
            Scene[NodeTag] \ {EditHistory.Rewind, GameEngine.Game,
                              Fs.FileRead, Fs.FileWrite} =
        match stateData#selected {
            case None => scene
            case Some((jsonPath, nodePath)) =>
                let edges = pressEdges(stateData#prevArrowKeys, curArrows);
                let shift = GameEngine.Game.isKeyPressed(GameEngine.Key.LeftShift);
                let step = if (shift) 10.0 else 1.0;
                let delta = nudgeDelta(edges, step);
                if (delta#x == 0.0 and delta#y == 0.0) scene
                else moveAndSave(jsonPath, nodePath, delta, scene)
        }

    /// 選択ノードの global 位置を delta だけ動かして JSON に書き戻す。
    /// nudge 直前の位置を `EditHistory.Rewind.save` で記録する（Cmd+Z 用）
    def moveAndSave(jsonPath: String, nodePath: NodePath, delta: Vec2.Vec2,
                    scene: Scene[NodeTag]):
            Scene[NodeTag] \ {EditHistory.Rewind, Fs.FileRead, Fs.FileWrite} =
        let curGlobal = Scene.globalPositionAt(nodePath, scene);
        EditHistory.Rewind.save({jsonPath = jsonPath, nodePath = nodePath,
                                 prevWorldPos = curGlobal});
        let newGlobal = Vec2.add(curGlobal, delta);
        let newScene = Scene.setGlobalPositionAt(nodePath, newGlobal, scene);
        let localPos = match Scene.getEngineNode(nodePath, newScene) {
            case Some(engineNode) => Node2D.getPosition(engineNode)
            case None             => Vec2.zero()
        };
        SceneSerializer.updatePos(jsonPath, nodePath, localPos);
        newScene
}
