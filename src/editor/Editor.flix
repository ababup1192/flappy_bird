// Editor — シーン上のノードをマウスで選択・ドラッグ移動して JSON に書き戻すミニエディタ
//
// 公開ファサード。Game.flix への差し込みは最小限で、
//   - Game.start で Editor.loadJsonRootIndex() を 1 回だけ呼んで Ref に持つ
//   - gameLoop の毎フレームで Editor.handleInput / Editor.applyOverlay を呼ぶ
// だけで動く。実装本体は SceneJsonIndex / EditableNode / Picking / DragInput /
// Overlay / SceneSerializer のサブモジュールに分割されている。
//
// 動作概要:
//   - F1 でエディタ ON/OFF
//   - ON 時にシーンを走査し、Sprite2D / TextureButton / Label2D を編集対象として認識する
//   - 左クリックで対象ノードを選択（黄色の矩形で囲む）
//   - ドラッグで pos 変更（シーン上は即時更新、ドロップ時に JSON 書き戻し）
//   - HotReload watcher が JSON 変更を拾って次フレームでシーン再構築

mod Editor {

    /// エディタの状態を保持するエフェクト。Game.start 内の Ref で実装する
    pub eff EditorState {
        def get(): EditorStateData
        def put(stateData: EditorStateData): Unit
    }

    /// エディタ状態の record 表現
    /// on:            エディタモード ON / OFF
    /// selected:      現在選択中のノード（編集対象 JSON のパスとシーン内の NodePath）
    /// dragOrigin:    ドラッグ開始時のマウス座標（None ならドラッグ中ではない）
    /// nodeOrigin:    ドラッグ開始時のノードのグローバル座標
    /// prevF1:        前フレームの F1 押下状態（エッジ検出用）
    /// prevMouseLeft: 前フレームのマウス左ボタン押下状態（エッジ検出用）
    /// rootJsonIndex: 「シーンのルートノード名 → 由来する scene.json ファイルパス」の
    ///                索引。Game.start で loadJsonRootIndex() の結果を入れる
    pub type alias EditorStateData = {
        on = Bool,
        selected = Option[(String, NodePath)],
        dragOrigin = Option[Vec2.Vec2],
        nodeOrigin = Option[Vec2.Vec2],
        prevF1 = Bool,
        prevMouseLeft = Bool,
        rootJsonIndex = Map[NodeName, String]
    }

    /// エディタ状態の初期値。rootJsonIndex は呼び出し側で別途与える
    pub def initialState(rootJsonIndex: Map[NodeName, String]): EditorStateData = {
        on = false,
        selected = None,
        dragOrigin = None,
        nodeOrigin = None,
        prevF1 = false,
        prevMouseLeft = false,
        rootJsonIndex = rootJsonIndex
    }

    /// scene.json ルート索引を構築する。Game.start から 1 回だけ呼ぶ
    pub def loadJsonRootIndex(): Map[NodeName, String] \ {Fs.Glob, Fs.FileRead} =
        SceneJsonIndex.load()

    /// 入力処理を行いシーンを更新する。Game.flix の gameLoop から毎フレーム呼ぶ。
    /// 副作用: EditorState を読み書き、JSON を読み書き、マウス・キー入力を読む
    pub def handleInput(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {EditorState, GameEngine.Game, Fs.FileRead, Fs.FileWrite} =
        let stateData = EditorState.get();
        let f1 = GameEngine.Game.isKeyPressed(GameEngine.Key.F1);
        let mouseLeft = GameEngine.Game.isMouseButtonPressed(GameEngine.MouseButton.Left);
        let mousePos = GameEngine.Game.getMousePosition();
        // F1 のエッジ検出: 前フレーム未押下 → 今フレーム押下 でトグル
        let toggledOn = if (f1 and not stateData#prevF1) not stateData#on else stateData#on;
        // OFF へ倒れたフレームは選択 / ドラッグ状態をクリアする。
        // ON 中（または ON のまま）は既存の選択 / ドラッグ状態を維持
        let stateAfterToggle = if (toggledOn)
            {on = true, prevF1 = f1 | stateData}
        else
            {on = false, selected = None, dragOrigin = None, nodeOrigin = None,
             prevF1 = f1 | stateData};
        if (not toggledOn) {
            EditorState.put({prevMouseLeft = mouseLeft | stateAfterToggle});
            scene
        } else {
            // エディタ ON 時のマウス処理
            let mouse = {pos = mousePos, leftDown = mouseLeft};
            let (newState, newScene) =
                DragInput.handleMouse(mouse, stateAfterToggle, scene);
            EditorState.put({prevMouseLeft = mouseLeft | newState});
            newScene
        }

    /// 描画用のオーバーレイをシーンに合成する。Game.flix の render 直前に呼ぶ。
    /// 戻り値の Scene は次フレームに引き継がない（一回限りの描画用）。
    /// エディタ OFF のときは何もせず scene をそのまま返す
    pub def applyOverlay(fontAtlas: FontAtlas, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {EditorState, GameEngine.Game} =
        let stateData = EditorState.get();
        if (not stateData#on) scene
        else {
            scene
                |> Overlay.addEditorIndicator(fontAtlas)
                |> Overlay.addSelectionBox(stateData#rootJsonIndex, stateData#selected)
        }
}
