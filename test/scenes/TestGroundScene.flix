// Tests for GroundScene — 地面タイルの構築と鳥との衝突応答
// 共通ヘルパーは TestGame.flix を参照

// ========================================================================
// 地面の構造
// ========================================================================

/// 地面タイル 2 枚の中心位置
///   ground_0: (168, 456) / ground_1: (504, 456)
@Test
def testGroundPositions(): Unit \ Assert =
    let scene = testScene();
    Assert.assertEq(
        expected = ((168.0, 456.0), (504.0, 456.0)),
        (vecToTuple(Scene.globalPosition("ground_0", scene)),
         vecToTuple(Scene.globalPosition("ground_1", scene))))

/// 地面ノードは StaticBody2D + Ground タグ + monitorable=true（鳥の Area2D から検知される）
@Test
def testGroundIsMonitorableStaticBody(): Unit \ Assert =
    match Scene.getEngineNode("ground_0" :: Nil, testScene()) {
        case Some(EngineNode.StaticBody2DWithState(body, NodeTag.Ground)) =>
            Assert.assertTrue(CollisionObject2D.isMonitorable(body))
        case _ => bug!("Expected StaticBody2DWithState with Ground tag")
    }

// ========================================================================
// 鳥と地面の衝突応答
// ========================================================================

/// 鳥が地面に衝突すると Grounded になる
@Test
def testBirdGroundCollision(): Unit \ Assert =
    let scene = withMockAudioAndState(() -> BirdScene.onBirdHitGround(testScene()));
    Assert.assertEq(expected = BirdState.Grounded, BirdScene.getBirdData(scene)#state)

/// PhysicsStep.resolveStaticCollisions が鳥を地面の上にクランプする
///
///   鳥を地面と重なる位置 (144, 410) に移動してから物理衝突解決
///   Ground top=400, half=56, Bird radius=13:
///     penetration depth = bird radius - (410 - 400) = 3
///     → 上方向に 23 押し出し → 410 - 23 = 387
///   期待: y = groundTopY(400) - birdRadius(13) = 387
@Test
def testBirdClampedAboveGround(): Unit \ Assert =
    let scene = testScene()
        |> BirdScene.mapBirdBody((body, birdData) ->
            (Node2D.setPosition({x = 144.0, y = 410.0}, body), birdData))
        |> PhysicsStep.resolveStaticCollisions;
    let pos = Scene.globalPosition("bird", scene);
    Assert.assertEq(expected = 387.0, pos#y)
