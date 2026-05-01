// ScoreScene — HUD レイヤーとスコアラベルの構築・更新
//
// CanvasLayer (layer=1) の子として Label2D を配置し、
// カメラに影響されないスクリーン固定のスコア表示を行う。
//
//   CanvasLayerWithState(hud, NoTag)
//     └── Label2DWithState(label, NoTag)

mod ScoreScene {

    // ========================================================================
    // 定数
    // ========================================================================

    /// HUD レイヤーのノード名
    def hudLayerName(): String = "hud"

    /// スコアラベルのノード名
    def scoreLabelName(): String = "score_label"

    /// スコアラベルのノードパス
    def scoreLabelPath(): NodePath = hudLayerName() :: scoreLabelName() :: Nil

    /// スコア用フォントサイズ
    def scoreFontSize(): Float64 = 60.0

    /// スコアラベルの表示位置（画面上部中央）
    def scorePosition(): Vec2.Vec2 = {x = 144.0, y = 50.0}

    // ========================================================================
    // シーン構築
    // ========================================================================

    /// HUD レイヤーとスコアラベルをシーンに追加する
    pub def addHud(fontAtlas: FontAtlas, scene: Scene[NodeTag]): Scene[NodeTag] =
        let layer = CanvasLayer.make(1);
        let label = Label2D.make("0", fontAtlas, scoreFontSize())
            |> Label2D.setCentered(true)
            |> Node2D.setPosition(scorePosition());
        scene
            |> Scene.addNode(hudLayerName(),
                EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag))
            |> Scene.addChild(hudLayerName(), scoreLabelName(),
                EngineNode.Label2DWithState(label, NodeTag.NoTag))

    // ========================================================================
    // スコア更新
    // ========================================================================

    /// スコアラベルのテキストを更新する
    pub def updateScore(score: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(scoreLabelPath(),
            EngineNode.mapLabel2D(Label2D.setText("${score}")),
            scene)
}
