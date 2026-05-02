// ScoreScene — HUD レイヤーとスコア/ベストスコアラベルの構築・更新
//
// CanvasLayer (layer=1) の子として Label2D を配置し、
// カメラに影響されないスクリーン固定のスコア表示を行う。
// スコア値は Label2D の NodeTag.ScoreLabel(Score) に保持する。
// ベストスコアは NodeTag.BestScoreLabel(BestScore) に保持する（非表示）。
//
//   CanvasLayerWithState(hud, NoTag)
//     ├── Label2DWithState(score_label, ScoreLabel(0))
//     └── Label2DWithState(best_score_label, BestScoreLabel(0))  // 非表示

mod ScoreScene {

    // ========================================================================
    // 定数
    // ========================================================================

    /// HUD レイヤーのノード名
    def hudLayerName(): String = "hud"

    /// スコアラベルのノード名
    def scoreLabelName(): String = "score_label"

    /// ベストスコアラベルのノード名
    def bestScoreLabelName(): String = "best_score_label"

    /// スコアラベルのノードパス
    pub def scoreLabelPath(): NodePath = hudLayerName() :: scoreLabelName() :: Nil

    /// ベストスコアラベルのノードパス
    pub def bestScoreLabelPath(): NodePath = hudLayerName() :: bestScoreLabelName() :: Nil

    /// スコア用フォントサイズ
    def scoreFontSize(): Float64 = 60.0

    /// スコアラベルの表示位置（画面上部中央）
    def scorePosition(): Vec2.Vec2 = {x = 144.0, y = 50.0}

    // ========================================================================
    // シーン構築
    // ========================================================================

    /// HUD レイヤーとスコア/ベストスコアラベルをシーンに追加する
    /// ベストスコアラベルは非表示（データ保持用）
    pub def addHud(fontAtlas: FontAtlas, bestScore: BestScore, scene: Scene[NodeTag]): Scene[NodeTag] =
        let layer = CanvasLayer.make(1);
        let label = Label2D.make("0", fontAtlas, scoreFontSize())
            |> Label2D.setCentered(true)
            |> Node2D.setPosition(scorePosition());
        let bestLabel = Label2D.make("${bestScore}", fontAtlas, scoreFontSize())
            |> CanvasItem.hide;
        scene
            |> Scene.addNode(hudLayerName(),
                EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag))
            |> Scene.addChild(hudLayerName(), scoreLabelName(),
                EngineNode.Label2DWithState(label, NodeTag.ScoreLabel(0)))
            |> Scene.addChild(hudLayerName(), bestScoreLabelName(),
                EngineNode.Label2DWithState(bestLabel, NodeTag.BestScoreLabel(bestScore)))

    // ========================================================================
    // スコア取得・更新
    // ========================================================================

    /// Scene から現在のスコアを取り出す
    pub def getScore(scene: Scene[NodeTag]): Score =
        match Scene.getState(scoreLabelPath(), scene) {
            case Some(NodeTag.ScoreLabel(score)) => score
            case _ => bug!("score_label not found")
        }

    /// Scene からベストスコアを取り出す
    pub def getBestScore(scene: Scene[NodeTag]): BestScore =
        match Scene.getState(bestScoreLabelPath(), scene) {
            case Some(NodeTag.BestScoreLabel(bestScore)) => bestScore
            case _ => bug!("best_score_label not found")
        }

    /// スコアを指定値に更新する（NodeTag とラベルテキストの両方）
    pub def setScore(score: Score, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(scoreLabelPath(), engineNode -> match engineNode {
            case EngineNode.Label2DWithState(label, NodeTag.ScoreLabel(_)) =>
                EngineNode.Label2DWithState(
                    Label2D.setText("${score}", label),
                    NodeTag.ScoreLabel(score))
            case other => other
        }, scene)

    /// スコアを 1 加算し、ラベルテキストも同時に更新する
    pub def incrementScore(scene: Scene[NodeTag]): Scene[NodeTag] =
        setScore(getScore(scene) + 1, scene)

    /// 現在のスコアでベストスコアを更新する（max を取って setBestScore）
    pub def finalizeScore(scene: Scene[NodeTag]): Scene[NodeTag] =
        let score = getScore(scene);
        let currentBest = getBestScore(scene);
        let newBest = Int32.max(score, currentBest);
        setBestScore(newBest, scene)

    /// ベストスコアを更新する
    pub def setBestScore(bestScore: BestScore, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(bestScoreLabelPath(), engineNode -> match engineNode {
            case EngineNode.Label2DWithState(label, NodeTag.BestScoreLabel(_)) =>
                EngineNode.Label2DWithState(label, NodeTag.BestScoreLabel(bestScore))
            case other => other
        }, scene)
}
