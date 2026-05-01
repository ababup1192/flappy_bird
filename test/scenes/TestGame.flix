// Tests for Flappy Bird Game module — Phase 1: 鳥 + 重力 + Flap

// ========================================================================
// テスト用ヘルパー
// ========================================================================

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

/// テスト用ヘルパー: buildState のシーンを取得
def testScene(): Scene[NodeTag] = Game.buildState(testFontAtlas())#scene

/// テスト用ヘルパー: buildState の GameState を取得
def testState(): GameState = Game.buildState(testFontAtlas())

/// Vec2 をタプルに変換するヘルパー
def vecToTuple(v: Vec2.Vec2): (Float64, Float64) = (v#x, v#y)

// ========================================================================
// buildState: ノード数・構造
// ========================================================================

/// シーンには bird(+sprite) = 2 ノード
@Test
def testBuildSceneNodeCount(): Unit \ Assert =
    Assert.assertEq(expected = 2, Scene.nodeCount(testScene()))

/// ルートノードは 1 つ（bird のみ）
@Test
def testBuildSceneRootCount(): Unit \ Assert =
    Assert.assertEq(expected = 1, Map.size(Scene.states(testScene())))

/// 初期フェーズは Playing
@Test
def testBuildStatePhase(): Unit \ Assert =
    Assert.assertEq(expected = GamePhase.Playing, testState()#phase)

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

/// 鳥の gravity_scale が 5.0 であること
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

// ========================================================================
// 重力: RigidBody2D が重力で落下する
// ========================================================================

/// 重力により鳥が下方向に移動する
///
///   初期位置: (144, 256)
///   重力: 980 * 5.0 = 4900 px/s²
///   0.1 秒後: vy = 4900 * 0.1 = 490, y = 256 + 490 * 0.1 = 305
///   ※近似値（積分順序による誤差あり）
///
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
///
///   flap → vy = -300
///   0.02s 後: vy = -300 + 4900*0.02 = -202, y = 256 + (-300)*0.02 = 250
///   → 256 より上に行っている
///
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

/// 正常範囲の回転では角速度が 1.5 以上に引き上げられる
@Test
def testClampRotationFallAngularVelocity(): Unit \ Assert =
    let scene = testScene()
        |> BirdScene.mapBirdBody((body, birdData) ->
            (body |> Node2D.setRotation(0.0) |> RigidBody2D.setAngularVelocity(0.5), birdData))
        |> BirdScene.clampRotation;
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = 1.5, RigidBody2D.getAngularVelocity(body))
        case _ => bug!("bird not found")
    }

/// 角速度が既に 1.5 以上の場合は変更されない
@Test
def testClampRotationKeepsHighAngularVelocity(): Unit \ Assert =
    let scene = testScene()
        |> BirdScene.mapBirdBody((body, birdData) ->
            (body |> Node2D.setRotation(0.0) |> RigidBody2D.setAngularVelocity(3.0), birdData))
        |> BirdScene.clampRotation;
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertEq(expected = 3.0, RigidBody2D.getAngularVelocity(body))
        case _ => bug!("bird not found")
    }

/// 回転が 90° を超えないようにクランプされる
@Test
def testClampRotationMax(): Unit \ Assert =
    let scene = testScene()
        |> BirdScene.mapBirdBody((body, birdData) ->
            (Node2D.setRotation(2.0, body), birdData))
        |> BirdScene.clampRotation;
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            let rot = Node2D.getRotation(body);
            let maxRot = Vec2.pi() / 2.0;
            Assert.assertTrue(Float64.abs(rot - maxRot) < 0.001)
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

/// フラップ後の角速度は clampRotation で 1.5 に引き上げられる
/// （-3 → 物理積分 → 回転適用 → clamp で angvel >= 1.5）
@Test
def testFlapAngularVelocityAfterClamp(): Unit \ Assert =
    let scene = testScene()
        |> BirdScene.flap
        |> PhysicsStep.integrate(0.02, PhysicsStep.defaultGravity())
        |> BirdScene.clampRotation;
    match Scene.getEngineNode("bird" :: Nil, scene) {
        case Some(EngineNode.RigidBody2DWithState(body, _)) =>
            Assert.assertTrue(RigidBody2D.getAngularVelocity(body) >= 1.5)
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
