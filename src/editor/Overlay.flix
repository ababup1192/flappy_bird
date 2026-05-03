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

    /// 4 辺の枠の見た目を表すスタイル。
    /// layerName は CanvasLayer のキー名で、選択枠とホバー枠が衝突しないよう別名にする
    type alias OutlineStyle = {
        layerName = String,
        color = {r = Float32, g = Float32, b = Float32},
        thickness = Float64
    }

    /// 選択中ノードを取り囲む黄色の矩形（4 辺の細い ColorRect）を最前面に追加する。
    /// 選択 entry をシーン走査で再取得して、ノードが描画されている screen 座標に枠を置く
    /// （オーバーレイ自体が CanvasLayer なのでカメラの影響を受けず、screen 座標 = 描画位置）
    pub def addSelectionBox(rootJsonIndex: Map[NodeName, String],
                            selected: Option[(String, NodePath)],
                            cameraOffset: Vec2.Vec2,
                            scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        match selected {
            case None => scene
            case Some((_, nodePath)) =>
                let ctx = {rootJsonIndex = rootJsonIndex, scene = scene};
                match EditableNode.findByNodePath(ctx, nodePath) {
                    case None => scene
                    case Some(entry) =>
                        let refPos = Scene.screenPositionAt(nodePath, cameraOffset, scene);
                        let topLeft = Vec2.add(refPos, entry#topLeftOffset);
                        let box = {topLeft = topLeft,
                                   size = {x = entry#width, y = entry#height}};
                        addOutline(box, selectionStyle(), scene)
                }
        }

    /// マウス位置の編集対象ノードに薄い枠を描く（重なりが多いシーンで「何がクリック対象か」
    /// を視覚化する）。選択中ノードは選択枠と重なって見えづらくなるためスキップ。
    /// 何も hit しない / 選択中ノードと一致 のときは scene 不変
    pub def addHoverBox(rootJsonIndex: Map[NodeName, String],
                        mousePos: Vec2.Vec2,
                        selected: Option[(String, NodePath)],
                        cameraOffset: Vec2.Vec2,
                        scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        let ctx = {rootJsonIndex = rootJsonIndex, scene = scene};
        let entries = EditableNode.collectAll(ctx);
        match Picking.pickTopAt(mousePos, entries, cameraOffset, scene) {
            case None => scene
            case Some((entry, _)) =>
                if (isSelectedPath(entry#nodePath, selected)) scene
                else {
                    let refPos = Scene.screenPositionAt(entry#nodePath, cameraOffset, scene);
                    let topLeft = Vec2.add(refPos, entry#topLeftOffset);
                    let box = {topLeft = topLeft,
                               size = {x = entry#width, y = entry#height}};
                    addOutline(box, hoverStyle(), scene)
                }
        }

    /// hover 対象が選択中ノードと一致するかを判定（一致するなら hover 枠を描かない）
    def isSelectedPath(path: NodePath, selected: Option[(String, NodePath)]): Bool =
        match selected {
            case Some((_, selPath)) => path == selPath
            case None               => false
        }

    /// 選択枠のスタイル: 明るい黄色 × 2px
    def selectionStyle(): OutlineStyle = {
        layerName = "_editor_box_layer",
        color = {r = 1.0f32, g = 0.85f32, b = 0.2f32},
        thickness = 2.0
    }

    /// ホバー枠のスタイル: 薄いグレー × 1px（選択枠より控えめに）
    def hoverStyle(): OutlineStyle = {
        layerName = "_editor_hover_layer",
        color = {r = 0.7f32, g = 0.7f32, b = 0.7f32},
        thickness = 1.0
    }

    /// 矩形の 4 辺を CanvasLayer の中に細い ColorRect として配置する。
    /// 選択枠 / ホバー枠で共有
    def addOutline(box: {topLeft = Vec2.Vec2, size = Vec2.Vec2},
                   style: OutlineStyle,
                   scene: Scene[NodeTag]): Scene[NodeTag] =
        let layerName = style#layerName;
        let layer = CanvasLayer.make(overlayLayerIndex());
        let color = style#color;
        let thickness = style#thickness;
        let topLeft = box#topLeft;
        let width = box#size#x;
        let height = box#size#y;
        let topLine = makeLine({pos = topLeft,
                                size = {x = width, y = thickness}}, color);
        let bottomLine = makeLine({pos = {x = topLeft#x,
                                          y = topLeft#y + height - thickness},
                                   size = {x = width, y = thickness}}, color);
        let leftLine = makeLine({pos = topLeft,
                                 size = {x = thickness, y = height}}, color);
        let rightLine = makeLine({pos = {x = topLeft#x + width - thickness,
                                         y = topLeft#y},
                                  size = {x = thickness, y = height}}, color);
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
    def makeLine(line: {pos = Vec2.Vec2, size = Vec2.Vec2},
                 color: {r = Float32, g = Float32, b = Float32}): ColorRect =
        ColorRect.make(line#size, color)
            |> Node2D.setPosition(line#pos)

    /// オーバーレイ用 CanvasLayer のレイヤー番号（既存の最前面 layer=2 より大きく取る）
    def overlayLayerIndex(): Int32 = 999
}
