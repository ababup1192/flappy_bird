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
// レベル管理データ
// ========================================================================

/// リサイクル用カウンタ（LevelManager ノードが保持する）
/// groundCounter: 次の地面タイル番号（ユニーク名生成用）
/// nextGroundX: 次の地面タイル中心の X 座標
/// pipeCounter: 次のパイプペア番号（ユニーク名生成用）
/// nextPipeX: 次のパイプペア中心の X 座標
pub type alias LevelManagerData = {
    groundCounter = Int32,
    nextGroundX = Float64,
    pipeCounter = Int32,
    nextPipeX = Float64
}

// ========================================================================
// ノードタグ
// ========================================================================

/// スコア値の型エイリアス
pub type alias Score = Int32

/// ベストスコア値の型エイリアス
pub type alias BestScore = Int32

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
    /// パイプ間の採点用 Area2D に付与
    case Coin
    /// スコアラベルに付与。現在のスコア値を保持する
    case ScoreLabel(Score)
    /// ベストスコアラベルに付与。セッション中のベストスコアを保持する
    case BestScoreLabel(BestScore)
    /// レベル管理ノード（リサイクルカウンタを保持）
    case LevelManager(LevelManagerData)
    /// タグ不要なノード（スプライト子ノード等）
    case NoTag
}

// ========================================================================
// ゲーム状態
// ========================================================================

/// ゲーム全体の状態レコード
/// scene: シーングラフ（ゲームの全状態は NodeTag バリアントに集約）
/// phase: ゲームフェーズ
pub type alias GameState = {
    scene = Scene[NodeTag],
    phase = GamePhase
}

// ========================================================================
// Node 実装
// ========================================================================

instance Node[NodeTag] {
    type Aef = { Math.Random }
    // Bird: 回転角クランプ / Camera2D: 追従 / LevelManager: リサイクル
    redef process(_delta: Float64, node: EngineNode[NodeTag],
                  _path: NodePath, scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ Math.Random =
        match node {
            case EngineNode.RigidBody2DWithState(body, NodeTag.Bird(birdData)) =>
                let (newBody, newData) = BirdScene.birdProcess(body, birdData);
                checked_ecast((EngineNode.RigidBody2DWithState(newBody, NodeTag.Bird(newData)), scene))
            case EngineNode.Camera2DWithState(cam, state) =>
                let birdPos = Scene.globalPosition("bird", scene);
                checked_ecast((EngineNode.Camera2DWithState(
                    Node2D.setPosition({x = birdPos#x, y = 0.0}, cam), state), scene))
            case EngineNode.Sprite2DWithState(sprite, NodeTag.LevelManager(levelData)) =>
                let (newData, newScene) = Game.levelManagerProcess(levelData, scene);
                (EngineNode.Sprite2DWithState(sprite, NodeTag.LevelManager(newData)), newScene)
            case _ => checked_ecast((node, scene))
        }

    // Bird: フラップリクエストの適用と落下時の角速度制御
    redef physicsProcess(_delta: Float64, node: EngineNode[NodeTag],
                         _path: NodePath, scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ Math.Random =
        match node {
            case EngineNode.RigidBody2DWithState(body, NodeTag.Bird(birdData)) =>
                let (newBody, newData) = BirdScene.birdPhysicsProcess(body, birdData);
                checked_ecast((EngineNode.RigidBody2DWithState(newBody, NodeTag.Bird(newData)), scene))
            case _ => checked_ecast((node, scene))
        }
}

// ========================================================================
// AreaHandler 実装（Phase 2: 鳥と地面の衝突）
// ========================================================================

instance AreaHandler[NodeTag] {
    type Aef = { GameEngine.Audio }
    pub def onAreaEntered(selfPath: NodePath, selfState: NodeTag,
                          otherPath: NodePath, otherState: NodeTag,
                          scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Audio =
        match (selfState, otherState) {
            case (NodeTag.BirdArea, NodeTag.Ground) =>
                checked_ecast(Game.onBirdHitGround(scene))
            case (NodeTag.Ground, NodeTag.BirdArea) =>
                checked_ecast(Game.onBirdHitGround(scene))
            case (NodeTag.BirdArea, NodeTag.Pipe) =>
                checked_ecast(Game.onBirdHitPipe(pipePath = otherPath, scene))
            case (NodeTag.Pipe, NodeTag.BirdArea) =>
                checked_ecast(Game.onBirdHitPipe(pipePath = selfPath, scene))
            case (NodeTag.BirdArea, NodeTag.Coin) =>
                Game.onBirdPassedCoin(coinPath = otherPath, scene)
            case (NodeTag.Coin, NodeTag.BirdArea) =>
                Game.onBirdPassedCoin(coinPath = selfPath, scene)
            case _ => checked_ecast(scene)
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
    // レベル管理ノード
    // ========================================================================

    /// レベル管理ノード名
    def levelManagerName(): String = "level_manager"

    /// Scene から LevelManagerData を取り出す
    pub def getLevelManagerData(scene: Scene[NodeTag]): LevelManagerData =
        match Scene.getState(levelManagerName() :: Nil, scene) {
            case Some(NodeTag.LevelManager(data)) => data
            case _ => bug!("level_manager not found")
        }

    // ========================================================================
    // 初期状態構築
    // ========================================================================

    /// ゲームの初期状態を構築する
    /// bestScore: セッション中のベストスコア（初回は 0）
    pub def buildState(fontAtlas: FontAtlas, bestScore: BestScore): GameState \ Math.Random =
        let (sceneWithGrounds, groundCounter, nextGroundX) =
            Scene.empty()
                |> addBackground
                |> BirdScene.addBird
                |> addCamera
                |> ScoreScene.addHud(fontAtlas, bestScore)
                |> GroundScene.addGrounds;
        let (sceneWithPipes, pipeCounter, nextPipeX) =
            PipeScene.addPipes(sceneWithGrounds);
        let levelData: LevelManagerData = {
            groundCounter = groundCounter, nextGroundX = nextGroundX,
            pipeCounter = pipeCounter, nextPipeX = nextPipeX
        };
        let manager = Sprite2D.make("", Vec2.zero(), {x = 1.0, y = 1.0});
        let scene = sceneWithPipes
            |> Scene.addNode(levelManagerName(),
                EngineNode.Sprite2DWithState(manager, NodeTag.LevelManager(levelData)));
        {scene = scene, phase = GamePhase.Playing}

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
    /// Flapping → Hit に遷移し、鳥をパイプの左端まで押し戻す
    pub def onBirdHitPipe(pipePath: {pipePath = NodePath}, scene: Scene[NodeTag]): Scene[NodeTag] =
        let birdData = BirdScene.getBirdData(scene);
        match birdData#state {
            case BirdState.Flapping =>
                let pipeX = Scene.globalPositionAt(pipePath#pipePath, scene)#x;
                scene
                    |> BirdScene.setBirdState(BirdState.Hit)
                    |> pushBirdOutOfPipe(pipeX)
            case _ => scene
        }

    /// 鳥がコインを通過したときの処理
    /// スコアを +1 し、効果音を鳴らし、コインの NodeTag を NoTag に変更して再採点を防止する
    pub def onBirdPassedCoin(coinPath: {coinPath = NodePath}, scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Audio =
        GameEngine.Audio.playAudio("sfx_point");
        scene
            |> ScoreScene.incrementScore
            |> Scene.setState(coinPath#coinPath, NodeTag.NoTag)

    /// 鳥をパイプの左端に押し戻す
    def pushBirdOutOfPipe(pipeX: Float64, scene: Scene[NodeTag]): Scene[NodeTag] =
        let birdRadius = 13.0;
        let pipeHalfW = PipeScene.pipeHalfWidth();
        scene |> BirdScene.mapBirdBody((body, birdData) ->
            let pos = Node2D.getPosition(body);
            (Node2D.setPosition({x = pipeX - pipeHalfW - birdRadius, y = pos#y}, body),
             birdData))

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
    def engineUpdate(dt: Float64, scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, Math.Random} =
        (GameEngine.process(dt, false)
        >> GameEngine.physicsProcess(dt, false, PhysicsStep.defaultGravity())
        >> GameEngine.emitCollision
        >> GameEngine.emitScreenNotify(screenWidth = screenWi(), screenHeight = screenHi())
        >> GameEngine.emitTimers)(scene)

    /// ビューポートの左端 X 座標を取得する
    pub def getViewportLeftX(scene: Scene[NodeTag]): Float64 =
        let birdPos = Scene.globalPosition("bird", scene);
        birdPos#x + cameraOffsetX()

    // ========================================================================
    // LevelManager process（リサイクル + スコア表示）
    // ========================================================================

    /// LevelManager の process コールバック
    /// 地面・パイプのリサイクルを行う
    pub def levelManagerProcess(levelData: LevelManagerData,
                                scene: Scene[NodeTag]): (LevelManagerData, Scene[NodeTag]) \ Math.Random =
        let viewportLeftX = getViewportLeftX(scene);
        let (groundScene, newGC, newGX) = GroundScene.recycleGrounds(
            viewportLeftX, levelData#groundCounter, levelData#nextGroundX, scene);
        let score = ScoreScene.getScore(groundScene);
        let (pipeScene, newPC, newPX) = PipeScene.recyclePipes(
            viewportLeftX, levelData#pipeCounter, levelData#nextPipeX, score, groundScene);
        ({groundCounter = newGC, nextGroundX = newGX,
          pipeCounter = newPC, nextPipeX = newPX},
         pipeScene)

    // ========================================================================
    // 入力
    // ========================================================================

    /// フラップ入力（スペースキーまたはマウス左クリック）が押されているか
    def isFlapInputPressed(): Bool \ GameEngine.Game =
        GameEngine.Game.isKeyPressed(GameEngine.Key.Space) or
        GameEngine.Game.isMouseButtonPressed(GameEngine.MouseButton.Left)

    /// 入力を読み取り、鳥の BirdData にフラグをセットする
    def handleInput(scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        let birdData = BirdScene.getBirdData(scene);
        let inputPressed = isFlapInputPressed();
        let justPressed = inputPressed and not birdData#flapPressed;
        let afterFlap = if (justPressed) BirdScene.requestFlap(scene) else scene;
        BirdScene.setFlapPressed(inputPressed, afterFlap)

    // ========================================================================
    // メインループ
    // ========================================================================

    /// ゲームのエントリポイント
    pub def start(fontAtlas: FontAtlas): Unit \ {GameEngine.Game, GameEngine.Audio, Math.Random} =
        gameLoop(fontAtlas, buildState(fontAtlas, 0))

    /// メインループ: 入力 → エンジン更新 → フェーズ遷移
    def gameLoop(fontAtlas: FontAtlas, state: GameState): Unit \ {GameEngine.Game, GameEngine.Audio, Math.Random} =
        if (GameEngine.Game.shouldClose()) ()
        else if (GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            let dt = clampDeltaTime(GameEngine.Game.getDeltaTime());
            let nextState: GameState = match state#phase {
                case GamePhase.Playing =>
                    let updatedScene = state#scene
                        |> handleInput
                        |> engineUpdate(dt);
                    let birdData = BirdScene.getBirdData(updatedScene);
                    if (birdData#state == BirdState.Grounded) {
                        let (score, newBest, sceneWithBest) = ScoreScene.finalizeScore(updatedScene);
                        let sceneWithGameOver = GameOverScene.addGameOverUI(
                            score, newBest, fontAtlas, sceneWithBest);
                        {scene = sceneWithGameOver, phase = GamePhase.GameOver}
                    } else
                        {scene = updatedScene, phase = GamePhase.Playing}
                case GamePhase.Menu =>
                    state
                case GamePhase.GameOver =>
                    let birdData = BirdScene.getBirdData(state#scene);
                    let inputPressed = isFlapInputPressed();
                    let justPressed = inputPressed and not birdData#flapPressed;
                    if (justPressed and GameOverScene.isPlayButtonClicked(
                            GameEngine.Game.getMousePosition())) {
                        let bestScore = ScoreScene.getBestScore(state#scene);
                        buildState(fontAtlas, bestScore)
                    } else {
                        let newScene = BirdScene.setFlapPressed(inputPressed, state#scene);
                        {scene = newScene, phase = GamePhase.GameOver}
                    }
            };
            GameEngine.render(nextState#scene);
            gameLoop(fontAtlas, nextState)
        }
}
