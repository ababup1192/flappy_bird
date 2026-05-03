// Editor — シーン上のノードをマウスで選択・ドラッグ移動して JSON に書き戻すミニエディタ
//
// HotReload と同じく Game.flix への差し込みは最小限。エディタ状態は EditorState エフェクトで
// Ref に保持し、毎フレーム gameLoop から handleInput / applyOverlay を呼ぶだけで動く。
//
// 動作概要:
//   - F1 でエディタ ON/OFF
//   - ON 時にシーンを走査し、Sprite2D / TextureButton をすべて編集対象として認識する
//   - 各ノードのルート名から scene.json ファイルを索引（rootJsonIndex）
//     索引は Game.start で `loadJsonRootIndex()` を呼んで一度だけ作成する
//   - 左クリックで対象ノードを選択（黄色の矩形で囲む）
//   - ドラッグで pos 変更（シーン上は即時更新、ドロップ時に JSON 書き戻し）
//   - HotReload watcher が JSON 変更を拾って次フレームでシーン再構築
//
// 書き戻しはドロップ時のみ。ドラッグ中は HotReload を発火させずシーンの中で動かすだけ
// にする（書き戻しごとに HotReload で再構築すると ドラッグ位置が一瞬戻って見えてしまう）

mod Editor {
    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonArray, JsonString}

    // ========================================================================
    // 公開エフェクト
    // ========================================================================

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

    // ========================================================================
    // scene.json インデックスの構築（Game.start から 1 回だけ呼ぶ）
    // ========================================================================

    /// src/scenes 配下の *.scene.json をすべて走査し、各ファイルのルートノード名から
    /// JSON ファイルパスを引けるインデックスを作る。
    /// JSON ルートが配列なら配列要素ごとに、オブジェクトならその "name" を採用する。
    /// 同じ root 名が複数の JSON ファイルにあった場合は後勝ち（実害はない想定）
    pub def loadJsonRootIndex(): Map[NodeName, String] \ {Fs.Glob, Fs.FileRead} =
        Fs.Glob.glob("src/scenes", "*.scene.json")
            |> Result.getWithDefault(Nil)
            |> List.foldLeft((acc, path) -> mergeRootsFromFile(path, acc), Map.empty())

    /// 1 ファイルから root 名を抜き出して acc にマージする
    def mergeRootsFromFile(path: String, acc: Map[NodeName, String]):
            Map[NodeName, String] \ Fs.FileRead =
        let content = run { Fs.ReadFile.read(path) } with Fs.ReadFile.runWithFileRead;
        match content {
            case Err(_) => acc
            case Ok(text) =>
                match Json.Parse.parse(String.trim(text)) {
                    case None => acc
                    case Some(json) =>
                        rootNamesOf(json) |> List.foldLeft((m, name) ->
                            Map.insert(name, path, m), acc)
                }
        }

    /// JSON ルート（オブジェクト or 配列）から各要素の "name" 文字列を取り出す
    def rootNamesOf(json: JsonElement): List[NodeName] =
        match json {
            case JsonObject(_) =>
                nameOf(json) |> Option.toList
            case JsonArray(arr) =>
                Vector.toList(arr) |> List.filterMap(nameOf)
            case _ => Nil
        }

    /// 単一 JSON オブジェクトの "name" フィールドを取り出す
    def nameOf(json: JsonElement): Option[NodeName] =
        match json {
            case JsonObject(map) =>
                match Map.get("name", map) {
                    case Some(JsonString(s)) => Some(s)
                    case _                   => None
                }
            case _ => None
        }

    // ========================================================================
    // 編集対象ノードの動的検出
    // ========================================================================

    /// 編集対象ノードの 1 件分の情報。
    /// jsonPath: 書き戻し対象の scene.json ファイルパス
    /// nodePath: シーン内の階層パス
    /// width / height: 画面上で見える矩形のサイズ（ピクセル単位）
    /// topLeftOffset: ノード position から矩形の左上までの相対オフセット。
    ///                Sprite2D centered=true なら (-w/2, -h/2)、Label2D centered=true なら
    ///                (-w/2, 0)（縦方向はベースライン基準）、centered=false ならゼロ
    type alias EditableEntry = {
        jsonPath = String,
        nodePath = NodePath,
        width = Float64,
        height = Float64,
        topLeftOffset = Vec2.Vec2
    }

    /// 与えられたシーンを走査し、編集可能ノード（Sprite2D / TextureButton）を抽出する。
    /// 各ノードのルート名が rootJsonIndex に登録されていなければ「JSON 書き戻し先が
    /// 不明」として除外する（procedural なノードや、エディタ自身のオーバーレイなど）
    def collectEditable(rootJsonIndex: Map[NodeName, String], scene: Scene[NodeTag]):
            List[EditableEntry] \ GameEngine.Game =
        Scene.preorderPaths(scene)
            |> List.foldLeft((acc, path) ->
                match buildEntry(rootJsonIndex, path, scene) {
                    case Some(entry) => List.append(acc, entry :: Nil)
                    case None        => acc
                }, Nil)

    /// 1 パス分の EditableEntry を構築する。Sprite2D / TextureButton / Label2D 以外は None。
    /// rootJsonIndex に未登録のルートに属するノードも None
    def buildEntry(rootJsonIndex: Map[NodeName, String], path: NodePath,
                   scene: Scene[NodeTag]): Option[EditableEntry] \ GameEngine.Game =
        match path {
            case Nil => None
            case rootName :: _ =>
                match Map.get(rootName, rootJsonIndex) {
                    case None => None
                    case Some(jsonPath) =>
                        match Scene.getEngineNode(path, scene) {
                            case None             => None
                            case Some(engineNode) => rectInfoOf(engineNode)
                                |> Option.map(rect -> {
                                    jsonPath = jsonPath,
                                    nodePath = path,
                                    width = rect#size#x,
                                    height = rect#size#y,
                                    topLeftOffset = rect#topLeftOffset
                                })
                        }
                }
        }

    /// ノードの表示サイズと topLeftOffset を返す（編集対象でなければ None）。
    /// Sprite2D: texture サイズ × scale。中央基準なら (-w/2, -h/2) 分シフト
    /// TextureButton: size 値そのもの
    /// Label2D: フォントメトリクスから幅・高さを計算。centered=true は X 方向のみセンタリング
    def rectInfoOf(engineNode: EngineNode[NodeTag]):
            Option[{size = Vec2.Vec2, topLeftOffset = Vec2.Vec2}] \ GameEngine.Game =
        match engineNode {
            case EngineNode.Sprite2DWithState(sprite, _) =>
                let Sprite2D.Sprite2D(record) = sprite;
                match GameEngine.Game.getTextureInfo(record#texture) {
                    case None => None
                    case Some(info) =>
                        let size = {x = info#width * record#scale#x,
                                    y = info#height * record#scale#y};
                        Some({size = size,
                              topLeftOffset = boxTopLeftOffset(record#centered, size)})
                }
            case EngineNode.TextureButtonWithState(btn, _) =>
                let size = TextureButton.getSize(btn);
                Some({size = size,
                      topLeftOffset = boxTopLeftOffset(TextureButton.isCentered(btn), size)})
            case EngineNode.Label2DWithState(label, _) =>
                Some(labelRectInfo(label))
            case _ => None
        }

    /// Sprite2D / TextureButton の topLeftOffset 計算（中央基準なら半サイズ分マイナス）
    def boxTopLeftOffset(centered: Bool, size: Vec2.Vec2): Vec2.Vec2 =
        if (centered) {x = -size#x / 2.0, y = -size#y / 2.0}
        else {x = 0.0, y = 0.0}

    /// Label2D の表示矩形を計算する。FontAtlas のグリフ advance 合計から幅、
    /// ascent + descent から高さを出す。改行 (\n) があれば最も長い行を採用 + 行数分の高さ
    def labelRectInfo(label: Label2D): {size = Vec2.Vec2, topLeftOffset = Vec2.Vec2} =
        let Label2D.Label2D(record) = label;
        let atlas = record#fontAtlas;
        let scale = record#fontSize / atlas#fontSize;
        let lines = TextLayout.splitLines(record#text);
        let lineWidths = List.map(lineChars -> {
            let advances = List.map(ch -> {
                let cp = TextLayout.charToCodePoint(ch);
                match Map.get(cp, atlas#glyphs) {
                    case Some(glyphMetrics) => glyphMetrics#advance
                    case None => 0.0
                }
            }, lineChars);
            TextLayout.totalAdvance(advances) * scale
        }, lines);
        let width = List.foldLeft(Float64.max, 0.0, lineWidths);
        let lineHeight = (atlas#ascent + atlas#descent + atlas#lineGap) * scale;
        let height = lineHeight * Int32.toFloat64(Int32.max(1, List.length(lines)));
        // Label2D の centered は X 方向のみ。Y は globalPos がベースライン上端
        let topLeftOffset = if (record#centered)
            {x = -width / 2.0, y = 0.0}
        else {x = 0.0, y = 0.0};
        {size = {x = width, y = height}, topLeftOffset = topLeftOffset}

    // ========================================================================
    // メインループから呼ぶ API
    // ========================================================================

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
        let stateAfterToggle = {
            on = toggledOn,
            selected = if (toggledOn) stateData#selected else None,
            dragOrigin = if (toggledOn) stateData#dragOrigin else None,
            nodeOrigin = if (toggledOn) stateData#nodeOrigin else None,
            prevF1 = f1,
            prevMouseLeft = stateData#prevMouseLeft,
            rootJsonIndex = stateData#rootJsonIndex
        };
        if (not toggledOn) {
            EditorState.put({prevMouseLeft = mouseLeft | stateAfterToggle});
            scene
        } else {
            // エディタ ON 時のマウス処理
            let (newState, newScene) =
                handleMouse(mousePos, mouseLeft, stateAfterToggle, scene);
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
                |> addEditorIndicator(fontAtlas)
                |> addSelectionBox(stateData#rootJsonIndex, stateData#selected)
        }

    // ========================================================================
    // 入力処理（クリック選択 + ドラッグ移動 + ドロップ書き戻し）
    // ========================================================================

    /// マウスの押下／継続／離脱を判定し、選択 / ドラッグ更新 / 書き戻し をディスパッチする
    def handleMouse(mousePos: Vec2.Vec2, mouseLeft: Bool, stateData: EditorStateData,
                    scene: Scene[NodeTag]):
            (EditorStateData, Scene[NodeTag]) \ {GameEngine.Game, Fs.FileRead, Fs.FileWrite} =
        let prevLeft = stateData#prevMouseLeft;
        let pressedNow = mouseLeft and not prevLeft;       // 押下したフレーム
        let releasedNow = (not mouseLeft) and prevLeft;    // 離した（ドロップ）フレーム
        if (pressedNow) {
            // 押下時: 候補から hit test して選択 or ドラッグ開始
            handleMouseDown(mousePos, stateData, scene)
        } else if (mouseLeft and Option.nonEmpty(stateData#dragOrigin)) {
            // ドラッグ中: 選択ノードの位置を更新（書き戻しはまだしない）
            (stateData, applyDrag(mousePos, stateData, scene))
        } else if (releasedNow and Option.nonEmpty(stateData#dragOrigin)) {
            // ドロップ: シーンの最終 pos を JSON に書き戻し
            saveDraggedPos(stateData, scene)
        } else {
            (stateData, scene)
        }

    /// クリック押下時: 編集対象ノードのうち hit したものを選択し、ドラッグ開始状態にする
    def handleMouseDown(mousePos: Vec2.Vec2, stateData: EditorStateData,
                        scene: Scene[NodeTag]):
            (EditorStateData, Scene[NodeTag]) \ GameEngine.Game =
        let hit = findHit(mousePos, stateData#rootJsonIndex, scene);
        match hit {
            case None =>
                ({selected = None, dragOrigin = None, nodeOrigin = None | stateData}, scene)
            case Some((entry, nodeGlobalPos)) =>
                let newState = {
                    selected = Some((entry#jsonPath, entry#nodePath)),
                    dragOrigin = Some(mousePos),
                    nodeOrigin = Some(nodeGlobalPos)
                    | stateData
                };
                (newState, scene)
        }

    /// 編集対象ノードの中からマウス位置に重なるものを 1 件返す。
    /// 複数 hit する場合はレンダラの draw-order と同じ計算
    /// （Scene.effectiveZIndexAt）で最も上に描かれるノードを優先する。
    /// z-index が同値のときは preorder で後（より深い／後発）を採用
    def findHit(mousePos: Vec2.Vec2, rootJsonIndex: Map[NodeName, String],
                scene: Scene[NodeTag]):
            Option[(EditableEntry, Vec2.Vec2)] \ GameEngine.Game =
        let hits = collectEditable(rootJsonIndex, scene) |> List.filterMap(entry -> {
            let globalPos = Scene.globalPositionAt(entry#nodePath, scene);
            let bbox = makeBBox(globalPos, entry);
            if (Rect2.hasPoint(mousePos, bbox)) Some((entry, globalPos))
            else None
        });
        let folded = List.foldLeft((best, hit) -> match hit {
            case (entry, _) =>
                let curZ = Scene.effectiveZIndexAt(entry#nodePath, scene);
                match best {
                    case None => Some((curZ, hit))
                    case Some((bestZ, _)) =>
                        if (curZ >= bestZ) Some((curZ, hit))
                        else best
                }
        }, None, hits);
        match folded {
            case None         => None
            case Some((_, h)) => Some(h)
        }

    /// ドラッグ中: マウスの移動量に応じてノードのグローバル位置を更新する。
    /// ピクセル単位に整数スナップして「カクカク」動かす（drop 時の保存値とも一致する）
    def applyDrag(mousePos: Vec2.Vec2, stateData: EditorStateData,
                  scene: Scene[NodeTag]): Scene[NodeTag] =
        match (stateData#selected, stateData#dragOrigin, stateData#nodeOrigin) {
            case (Some((_, nodePath)), Some(dragOrigin), Some(nodeOrigin)) =>
                let delta = Vec2.sub(mousePos, dragOrigin);
                let newGlobalPos = snapVec2(Vec2.add(nodeOrigin, delta));
                Scene.setGlobalPositionAt(nodePath, newGlobalPos, scene)
            case _ => scene
        }

    /// Vec2 を整数ピクセルに丸める（HotReload 後の JSON も整数値で残るようにするため）
    def snapVec2(v: Vec2.Vec2): Vec2.Vec2 =
        {x = Float64.round(v#x), y = Float64.round(v#y)}

    /// ドロップ: 現在のシーン上のノード位置を JSON に書き戻し、ドラッグ状態を解除する。
    /// 書き戻し対象は「ローカル位置」（JSON が pos として持つのはローカル座標のため）。
    /// ただし押下→そのまま離した（クリック選択のみ）場合は位置が変わっていないので
    /// ファイル書き込みをスキップする（mtime 更新で HotReload を無駄打ちさせない）
    def saveDraggedPos(stateData: EditorStateData,
                       scene: Scene[NodeTag]): (EditorStateData, Scene[NodeTag]) \
                       {Fs.FileRead, Fs.FileWrite} =
        match stateData#selected {
            case Some((jsonPath, nodePath)) =>
                let currentGlobal = Scene.globalPositionAt(nodePath, scene);
                let moved = match stateData#nodeOrigin {
                    case Some(origin) =>
                        currentGlobal#x != origin#x or currentGlobal#y != origin#y
                    case None => false
                };
                if (moved) {
                    let localPos = match Scene.getEngineNode(nodePath, scene) {
                        case Some(engineNode) => Node2D.getPosition(engineNode)
                        case None => Vec2.zero()
                    };
                    SceneSerializer.updatePos(jsonPath, nodePath, localPos)
                } else ();
                let cleared = {
                    dragOrigin = None,
                    nodeOrigin = None
                    | stateData
                };
                (cleared, scene)
            case None => (stateData, scene)
        }

    /// グローバル位置と EditableEntry から表示矩形 Rect2 を作る
    def makeBBox(refPos: Vec2.Vec2, entry: EditableEntry): Rect2.Rect2 =
        let topLeft = Vec2.add(refPos, entry#topLeftOffset);
        {position = topLeft, size = {x = entry#width, y = entry#height}}

    // ========================================================================
    // オーバーレイ構築
    // ========================================================================

    /// エディタが ON であることを示す右上の "EDITOR" ラベルを最前面に追加する
    def addEditorIndicator(fontAtlas: FontAtlas, scene: Scene[NodeTag]): Scene[NodeTag] =
        let layerName = "_editor_indicator_layer";
        let labelName = "_editor_indicator_label";
        let layer = CanvasLayer.make(overlayLayerIndex());
        let label = Label2D.make("EDITOR", fontAtlas, 14.0)
            |> Node2D.setPosition({x = 230.0, y = 16.0})
            |> CanvasItem.setModulate({r = 1.0f32, g = 0.85f32, b = 0.2f32});
        scene
            |> Scene.addNode(layerName,
                EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag))
            |> Scene.addChildAt(layerName :: Nil, labelName,
                EngineNode.Label2DWithState(label, NodeTag.NoTag))

    /// 選択中ノードを取り囲む黄色の矩形（4 辺の細い ColorRect）を最前面に追加する。
    /// エディタ ON 中はマウス位置に追従する選択 entry をシーン走査で再取得して使う
    def addSelectionBox(rootJsonIndex: Map[NodeName, String],
                        selected: Option[(String, NodePath)],
                        scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        match selected {
            case None => scene
            case Some((_, nodePath)) =>
                match findEntryFor(rootJsonIndex, nodePath, scene) {
                    case None => scene
                    case Some(entry) =>
                        let refPos = Scene.globalPositionAt(nodePath, scene);
                        let topLeft = Vec2.add(refPos, entry#topLeftOffset);
                        addBoxLines(topLeft, entry#width, entry#height, scene)
                }
        }

    /// 現在のシーンから NodePath 一致の entry を 1 件取り出す
    def findEntryFor(rootJsonIndex: Map[NodeName, String], nodePath: NodePath,
                     scene: Scene[NodeTag]):
            Option[EditableEntry] \ GameEngine.Game =
        collectEditable(rootJsonIndex, scene)
            |> List.find(entry -> entry#nodePath == nodePath)

    /// 矩形の 4 辺を CanvasLayer の中に細い ColorRect として配置する。
    /// 各辺は 2px の太さ。色は明るい黄色で目立たせる
    def addBoxLines(topLeft: Vec2.Vec2, width: Float64, height: Float64,
                    scene: Scene[NodeTag]): Scene[NodeTag] =
        let layerName = "_editor_box_layer";
        let layer = CanvasLayer.make(overlayLayerIndex());
        let yellow: {r = Float32, g = Float32, b = Float32} =
            {r = 1.0f32, g = 0.85f32, b = 0.2f32};
        let thickness = 2.0;
        let topLine = makeLine(topLeft, width, thickness, yellow);
        let bottomLine = makeLine({x = topLeft#x, y = topLeft#y + height - thickness},
                                  width, thickness, yellow);
        let leftLine = makeLine(topLeft, thickness, height, yellow);
        let rightLine = makeLine({x = topLeft#x + width - thickness, y = topLeft#y},
                                 thickness, height, yellow);
        scene
            |> Scene.addNode(layerName,
                EngineNode.CanvasLayerWithState(layer, NodeTag.NoTag))
            |> Scene.addChildAt(layerName :: Nil, "top",
                EngineNode.ColorRectWithState(topLine, NodeTag.NoTag))
            |> Scene.addChildAt(layerName :: Nil, "bottom",
                EngineNode.ColorRectWithState(bottomLine, NodeTag.NoTag))
            |> Scene.addChildAt(layerName :: Nil, "left",
                EngineNode.ColorRectWithState(leftLine, NodeTag.NoTag))
            |> Scene.addChildAt(layerName :: Nil, "right",
                EngineNode.ColorRectWithState(rightLine, NodeTag.NoTag))

    /// 1 本の線分を ColorRect で作る
    def makeLine(pos: Vec2.Vec2, width: Float64, height: Float64,
                 color: {r = Float32, g = Float32, b = Float32}): ColorRect =
        ColorRect.make({x = width, y = height}, color)
            |> Node2D.setPosition(pos)

    /// オーバーレイ用 CanvasLayer のレイヤー番号（既存の最前面 layer=2 より大きく取る）
    def overlayLayerIndex(): Int32 = 999
}
