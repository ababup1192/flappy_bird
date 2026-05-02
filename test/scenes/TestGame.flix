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

/// GameEngine.Audio のモックハンドラ（playAudio/stopAudio は no-op）
def withMockAudio(f: Unit -> a \ GameEngine.Audio): a =
    run f() with handler GameEngine.Audio {
        def playAudio(_, k) = k(())
        def stopAudio(_, k) = k(())
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
    withMockRandom(() -> Game.buildState(testFontAtlas(), 0)#scene)

/// テスト用ヘルパー: buildState の GameState を取得（Math.Random をモックで処理）
def testState(): GameState =
    withMockRandom(() -> Game.buildState(testFontAtlas(), 0))

/// テスト用ヘルパー: LevelManagerData を取得
def testLevelData(): LevelManagerData =
    Game.getLevelManagerData(testScene())

/// Vec2 をタプルに変換するヘルパー
def vecToTuple(v: Vec2.Vec2): (Float64, Float64) = (v#x, v#y)

/// 鳥のノードに BirdScene.physicsProcess を適用するテストヘルパー
/// （旧 BirdScene.clampRotation の代替: physicsProcess は Flapping 状態のみ動作）
def runBirdPhysicsProcess(scene: Scene[NodeTag]): Scene[NodeTag] =
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(node) =>
            let (newNode, newScene) = BirdScene.physicsProcess(0.0, node, "bird" :: Nil, scene);
            Scene.setEngineNode("bird" :: Nil, newNode, newScene)
        case None => bug!("bird not found")
    }

/// 鳥に Space キー入力経由で flap を発火させるテストヘルパー
/// （flap は flappingInput にインライン化済みのため、入力 API 経由でテスト）
def runFlap(scene: Scene[NodeTag]): Scene[NodeTag] =
    withMockAudio(() -> BirdScene.input(BirdInputEvent.KeyPressed(GameEngine.Key.Space), scene))

// ========================================================================
// buildState: ノード数・構造
// ========================================================================

/// シーンには bird(+sprite+area) + camera + background(+bg_sprite)
///   + hud(+score_label+best_score_label) + level_manager
///   + ground_0(+sprite) + ground_1(+sprite)
///   + 3ペア × (2パイプ(+sprite) + coin) = 29 ノード
@Test
def testBuildSceneNodeCount(): Unit \ Assert =
    Assert.assertEq(expected = 29, Scene.nodeCount(testScene()))

/// ルートノードは 16（bird, camera, background, hud, level_manager, ground_0, ground_1, pipe_0〜2 × top/bottom/coin）
@Test
def testBuildSceneRootCount(): Unit \ Assert =
    Assert.assertEq(expected = 16, Map.size(Scene.states(testScene())))

/// 初期フェーズは Playing
@Test
def testBuildStatePhase(): Unit \ Assert =
    Assert.assertEq(expected = GamePhase.Playing, testState()#phase)

/// 初期 groundCounter は 2（ground_0, ground_1 が配置済み）
@Test
def testBuildStateGroundCounter(): Unit \ Assert =
    Assert.assertEq(expected = 2, testLevelData()#groundCounter)

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
    let scene = runFlap(testScene());
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = -300.0, RigidBody2D.getLinearVelocity(body)#y)
        case _ => bug!("bird not found")
    }

/// flap で角速度が -3.0 に設定される
@Test
def testFlapSetsAngularVelocity(): Unit \ Assert =
    let scene = runFlap(testScene());
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = -3.0, RigidBody2D.getAngularVelocity(body))
        case _ => bug!("bird not found")
    }

/// flap 後に重力を適用すると、一度上昇してから落下する
@Test
def testFlapThenGravity(): Unit \ Assert =
    let scene = testScene()
        |> runFlap
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
        |> runBirdPhysicsProcess;
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
        |> runBirdPhysicsProcess;
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
        |> runBirdPhysicsProcess;
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
        |> runBirdPhysicsProcess;
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
        |> runFlap
        |> PhysicsStep.integrate(0.02, PhysicsStep.defaultGravity())
        |> runBirdPhysicsProcess;
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
        |> runFlap
        |> PhysicsStep.integrate(0.02, PhysicsStep.defaultGravity())
        |> runBirdPhysicsProcess;
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
    match withMockRandom(() -> testScene() |> Scene.processAll(0.15, false))
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
    let scene = withMockAudio(() ->
        testScene()
            |> runFlap
            |> BirdScene.setBirdState(BirdState.Grounded));
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = (0.0, 0.0),
                vecToTuple(RigidBody2D.getLinearVelocity(body)))
        case _ => bug!("bird not found")
    }

/// Grounded 状態にすると重力が無効になること
@Test
def testSetBirdStateGroundedDisablesGravity(): Unit \ Assert =
    let scene = withMockAudio(() ->
        testScene()
            |> BirdScene.setBirdState(BirdState.Grounded));
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = 0.0, RigidBody2D.getGravityScale(body))
        case _ => bug!("bird not found")
    }

/// Grounded 状態にすると BirdData の state が Grounded になること
@Test
def testSetBirdStateGroundedUpdatesData(): Unit \ Assert =
    let scene = withMockAudio(() ->
        testScene()
            |> BirdScene.setBirdState(BirdState.Grounded));
    Assert.assertEq(expected = BirdState.Grounded, BirdScene.getBirdData(scene)#state)

/// Hit 状態にすると angular velocity が 2.0 になること（落下回転演出）
@Test
def testSetBirdStateHitSetsAngularVelocity(): Unit \ Assert =
    let scene = withMockAudio(() ->
        testScene()
            |> BirdScene.setBirdState(BirdState.Hit));
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
    let scene = withMockAudio(() -> Game.onBirdHitGround(testScene()));
    Assert.assertEq(expected = BirdState.Grounded, BirdScene.getBirdData(scene)#state)

/// 鳥が地面に衝突すると地面の上にクランプされること
///
///   鳥を地面に重なる位置 (144, 470) に移動してから衝突処理
///   → 地面上端(400) - 鳥半径(13) = 387 にクランプ
///
@Test
def testBirdClampedAboveGround(): Unit \ Assert =
    let scene = withMockAudio(() ->
        testScene()
            |> BirdScene.mapBirdBody((body, birdData) ->
                (Node2D.setPosition({x = 144.0, y = 470.0}, body), birdData))
            |> Game.onBirdHitGround);
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

/// 最初のボトムパイプの位置（X=576, Y=200+250=450）
///
///   gapY = 110 + (290-110) × 0.5 = 200.0
///   score=0 → easySpriteOffset=250
///   bottomY = 200 + 250 = 450.0
///
@Test
def testPipe0BottomPosition(): Unit \ Assert =
    let pos = Scene.globalPosition("pipe_0_bottom", testScene());
    Assert.assertEq(expected = (576.0, 450.0), vecToTuple(pos))

/// 最初のトップパイプの位置（X=576, Y=200-250=-50）
///
///   score=0 → easySpriteOffset=250
///   topY = 200 - 250 = -50.0
///
@Test
def testPipe0TopPosition(): Unit \ Assert =
    let pos = Scene.globalPosition("pipe_0_top", testScene());
    Assert.assertEq(expected = (576.0, -50.0), vecToTuple(pos))

/// 2 番目のパイプペアの位置（X=576+182=758、score=0 の初心者向けギャップ）
@Test
def testPipe1Position(): Unit \ Assert =
    let pos = Scene.globalPosition("pipe_1_bottom", testScene());
    Assert.assertEq(expected = (758.0, 450.0), vecToTuple(pos))

/// 3 番目のパイプペアの位置（X=576+364=940、score=0 の初心者向けギャップ）
@Test
def testPipe2Position(): Unit \ Assert =
    let pos = Scene.globalPosition("pipe_2_bottom", testScene());
    Assert.assertEq(expected = (940.0, 450.0), vecToTuple(pos))

// ========================================================================
// Phase 4: GameState パイプフィールド
// ========================================================================

/// pipeCounter は 3（3 ペア配置済み）
@Test
def testBuildStatePipeCounter(): Unit \ Assert =
    Assert.assertEq(expected = 3, testLevelData()#pipeCounter)

/// nextPipeX は 1122.0（576 + 182×3）
@Test
def testBuildStateNextPipeX(): Unit \ Assert =
    Assert.assertEq(expected = 1122.0, testLevelData()#nextPipeX)

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
    let scene = withMockAudio(() -> Game.onBirdHitPipe(pipePath = pipePath, testScene()));
    Assert.assertEq(expected = BirdState.Hit, BirdScene.getBirdData(scene)#state)

/// パイプ衝突時に鳥がパイプの左端に押し戻されること
///
///   pipe_0_top の X=576、pipeHalfWidth=26、birdRadius=13
///   → 押し戻し後の鳥 X = 576 - 26 - 13 = 537
///
@Test
def testBirdPipeCollisionPushBack(): Unit \ Assert =
    let pipePath = "pipe_0_top" :: Nil;
    let scene = withMockAudio(() -> Game.onBirdHitPipe(pipePath = pipePath, testScene()));
    let birdX = Scene.globalPosition("bird", scene)#x;
    Assert.assertEq(expected = 537.0, birdX)

/// Hit 状態で再度パイプ衝突しても変化しないこと
@Test
def testBirdPipeCollisionHitNoChange(): Unit \ Assert =
    let pipePath = "pipe_0_top" :: Nil;
    let scene = withMockAudio(() ->
        testScene()
            |> BirdScene.setBirdState(BirdState.Hit)
            |> Game.onBirdHitPipe(pipePath = pipePath));
    Assert.assertEq(expected = BirdState.Hit, BirdScene.getBirdData(scene)#state)

/// Grounded 状態でパイプ衝突しても変化しないこと
@Test
def testBirdPipeCollisionGroundedNoChange(): Unit \ Assert =
    let pipePath = "pipe_0_top" :: Nil;
    let scene = withMockAudio(() ->
        testScene()
            |> BirdScene.setBirdState(BirdState.Grounded)
            |> Game.onBirdHitPipe(pipePath = pipePath));
    Assert.assertEq(expected = BirdState.Grounded, BirdScene.getBirdData(scene)#state)

// ========================================================================
// Phase 4: パイプリサイクル
// ========================================================================

/// ビューポート右にあるパイプはリサイクルされないこと
@Test
def testRecyclePipesNoOp(): Unit \ Assert =
    let (recycledScene, counter, _nextX) = withMockRandom(() ->
        PipeScene.recyclePipes(0.0, 3, 978.0, 10, testScene()));
    Assert.assertEq(expected = (3, 9),
        (counter, List.length(Scene.getNodesInGroup(PipeScene.pipeGroup(), recycledScene))))

/// ビューポート左端を超えたパイプペアがリサイクルされること（score=10 の通常間隔 182）
///
///   viewportLeft=700 のとき、pipe_0(X=576) は右端(576+26=602) < 700 で画面外
///   → pipe_0_top, pipe_0_bottom, pipe_0_coin が削除され、pipe_3 ペアが nextPipeX=978 に生成
///   → パイプ数は変わらず 9、counter=4、nextX=978+182=1160
///
@Test
def testRecyclePipesRemovesOffScreen(): Unit \ Assert =
    let (recycledScene, counter, nextX) = withMockRandom(() ->
        PipeScene.recyclePipes(700.0, 3, 978.0, 10, testScene()));
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
        PipeScene.recyclePipes(700.0, 3, 978.0, 10, testScene()));
    let pos = Scene.globalPosition("pipe_3_bottom", recycledScene);
    Assert.assertEq(expected = (978.0, 402.0), vecToTuple(pos))

// ========================================================================
// Phase 6: GameOverScene — メダル判定
// ========================================================================

/// score=10 → bronze メダル
@Test
def testMedalBronze(): Unit \ Assert =
    Assert.assertEq(expected = Some("medal_bronze"), GameOverScene.getMedalTexture(10))

/// score=20 → silver メダル
@Test
def testMedalSilver(): Unit \ Assert =
    Assert.assertEq(expected = Some("medal_silver"), GameOverScene.getMedalTexture(20))

/// score=30 → gold メダル
@Test
def testMedalGold(): Unit \ Assert =
    Assert.assertEq(expected = Some("medal_gold"), GameOverScene.getMedalTexture(30))

/// score=50 → platinum メダル
@Test
def testMedalPlatinum(): Unit \ Assert =
    Assert.assertEq(expected = Some("medal_platinum"), GameOverScene.getMedalTexture(50))

/// score=15 → bronze メダル（10 以上 20 未満）
@Test
def testMedalBronze15(): Unit \ Assert =
    Assert.assertEq(expected = Some("medal_bronze"), GameOverScene.getMedalTexture(15))

/// score=5 → メダルなし（10 未満）
@Test
def testNoMedalBelowThreshold(): Unit \ Assert =
    Assert.assertEq(expected = (None: Option[String]), GameOverScene.getMedalTexture(5))

/// score=0 → メダルなし
@Test
def testNoMedalZero(): Unit \ Assert =
    Assert.assertEq(expected = (None: Option[String]), GameOverScene.getMedalTexture(0))

// ========================================================================
// Phase 6: GameOverScene — Play ボタン判定
// ========================================================================

/// ボタン中央をクリック → true
@Test
def testPlayButtonClickCenter(): Unit \ Assert =
    Assert.assertTrue(GameOverScene.isPlayButtonClicked({x = 144.0, y = 390.0}))

/// ボタン範囲内（右端ギリギリ）→ true
@Test
def testPlayButtonClickInBounds(): Unit \ Assert =
    Assert.assertTrue(GameOverScene.isPlayButtonClicked({x = 196.0, y = 419.0}))

/// ボタン範囲外（右に大きくずれ）→ false
@Test
def testPlayButtonClickOutOfBoundsRight(): Unit \ Assert =
    Assert.assertFalse(GameOverScene.isPlayButtonClicked({x = 250.0, y = 390.0}))

/// ボタン範囲外（下に大きくずれ）→ false
@Test
def testPlayButtonClickOutOfBoundsBelow(): Unit \ Assert =
    Assert.assertFalse(GameOverScene.isPlayButtonClicked({x = 144.0, y = 460.0}))

// ========================================================================
// Phase 6: GameOverScene — UI ノード構築
// ========================================================================

/// addGameOverUI で score < 10 の場合、6 ノード追加される（メダルなし）
///   gameover(layer) + gameover_label + score_panel + final_score + best_score + play_button = 6
@Test
def testGameOverUINodeCountNoMedal(): Unit \ Assert =
    let baseScene = testScene();
    let baseCount = Scene.nodeCount(baseScene);
    let scene = GameOverScene.addGameOverUI(5, 0, testFontAtlas(), baseScene);
    Assert.assertEq(expected = 6, Scene.nodeCount(scene) - baseCount)

/// addGameOverUI で score >= 10 の場合、7 ノード追加される（メダルあり）
///   gameover(layer) + gameover_label + score_panel + medal + final_score + best_score + play_button = 7
@Test
def testGameOverUINodeCountWithMedal(): Unit \ Assert =
    let baseScene = testScene();
    let baseCount = Scene.nodeCount(baseScene);
    let scene = GameOverScene.addGameOverUI(15, 15, testFontAtlas(), baseScene);
    Assert.assertEq(expected = 7, Scene.nodeCount(scene) - baseCount)

/// 今回のスコアが低くても bestScore >= 10 ならメダルが表示されること（メダル永続化）
///   score=3, bestScore=15 → bronze メダルが表示される → 7 ノード追加
@Test
def testGameOverUINodeCountMedalFromBestScore(): Unit \ Assert =
    let baseScene = testScene();
    let baseCount = Scene.nodeCount(baseScene);
    let scene = GameOverScene.addGameOverUI(3, 15, testFontAtlas(), baseScene);
    Assert.assertEq(expected = 7, Scene.nodeCount(scene) - baseCount)

/// addGameOverUI 後に HUD スコアラベルが非表示になること
@Test
def testGameOverHidesHudScore(): Unit \ Assert =
    let scene = GameOverScene.addGameOverUI(0, 0, testFontAtlas(), testScene());
    match Scene.getEngineNode(ScoreScene.scoreLabelPath(), scene) {
        case Some(EngineNode.Label2DWithState(label, _)) =>
            Assert.assertFalse(CanvasItem.isVisible(label))
        case _ => bug!("score_label not found")
    }

/// buildState のノード数は GameOver UI 追加前と同じ（29）
@Test
def testBuildStateNodeCountUnchanged(): Unit \ Assert =
    Assert.assertEq(expected = 29, Scene.nodeCount(testScene()))

// ========================================================================
// Phase 7: MenuScene — メニュー画面
// ========================================================================

/// テスト用ヘルパー: buildMenuState のシーンを取得
def testMenuScene(): Scene[NodeTag] =
    Game.buildMenuState(testFontAtlas(), 0)#scene

/// テスト用ヘルパー: buildMenuState の GameState を取得
def testMenuState(): GameState =
    Game.buildMenuState(testFontAtlas(), 0)

/// メニューの初期フェーズは Menu
@Test
def testMenuStatePhase(): Unit \ Assert =
    Assert.assertEq(expected = GamePhase.Menu, testMenuState()#phase)

/// メニュー画面の鳥の状態は Flying
@Test
def testMenuBirdStateFlying(): Unit \ Assert =
    let birdData = BirdScene.getBirdData(testMenuScene());
    Assert.assertEq(expected = BirdState.Flying, birdData#state)

/// メニュー画面の鳥の重力は 0
@Test
def testMenuBirdGravityZero(): Unit \ Assert =
    match Scene.getEngineNode("bird" :: Nil, testMenuScene()) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = 0.0, RigidBody2D.getGravityScale(body))
        case _ => bug!("bird not found")
    }

/// メニュー画面の鳥の速度は 0
@Test
def testMenuBirdVelocityZero(): Unit \ Assert =
    match Scene.getEngineNode("bird" :: Nil, testMenuScene()) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = (0.0, 0.0),
                vecToTuple(RigidBody2D.getLinearVelocity(body)))
        case _ => bug!("bird not found")
    }

/// メニュー画面にタイトルロゴが存在すること
@Test
def testMenuTitleLogoExists(): Unit \ Assert =
    match Scene.getEngineNode(MenuScene.titleLogoPath(), testMenuScene()) {
        case Some(EngineNode.Sprite2DWithState(_, _)) =>
            Assert.assertTrue(true)
        case _ => bug!("title_logo not found")
    }

/// メニュー画面に操作説明画像が存在すること
@Test
def testMenuInstructionsExists(): Unit \ Assert =
    match Scene.getEngineNode(MenuScene.instructionsPath(), testMenuScene()) {
        case Some(EngineNode.Sprite2DWithState(_, _)) =>
            Assert.assertTrue(true)
        case _ => bug!("instructions_img not found")
    }

/// メニュー画面のスコアラベルが非表示であること
@Test
def testMenuScoreLabelHidden(): Unit \ Assert =
    match Scene.getEngineNode(ScoreScene.scoreLabelPath(), testMenuScene()) {
        case Some(EngineNode.Label2DWithState(label, _)) =>
            Assert.assertFalse(CanvasItem.isVisible(label))
        case _ => bug!("score_label not found")
    }

/// メニュー画面にパイプがないこと
@Test
def testMenuNoPipes(): Unit \ Assert =
    let paths = Scene.getNodesInGroup(PipeScene.pipeGroup(), testMenuScene());
    Assert.assertEq(expected = 0, List.length(paths))

/// メニュー画面に地面があること
@Test
def testMenuHasGrounds(): Unit \ Assert =
    let paths = Scene.getNodesInGroup(GroundScene.groundGroup(), testMenuScene());
    Assert.assertEq(expected = 2, List.length(paths))

/// メニュー画面のノード数は 16
///   background(+bg_sprite) + bird(+sprite+area) + camera + hud(+score_label+best_score_label)
///   + ground_0(+sprite) + ground_1(+sprite) + menu(+title_logo+instructions_img) = 16
@Test
def testMenuNodeCount(): Unit \ Assert =
    Assert.assertEq(expected = 16, Scene.nodeCount(testMenuScene()))

/// メニュー画面では鳥は静止する（bird.gd 忠実化により bobbing は削除済み。
/// Godot ではアニメーションで実現される視覚効果だが Flix エンジンに該当機能なし）
@Test
def testMenuBirdStatic(): Unit \ Assert =
    let scene = testMenuScene();
    let posBefore = Scene.globalPosition("bird", scene);
    let sceneAfter = withMockRandom(() -> scene |> Scene.processAll(0.5, false));
    let posAfter = Scene.globalPosition("bird", sceneAfter);
    Assert.assertTrue(Float64.abs(posAfter#y - posBefore#y) < 0.001)
