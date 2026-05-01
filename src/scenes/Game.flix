// Game — Flappy Bird のノードタグ定義・trait instance・シーン構築・ゲームループ

// ========================================================================
// 鳥の状態マシン
// ========================================================================

/// 鳥の状態遷移: Flying → Flapping → Hit → Grounded
/// Flying:   メニュー画面（重力なし、ボビングアニメ）
/// Flapping: プレイ中（重力あり、フラップ操作可）
/// Hit:      パイプ衝突（移動停止、回転のみ）
/// Grounded: 地面着地（完全停止）
pub enum BirdState with Eq, ToString {
    case Flying
    case Flapping
    case Hit
    case Grounded
}

// ========================================================================
// ゲームフェーズ
// ========================================================================

/// ゲーム全体の進行状態
/// Menu:     メニュー画面
/// Playing:  プレイ中
/// GameOver: ゲームオーバー
pub enum GamePhase with Eq, ToString {
    case Menu
    case Playing
    case GameOver
}

// ========================================================================
// ノードタグ
// ========================================================================

/// 各ノードに付与する識別タグ（Scene[NodeTag] の型パラメータ）
pub enum NodeTag {
    /// 鳥の RigidBody2D に付与。BirdData を保持する
    case Bird(BirdScene.BirdData)
    /// 鳥の衝突検知用 Area2D に付与
    case BirdArea
    /// 地面の StaticBody2D に付与
    case Ground
    /// パイプの StaticBody2D に付与
    case Pipe
    /// タグ不要なノード（スプライト子ノード等）
    case NoTag
}

// ========================================================================
// ゲーム状態
// ========================================================================

/// ゲーム全体の状態レコード
/// scene: シーングラフ
/// phase: ゲームフェーズ
/// flapPressed: 前フレームでフラップ入力があったか（連続入力防止用）
/// groundCounter: 次の地面タイル番号（ユニーク名生成用）
/// nextGroundX: 次の地面タイル中心の X 座標
/// pipeCounter: 次のパイプペア番号（ユニーク名生成用）
/// nextPipeX: 次のパイプペア中心の X 座標
pub type alias GameState = {
    scene = Scene[NodeTag],
    phase = GamePhase,
    flapPressed = Bool,
    groundCounter = Int32,
    nextGroundX = Float64,
    pipeCounter = Int32,
    nextPipeX = Float64
}

// ========================================================================
// Node 実装（Phase 2: 特別な process なし）
// ========================================================================

instance Node[NodeTag] {
    redef process(_delta: Float64, node: EngineNode[NodeTag],
                  _path: NodePath, scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ Math.Random =
        checked_ecast((node, scene))
}

// ========================================================================
// AreaHandler 実装（Phase 2: 鳥と地面の衝突）
// ========================================================================

instance AreaHandler[NodeTag] {
    pub def onAreaEntered(_selfPath: NodePath, selfState: NodeTag,
                          _otherPath: NodePath, otherState: NodeTag,
                          scene: Scene[NodeTag]): Scene[NodeTag] =
        match (selfState, otherState) {
            case (NodeTag.BirdArea, NodeTag.Ground) =>
                Game.onBirdHitGround(scene)
            case (NodeTag.Ground, NodeTag.BirdArea) =>
                Game.onBirdHitGround(scene)
            case (NodeTag.BirdArea, NodeTag.Pipe) =>
                Game.onBirdHitPipe(scene)
            case (NodeTag.Pipe, NodeTag.BirdArea) =>
                Game.onBirdHitPipe(scene)
            case _ => scene
        }
}

// ========================================================================
// ScreenNotifyHandler 実装
// ========================================================================

instance ScreenNotifyHandler[NodeTag] {
    redef onScreenExited(_path: NodePath, _state: NodeTag,
                         scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
}

// ========================================================================
// TimerHandler 実装
// ========================================================================

instance TimerEvent.TimerHandler[NodeTag] {
    redef onTimeout(_timerPath: NodePath, _state: NodeTag,
                    scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        checked_ecast(scene)
}

// ========================================================================
// mod Game
// ========================================================================

mod Game {

    // ========================================================================
    // 画面定数
    // ========================================================================

    /// 画面幅（参考実装 144 の 2 倍）
    pub def screenWi(): Int32 = 288

    /// 画面高さ（参考実装 256 の 2 倍）
    pub def screenHi(): Int32 = 512

    // ========================================================================
    // カメラ定数
    // ========================================================================

    /// カメラノード名
    def cameraName(): String = "camera"

    /// カメラノードパス
    def cameraPath(): NodePath = cameraName() :: Nil

    /// カメラオフセット X（参考実装 -36 の 2 倍）
    def cameraOffsetX(): Float64 = -72.0

    // ========================================================================
    // 背景定数
    // ========================================================================

    /// 背景レイヤーノード名
    def backgroundName(): String = "background"

    /// 背景スプライト子ノード名
    def bgSpriteName(): String = "bg_sprite"

    // ========================================================================
    // 初期状態構築
    // ========================================================================

    /// ゲームの初期状態を構築する
    pub def buildState(_fontAtlas: FontAtlas): GameState \ Math.Random =
        let (sceneWithGrounds, groundCounter, nextGroundX) =
            Scene.empty()
                |> addBackground
                |> BirdScene.addBird
                |> addCamera
                |> GroundScene.addGrounds;
        let (sceneWithPipes, pipeCounter, nextPipeX) =
            PipeScene.addPipes(sceneWithGrounds);
        {   scene = sceneWithPipes,
            phase = GamePhase.Playing,
            flapPressed = false,
            groundCounter = groundCounter,
            nextGroundX = nextGroundX,
            pipeCounter = pipeCounter,
            nextPipeX = nextPipeX
        }

    // ========================================================================
    // シーン構築ヘルパー
    // ========================================================================

    /// カメラを追加する（FixedTopLeft、鳥の初期位置に配置）
    def addCamera(scene: Scene[NodeTag]): Scene[NodeTag] =
        let birdPos = Scene.globalPosition("bird", scene);
        let camera = Camera2D.makeWithOffset(
                {x = birdPos#x, y = 0.0},
                {x = cameraOffsetX(), y = 0.0})
            |> Camera2D.setAnchorMode(Camera2DAnchorMode.FixedTopLeft);
        scene |> Scene.addNode(cameraName(),
            EngineNode.Camera2DWithState(camera, NodeTag.NoTag))

    /// 背景を追加する（CanvasLayer layer=-1 + Sprite2D）
    def addBackground(scene: Scene[NodeTag]): Scene[NodeTag] =
        let layer = CanvasLayer.make(-1);
        let sprite = Sprite2D.make("background_day", {x = 144.0, y = 256.0}, {x = 2.0, y = 2.0});
        scene
            |> Scene.addNode(backgroundName(),
                EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag))
            |> Scene.addChild(backgroundName(), bgSpriteName(),
                EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))

    // ========================================================================
    // 衝突応答
    // ========================================================================

    /// 鳥が地面に衝突したときの処理
    /// 鳥を Grounded 状態にし、地面の上にクランプする
    pub def onBirdHitGround(scene: Scene[NodeTag]): Scene[NodeTag] =
        let birdData = BirdScene.getBirdData(scene);
        match birdData#state {
            case BirdState.Flapping =>
                scene
                    |> BirdScene.setBirdState(BirdState.Grounded)
                    |> clampBirdAboveGround
            case BirdState.Hit =>
                scene
                    |> BirdScene.setBirdState(BirdState.Grounded)
                    |> clampBirdAboveGround
            case _ => scene
        }

    /// 鳥がパイプに衝突したときの処理
    /// Flapping → Hit に遷移し、横移動を停止させる
    pub def onBirdHitPipe(scene: Scene[NodeTag]): Scene[NodeTag] =
        let birdData = BirdScene.getBirdData(scene);
        match birdData#state {
            case BirdState.Flapping =>
                scene |> BirdScene.setBirdState(BirdState.Hit)
            case _ => scene
        }

    /// 鳥の Y 座標を地面の上端にクランプする
    def clampBirdAboveGround(scene: Scene[NodeTag]): Scene[NodeTag] =
        let maxY = GroundScene.groundTopY() - 13.0;
        scene |> BirdScene.mapBirdBody((body, birdData) ->
            let pos = Node2D.getPosition(body);
            if (pos#y > maxY)
                (Node2D.setPosition({x = pos#x, y = maxY}, body), birdData)
            else
                (body, birdData))

    // ========================================================================
    // デルタタイム
    // ========================================================================

    /// デルタタイムの上限（秒）。初回フレームのウィンドウ初期化遅延を吸収する
    def maxDeltaTime(): Float64 = 0.05

    /// デルタタイムを上限でクランプする
    def clampDeltaTime(dt: Float64): Float64 = Float64.min(dt, maxDeltaTime())

    // ========================================================================
    // エンジン更新パイプライン
    // ========================================================================

    /// エンジン更新パイプライン（process → physics → collision → screen → timers）
    def engineUpdate(dt: Float64, scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Math.Random} =
        (GameEngine.process(dt, false)
        >> GameEngine.physicsProcess(dt, false, PhysicsStep.defaultGravity())
        >> GameEngine.emitCollision
        >> GameEngine.emitScreenNotify(screenWidth = screenWi(), screenHeight = screenHi())
        >> GameEngine.emitTimers)(scene)

    // ========================================================================
    // カメラ追従
    // ========================================================================

    /// カメラを鳥の X 座標に追従させる（Y は固定）
    def followCamera(scene: Scene[NodeTag]): Scene[NodeTag] =
        let birdPos = Scene.globalPosition("bird", scene);
        Scene.mapEngineNode(cameraPath(),
            EngineNode.mapCamera2D(cam ->
                Node2D.setPosition({x = birdPos#x, y = 0.0}, cam)),
            scene)

    /// ビューポートの左端 X 座標を取得する
    def getViewportLeftX(scene: Scene[NodeTag]): Float64 =
        let birdPos = Scene.globalPosition("bird", scene);
        birdPos#x + cameraOffsetX()

    // ========================================================================
    // 入力
    // ========================================================================

    /// フラップ入力（スペースキーまたはマウス左クリック）が押されているか
    def isFlapInputPressed(): Bool \ GameEngine.Game =
        GameEngine.Game.isKeyPressed(GameEngine.Key.Space) or
        GameEngine.Game.isMouseButtonPressed(GameEngine.MouseButton.Left)

    // ========================================================================
    // メインループ
    // ========================================================================

    /// ゲームのエントリポイント
    pub def start(fontAtlas: FontAtlas): Unit \ {GameEngine.Game, GameEngine.Audio, Math.Random} =
        gameLoop(fontAtlas, buildState(fontAtlas))

    /// メインループ: フェーズごとに処理を切り替え、末尾再帰する
    def gameLoop(fontAtlas: FontAtlas, state: GameState): Unit \ {GameEngine.Game, GameEngine.Audio, Math.Random} =
        if (GameEngine.Game.shouldClose()) ()
        else if (GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            let dt = clampDeltaTime(GameEngine.Game.getDeltaTime());
            let nextState: GameState = match state#phase {
                case GamePhase.Playing =>
                    let inputPressed = isFlapInputPressed();
                    let justPressed = inputPressed and not state#flapPressed;
                    // フラップ入力があれば速度・角速度をセット
                    let sceneAfterFlap =
                        if (justPressed) BirdScene.flap(state#scene)
                        else state#scene;
                    // エンジン更新（process → physics → collision → ...）
                    let updatedScene = engineUpdate(dt, sceneAfterFlap);
                    // 物理積分後に回転をクランプ
                    let sceneAfterClamp = BirdScene.clampRotation(updatedScene);
                    // カメラを鳥に追従させる
                    let sceneWithCamera = followCamera(sceneAfterClamp);
                    // 地面をリサイクルする
                    let viewportLeftX = getViewportLeftX(sceneWithCamera);
                    let (groundRecycledScene, newCounter, newNextX) =
                        GroundScene.recycleGrounds(
                            viewportLeftX,
                            state#groundCounter, state#nextGroundX,
                            sceneWithCamera);
                    // パイプをリサイクルする
                    let (recycledScene, newPipeCounter, newNextPipeX) =
                        PipeScene.recyclePipes(
                            viewportLeftX,
                            state#pipeCounter, state#nextPipeX,
                            groundRecycledScene);
                    // 鳥が Grounded になったらゲームオーバー
                    let birdState = BirdScene.getBirdData(recycledScene)#state;
                    let nextPhase =
                        if (birdState == BirdState.Grounded) GamePhase.GameOver
                        else GamePhase.Playing;
                    {scene = recycledScene, phase = nextPhase,
                     flapPressed = inputPressed,
                     groundCounter = newCounter, nextGroundX = newNextX,
                     pipeCounter = newPipeCounter, nextPipeX = newNextPipeX}
                case GamePhase.Menu =>
                    state
                case GamePhase.GameOver =>
                    state
            };
            GameEngine.render(nextState#scene);
            gameLoop(fontAtlas, nextState)
        }
}
