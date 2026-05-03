// Overlay — エディタ ON 時にだけ追加で描画するオーバーレイ要素
//
// エディタが効いていることを示す右上の "EDITOR" ラベル と、選択中ノードを取り囲む
// 黄色の矩形を、最前面の CanvasLayer に追加する。
// ここで返したシーンは「次フレームに引き継がない」想定。Game.flix の render 直前に
// 1 回だけ合成して使い、次フレームの handleInput は元のシーンから始める

mod Overlay {

    /// エディタが ON であることを示す右上の "EDITOR" ラベルを最前面に追加する
    pub def addEditorIndicator(fontAtlas: FontAtlas, scene: Scene[NodeTag]): Scene[NodeTag] =
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

    /// 選択中ノードを取り囲む黄色の矩形（4 辺の細い ColorRect）を最前面に追加する。
    /// 選択 entry をシーン走査で再取得して使う
    pub def addSelectionBox(rootJsonIndex: Map[NodeName, String],
                            selected: Option[(String, NodePath)],
                            scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        match selected {
            case None => scene
            case Some((_, nodePath)) =>
                match EditableNode.findByNodePath(rootJsonIndex, nodePath, scene) {
                    case None => scene
                    case Some(entry) =>
                        let refPos = Scene.globalPositionAt(nodePath, scene);
                        let topLeft = Vec2.add(refPos, entry#topLeftOffset);
                        addBoxLines(topLeft, entry#width, entry#height, scene)
                }
        }

    /// 矩形の 4 辺を CanvasLayer の中に細い ColorRect として配置する。
    /// 各辺は 2px の太さ。色は明るい黄色で目立たせる
    def addBoxLines(topLeft: Vec2.Vec2, width: Float64, height: Float64,
                    scene: Scene[NodeTag]): Scene[NodeTag] =
        let layerName = "_editor_box_layer";
        let layer = CanvasLayer.make(overlayLayerIndex());
        let yellow: {r = Float32, g = Float32, b = Float32} =
            {r = 1.0f32, g = 0.85f32, b = 0.2f32};
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
