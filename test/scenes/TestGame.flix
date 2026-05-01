// Tests for Flappy Bird Game module — Phase 1〜3

// ========================================================================
// テスト用ヘルパー
// ========================================================================

/// Math.Random のモックハンドラ（randomFloat64 → 0.5）
def withMockRandom(f: Unit -> a \ Math.Random): a =
    run f() with handler Math.Random {
        def randomFloat64(k) = k(0.5)
        def randomInt64(k) = k(42i64)
    }

/// GameEngine.Game + Math.Random のモックハンドラ
def withMockEngine(f: Unit -> a \ {GameEngine.Game, Math.Random}): a =
    run {
        run f() with handler GameEngine.Game {
            def render(_, k) = k(())
            def shouldClose(k) = k(false)
            def getDeltaTime(k) = k(0.016)
            def isKeyPressed(_, k) = k(false)
            def getMousePosition(k) = k(Vec2.zero())
            def isMouseButtonPressed(_, k) = k(false)
            def getFontAtlas(_, k) = k(testFontAtlas())
            def getViewportRect(k) = k(Rect2.fromSize({x = 288.0, y = 512.0}))
        }
    } with handler Math.Random {
        def randomFloat64(k) = k(0.5)
        def randomInt64(k) = k(42i64)
    }

/// テスト用のダミー FontAtlas（空のグリフマップ）
def testFontAtlas(): FontAtlas = {
    textureName = "font_test",
    fontSize = 32.0,
    textureSize = 512.0,
    ascent = 0.0,
    descent = 0.0,
    lineGap = 0.0,
    glyphs = Map.empty()
}

/// テスト用ヘルパー: buildState のシーンを取得（Math.Random をモックで処理）
def testScene(): Scene[NodeTag] =
    withMockRandom(() -> Game.buildState(testFontAtlas())#scene)

/// テスト用ヘルパー: buildState の GameState を取得（Math.Random をモックで処理）
def testState(): GameState =
    withMockRandom(() -> Game.buildState(testFontAtlas()))

/// Vec2 をタプルに変換するヘルパー
def vecToTuple(v: Vec2.Vec2): (Float64, Float64) = (v#x, v#y)

// ========================================================================
// buildState: ノード数・構造
// ========================================================================

/// シーンには bird(+sprite+area) + camera + background(+bg_sprite)
///   + ground_0(+sprite) + ground_1(+sprite)
///   + 3ペア × (2パイプ(+sprite) + coin) = 25 ノード
@Test
def testBuildSceneNodeCount(): Unit \ Assert =
    Assert.assertEq(expected = 25, Scene.nodeCount(testScene()))

/// ルートノードは 14（bird, camera, background, ground_0, ground_1, pipe_0〜2 × top/bottom/coin）
@Test
def testBuildSceneRootCount(): Unit \ Assert =
    Assert.assertEq(expected = 14, Map.size(Scene.states(testScene())))

/// 初期フェーズは Playing
@Test
def testBuildStatePhase(): Unit \ Assert =
    Assert.assertEq(expected = GamePhase.Playing, testState()#phase)

/// 初期 groundCounter は 2（ground_0, ground_1 が配置済み）
@Test
def testBuildStateGroundCounter(): Unit \ Assert =
    Assert.assertEq(expected = 2, testState()#groundCounter)

// ========================================================================
// BirdScene: 鳥の初期配置
// ========================================================================

/// 鳥の初期位置は画面中央付近 (144, 256)
@Test
def testBirdInitialPosition(): Unit \ Assert =
    let pos = Scene.globalPosition("bird", testScene());
    Assert.assertEq(expected = (144.0, 256.0), vecToTuple(pos))

/// 鳥の初期状態が Flapping であること
@Test
def testBirdInitialState(): Unit \ Assert =
    let birdData = BirdScene.getBirdData(testScene());
    Assert.assertEq(expected = BirdState.Flapping, birdData#state)

/// 鳥のルートノードが RigidBody2D であること
@Test
def testBirdIsRigidBody(): Unit \ Assert =
    match Scene.getEngineNode("bird" :: Nil, testScene()) {
        case Some(EngineNode.RigidBody2DWithState(_, _)) => Assert.assertTrue(true)
        case _ => bug!("Expected RigidBody2DWithState")
    }

/// 鳥の gravity_scale が 1.0 であること
@Test
def testBirdGravityScale(): Unit \ Assert =
    match Scene.getEngineNode("bird" :: Nil, testScene()) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = 1.0, RigidBody2D.getGravityScale(body))
        case _ => bug!("bird not found")
    }

/// 鳥のスプライト子ノードが存在すること
@Test
def testBirdHasSpriteChild(): Unit \ Assert =
    match Scene.getState("bird" :: "sprite" :: Nil, testScene()) {
        case Some(NodeTag.NoTag) => Assert.assertTrue(true)
        case _ => bug!("Expected NoTag child")
    }

/// 鳥のスプライトの初期アニメーションが flap であること
@Test
def testBirdFlapAnimation(): Unit \ Assert =
    match Scene.getEngineNode("bird" :: "sprite" :: Nil, testScene()) {
        case Some(EngineNode.AnimSprite2DWithState(sprite, _)) =>
            Assert.assertEq(expected = "flap", AnimatedSprite2D.getCurrentAnimation(sprite))
        case _ => bug!("bird sprite not found")
    }

/// 鳥の初期 X 速度が 100 であること（横スクロール用）
@Test
def testBirdInitialXVelocity(): Unit \ Assert =
    match Scene.getEngineNode("bird" :: Nil, testScene()) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = 100.0, RigidBody2D.getLinearVelocity(body)#x)
        case _ => bug!("bird not found")
    }

// ========================================================================
// BirdScene: Area2D 子ノード（衝突検知用）
// ========================================================================

/// 鳥に Area2D 子ノードが存在すること
@Test
def testBirdHasAreaChild(): Unit \ Assert =
    match Scene.getState("bird" :: "area" :: Nil, testScene()) {
        case Some(NodeTag.BirdArea) => Assert.assertTrue(true)
        case _ => bug!("Expected BirdArea child")
    }

/// Area2D の monitoring が true であること（衝突を検知する側）
@Test
def testBirdAreaMonitoring(): Unit \ Assert =
    match Scene.getEngineNode("bird" :: "area" :: Nil, testScene()) {
        case Some(EngineNode.Area2DWithState(area, _)) =>
            Assert.assertTrue(CollisionObject2D.isMonitoring(area))
        case _ => bug!("bird area not found")
    }

// ========================================================================
// 重力: RigidBody2D が重力で落下する
// ========================================================================

/// 重力により鳥が下方向に移動する
@Test
def testBirdFallsWithGravity(): Unit \ Assert =
    let scene = testScene()
        |> PhysicsStep.integrate(0.1, PhysicsStep.defaultGravity());
    let pos = Scene.globalPosition("bird", scene);
    Assert.assertTrue(pos#y > 256.0)

/// 0.5 秒後にはかなり落下している
@Test
def testBirdFallsSignificantly(): Unit \ Assert =
    let scene = testScene()
        |> PhysicsStep.integrate(0.5, PhysicsStep.defaultGravity());
    let pos = Scene.globalPosition("bird", scene);
    Assert.assertTrue(pos#y > 400.0)

// ========================================================================
// フラップ: 上方向の速度が設定される
// ========================================================================

/// flap で Y 方向の速度が -300 に設定される
@Test
def testFlapSetsVelocity(): Unit \ Assert =
    let scene = BirdScene.flap(testScene());
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = -300.0, RigidBody2D.getLinearVelocity(body)#y)
        case _ => bug!("bird not found")
    }

/// flap で角速度が -3.0 に設定される
@Test
def testFlapSetsAngularVelocity(): Unit \ Assert =
    let scene = BirdScene.flap(testScene());
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = -3.0, RigidBody2D.getAngularVelocity(body))
        case _ => bug!("bird not found")
    }

/// flap 後に重力を適用すると、一度上昇してから落下する
@Test
def testFlapThenGravity(): Unit \ Assert =
    let scene = testScene()
        |> BirdScene.flap
        |> PhysicsStep.integrate(0.02, PhysicsStep.defaultGravity());
    let pos = Scene.globalPosition("bird", scene);
    Assert.assertTrue(pos#y < 256.0)

// ========================================================================
// 回転制御: clampRotation
// ========================================================================

/// 回転が -30° 未満の場合 -30° にクランプされる
@Test
def testClampRotationMin(): Unit \ Assert =
    let scene = testScene()
        |> BirdScene.mapBirdBody((body, birdData) ->
            (Node2D.setRotation(-1.0, body), birdData))
        |> BirdScene.clampRotation;
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            let rot = Node2D.getRotation(body);
            let expected = -30.0 * Vec2.pi() / 180.0;
            Assert.assertTrue(Float64.abs(rot - expected) < 0.001)
        case _ => bug!("bird not found")
    }

/// 回転が -30° 未満の場合、角速度が 0 にリセットされる
@Test
def testClampRotationMinResetsAngularVelocity(): Unit \ Assert =
    let scene = testScene()
        |> BirdScene.mapBirdBody((body, birdData) ->
            (body |> Node2D.setRotation(-1.0) |> RigidBody2D.setAngularVelocity(-3.0), birdData))
        |> BirdScene.clampRotation;
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = 0.0, RigidBody2D.getAngularVelocity(body))
        case _ => bug!("bird not found")
    }

/// 落下中（linear_velocity.y > 0）は角速度が 1.5 に設定される
@Test
def testClampRotationFallAngularVelocity(): Unit \ Assert =
    let scene = testScene()
        |> BirdScene.mapBirdBody((body, birdData) ->
            (body |> Node2D.setRotation(0.0)
                  |> RigidBody2D.setAngularVelocity(0.5)
                  |> RigidBody2D.setLinearVelocity({x = 100.0, y = 50.0}),
             birdData))
        |> BirdScene.clampRotation;
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = 1.5, RigidBody2D.getAngularVelocity(body))
        case _ => bug!("bird not found")
    }

/// 上昇中（linear_velocity.y <= 0）は角速度が保持される
@Test
def testClampRotationKeepsAngularVelocityWhenRising(): Unit \ Assert =
    let scene = testScene()
        |> BirdScene.mapBirdBody((body, birdData) ->
            (body |> Node2D.setRotation(0.0)
                  |> RigidBody2D.setAngularVelocity(-3.0)
                  |> RigidBody2D.setLinearVelocity({x = 100.0, y = -150.0}),
             birdData))
        |> BirdScene.clampRotation;
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = -3.0, RigidBody2D.getAngularVelocity(body))
        case _ => bug!("bird not found")
    }

// ========================================================================
// 統合: フラップ → 物理積分 → 回転クランプ
// ========================================================================

/// フラップ → 物理積分 → 回転クランプの一連の流れ
@Test
def testFlapIntegrateClamp(): Unit \ Assert =
    let scene = testScene()
        |> BirdScene.flap
        |> PhysicsStep.integrate(0.02, PhysicsStep.defaultGravity())
        |> BirdScene.clampRotation;
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            let rot = Node2D.getRotation(body);
            let minRot = -30.0 * Vec2.pi() / 180.0;
            let maxRot = Vec2.pi() / 2.0;
            // 回転がクランプ範囲内であること
            Assert.assertTrue(rot >= minRot and rot <= maxRot)
        case _ => bug!("bird not found")
    }

/// フラップ直後は角速度が負（上向き回転）のため、clampRotation はそのまま保持する
@Test
def testFlapAngularVelocityAfterClamp(): Unit \ Assert =
    let scene = testScene()
        |> BirdScene.flap
        |> PhysicsStep.integrate(0.02, PhysicsStep.defaultGravity())
        |> BirdScene.clampRotation;
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            // フラップ角速度 -3.0 が保持される（負の角速度は clamp されない）
            Assert.assertTrue(RigidBody2D.getAngularVelocity(body) < 0.0)
        case _ => bug!("bird not found")
    }

// ========================================================================
// AnimatedSprite2D: フレーム進行
// ========================================================================

/// processAll で鳥のスプライトアニメーションが進行する
@Test
def testBirdSpriteAnimationAdvances(): Unit \ Assert =
    // fps=10, 0.15s 後にフレーム 1 に進む (frameDuration = 0.1s)
    match withMockEngine(() -> testScene() |> Scene.processAll(0.15, false))
        |> Scene.getEngineNode("bird" :: "sprite" :: Nil) {
        case Some(EngineNode.AnimSprite2DWithState(sprite, _)) =>
            Assert.assertEq(expected = "bird_orange_1", AnimatedSprite2D.currentTexture(sprite))
        case _ => bug!("bird sprite not found after process")
    }

// ========================================================================
// Phase 2: 地面の構造
// ========================================================================

/// 地面タイルが 2 枚存在すること
@Test
def testGroundTileCount(): Unit \ Assert =
    let paths = Scene.getNodesInGroup(GroundScene.groundGroup(), testScene());
    Assert.assertEq(expected = 2, List.length(paths))

/// 地面タイル 0 の位置（中心 X=168, Y=456）
@Test
def testGround0Position(): Unit \ Assert =
    let pos = Scene.globalPosition("ground_0", testScene());
    Assert.assertEq(expected = (168.0, 456.0), vecToTuple(pos))

/// 地面タイル 1 の位置（中心 X=504, Y=456）
@Test
def testGround1Position(): Unit \ Assert =
    let pos = Scene.globalPosition("ground_1", testScene());
    Assert.assertEq(expected = (504.0, 456.0), vecToTuple(pos))

/// 地面ノードが StaticBody2D であること
@Test
def testGroundIsStaticBody(): Unit \ Assert =
    match Scene.getEngineNode("ground_0" :: Nil, testScene()) {
        case Some(EngineNode.StaticBody2DWithState(_, NodeTag.Ground)) =>
            Assert.assertTrue(true)
        case _ => bug!("Expected StaticBody2DWithState with Ground tag")
    }

/// 地面の StaticBody2D が monitorable=true であること（鳥の Area2D から検知される）
@Test
def testGroundMonitorable(): Unit \ Assert =
    match Scene.getEngineNode("ground_0" :: Nil, testScene()) {
        case Some(EngineNode.StaticBody2DWithState(body, _)) =>
            Assert.assertTrue(CollisionObject2D.isMonitorable(body))
        case _ => bug!("ground not found")
    }

/// 地面にスプライト子ノードがあること
@Test
def testGroundHasSpriteChild(): Unit \ Assert =
    match Scene.getState("ground_0" :: "sprite" :: Nil, testScene()) {
        case Some(NodeTag.NoTag) => Assert.assertTrue(true)
        case _ => bug!("Expected NoTag child for ground sprite")
    }

// ========================================================================
// Phase 2: 地面リサイクル
// ========================================================================

/// ビューポート左端より右にあるタイルはリサイクルされない
@Test
def testRecycleGroundsNoOp(): Unit \ Assert =
    let scene = testScene();
    let (recycledScene, counter, _nextX) =
        GroundScene.recycleGrounds(0.0, 2, 840.0, scene);
    // 何も変わらないこと
    Assert.assertEq(expected = (2, 2),
        (counter, List.length(Scene.getNodesInGroup(GroundScene.groundGroup(), recycledScene))))

/// ビューポート左端を超えたタイルがリサイクルされる
///
///   viewportLeft = 400 のとき、ground_0(center=168, right=336) は画面外
///   → ground_0 が削除され、ground_2 が nextGroundX=840 に生成される
///
@Test
def testRecycleGroundsRemovesOffScreen(): Unit \ Assert =
    let scene = testScene();
    let (recycledScene, counter, nextX) =
        GroundScene.recycleGrounds(400.0, 2, 840.0, scene);
    let paths = Scene.getNodesInGroup(GroundScene.groundGroup(), recycledScene);
    // タイル数は変わらず 2 枚
    Assert.assertEq(expected = (2, 3, 1176.0),
        (List.length(paths), counter, nextX))

/// リサイクル後の新タイルが正しい位置にあること
@Test
def testRecycleGroundsNewTilePosition(): Unit \ Assert =
    let scene = testScene();
    let (recycledScene, _counter, _nextX) =
        GroundScene.recycleGrounds(400.0, 2, 840.0, scene);
    let pos = Scene.globalPosition("ground_2", recycledScene);
    Assert.assertEq(expected = (840.0, 456.0), vecToTuple(pos))

// ========================================================================
// Phase 2: 鳥の状態遷移 — setBirdState
// ========================================================================

/// Grounded 状態にすると速度がゼロになること
@Test
def testSetBirdStateGroundedStopsVelocity(): Unit \ Assert =
    let scene = testScene()
        |> BirdScene.flap
        |> BirdScene.setBirdState(BirdState.Grounded);
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = (0.0, 0.0),
                vecToTuple(RigidBody2D.getLinearVelocity(body)))
        case _ => bug!("bird not found")
    }

/// Grounded 状態にすると重力が無効になること
@Test
def testSetBirdStateGroundedDisablesGravity(): Unit \ Assert =
    let scene = testScene()
        |> BirdScene.setBirdState(BirdState.Grounded);
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = 0.0, RigidBody2D.getGravityScale(body))
        case _ => bug!("bird not found")
    }

/// Grounded 状態にすると BirdData の state が Grounded になること
@Test
def testSetBirdStateGroundedUpdatesData(): Unit \ Assert =
    let scene = testScene()
        |> BirdScene.setBirdState(BirdState.Grounded);
    Assert.assertEq(expected = BirdState.Grounded, BirdScene.getBirdData(scene)#state)

/// Hit 状態にすると angular velocity が 2.0 になること（落下回転演出）
@Test
def testSetBirdStateHitSetsAngularVelocity(): Unit \ Assert =
    let scene = testScene()
        |> BirdScene.setBirdState(BirdState.Hit);
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = 2.0, RigidBody2D.getAngularVelocity(body))
        case _ => bug!("bird not found")
    }

// ========================================================================
// Phase 2: 鳥と地面の衝突応答
// ========================================================================

/// 鳥が地面に衝突すると Grounded になること
@Test
def testBirdGroundCollision(): Unit \ Assert =
    let scene = Game.onBirdHitGround(testScene());
    Assert.assertEq(expected = BirdState.Grounded, BirdScene.getBirdData(scene)#state)

/// 鳥が地面に衝突すると地面の上にクランプされること
///
///   鳥を地面に重なる位置 (144, 470) に移動してから衝突処理
///   → 地面上端(400) - 鳥半径(13) = 387 にクランプ
///
@Test
def testBirdClampedAboveGround(): Unit \ Assert =
    let scene = testScene()
        |> BirdScene.mapBirdBody((body, birdData) ->
            (Node2D.setPosition({x = 144.0, y = 470.0}, body), birdData))
        |> Game.onBirdHitGround;
    let pos = Scene.globalPosition("bird", scene);
    Assert.assertEq(expected = 387.0, pos#y)

// ========================================================================
// Phase 3: カメラ
// ========================================================================

/// カメラが存在し、有効であること
@Test
def testCameraExists(): Unit \ Assert =
    match Scene.getEngineNode("camera" :: Nil, testScene()) {
        case Some(EngineNode.Camera2DWithState(cam, _)) =>
            Assert.assertTrue(Camera2D.isEnabled(cam))
        case _ => bug!("camera not found")
    }

/// カメラのアンカーモードが FixedTopLeft であること
@Test
def testCameraAnchorMode(): Unit \ Assert =
    match Scene.getEngineNode("camera" :: Nil, testScene()) {
        case Some(EngineNode.Camera2DWithState(cam, _)) =>
            Assert.assertEq(expected = Camera2DAnchorMode.FixedTopLeft,
                Camera2D.getAnchorMode(cam))
        case _ => bug!("camera not found")
    }

/// カメラのオフセットが (-72, 0) であること
@Test
def testCameraOffset(): Unit \ Assert =
    match Scene.getEngineNode("camera" :: Nil, testScene()) {
        case Some(EngineNode.Camera2DWithState(cam, _)) =>
            Assert.assertEq(expected = (-72.0, 0.0),
                vecToTuple(Camera2D.getOffset(cam)))
        case _ => bug!("camera not found")
    }

/// カメラの初期位置が鳥の X 座標と一致すること
@Test
def testCameraInitialPosition(): Unit \ Assert =
    match Scene.getEngineNode("camera" :: Nil, testScene()) {
        case Some(EngineNode.Camera2DWithState(cam, _)) =>
            let camPos = Node2D.getPosition(cam);
            Assert.assertEq(expected = (144.0, 0.0), vecToTuple(camPos))
        case _ => bug!("camera not found")
    }

// ========================================================================
// Phase 3: Camera2D FixedTopLeft ビューポートオフセット
// ========================================================================

/// FixedTopLeft モードでは position+offset がビューポート左上になること
///
///   camera position=(200, 0), offset=(-72, 0)
///   → ビューポート左上 = (128, 0)
///
@Test
def testFixedTopLeftViewportOffset(): Unit \ Assert =
    let cam = Camera2D.makeWithOffset({x = 200.0, y = 0.0}, {x = -72.0, y = 0.0})
        |> Camera2D.setAnchorMode(Camera2DAnchorMode.FixedTopLeft);
    let offset = Camera2D.getViewportOffset(cam,
        {viewportWidth = 288.0, viewportHeight = 512.0});
    Assert.assertEq(expected = (128.0, 0.0), vecToTuple(offset))

/// DragCenter モードでは position+offset がビューポート中心になること
///
///   camera position=(200, 256), offset=(0, 0)
///   → ビューポート左上 = (200-144, 256-256) = (56, 0)
///
@Test
def testDragCenterViewportOffset(): Unit \ Assert =
    let cam = Camera2D.make({x = 200.0, y = 256.0});
    let offset = Camera2D.getViewportOffset(cam,
        {viewportWidth = 288.0, viewportHeight = 512.0});
    Assert.assertEq(expected = (56.0, 0.0), vecToTuple(offset))

// ========================================================================
// Phase 3: 背景
// ========================================================================

/// 背景が CanvasLayer であること
@Test
def testBackgroundIsCanvasLayer(): Unit \ Assert =
    match Scene.getEngineNode("background" :: Nil, testScene()) {
        case Some(EngineNode.CanvasLayerWithState(cl, _)) =>
            Assert.assertEq(expected = -1, CanvasLayer.getDrawLayer(cl))
        case _ => bug!("background not found")
    }

/// 背景にスプライト子ノードがあること
@Test
def testBackgroundHasSprite(): Unit \ Assert =
    match Scene.getEngineNode("background" :: "bg_sprite" :: Nil, testScene()) {
        case Some(EngineNode.Sprite2DWithState(_, _)) =>
            Assert.assertTrue(true)
        case _ => bug!("background sprite not found")
    }

// ========================================================================
// Phase 4: パイプの構造
// ========================================================================

/// パイプグループに 9 ノード（3 ペア × (上下 + coin)）があること
@Test
def testPipeGroupCount(): Unit \ Assert =
    let paths = Scene.getNodesInGroup(PipeScene.pipeGroup(), testScene());
    Assert.assertEq(expected = 9, List.length(paths))

/// パイプノードが StaticBody2D であること
@Test
def testPipeIsStaticBody(): Unit \ Assert =
    match Scene.getEngineNode("pipe_0_bottom" :: Nil, testScene()) {
        case Some(EngineNode.StaticBody2DWithState(_, NodeTag.Pipe)) =>
            Assert.assertTrue(true)
        case _ => bug!("Expected StaticBody2DWithState with Pipe tag")
    }

/// パイプの StaticBody2D が monitorable=true であること（鳥の Area2D から検知される）
@Test
def testPipeMonitorable(): Unit \ Assert =
    match Scene.getEngineNode("pipe_0_bottom" :: Nil, testScene()) {
        case Some(EngineNode.StaticBody2DWithState(body, _)) =>
            Assert.assertTrue(CollisionObject2D.isMonitorable(body))
        case _ => bug!("pipe not found")
    }

/// パイプにスプライト子ノードがあること
@Test
def testPipeHasSpriteChild(): Unit \ Assert =
    match Scene.getState("pipe_0_bottom" :: "sprite" :: Nil, testScene()) {
        case Some(NodeTag.NoTag) => Assert.assertTrue(true)
        case _ => bug!("Expected NoTag child for pipe sprite")
    }

// ========================================================================
// Phase 4: パイプの配置（mock random=0.5 → gapY=200.0）
// ========================================================================

/// 最初のボトムパイプの位置（X=432, Y=200+202=402）
///
///   gapY = 110 + (290-110) × 0.5 = 200.0
///   bottomY = 200 + 202 = 402.0
///
@Test
def testPipe0BottomPosition(): Unit \ Assert =
    let pos = Scene.globalPosition("pipe_0_bottom", testScene());
    Assert.assertEq(expected = (432.0, 402.0), vecToTuple(pos))

/// 最初のトップパイプの位置（X=432, Y=200-202=-2）
///
///   topY = 200 - 202 = -2.0
///
@Test
def testPipe0TopPosition(): Unit \ Assert =
    let pos = Scene.globalPosition("pipe_0_top", testScene());
    Assert.assertEq(expected = (432.0, -2.0), vecToTuple(pos))

/// 2 番目のパイプペアの X 座標（432+182=614）
@Test
def testPipe1Position(): Unit \ Assert =
    let pos = Scene.globalPosition("pipe_1_bottom", testScene());
    Assert.assertEq(expected = (614.0, 402.0), vecToTuple(pos))

/// 3 番目のパイプペアの X 座標（432+364=796）
@Test
def testPipe2Position(): Unit \ Assert =
    let pos = Scene.globalPosition("pipe_2_bottom", testScene());
    Assert.assertEq(expected = (796.0, 402.0), vecToTuple(pos))

// ========================================================================
// Phase 4: GameState パイプフィールド
// ========================================================================

/// pipeCounter は 3（3 ペア配置済み）
@Test
def testBuildStatePipeCounter(): Unit \ Assert =
    Assert.assertEq(expected = 3, testState()#pipeCounter)

/// nextPipeX は 978.0（432 + 182×3）
@Test
def testBuildStateNextPipeX(): Unit \ Assert =
    Assert.assertEq(expected = 978.0, testState()#nextPipeX)

// ========================================================================
// Phase 4: spawnPipePairAt
// ========================================================================

/// spawnPipePairAt で指定位置にペアが配置されること
///
///   gapY=200 → top=(400, -2), bottom=(400, 402)
///
@Test
def testSpawnPipePairAt(): Unit \ Assert =
    let scene = Scene.empty()
        |> PipeScene.spawnPipePairAt(0, 400.0, 200.0);
    let topPos = Scene.globalPosition("pipe_0_top", scene);
    let bottomPos = Scene.globalPosition("pipe_0_bottom", scene);
    Assert.assertEq(expected = ((400.0, -2.0), (400.0, 402.0)),
        (vecToTuple(topPos), vecToTuple(bottomPos)))

// ========================================================================
// Phase 4: パイプ衝突応答
// ========================================================================

/// Flapping 状態で鳥がパイプに衝突すると Hit になること
@Test
def testBirdPipeCollisionFlappingToHit(): Unit \ Assert =
    let pipePath = "pipe_0_top" :: Nil;
    let scene = Game.onBirdHitPipe(pipePath = pipePath, testScene());
    Assert.assertEq(expected = BirdState.Hit, BirdScene.getBirdData(scene)#state)

/// パイプ衝突時に鳥がパイプの左端に押し戻されること
///
///   pipe_0_top の X=432、pipeHalfWidth=26、birdRadius=13
///   → 押し戻し後の鳥 X = 432 - 26 - 13 = 393
///
@Test
def testBirdPipeCollisionPushBack(): Unit \ Assert =
    let pipePath = "pipe_0_top" :: Nil;
    let scene = Game.onBirdHitPipe(pipePath = pipePath, testScene());
    let birdX = Scene.globalPosition("bird", scene)#x;
    Assert.assertEq(expected = 393.0, birdX)

/// Hit 状態で再度パイプ衝突しても変化しないこと
@Test
def testBirdPipeCollisionHitNoChange(): Unit \ Assert =
    let pipePath = "pipe_0_top" :: Nil;
    let scene = testScene()
        |> BirdScene.setBirdState(BirdState.Hit)
        |> Game.onBirdHitPipe(pipePath = pipePath);
    Assert.assertEq(expected = BirdState.Hit, BirdScene.getBirdData(scene)#state)

/// Grounded 状態でパイプ衝突しても変化しないこと
@Test
def testBirdPipeCollisionGroundedNoChange(): Unit \ Assert =
    let pipePath = "pipe_0_top" :: Nil;
    let scene = testScene()
        |> BirdScene.setBirdState(BirdState.Grounded)
        |> Game.onBirdHitPipe(pipePath = pipePath);
    Assert.assertEq(expected = BirdState.Grounded, BirdScene.getBirdData(scene)#state)

// ========================================================================
// Phase 4: パイプリサイクル
// ========================================================================

/// ビューポート右にあるパイプはリサイクルされないこと
@Test
def testRecyclePipesNoOp(): Unit \ Assert =
    let (recycledScene, counter, _nextX) = withMockRandom(() ->
        PipeScene.recyclePipes(0.0, 3, 978.0, testScene()));
    Assert.assertEq(expected = (3, 9),
        (counter, List.length(Scene.getNodesInGroup(PipeScene.pipeGroup(), recycledScene))))

/// ビューポート左端を超えたパイプペアがリサイクルされること
///
///   viewportLeft=500 のとき、pipe_0(X=432) は右端(432+26=458) < 500 で画面外
///   → pipe_0_top, pipe_0_bottom が削除され、pipe_3 ペアが nextPipeX=978 に生成
///   → パイプ数は変わらず 6、counter=4、nextX=1160
///
@Test
def testRecyclePipesRemovesOffScreen(): Unit \ Assert =
    let (recycledScene, counter, nextX) = withMockRandom(() ->
        PipeScene.recyclePipes(500.0, 3, 978.0, testScene()));
    let paths = Scene.getNodesInGroup(PipeScene.pipeGroup(), recycledScene);
    Assert.assertEq(expected = (9, 4, 1160.0),
        (List.length(paths), counter, nextX))

/// リサイクル後の新パイプが正しい位置にあること
///
///   pipe_3_bottom は (978, 402) に配置される（mock random=0.5 → gapY=200）
///
@Test
def testRecyclePipesNewPipePosition(): Unit \ Assert =
    let (recycledScene, _counter, _nextX) = withMockRandom(() ->
        PipeScene.recyclePipes(500.0, 3, 978.0, testScene()));
    let pos = Scene.globalPosition("pipe_3_bottom", recycledScene);
    Assert.assertEq(expected = (978.0, 402.0), vecToTuple(pos))
