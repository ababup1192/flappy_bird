// Editor — シーン上のノードをマウスで選択・ドラッグ移動して JSON に書き戻すミニエディタ
//
// HotReload と同じく Game.flix への差し込みは最小限。エディタ状態は EditorState エフェクトで
// Ref に保持し、毎フレーム gameLoop から handleInput / applyOverlay を呼ぶだけで動く。
//
// Phase 1 スコープ:
//   - 編集対象は MenuScene.scene.json の Sprite2D / TextureButton のみ（pos のみ）
//   - F1 でエディタ ON/OFF
//   - 左クリックで対象ノードを選択（黄色の矩形で囲む）
//   - ドラッグで pos 変更（シーン上は即時更新、ドロップ時に JSON 書き戻し）
//   - HotReload watcher が JSON 変更を拾って次フレームでシーン再構築
//
// 書き戻しはドロップ時のみ。ドラッグ中は HotReload を発火させずシーンの中で動かすだけ
// にする（書き戻しごとに HotReload で再構築すると ドラッグ位置が一瞬戻って見えてしまう）

mod Editor {
    // ========================================================================
    // 公開エフェクト
    // ========================================================================

    /// エディタの状態を保持するエフェクト。Game.start 内の Ref で実装する
    pub eff EditorState {
        def get(): EditorStateData
        def put(stateData: EditorStateData): Unit
    }

    /// エディタ状態の record 表現
    /// on:           エディタモード ON / OFF
    /// selected:     現在選択中のノード（編集対象 JSON のパスとシーン内の NodePath）
    /// dragOrigin:   ドラッグ開始時のマウス座標（None ならドラッグ中ではない）
    /// nodeOrigin:   ドラッグ開始時のノードのグローバル座標
    /// prevF1:       前フレームの F1 押下状態（エッジ検出用）
    /// prevMouseLeft: 前フレームのマウス左ボタン押下状態（エッジ検出用）
    pub type alias EditorStateData = {
        on = Bool,
        selected = Option[(String, NodePath)],
        dragOrigin = Option[Vec2.Vec2],
        nodeOrigin = Option[Vec2.Vec2],
        prevF1 = Bool,
        prevMouseLeft = Bool
    }

    /// エディタ状態の初期値
    pub def initialState(): EditorStateData = {
        on = false,
        selected = None,
        dragOrigin = None,
        nodeOrigin = None,
        prevF1 = false,
        prevMouseLeft = false
    }

    // ========================================================================
    // 編集可能ノードのテーブル（Phase 1 はハードコード）
    // ========================================================================

    /// 編集対象ノードの 1 件分の情報
    /// jsonPath: 書き戻し対象の scene.json ファイルパス
    /// nodePath: シーン内の階層パス
    /// width / height: 画面上で見える矩形のサイズ（ピクセル単位）。
    ///                 Sprite2D 系は texture サイズ × scale、TextureButton は size 値
    type alias EditableEntry = {
        jsonPath = String,
        nodePath = NodePath,
        width = Float64,
        height = Float64
    }

    /// 編集対象として認識するノード一覧。Phase 1 は MenuScene の 3 ノードを直書き。
    /// 矩形サイズは MenuScene.scene.json の値と sprites/*.png の実寸から事前計算した値。
    /// scale はすべて (2, 2) 前提：
    ///   - title_logo:       89 × 24 × 2 = 178 × 48
    ///   - instructions_img: 57 × 49 × 2 = 114 × 98
    ///   - play_button:      JSON の size [104, 58] をそのまま使う（scale が掛かった値）
    def editableNodes(): List[EditableEntry] =
        let jsonPath = "src/scenes/MenuScene.scene.json";
        {jsonPath = jsonPath, nodePath = "menu" :: "title_logo" :: Nil,
         width = 178.0, height = 48.0} ::
        {jsonPath = jsonPath, nodePath = "menu" :: "instructions_img" :: Nil,
         width = 114.0, height = 98.0} ::
        {jsonPath = jsonPath, nodePath = "menu" :: "play_button" :: Nil,
         width = 104.0, height = 58.0} ::
        Nil

    // ========================================================================
    // メインループから呼ぶ API
    // ========================================================================

    /// 入力処理を行いシーンを更新する。Game.flix の gameLoop から毎フレーム呼ぶ。
    /// 副作用: EditorState を読み書き、JSON を読み書き、マウス・キー入力を読む
    pub def handleInput(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {EditorState, GameEngine.Game, Fs.FileRead, Fs.FileWrite} =
        let stateData = EditorState.get();
        let f1 = GameEngine.Game.isKeyPressed(GameEngine.Key.F1);
        let mouseLeft = GameEngine.Game.isMouseButtonPressed(GameEngine.MouseButton.Left);
        let mousePos = GameEngine.Game.getMousePosition();
        // F1 のエッジ検出: 前フレーム未押下 → 今フレーム押下 でトグル
        let toggledOn = if (f1 and not stateData#prevF1) not stateData#on else stateData#on;
        let stateAfterToggle = {
            on = toggledOn,
            selected = if (toggledOn) stateData#selected else None,
            dragOrigin = if (toggledOn) stateData#dragOrigin else None,
            nodeOrigin = if (toggledOn) stateData#nodeOrigin else None,
            prevF1 = f1,
            prevMouseLeft = stateData#prevMouseLeft
        };
        if (not toggledOn) {
            EditorState.put({prevMouseLeft = mouseLeft | stateAfterToggle});
            scene
        } else {
            // エディタ ON 時のマウス処理
            let (newState, newScene) =
                handleMouse(mousePos, mouseLeft, stateAfterToggle, scene);
            EditorState.put({prevMouseLeft = mouseLeft | newState});
            newScene
        }

    /// 描画用のオーバーレイをシーンに合成する。Game.flix の render 直前に呼ぶ。
    /// 戻り値の Scene は次フレームに引き継がない（一回限りの描画用）。
    /// エディタ OFF のときは何もせず scene をそのまま返す
    pub def applyOverlay(fontAtlas: FontAtlas, scene: Scene[NodeTag]):
            Scene[NodeTag] \ EditorState =
        let stateData = EditorState.get();
        if (not stateData#on) scene
        else {
            scene
                |> addEditorIndicator(fontAtlas)
                |> addSelectionBox(stateData#selected)
        }

    // ========================================================================
    // 入力処理（クリック選択 + ドラッグ移動 + ドロップ書き戻し）
    // ========================================================================

    /// マウスの押下／継続／離脱を判定し、選択 / ドラッグ更新 / 書き戻し をディスパッチする
    def handleMouse(mousePos: Vec2.Vec2, mouseLeft: Bool, stateData: EditorStateData,
                    scene: Scene[NodeTag]):
            (EditorStateData, Scene[NodeTag]) \ {Fs.FileRead, Fs.FileWrite} =
        let prevLeft = stateData#prevMouseLeft;
        let pressedNow = mouseLeft and not prevLeft;       // 押下したフレーム
        let releasedNow = (not mouseLeft) and prevLeft;    // 離した（ドロップ）フレーム
        if (pressedNow) {
            // 押下時: 候補から hit test して選択 or ドラッグ開始
            handleMouseDown(mousePos, stateData, scene)
        } else if (mouseLeft and Option.nonEmpty(stateData#dragOrigin)) {
            // ドラッグ中: 選択ノードの位置を更新（書き戻しはまだしない）
            (stateData, applyDrag(mousePos, stateData, scene))
        } else if (releasedNow and Option.nonEmpty(stateData#dragOrigin)) {
            // ドロップ: シーンの最終 pos を JSON に書き戻し
            saveDraggedPos(stateData, scene)
        } else {
            (stateData, scene)
        }

    /// クリック押下時: 編集対象ノードのうち hit したものを選択し、ドラッグ開始状態にする
    def handleMouseDown(mousePos: Vec2.Vec2, stateData: EditorStateData,
                        scene: Scene[NodeTag]): (EditorStateData, Scene[NodeTag]) =
        let hit = findHit(mousePos, scene);
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

    /// 編集対象ノードの中からマウス位置に重なるものを 1 件返す。
    /// 複数 hit する場合はリストの後ろ（より手前に描画される想定）を優先する
    def findHit(mousePos: Vec2.Vec2,
                scene: Scene[NodeTag]): Option[(EditableEntry, Vec2.Vec2)] =
        let hits = editableNodes() |> List.filterMap(entry -> {
            let globalPos = Scene.globalPositionAt(entry#nodePath, scene);
            let bbox = makeBBox(globalPos, entry#width, entry#height);
            if (Rect2.hasPoint(mousePos, bbox)) Some((entry, globalPos))
            else None
        });
        List.last(hits)

    /// ドラッグ中: マウスの移動量に応じてノードのグローバル位置を更新する
    def applyDrag(mousePos: Vec2.Vec2, stateData: EditorStateData,
                  scene: Scene[NodeTag]): Scene[NodeTag] =
        match (stateData#selected, stateData#dragOrigin, stateData#nodeOrigin) {
            case (Some((_, nodePath)), Some(dragOrigin), Some(nodeOrigin)) =>
                let delta = Vec2.sub(mousePos, dragOrigin);
                let newGlobalPos = Vec2.add(nodeOrigin, delta);
                Scene.setGlobalPositionAt(nodePath, newGlobalPos, scene)
            case _ => scene
        }

    /// ドロップ: 現在のシーン上のノード位置を JSON に書き戻し、ドラッグ状態を解除する。
    /// 書き戻し対象は「ローカル位置」（JSON が pos として持つのはローカル座標のため）
    def saveDraggedPos(stateData: EditorStateData,
                       scene: Scene[NodeTag]): (EditorStateData, Scene[NodeTag]) \
                       {Fs.FileRead, Fs.FileWrite} =
        match stateData#selected {
            case Some((jsonPath, nodePath)) =>
                let localPos = match Scene.getEngineNode(nodePath, scene) {
                    case Some(engineNode) => Node2D.getPosition(engineNode)
                    case None => Vec2.zero()
                };
                SceneSerializer.updatePos(jsonPath, nodePath, localPos);
                let cleared = {
                    dragOrigin = None,
                    nodeOrigin = None
                    | stateData
                };
                (cleared, scene)
            case None => (stateData, scene)
        }

    /// グローバル中心座標とサイズ（centered=true 前提）から Rect2 を作る
    def makeBBox(centerPos: Vec2.Vec2, width: Float64, height: Float64): Rect2.Rect2 =
        let topLeft = {x = centerPos#x - width / 2.0, y = centerPos#y - height / 2.0};
        {position = topLeft, size = {x = width, y = height}}

    // ========================================================================
    // オーバーレイ構築
    // ========================================================================

    /// エディタが ON であることを示す右上の "EDITOR" ラベルを最前面に追加する
    def addEditorIndicator(fontAtlas: FontAtlas, scene: Scene[NodeTag]): Scene[NodeTag] =
        let layerName = "_editor_indicator_layer";
        let labelName = "_editor_indicator_label";
        let layer = CanvasLayer.make(overlayLayerIndex());
        let label = Label2D.make("EDITOR", fontAtlas, 14.0)
            |> Node2D.setPosition({x = 230.0, y = 16.0})
            |> CanvasItem.setModulate({r = 1.0f32, g = 0.85f32, b = 0.2f32});
        scene
            |> Scene.addNode(layerName,
                EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag))
            |> Scene.addChildAt(layerName :: Nil, labelName,
                EngineNode.Label2DWithState(label, NodeTag.NoTag))

    /// 選択中ノードを取り囲む黄色の矩形（4 辺の細い ColorRect）を最前面に追加する
    def addSelectionBox(selected: Option[(String, NodePath)],
                        scene: Scene[NodeTag]): Scene[NodeTag] =
        match selected {
            case None => scene
            case Some((_, nodePath)) =>
                match findEntryFor(nodePath) {
                    case None => scene
                    case Some(entry) =>
                        let center = Scene.globalPositionAt(nodePath, scene);
                        let topLeft = {x = center#x - entry#width / 2.0,
                                       y = center#y - entry#height / 2.0};
                        addBoxLines(topLeft, entry#width, entry#height, scene)
                }
        }

    /// 編集テーブルから NodePath で entry を引く
    def findEntryFor(nodePath: NodePath): Option[EditableEntry] =
        editableNodes() |> List.find(entry -> entry#nodePath == nodePath)

    /// 矩形の 4 辺を CanvasLayer の中に細い ColorRect として配置する。
    /// 各辺は 2px の太さ。色は明るい黄色で目立たせる
    def addBoxLines(topLeft: Vec2.Vec2, width: Float64, height: Float64,
                    scene: Scene[NodeTag]): Scene[NodeTag] =
        let layerName = "_editor_box_layer";
        let layer = CanvasLayer.make(overlayLayerIndex());
        let yellow: {r = Float32, g = Float32, b = Float32} = {r = 1.0f32, g = 0.85f32, b = 0.2f32};
        let thickness = 2.0;
        let topLine = makeLine(topLeft, width, thickness, yellow);
        let bottomLine = makeLine({x = topLeft#x, y = topLeft#y + height - thickness},
                                  width, thickness, yellow);
        let leftLine = makeLine(topLeft, thickness, height, yellow);
        let rightLine = makeLine({x = topLeft#x + width - thickness, y = topLeft#y},
                                 thickness, height, yellow);
        scene
            |> Scene.addNode(layerName,
                EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag))
            |> Scene.addChildAt(layerName :: Nil, "top",
                EngineNode.ColorRectWithState(topLine, NodeTag.NoTag))
            |> Scene.addChildAt(layerName :: Nil, "bottom",
                EngineNode.ColorRectWithState(bottomLine, NodeTag.NoTag))
            |> Scene.addChildAt(layerName :: Nil, "left",
                EngineNode.ColorRectWithState(leftLine, NodeTag.NoTag))
            |> Scene.addChildAt(layerName :: Nil, "right",
                EngineNode.ColorRectWithState(rightLine, NodeTag.NoTag))

    /// 1 本の線分を ColorRect で作る
    def makeLine(pos: Vec2.Vec2, width: Float64, height: Float64,
                 color: {r = Float32, g = Float32, b = Float32}): ColorRect =
        ColorRect.make({x = width, y = height}, color)
            |> Node2D.setPosition(pos)

    /// オーバーレイ用 CanvasLayer のレイヤー番号（既存の最前面 layer=2 より大きく取る）
    def overlayLayerIndex(): Int32 = 999
}
