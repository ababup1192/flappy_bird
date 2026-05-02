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
    /// カメラシェイク状態を保持する
    case CameraShake(CameraScene.ShakeData)
    /// ゲームオーバーアニメーション状態を保持する
    case GameOverAnim(GameOverAnimData)
    /// Play ボタンノードに付与。ButtonHandler が path で識別して StageRequested を発火する
    case PlayButton
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
    // Bird: bird.gd `FlappingState._init → flap()` 相当の初期 flap を発火
    redef ready(node: EngineNode[NodeTag], path: NodePath,
                scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ Math.Random =
        match node {
            case EngineNode.RigidBody2DWithState(_, NodeTag.Bird(_)) =>
                checked_ecast(BirdScene.ready(node, path, scene))
            case _ => (node, scene)
        }

    // Camera2D: CameraScene に委譲 / Ground & Coin: 画面外で自殺 / GameOverAnim: 自走
    // Bird は bird.gd に倣い _process を使わない（physicsProcess のみ）
    redef process(delta: Float64, node: EngineNode[NodeTag],
                  path: NodePath, scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ Math.Random =
        match node {
            case EngineNode.Camera2DWithState(_, NodeTag.CameraShake(_)) =>
                CameraScene.process(delta, node, scene)
            case EngineNode.CanvasLayerWithState(layer, NodeTag.GameOverAnim(_)) =>
                let newScene = GameOverScene.updateAnimation(delta, scene);
                let newState = match Scene.getState(GameOverScene.layerPath(), newScene) {
                    case Some(tag) => tag
                    case _         => NodeTag.GameOverAnim({elapsed = 0.0})
                };
                checked_ecast((EngineNode.CanvasLayerWithState(layer, newState), newScene))
            case EngineNode.StaticBody2DWithState(_, NodeTag.Ground) =>
                let pos = Scene.globalPositionAt(path, scene);
                let halfWidth = GroundScene.groundWidth() / 2.0;
                if (pos#x + halfWidth < Game.getViewportLeftX(scene))
                    checked_ecast((node, Scene.removeAtAndNotify(path, scene)))
                else
                    (node, scene)
            case EngineNode.Marker2DWithState(_, NodeTag.Pipe) =>
                // 親ノード自身を removeAt するとサブツリー全削除（top/bottom/coin も同時に消える）
                let pos = Scene.globalPositionAt(path, scene);
                if (pos#x + PipeScene.pipeHalfWidth() < Game.getViewportLeftX(scene))
                    checked_ecast((node, Scene.removeAtAndNotify(path, scene)))
                else
                    (node, scene)
            case _ => checked_ecast((node, scene))
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
// AreaHandler 実装（Phase 2: 鳥と地面の衝突）
// ========================================================================

instance AreaHandler[NodeTag] {
    type Aef = { GameEngine.Audio, BirdStateChanged }
    pub def onAreaEntered(selfPath: NodePath, selfState: NodeTag,
                          otherPath: NodePath, otherState: NodeTag,
                          scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, BirdStateChanged} =
        match (selfState, otherState) {
            case (NodeTag.BirdArea, NodeTag.Ground) =>
                Game.onBirdHitGround(scene)
            case (NodeTag.Ground, NodeTag.BirdArea) =>
                Game.onBirdHitGround(scene)
            case (NodeTag.BirdArea, NodeTag.PipePart) =>
                Game.onBirdHitPipe(pipePath = otherPath, scene)
            case (NodeTag.PipePart, NodeTag.BirdArea) =>
                Game.onBirdHitPipe(pipePath = selfPath, scene)
            case (NodeTag.BirdArea, NodeTag.Coin) =>
                Game.onBirdPassedCoin(coinPath = otherPath, scene)
            case (NodeTag.Coin, NodeTag.BirdArea) =>
                Game.onBirdPassedCoin(coinPath = selfPath, scene)
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
                let nextX = Game.maxGroundX(scene) + GroundScene.groundWidth();
                let id = Float64.tryToInt32(nextX) |> Option.getWithDefault(0);
                checked_ecast(GroundScene.spawnGround("ground_${id}", nextX, scene))
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
    // フェーズ判定（Scene 構造から導出）
    // ========================================================================

    /// Scene の構造から現在のゲームフェーズを判定する
    /// GameOver layer 存在 → GameOver / Pipe 存在 → Playing / それ以外 → Menu
    pub def currentPhase(scene: Scene[NodeTag]): GamePhase =
        match Scene.getEngineNode(GameOverScene.layerPath(), scene) {
            case Some(_) => GamePhase.GameOver
            case None    =>
                if (List.length(Scene.getNodesInGroup(PipeScene.pipeGroup(), scene)) > 0)
                    GamePhase.Playing
                else
                    GamePhase.Menu
        }

    /// ゲーム開始入力を受け付けるか判定する
    /// Menu / GameOver(アニメ完了後) のとき true
    pub def canStart(scene: Scene[NodeTag]): Bool =
        match currentPhase(scene) {
            case GamePhase.Menu     => true
            case GamePhase.GameOver => GameOverScene.isAnimationFinished(scene)
            case GamePhase.Playing  => false
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
            |> CameraScene.addCamera
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
            |> CameraScene.addCamera
            |> ScoreScene.addHud(fontAtlas, bestScore)
            |> GroundScene.addGrounds
            |> MenuScene.addMenuUI
            |> Scene.mapEngineNode(ScoreScene.scoreLabelPath(),
                EngineNode.mapLabel2D(CanvasItem.hide));
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
    // 衝突応答
    // ========================================================================

    /// 鳥が地面に衝突したときの処理
    /// 鳥を Grounded 状態にする。地面への押し戻しは PhysicsStep.resolveStaticCollisions が自動処理。
    /// SE と camera shake は BirdScene.handleGrounded 側で発火される（bird.gd GroundedState._init 準拠）
    pub def onBirdHitGround(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, BirdStateChanged} =
        let birdData = BirdScene.getBirdData(scene);
        let flappingOrHit = match birdData#state {
            case BirdState.Flapping => true
            case BirdState.Hit      => true
            case _                  => false
        };
        if(flappingOrHit) BirdScene.handleGrounded(scene)
        else scene

    /// 鳥がパイプに衝突したときの処理
    /// Flapping → Hit: 衝突パイプを collisionException に登録し、鳥は重力で落下する
    /// Hit → Grounded: 衝突パイプが exception に未登録 = 別パイプの上に乗ってしまった
    ///                 状態とみなし、Grounded に遷移してゲームオーバーへ繋ぐ
    /// SE と camera shake は BirdScene 側のハンドラで発火される
    pub def onBirdHitPipe(pipePath: {pipePath = NodePath}, scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, BirdStateChanged} =
        let birdData = BirdScene.getBirdData(scene);
        match birdData#state {
            case BirdState.Flapping =>
                BirdScene.handleHit(pipePath#pipePath, scene)
            case BirdState.Hit =>
                if (BirdScene.bodyHasCollisionException(pipePath#pipePath, scene)) scene
                else BirdScene.handleGrounded(scene)
            case _ => scene
        }

    /// 鳥がコインを通過したときの処理
    /// スコアを +1 し、効果音を鳴らし、コインの NodeTag を NoTag に変更して再採点を防止する
    pub def onBirdPassedCoin(coinPath: {coinPath = NodePath}, scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Audio =
        GameEngine.Audio.playAudio("sfx_point");
        scene
            |> ScoreScene.incrementScore
            |> Scene.setState(coinPath#coinPath, NodeTag.NoTag)

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
        let birdPos = Scene.globalPosition("bird", scene);
        birdPos#x + CameraScene.offsetX()

    /// 地面グループ内の最右端 X 座標を返す（NodeRemovedHandler の再配置に使う）
    pub def maxGroundX(scene: Scene[NodeTag]): Float64 =
        Scene.getNodesInGroup(GroundScene.groundGroup(), scene)
            |> List.map(p -> Scene.globalPositionAt(p, scene)#x)
            |> List.maximum
            |> Option.getWithDefault(0.0)

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
                            GameEngine.Audio.playAudio("sfx_swooshing");
                            StageRequested.emit(GamePhase.GameOver);
                            scene
                                |> CameraScene.triggerShake(CameraScene.shakeIntensity(),
                                                            CameraScene.shakeDuration())
                                |> ScoreScene.finalizeScore
                                |> GameOverScene.addGameOverUI(fontAtlas)
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
