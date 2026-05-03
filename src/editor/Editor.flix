// Editor — シーン上のノードをマウスで選択・ドラッグ移動して JSON に書き戻すミニエディタ
//
// 公開ファサード。Game.flix への差し込みは最小限で、
//   - `run { gameLoop(...) } with Editor.withState(rc)` で Ref / handler / HotReload watcher を一括下準備
//   - gameLoop の毎フレームで Editor.handleInput / Editor.pollReload / Editor.applyOverlay を呼ぶ
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

    /// エディタの状態を保持するエフェクト。withState ハンドラが Ref と
    /// HotReload watcher の Receiver を closure で握って実装する
    pub eff EditorState {
        def get(): EditorStateData
        def put(stateData: EditorStateData): Unit
        def pollReload(): Bool
    }

    /// エディタ状態の record 表現
    /// on:             エディタモード ON / OFF
    /// selected:       現在選択中のノード（編集対象 JSON のパスとシーン内の NodePath）
    /// dragOrigin:     ドラッグ開始時のマウス座標（None ならドラッグ中ではない）
    /// nodeOrigin:     ドラッグ開始時のノードのグローバル座標
    /// prevF1:         前フレームの F1 押下状態（エッジ検出用）
    /// prevMouseLeft:  前フレームのマウス左ボタン押下状態（エッジ検出用）
    /// prevArrowKeys:  前フレームの矢印キー押下状態（KeyboardNudge のエッジ検出用）
    /// rootJsonIndex:  「シーンのルートノード名 → 由来する scene.json ファイルパス」の
    ///                 索引。Game.start で loadJsonRootIndex() の結果を入れる
    pub type alias EditorStateData = {
        on = Bool,
        selected = Option[(String, NodePath)],
        dragOrigin = Option[Vec2.Vec2],
        nodeOrigin = Option[Vec2.Vec2],
        prevF1 = Bool,
        prevMouseLeft = Bool,
        prevArrowKeys = KeyboardNudge.ArrowKeys,
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
        prevArrowKeys = KeyboardNudge.initialPrev(),
        rootJsonIndex = rootJsonIndex
    }

    /// エディタが現在 ON かどうかを返す。gameLoop からゲーム更新を止めるか判断するのに使う
    pub def isOn(): Bool \ EditorState = (EditorState.get())#on

    /// scene.json ルート索引を構築する。Game.start から 1 回だけ呼ぶ
    pub def loadJsonRootIndex(): Map[NodeName, String] \ {Fs.Glob, Fs.FileRead} =
        SceneJsonIndex.load()

    /// エディタ状態の Ref と HotReload watcher を一括して下準備し、
    /// EditorState ハンドラを掛けた状態で thunk を実行する。
    /// Game.start からはこの関数 1 つを `run { ... } with Editor.withState(rc)` の形で
    /// 使うだけでビジュアルエディタが使える。watcher の Receiver はハンドラが内部に
    /// 隠して持つので、gameLoop からは Editor.pollReload() で消費する。
    pub def withState(rc: Region[r]):
            (Unit -> Unit \ ef) -> Unit \ (ef - EditorState) + r + Fs.Glob + Fs.FileRead +
                                          Chan + NonDet + IO + Fs.ModificationTime =
        thunk -> {
            let editorIndex = loadJsonRootIndex();
            let editorRef: Ref[EditorStateData, r] = Ref.fresh(rc, initialState(editorIndex));
            let reloadRx = HotReload.startWatcher();
            run {
                thunk()
            } with handler EditorState {
                def get(k) = k(Ref.get(editorRef))
                def put(stateData, k) = { Ref.put(stateData, editorRef); k() }
                def pollReload(k) = k(HotReload.pollReload(reloadRx))
            }
        }

    /// 入力処理を行いシーンを更新する。Game.flix の gameLoop から毎フレーム呼ぶ。
    /// 副作用: EditorState を読み書き、JSON を読み書き、マウス・キー入力を読む
    pub def handleInput(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {EditorState, GameEngine.Game, Fs.FileRead, Fs.FileWrite} =
        let stateData = EditorState.get();
        let f1 = GameEngine.Game.isKeyPressed(GameEngine.Key.F1);
        let mouseLeft = GameEngine.Game.isMouseButtonPressed(GameEngine.MouseButton.Left);
        let mousePos = GameEngine.Game.getMousePosition();
        let curArrows = KeyboardNudge.readArrows();
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
            EditorState.put({prevMouseLeft = mouseLeft,
                             prevArrowKeys = curArrows | stateAfterToggle});
            scene
        } else {
            // エディタ ON 時のマウス処理
            let mouse = {pos = mousePos, leftDown = mouseLeft};
            let (afterMouseState, afterMouseScene) =
                DragInput.handleMouse(mouse, stateAfterToggle, scene);
            // ドラッグ中でなければ矢印キーで微調整できる
            let nudgedScene = if (Option.isEmpty(afterMouseState#dragOrigin))
                KeyboardNudge.applyNudge(afterMouseState, curArrows, afterMouseScene)
            else
                afterMouseScene;
            EditorState.put({prevMouseLeft = mouseLeft,
                             prevArrowKeys = curArrows | afterMouseState});
            nudgedScene
        }

    /// HotReload watcher の通知をノンブロッキングで消費する。
    /// withState ハンドラが内部で抱えている Receiver から 1 件取ったかどうかを返す
    pub def pollReload(): Bool \ EditorState =
        EditorState.pollReload()

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
