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
    case Bird(BirdScene.BirdData)
    case NoTag
}

// ========================================================================
// ゲーム状態
// ========================================================================

/// ゲーム全体の状態レコード
/// scene: シーングラフ
/// phase: ゲームフェーズ
/// flapPressed: 前フレームでフラップ入力があったか（連続入力防止用）
pub type alias GameState = {
    scene = Scene[NodeTag],
    phase = GamePhase,
    flapPressed = Bool
}

// ========================================================================
// Node 実装（Phase 1: 特別な process なし）
// ========================================================================

instance Node[NodeTag] {
    redef process(_delta: Float64, node: EngineNode[NodeTag],
                  _path: NodePath, scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ Math.Random =
        checked_ecast((node, scene))
}

// ========================================================================
// AreaHandler 実装（Phase 1: 衝突応答なし）
// ========================================================================

instance AreaHandler[NodeTag] {
    pub def onAreaEntered(_selfPath: NodePath, _selfState: NodeTag,
                          _otherPath: NodePath, _otherState: NodeTag,
                          scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
}

// ========================================================================
// ScreenNotifyHandler 実装（Phase 1: 画面外通知なし）
// ========================================================================

instance ScreenNotifyHandler[NodeTag] {
    redef onScreenExited(_path: NodePath, _state: NodeTag,
                         scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
}

// ========================================================================
// TimerHandler 実装（Phase 1: タイマーなし）
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
    // 初期状態構築
    // ========================================================================

    /// ゲームの初期状態を構築する
    pub def buildState(_fontAtlas: FontAtlas): GameState =
        {   scene = Scene.empty()
                |> BirdScene.addBird,
            phase = GamePhase.Playing,
            flapPressed = false
        }

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
                    let finalScene = BirdScene.clampRotation(updatedScene);
                    {scene = finalScene, phase = GamePhase.Playing, flapPressed = inputPressed}
                case GamePhase.Menu =>
                    state
                case GamePhase.GameOver =>
                    state
            };
            GameEngine.render(nextState#scene);
            gameLoop(fontAtlas, nextState)
        }
}
