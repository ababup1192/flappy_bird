// DragInput — マウス入力 → 選択 → ドラッグ → 書き戻し のディスパッチ
//
// 押下／継続／離脱 のフレーム判定を `EditorStateData#prevMouseLeft` のエッジから行い、
// 編集対象ノードへの選択 / 移動 / JSON 書き戻し に振り分ける。
// 押下したがそのまま離した（クリック選択のみ）場合は位置が変わっていないので
// ファイル書き込みをスキップする（mtime 更新で HotReload を無駄打ちさせない）

mod DragInput {

    /// マウスの押下／継続／離脱を判定し、選択 / ドラッグ更新 / 書き戻し をディスパッチする
    pub def handleMouse(mousePos: Vec2.Vec2, mouseLeft: Bool,
                        stateData: Editor.EditorStateData,
                        scene: Scene[NodeTag]):
            (Editor.EditorStateData, Scene[NodeTag]) \
            {GameEngine.Game, Fs.FileRead, Fs.FileWrite} =
        let prevLeft = stateData#prevMouseLeft;
        let pressedNow = mouseLeft and not prevLeft;       // 押下したフレーム
        let releasedNow = (not mouseLeft) and prevLeft;    // 離した（ドロップ）フレーム
        if (pressedNow) {
            handleMouseDown(mousePos, stateData, scene)
        } else if (mouseLeft and Option.nonEmpty(stateData#dragOrigin)) {
            // ドラッグ中: 選択ノードの位置を更新（書き戻しはまだしない）
            (stateData, applyDrag(mousePos, stateData, scene))
        } else if (releasedNow and Option.nonEmpty(stateData#dragOrigin)) {
            // ドロップ: シーンの最終 pos を JSON に書き戻し（位置が変わっていれば）
            saveDraggedPos(stateData, scene)
        } else {
            (stateData, scene)
        }

    /// ドラッグ中: マウスの移動量に応じてノードのグローバル位置を更新する。
    /// ピクセル単位に整数スナップして「カクカク」動かす（drop 時の保存値とも一致する）。
    /// 単体テストしやすいよう pub。状態 + シーンに対して pure
    pub def applyDrag(mousePos: Vec2.Vec2, stateData: Editor.EditorStateData,
                      scene: Scene[NodeTag]): Scene[NodeTag] =
        match (stateData#selected, stateData#dragOrigin, stateData#nodeOrigin) {
            case (Some((_, nodePath)), Some(dragOrigin), Some(nodeOrigin)) =>
                let delta = Vec2.sub(mousePos, dragOrigin);
                let newGlobalPos = snapVec2(Vec2.add(nodeOrigin, delta));
                Scene.setGlobalPositionAt(nodePath, newGlobalPos, scene)
            case _ => scene
        }

    /// Vec2 を整数ピクセルに丸める（HotReload 後の JSON も整数値で残るようにするため）
    pub def snapVec2(v: Vec2.Vec2): Vec2.Vec2 =
        {x = Float64.round(v#x), y = Float64.round(v#y)}

    /// クリック押下時: 編集対象ノードのうち hit したものを選択し、ドラッグ開始状態にする
    def handleMouseDown(mousePos: Vec2.Vec2, stateData: Editor.EditorStateData,
                        scene: Scene[NodeTag]):
            (Editor.EditorStateData, Scene[NodeTag]) \ GameEngine.Game =
        let entries = EditableNode.collectAll(stateData#rootJsonIndex, scene);
        let hit = Picking.pickTopAt(mousePos, entries, scene);
        match hit {
            case None =>
                ({selected = None, dragOrigin = None, nodeOrigin = None | stateData}, scene)
            case Some((entry, nodeGlobalPos)) =>
                let newState = {
                    selected = Some((entry#jsonPath, entry#nodePath)),
                    dragOrigin = Some(mousePos),
                    nodeOrigin = Some(nodeGlobalPos)
                    | stateData
                };
                (newState, scene)
        }

    /// ドロップ: 現在のシーン上のノード位置を JSON に書き戻し、ドラッグ状態を解除する。
    /// 書き戻し対象は「ローカル位置」（JSON が pos として持つのはローカル座標のため）。
    /// クリックのみで位置が変わっていない場合はファイル書き込みをスキップする
    def saveDraggedPos(stateData: Editor.EditorStateData,
                       scene: Scene[NodeTag]):
            (Editor.EditorStateData, Scene[NodeTag]) \ {Fs.FileRead, Fs.FileWrite} =
        match stateData#selected {
            case Some((jsonPath, nodePath)) =>
                let currentGlobal = Scene.globalPositionAt(nodePath, scene);
                let moved = match stateData#nodeOrigin {
                    case Some(origin) =>
                        currentGlobal#x != origin#x or currentGlobal#y != origin#y
                    case None => false
                };
                if (moved) {
                    let localPos = match Scene.getEngineNode(nodePath, scene) {
                        case Some(engineNode) => Node2D.getPosition(engineNode)
                        case None => Vec2.zero()
                    };
                    SceneSerializer.updatePos(jsonPath, nodePath, localPos)
                } else ();
                let cleared = {
                    dragOrigin = None,
                    nodeOrigin = None
                    | stateData
                };
                (cleared, scene)
            case None => (stateData, scene)
        }
}
