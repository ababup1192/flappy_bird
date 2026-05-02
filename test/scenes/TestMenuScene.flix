// Tests for MenuScene — メニュー画面の構築と挙動
// 共通ヘルパーは TestGame.flix を参照

// ========================================================================
// メニュー画面の鳥
// ========================================================================

/// メニュー画面の鳥は Flying 状態・重力 0・速度 0 で静止する
@Test
def testMenuBirdState(): Unit \ Assert =
    let scene = testMenuScene();
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(
                expected = (BirdState.Flying, 0.0, (0.0, 0.0)),
                (BirdScene.getBirdData(scene)#state,
                 RigidBody2D.getGravityScale(body),
                 vecToTuple(RigidBody2D.getLinearVelocity(body))))
        case _ => bug!("bird not found")
    }

/// メニュー画面では鳥は静止する（bird.gd 忠実化により bobbing は削除済み。
/// Godot ではアニメーションで実現される視覚効果だが Flix エンジンに該当機能なし）
@Test
def testMenuBirdStatic(): Unit \ Assert =
    let scene = testMenuScene();
    let posBefore = Scene.globalPosition("bird", scene);
    let sceneAfter = withMockRandom(() -> withMockRecycle(() -> scene |> Scene.processAll(0.5, false)));
    let posAfter = Scene.globalPosition("bird", sceneAfter);
    Assert.assertTrue(Float64.abs(posAfter#y - posBefore#y) < 0.001)

// ========================================================================
// メニュー画面の構成要素
// ========================================================================

/// メニュー画面の UI 要素（タイトルロゴと操作説明画像が Sprite2D として存在）
@Test
def testMenuUIElements(): Unit \ Assert =
    let scene = testMenuScene();
    match (Scene.getEngineNode(MenuScene.titleLogoPath(), scene),
           Scene.getEngineNode(MenuScene.instructionsPath(), scene)) {
        case (Some(EngineNode.Sprite2DWithState(_, _)),
              Some(EngineNode.Sprite2DWithState(_, _))) =>
            Assert.assertTrue(true)
        case _ => bug!("title_logo or instructions_img not found")
    }

/// メニュー画面の差分: パイプなし・地面 2 枚・スコアラベル非表示
@Test
def testMenuSceneStructure(): Unit \ Assert =
    let scene = testMenuScene();
    let scoreVisible = match Scene.getEngineNode(ScoreScene.scoreLabelPath(), scene) {
        case Some(EngineNode.Label2DWithState(label, _)) => CanvasItem.isVisible(label)
        case _ => bug!("score_label not found")
    };
    Assert.assertEq(
        expected = (0, 2, false),
        (List.length(Scene.getNodesInGroup(PipeScene.pipeGroup(), scene)),
         List.length(Scene.getNodesInGroup(GroundScene.groundGroup(), scene)),
         scoreVisible))
