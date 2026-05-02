// GameOverScene — ゲームオーバー画面の構築・アニメーション・ボタン判定
//
// CanvasLayer (layer=2) の子として各 UI 要素を配置する。
// HUD (layer=1) の上に描画される。
// 子ノードは初期非表示で追加され、GameOverAnim state の経過時間に応じて段階的に表示される。
//
//   CanvasLayerWithState(gameover, GameOverAnim({elapsed = 0.0}))
//     ├── Sprite2DWithState(gameover_label, NoTag)              // "GAME OVER" ラベル
//     ├── Sprite2DWithState(score_panel, NoTag)                 // スコアパネル背景
//     ├── Sprite2DWithState(medal, NoTag)                       // メダル（score>=10 のみ）
//     ├── Label2DWithState(final_score, NoTag)                  // パネル上のスコア数値
//     ├── Label2DWithState(best_score, NoTag)                   // パネル上のベストスコア数値
//     └── TextureButtonWithState(play_button, NoTag)            // Play ボタン

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
    // 定数 — パス
    // ========================================================================

    /// ゲームオーバーレイヤーのパス
    def layerPath(): NodePath = layerName() :: Nil

    // ========================================================================
    // 状態判定
    // ========================================================================

    /// ゲームオーバー画面が出ているか判定する
    pub def isActive(scene: Scene[NodeTag]): Bool =
        match Scene.getState(layerPath(), scene) {
            case Some(_) => true
            case None    => false
        }

    // ========================================================================
    // 定数 — 位置（2x スケール、画面幅 288 の中央 x=144）
    // ========================================================================

    /// GAME OVER ラベルの位置
    def gameOverLabelPos(): Vec2.Vec2 = {x = 144.0, y = 160.0}

    /// スコアパネルの位置
    def scorePanelPos(): Vec2.Vec2 = {x = 144.0, y = 280.0}

    /// メダルの位置（パネル左側、パネル中心より少し下）
    def medalPos(): Vec2.Vec2 = {x = 81.0, y = 287.0}

    /// 最終スコアの位置（パネル右上、"SCORE" テキストと同じ行）
    def finalScorePos(): Vec2.Vec2 = {x = 220.0, y = 253.0}

    /// ベストスコアの位置（パネル右下、"BEST" テキストと同じ行）
    def bestScorePos(): Vec2.Vec2 = {x = 218.0, y = 295.0}

    /// Play ボタンの位置（中心座標）
    def playButtonPos(): Vec2.Vec2 = {x = 144.0, y = 390.0}

    /// Play ボタンサイズ（button_play_normal 52x29 px × 2x スケール = 104x58）
    def playButtonSize(): Vec2.Vec2 = {x = 104.0, y = 58.0}

    /// Play ボタンのパス
    pub def playButtonPath(): NodePath = layerName() :: playButtonName() :: Nil

    // ========================================================================
    // 2x スケール
    // ========================================================================

    /// 共通の 2x スケール
    def scale2x(): Vec2.Vec2 = {x = 2.0, y = 2.0}

    // ========================================================================
    // アニメーション定数
    // ========================================================================

    /// GAME OVER ラベルの表示タイミング（即座）
    def labelShowTime(): Float64 = 0.0

    /// スコアパネル + スコア数値の表示タイミング
    def panelShowTime(): Float64 = 0.3

    /// メダルの表示タイミング
    def medalShowTime(): Float64 = 0.5

    /// Play ボタンの表示タイミング
    def buttonShowTime(): Float64 = 0.7

    /// アニメーション全体の長さ
    def animDuration(): Float64 = 0.8

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

    /// ゲームオーバー画面への遷移処理
    /// 効果音再生 → スコア確定 → UI 追加をまとめる
    pub def enterGameOver(fontAtlas: FontAtlas, scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Audio =
        GameEngine.Audio.playAudio("sfx_swooshing");
        scene
            |> ScoreScene.finalizeScore
            |> addGameOverUI(fontAtlas)

    /// ゲームオーバー UI をシーンに追加する
    /// score / bestScore は scene の ScoreLabel / BestScoreLabel から読み出す
    /// CanvasLayer (layer=2) に GAME OVER ラベル、スコアパネル、メダル、スコア/ベストスコア数値、Play ボタンを配置する
    /// 全子ノードは初期非表示で追加され、アニメーションで段階的に表示される
    /// HUD のスコアラベルを非表示にする
    pub def addGameOverUI(fontAtlas: FontAtlas, scene: Scene[NodeTag]): Scene[NodeTag] =
        let score = ScoreScene.getScore(scene);
        let bestScore = ScoreScene.getBestScore(scene);
        let layer = CanvasLayer.make(2);
        let gameOverLabel = Sprite2D.make("label_game_over", gameOverLabelPos(), scale2x())
            |> CanvasItem.hide;
        let panel = Sprite2D.make("panel_score", scorePanelPos(), scale2x())
            |> CanvasItem.hide;
        let scoreLabel = Label2D.make("${score}", fontAtlas, 30.0)
            |> Label2D.setCentered(true)
            |> Node2D.setPosition(finalScorePos())
            |> CanvasItem.setZIndex(1)
            |> CanvasItem.hide;
        let bestLabel = Label2D.make("${bestScore}", fontAtlas, 30.0)
            |> Label2D.setCentered(true)
            |> Node2D.setPosition(bestScorePos())
            |> CanvasItem.setZIndex(1)
            |> CanvasItem.hide;
        let playButton = TextureButton.make("button_play_normal", playButtonSize())
            |> TextureButton.setTexturePressed("button_play_pressed")
            |> TextureButton.setCentered(true)
            |> Node2D.setPosition(playButtonPos())
            |> Node2D.setScale(scale2x())
            |> CanvasItem.hide;
        let sceneWithLayer = scene
            // HUD のスコアラベルを非表示にする
            |> ScoreScene.hideScoreLabel
            // ゲームオーバーレイヤーを追加（GameOverAnim state でアニメーション経過時間を管理）
            |> Scene.addNode(layerName(),
                EngineNode.CanvasLayerWithState(layer,
                    NodeTag.GameOverAnim({elapsed = 0.0})))
            |> Scene.addChild(layerName(), labelName(),
                EngineNode.Sprite2DWithState(gameOverLabel, NodeTag.NoTag))
            |> Scene.addChild(layerName(), panelName(),
                EngineNode.Sprite2DWithState(panel, NodeTag.NoTag))
            |> Scene.addChild(layerName(), finalScoreName(),
                EngineNode.Label2DWithState(scoreLabel, NodeTag.NoTag))
            |> Scene.addChild(layerName(), bestScoreName(),
                EngineNode.Label2DWithState(bestLabel, NodeTag.NoTag))
            |> Scene.addChild(layerName(), playButtonName(),
                EngineNode.TextureButtonWithState(playButton, NodeTag.NoTag));
        // メダルを追加（bestScore >= 10 の場合のみ、非表示で追加）
        // bestScore を使うことで、一度取得したメダルは以降も表示され続け、
        // ベストスコア更新時に新しいメダルに差し替わる
        match getMedalTexture(bestScore) {
            case Some(medalTex) =>
                let medalSprite = Sprite2D.make(medalTex, medalPos(), scale2x())
                    |> CanvasItem.setZIndex(1)
                    |> CanvasItem.hide;
                sceneWithLayer
                    |> Scene.addChild(layerName(), medalName(),
                        EngineNode.Sprite2DWithState(medalSprite, NodeTag.NoTag))
            case None => sceneWithLayer
        }

    // ========================================================================
    // アニメーション
    // ========================================================================

    /// アニメーションが完了したか判定する
    pub def isAnimationFinished(scene: Scene[NodeTag]): Bool =
        match Scene.getState(layerPath(), scene) {
            case Some(NodeTag.GameOverAnim(animData)) =>
                animData#elapsed >= animDuration()
            case _ => true
        }

    /// CanvasLayer の毎フレーム更新（GameOverAnim 状態を進めて再ラップする）
    /// 該当しないノードはそのまま返す
    pub def process(delta: Float64, node: EngineNode[NodeTag],
                    scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.CanvasLayerWithState(layer, NodeTag.GameOverAnim(_)) =>
                let newScene = updateAnimation(delta, scene);
                let newState = match Scene.getState(layerPath(), newScene) {
                    case Some(tag) => tag
                    case _         => NodeTag.GameOverAnim({elapsed = 0.0})
                };
                (EngineNode.CanvasLayerWithState(layer, newState), newScene)
            case _ => (node, scene)
        }

    /// アニメーションの経過時間を進め、閾値超過時にノードを表示する
    pub def updateAnimation(dt: Float64, scene: Scene[NodeTag]): Scene[NodeTag] =
        match Scene.getState(layerPath(), scene) {
            case Some(NodeTag.GameOverAnim(animData)) =>
                let prevElapsed = animData#elapsed;
                let newElapsed = prevElapsed + dt;
                let updatedScene = Scene.setState(layerPath(),
                    NodeTag.GameOverAnim({elapsed = newElapsed}), scene);
                // 閾値を超えた瞬間にノードを show する
                updatedScene
                    |> showChildIfCrossed(labelName(), labelShowTime(), prevElapsed, newElapsed)
                    |> showChildIfCrossed(panelName(), panelShowTime(), prevElapsed, newElapsed)
                    |> showChildIfCrossed(finalScoreName(), panelShowTime(), prevElapsed, newElapsed)
                    |> showChildIfCrossed(bestScoreName(), panelShowTime(), prevElapsed, newElapsed)
                    |> showChildIfCrossed(medalName(), medalShowTime(), prevElapsed, newElapsed)
                    |> showChildIfCrossed(playButtonName(), buttonShowTime(), prevElapsed, newElapsed)
            case _ => scene
        }

    /// 閾値を超えた瞬間に子ノードを表示する
    def showChildIfCrossed(childName: String, threshold: Float64,
                            prevElapsed: Float64, newElapsed: Float64,
                            scene: Scene[NodeTag]): Scene[NodeTag] =
        if (prevElapsed < threshold and newElapsed >= threshold)
            showChild(childName, scene)
        else
            scene

    /// 子ノードを表示する（存在しない場合は何もしない）
    def showChild(childName: String, scene: Scene[NodeTag]): Scene[NodeTag] =
        let path = layerName() :: childName :: Nil;
        match Scene.getEngineNode(path, scene) {
            case Some(_) =>
                Scene.mapEngineNode(path, CanvasItem.show, scene)
            case None => scene
        }

}
