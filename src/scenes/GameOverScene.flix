// GameOverScene — ゲームオーバー画面の構築とボタン判定
//
// CanvasLayer (layer=2) の子として各 UI 要素を配置する。
// HUD (layer=1) の上に描画される。
//
//   CanvasLayerWithState(gameover, NoTag)
//     ├── Sprite2DWithState(gameover_label, NoTag)     // "GAME OVER" ラベル
//     ├── Sprite2DWithState(score_panel, NoTag)        // スコアパネル背景
//     ├── Sprite2DWithState(medal, NoTag)              // メダル（score>=10 のみ）
//     ├── Label2DWithState(final_score, NoTag)         // パネル上のスコア数値
//     ├── Label2DWithState(best_score, NoTag)          // パネル上のベストスコア数値
//     └── Sprite2DWithState(play_button, NoTag)        // Play ボタン

mod GameOverScene {

    // ========================================================================
    // 定数 — ノード名
    // ========================================================================

    /// ゲームオーバーレイヤーのノード名
    def layerName(): String = "gameover"

    /// GAME OVER ラベルのノード名
    def labelName(): String = "gameover_label"

    /// スコアパネルのノード名
    def panelName(): String = "score_panel"

    /// メダルのノード名
    def medalName(): String = "medal"

    /// 最終スコアラベルのノード名
    def finalScoreName(): String = "final_score"

    /// ベストスコアラベルのノード名
    def bestScoreName(): String = "best_score"

    /// Play ボタンのノード名
    def playButtonName(): String = "play_button"

    // ========================================================================
    // 定数 — 位置（2x スケール、画面幅 288 の中央 x=144）
    // ========================================================================

    /// GAME OVER ラベルの位置
    def gameOverLabelPos(): Vec2.Vec2 = {x = 144.0, y = 160.0}

    /// スコアパネルの位置
    def scorePanelPos(): Vec2.Vec2 = {x = 144.0, y = 280.0}

    /// メダルの位置（パネル左側）
    def medalPos(): Vec2.Vec2 = {x = 76.0, y = 280.0}

    /// 最終スコアの位置（パネル右上、"SCORE" テキストと同じ行）
    def finalScorePos(): Vec2.Vec2 = {x = 220.0, y = 253.0}

    /// ベストスコアの位置（パネル右下、"BEST" テキストと同じ行）
    def bestScorePos(): Vec2.Vec2 = {x = 220.0, y = 295.0}

    /// Play ボタンの位置
    def playButtonPos(): Vec2.Vec2 = {x = 144.0, y = 390.0}

    // ========================================================================
    // 定数 — ボタンサイズ
    // ========================================================================

    /// Play ボタンの半幅（52px × 2x スケール / 2）
    def buttonHalfW(): Float64 = 52.0

    /// Play ボタンの半高（29px × 2x スケール / 2）
    def buttonHalfH(): Float64 = 29.0

    // ========================================================================
    // 2x スケール
    // ========================================================================

    /// 共通の 2x スケール
    def scale2x(): Vec2.Vec2 = {x = 2.0, y = 2.0}

    // ========================================================================
    // メダル判定
    // ========================================================================

    /// スコアに応じたメダルテクスチャ名を返す
    /// score >= 50: platinum, >= 30: gold, >= 20: silver, >= 10: bronze
    pub def getMedalTexture(score: Int32): Option[String] =
        if (score >= 50) Some("medal_platinum")
        else if (score >= 30) Some("medal_gold")
        else if (score >= 20) Some("medal_silver")
        else if (score >= 10) Some("medal_bronze")
        else None

    // ========================================================================
    // シーン構築
    // ========================================================================

    /// ゲームオーバー UI をシーンに追加する
    /// CanvasLayer (layer=2) に GAME OVER ラベル、スコアパネル、メダル、スコア/ベストスコア数値、Play ボタンを配置する
    /// HUD のスコアラベルを非表示にする
    pub def addGameOverUI(score: Score, bestScore: BestScore, fontAtlas: FontAtlas, scene: Scene[NodeTag]): Scene[NodeTag] =
        let layer = CanvasLayer.make(2);
        let gameOverLabel = Sprite2D.make("label_game_over", gameOverLabelPos(), scale2x());
        let panel = Sprite2D.make("panel_score", scorePanelPos(), scale2x());
        let scoreLabel = Label2D.make("${score}", fontAtlas, 30.0)
            |> Label2D.setCentered(true)
            |> Node2D.setPosition(finalScorePos())
            |> CanvasItem.setZIndex(1);
        let bestLabel = Label2D.make("${bestScore}", fontAtlas, 30.0)
            |> Label2D.setCentered(true)
            |> Node2D.setPosition(bestScorePos())
            |> CanvasItem.setZIndex(1);
        let playButton = Sprite2D.make("button_play_normal", playButtonPos(), scale2x());
        let sceneWithLayer = scene
            // HUD のスコアラベルを非表示にする
            |> Scene.mapEngineNode(ScoreScene.scoreLabelPath(),
                EngineNode.mapLabel2D(CanvasItem.hide))
            // ゲームオーバーレイヤーを追加
            |> Scene.addNode(layerName(),
                EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag))
            |> Scene.addChild(layerName(), labelName(),
                EngineNode.Sprite2DWithState(gameOverLabel, NodeTag.NoTag))
            |> Scene.addChild(layerName(), panelName(),
                EngineNode.Sprite2DWithState(panel, NodeTag.NoTag))
            |> Scene.addChild(layerName(), finalScoreName(),
                EngineNode.Label2DWithState(scoreLabel, NodeTag.NoTag))
            |> Scene.addChild(layerName(), bestScoreName(),
                EngineNode.Label2DWithState(bestLabel, NodeTag.NoTag))
            |> Scene.addChild(layerName(), playButtonName(),
                EngineNode.Sprite2DWithState(playButton, NodeTag.NoTag));
        // メダルを追加（score >= 10 の場合のみ）
        match getMedalTexture(score) {
            case Some(medalTex) =>
                let medalSprite = Sprite2D.make(medalTex, medalPos(), scale2x());
                sceneWithLayer
                    |> Scene.addChild(layerName(), medalName(),
                        EngineNode.Sprite2DWithState(medalSprite, NodeTag.NoTag))
            case None => sceneWithLayer
        }

    // ========================================================================
    // ボタン判定
    // ========================================================================

    /// マウス座標が Play ボタンの矩形内にあるか判定する
    /// button_play_normal は 52x29 px、2x スケールで 104x58
    pub def isPlayButtonClicked(mousePos: Vec2.Vec2): Bool =
        let center = playButtonPos();
        let dx = Float64.abs(mousePos#x - center#x);
        let dy = Float64.abs(mousePos#y - center#y);
        dx <= buttonHalfW() and dy <= buttonHalfH()
}
