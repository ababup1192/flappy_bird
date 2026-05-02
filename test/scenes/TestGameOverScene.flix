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

/// メダルノードは「今回のスコア」「ベストスコア」のいずれかが 10 以上の時だけ追加される
///   - score=5,  bestScore=0  → なし
///   - score=15, bestScore=15 → あり（今回スコア）
///   - score=3,  bestScore=15 → あり（ベストスコア由来、メダル永続化）
@Test
def testGameOverUIMedalPresence(): Unit \ Assert =
    let medalPath = "gameover" :: "medal" :: Nil;
    let buildWith = (score, best) ->
        testScene()
            |> ScoreScene.setScore(score)
            |> ScoreScene.setBestScore(best)
            |> GameOverScene.addGameOverUI(testFontAtlas());
    let hasMedal = scene -> not Option.isEmpty(Scene.getEngineNode(medalPath, scene));
    Assert.assertEq(
        expected = (false, true, true),
        (hasMedal(buildWith(5, 0)),
         hasMedal(buildWith(15, 15)),
         hasMedal(buildWith(3, 15))))

/// addGameOverUI 後に HUD スコアラベルが非表示になる
@Test
def testGameOverHidesHudScore(): Unit \ Assert =
    let scene = GameOverScene.addGameOverUI(testFontAtlas(), testScene());
    match Scene.getEngineNode(ScoreScene.scoreLabelPath(), scene) {
        case Some(EngineNode.Label2DWithState(label, _)) =>
            Assert.assertFalse(CanvasItem.isVisible(label))
        case _ => bug!("score_label not found")
    }
