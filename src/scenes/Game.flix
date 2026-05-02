// Game — Flappy Bird のノードタグ定義・trait instance・シーン構築・ゲームループ

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

/// ステージ遷移要求イベント（godot stage_manager.change_stage 相当）
/// ButtonHandler / BirdStateChanged から発火し、gameLoop が次フレームで処理する
pub eff StageRequested {
    def emit(target: GamePhase): Unit
}

// ========================================================================
// ノードタグ
// ========================================================================

/// スコア値の型エイリアス
pub type alias Score = Int32

/// ベストスコア値の型エイリアス
pub type alias BestScore = Int32

/// ゲームオーバーアニメーションの経過時間
pub type alias GameOverAnimData = {elapsed = Float64}

/// 各ノードに付与する識別タグ（Scene[NodeTag] の型パラメータ）
pub enum NodeTag {
    /// 鳥の RigidBody2D に付与。BirdData を保持する
    case Bird(BirdScene.BirdData)
    /// 鳥の衝突検知用 Area2D に付与
    case BirdArea
    /// 地面の StaticBody2D に付与
    case Ground
    /// パイプペアの親ノード（Marker2D）に付与。process で画面外自殺判定を行う
    case Pipe
    /// パイプペアの子（Top/Bottom の StaticBody2D）に付与。AreaHandler で衝突判定に使う
    case PipePart
    /// パイプ間の採点用 Area2D に付与
    case Coin
    /// スコアラベルに付与。現在のスコア値を保持する
    case ScoreLabel(Score)
    /// ベストスコアラベルに付与。セッション中のベストスコアを保持する
    case BestScoreLabel(BestScore)
    /// カメラの追従対象とシェイク状態を保持する
    case Camera(CameraScene.CameraData)
    /// ゲームオーバーアニメーション状態を保持する
    case GameOverAnim(GameOverAnimData)
    /// タグ不要なノード（スプライト子ノード、ボタン等）
    /// ボタンの識別は ButtonHandler 側で path 比較によって行う
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
    // Bird: bird.gd `FlappingState._init → flap()` 相当の初期 flap を発火
    redef ready(node: EngineNode[NodeTag], path: NodePath,
                scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ Math.Random =
        match node {
            case EngineNode.RigidBody2DWithState(_, NodeTag.Bird(_)) =>
                checked_ecast(BirdScene.ready(node, path, scene))
            case _ => (node, scene)
        }

    // 各シーンへ委譲するだけのディスパッチ
    // Bird は bird.gd に倣い _process を使わない（physicsProcess のみ）
    redef process(delta: Float64, node: EngineNode[NodeTag],
                  path: NodePath, scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ Math.Random =
        match node {
            case EngineNode.Camera2DWithState(_, NodeTag.Camera(_)) =>
                CameraScene.process(delta, node, scene)
            case EngineNode.CanvasLayerWithState(_, NodeTag.GameOverAnim(_)) =>
                GameOverScene.process(delta, node, scene)
            case EngineNode.StaticBody2DWithState(_, NodeTag.Ground) =>
                GroundScene.process(node, path, scene)
            case EngineNode.Marker2DWithState(_, NodeTag.Pipe) =>
                PipeScene.process(node, path, scene)
            case _ => (node, scene)
        }

    // Bird: 回転 -30° クランプ + 落下時 angVel = 1.5（bird.gd FlappingState.update 準拠）
    redef physicsProcess(delta: Float64, node: EngineNode[NodeTag],
                         path: NodePath, scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ Math.Random =
        match node {
            case EngineNode.RigidBody2DWithState(_, NodeTag.Bird(_)) =>
                checked_ecast(BirdScene.physicsProcess(delta, node, path, scene))
            case _ => (node, scene)
        }
}

// ========================================================================
// InputHandler 実装（bird.gd _input 相当を BirdScene にディスパッチ）
// Menu / GameOver(アニメ完了後) のスペースキー押下は Play ボタンと等価扱い
// ========================================================================

instance InputEvent.InputHandler[NodeTag] {
    type Aef = { GameEngine.Audio, StageRequested }
    redef onKeyPressed(key: GameEngine.Key,
                       scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, StageRequested} =
        if (key == GameEngine.Key.Space and Game.canStart(scene)) {
            StageRequested.emit(GamePhase.Playing); scene
        } else
            BirdScene.input(BirdInputEvent.KeyPressed(key), scene)

    redef onMouseButtonPressed(button: GameEngine.MouseButton,
                               _position: Vec2.Vec2,
                               scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, StageRequested} =
        checked_ecast(BirdScene.input(BirdInputEvent.MouseButtonPressed(button), scene))
}

// ========================================================================
// ButtonHandler 実装（Godot TextureButton.pressed シグナル相当）
// godot btn_play.gd と同じく、押下時に直接 stage_manager.change_stage(...) 相当の
// StageRequested.emit(...) を発火する
// ========================================================================

instance ButtonEvent.ButtonHandler[NodeTag] {
    type Aef = { StageRequested }
    redef onButtonPressed(buttonPath: NodePath, _state: NodeTag,
                          scene: Scene[NodeTag]): Scene[NodeTag] \ StageRequested =
        let isPlayPath = buttonPath == MenuScene.playButtonPath()
                         or buttonPath == GameOverScene.playButtonPath();
        if (isPlayPath and Game.canStart(scene)) {
            StageRequested.emit(GamePhase.Playing); scene
        } else scene
}

// ========================================================================
// AreaHandler 実装（Area2D の重なり通知）
// 鳥 ↔ 地面 / パイプ / コイン の交差を各シーンの応答処理にディスパッチする
// ========================================================================

instance AreaHandler[NodeTag] {
    type Aef = { GameEngine.Audio, BirdStateChanged }
    pub def onAreaEntered(selfPath: NodePath, selfState: NodeTag,
                          otherPath: NodePath, otherState: NodeTag,
                          scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, BirdStateChanged} =
        match (selfState, otherState) {
            case (NodeTag.BirdArea, NodeTag.Ground) =>
                BirdScene.onBirdHitGround(scene)
            case (NodeTag.Ground, NodeTag.BirdArea) =>
                BirdScene.onBirdHitGround(scene)
            case (NodeTag.BirdArea, NodeTag.PipePart) =>
                BirdScene.onBirdHitPipe(pipePath = otherPath, scene)
            case (NodeTag.PipePart, NodeTag.BirdArea) =>
                BirdScene.onBirdHitPipe(pipePath = selfPath, scene)
            case (NodeTag.BirdArea, NodeTag.Coin) =>
                ScoreScene.onBirdPassedCoin(coinPath = otherPath, scene)
            case (NodeTag.Coin, NodeTag.BirdArea) =>
                ScoreScene.onBirdPassedCoin(coinPath = selfPath, scene)
            case _ => checked_ecast(scene)
        }
}

// ========================================================================
// NodeRemovedHandler 実装（godot tree_exited シグナル相当）
// 自殺した Ground / Pipe ペアの Coin を受けて、新しい個体を spawn する
// ========================================================================

instance NodeRemovedHandler[NodeTag] {
    type Aef = { Math.Random }
    redef onNodeRemoved(_path: NodePath, state: NodeTag,
                        scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        match state {
            case NodeTag.Ground =>
                checked_ecast(GroundScene.spawnRecycledGround(scene))
            case NodeTag.Pipe =>
                let score = ScoreScene.getScore(scene);
                PipeScene.spawnRecycledPair(score, scene)
            case _ => checked_ecast(scene)
        }
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
    // 背景定数
    // ========================================================================

    /// 背景レイヤーノード名
    def backgroundName(): String = "background"

    /// 背景スプライト子ノード名
    def bgSpriteName(): String = "bg_sprite"

    // ========================================================================
    // 開始入力受付判定
    // ========================================================================

    /// ゲーム開始入力を受け付けるか判定する
    /// GameOver layer 存在: アニメ完了後 / 不在: パイプが無いとき (= Menu)
    pub def canStart(scene: Scene[NodeTag]): Bool =
        match Scene.getEngineNode(GameOverScene.layerPath(), scene) {
            case Some(_) => GameOverScene.isAnimationFinished(scene)
            case None    => Scene.getNodesInGroup(PipeScene.pipeGroup(), scene) |> List.isEmpty
        }

    // ========================================================================
    // 初期状態構築
    // ========================================================================

    /// ゲームの初期状態を構築する
    /// bestScore: セッション中のベストスコア（初回は 0）
    pub def buildState(fontAtlas: FontAtlas, bestScore: BestScore): GameState \ Math.Random =
        let scene = Scene.empty()
            |> addBackground
            |> BirdScene.addBird
            |> CameraScene.addCamera(BirdScene.name())
            |> ScoreScene.addHud(fontAtlas, bestScore)
            |> GroundScene.addGrounds
            |> PipeScene.addPipes;
        {scene = scene, phase = GamePhase.Playing}

    /// メニュー画面の初期状態を構築する
    /// 背景 + 鳥(Flying) + カメラ + HUD(スコア非表示) + 地面 + メニュー UI
    pub def buildMenuState(fontAtlas: FontAtlas, bestScore: BestScore): GameState =
        let scene = Scene.empty()
            |> addBackground
            |> BirdScene.addBirdForMenu
            |> CameraScene.addCamera(BirdScene.name())
            |> ScoreScene.addHud(fontAtlas, bestScore)
            |> GroundScene.addGrounds
            |> MenuScene.addMenuUI
            |> ScoreScene.hideScoreLabel;
        {scene = scene, phase = GamePhase.Menu}

    // ========================================================================
    // シーン構築ヘルパー
    // ========================================================================

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
    // エンジン更新パイプライン
    // ========================================================================

    /// エンジン更新パイプライン（input → buttons → process → physics → collision）
    def engineUpdate(dt: Float64, scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, GameEngine.Game, Math.Random, BirdStateChanged, StageRequested} =
        (GameEngine.emitInput
        >> GameEngine.emitButtons
        >> GameEngine.process(dt, false)
        >> GameEngine.physicsProcess(dt, false, PhysicsStep.defaultGravity())
        >> GameEngine.emitCollision)(scene)

    /// ビューポートの左端 X 座標を取得する
    pub def getViewportLeftX(scene: Scene[NodeTag]): Float64 =
        let birdPos = Scene.globalPosition(BirdScene.name(), scene);
        birdPos#x + CameraScene.offsetX()

    // ========================================================================
    // メインループ
    // ========================================================================

    /// ゲームのエントリポイント
    /// godot の bird.state_changed + stage_manager.change_stage シグナルに対応:
    ///   - BirdStateChanged: Hit/Grounded でカメラシェイク、Grounded で GameOver 遷移発火
    ///   - StageRequested:   ButtonHandler / BirdStateChanged からの遷移要求を Ref に蓄積
    pub def start(fontAtlas: FontAtlas): Unit \ {GameEngine.Game, GameEngine.Audio, Math.Random, IO} =
        region rc {
            let pending: Ref[Option[GamePhase], rc] = Ref.fresh(rc, None);
            run {
                gameLoop(fontAtlas, buildMenuState(fontAtlas, 0), pending)
            } with handler BirdStateChanged {
                def emit(newState, scene, k) = {
                    let nextScene = match newState {
                        case BirdState.Hit =>
                            CameraScene.triggerShake(CameraScene.shakeIntensity(),
                                                     CameraScene.shakeDuration(), scene)
                        case BirdState.Grounded =>
                            StageRequested.emit(GamePhase.GameOver);
                            scene
                                |> CameraScene.triggerShake(CameraScene.shakeIntensity(),
                                                            CameraScene.shakeDuration())
                                |> GameOverScene.enterGameOver(fontAtlas)
                        case _ => scene
                    };
                    k(nextScene)
                }
            } with handler StageRequested {
                def emit(target, k) = {
                    Ref.put(Some(target), pending);
                    k()
                }
            }
        }

    /// 蓄積された遷移要求を読み出し、次の GameState を返す
    /// Playing: シーンを作り直す。GameOver: phase だけ切替（scene は BirdStateChanged が組み済み）。
    def applyPendingPhase(fontAtlas: FontAtlas,
                          state: GameState,
                          scene: Scene[NodeTag],
                          pending: Ref[Option[GamePhase], r]):
                          GameState \ {GameEngine.Audio, Math.Random, r} =
        let req = Ref.get(pending);
        Ref.put(None, pending);
        match req {
            case Some(GamePhase.Playing) =>
                GameEngine.Audio.playAudio("sfx_swooshing");
                buildState(fontAtlas, ScoreScene.getBestScore(scene))
            case Some(GamePhase.GameOver) =>
                {scene = scene, phase = GamePhase.GameOver}
            case _ =>
                {scene = scene, phase = state#phase}
        }

    /// メインループ: shouldClose 判定 → engineUpdate → applyPendingPhase → render
    /// フェーズ判定はすべて handler 側に移譲。gameLoop は scene を回すだけ。
    def gameLoop(fontAtlas: FontAtlas, state: GameState, pending: Ref[Option[GamePhase], r]):
                 Unit \ {GameEngine.Game, GameEngine.Audio, Math.Random, BirdStateChanged, StageRequested, r} =
        if (GameEngine.Game.shouldClose() or
            GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            let dt = GameEngine.Game.getDeltaTime();
            let updatedScene = state#scene |> engineUpdate(dt);
            let nextState = applyPendingPhase(fontAtlas, state, updatedScene, pending);
            GameEngine.render(nextState#scene);
            gameLoop(fontAtlas, nextState, pending)
        }
}
