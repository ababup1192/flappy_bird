// Tests for GameOverScene — メダル判定と GameOver UI 構築
// 共通ヘルパーは TestGame.flix を参照

// ========================================================================
// メダル判定
// ========================================================================

/// score 別メダル境界（< 10: なし、10〜19: bronze、20〜29: silver、30〜49: gold、50+: platinum）
@Test
def testMedalThresholds(): Unit \ Assert =
    Assert.assertEq(
        expected = (
            (None: Option[String]),         //  0:  なし
            (None: Option[String]),         //  5:  なし
            Some("medal_bronze"),           // 10:  bronze 境界
            Some("medal_bronze"),           // 15:  bronze 範囲内
            Some("medal_silver"),           // 20:  silver 境界
            Some("medal_gold"),             // 30:  gold 境界
            Some("medal_platinum")),        // 50:  platinum 境界
        (GameOverScene.getMedalTexture(0),
         GameOverScene.getMedalTexture(5),
         GameOverScene.getMedalTexture(10),
         GameOverScene.getMedalTexture(15),
         GameOverScene.getMedalTexture(20),
         GameOverScene.getMedalTexture(30),
         GameOverScene.getMedalTexture(50)))

// ========================================================================
// UI ノード構築
// ========================================================================

/// addGameOverUI は score < 10 かつ bestScore < 10 の場合、メダルなし UI で 6 ノード追加
///   gameover(layer) + gameover_label + score_panel + final_score + best_score + play_button = 6
@Test
def testGameOverUINoMedal(): Unit \ Assert =
    let baseScene = testScene()
        |> ScoreScene.setScore(5)
        |> ScoreScene.setBestScore(0);
    let baseCount = Scene.nodeCount(baseScene);
    let scene = GameOverScene.addGameOverUI(testFontAtlas(), baseScene);
    Assert.assertEq(expected = 6, Scene.nodeCount(scene) - baseCount)

/// 今回のスコアが低くても bestScore >= 10 ならメダルが追加される（メダル永続化）
///   → gameover(layer) + label + panel + medal + final + best + play_button = 7
@Test
def testGameOverUIMedalFromBestScore(): Unit \ Assert =
    let baseScene = testScene()
        |> ScoreScene.setScore(3)
        |> ScoreScene.setBestScore(15);
    let baseCount = Scene.nodeCount(baseScene);
    let scene = GameOverScene.addGameOverUI(testFontAtlas(), baseScene);
    Assert.assertEq(expected = 7, Scene.nodeCount(scene) - baseCount)

/// addGameOverUI 後に HUD スコアラベルが非表示になる
@Test
def testGameOverHidesHudScore(): Unit \ Assert =
    let scene = GameOverScene.addGameOverUI(testFontAtlas(), testScene());
    match Scene.getEngineNode(ScoreScene.scoreLabelPath(), scene) {
        case Some(EngineNode.Label2DWithState(label, _)) =>
            Assert.assertFalse(CanvasItem.isVisible(label))
        case _ => bug!("score_label not found")
    }
