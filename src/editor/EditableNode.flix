// EditableNode — エディタが編集対象として扱うノードの抽出と矩形計算
//
// シーンを走査し Sprite2D / TextureButton / Label2D を編集対象として認識する。
// 各ノードの「画面上の表示矩形」（width / height と topLeftOffset）を計算して返すのが主な仕事。
//
// rootJsonIndex (root 名 → scene.json パス) に登録されていないルートに属する
// ノードは「JSON 書き戻し先が不明」として除外する（procedural 生成ノードや、
// エディタ自身のオーバーレイなど）

mod EditableNode {

    /// 編集対象ノードの 1 件分の情報。
    /// jsonPath: 書き戻し対象の scene.json ファイルパス
    /// nodePath: シーン内の階層パス
    /// width / height: 画面上で見える矩形のサイズ（ピクセル単位）
    /// topLeftOffset: ノード position から矩形の左上までの相対オフセット。
    ///                Sprite2D centered=true なら (-w/2, -h/2)、Label2D centered=true なら
    ///                (-w/2, 0)（縦方向はベースライン基準）、centered=false ならゼロ
    pub type alias EditableEntry = {
        jsonPath = String,
        nodePath = NodePath,
        width = Float64,
        height = Float64,
        topLeftOffset = Vec2.Vec2
    }

    /// シーン全体を走査して編集対象ノードを抽出する。
    /// rootJsonIndex に登録されていないルートのノードは除外される
    pub def collectAll(rootJsonIndex: Map[NodeName, String], scene: Scene[NodeTag]):
            List[EditableEntry] \ GameEngine.Game =
        Scene.preorderPaths(scene)
            |> List.foldLeft((acc, path) ->
                match buildEntry(rootJsonIndex, path, scene) {
                    case Some(entry) => List.append(acc, entry :: Nil)
                    case None        => acc
                }, Nil)

    /// 走査結果から指定 NodePath の entry を 1 件取り出す
    pub def findByNodePath(rootJsonIndex: Map[NodeName, String], nodePath: NodePath,
                           scene: Scene[NodeTag]):
            Option[EditableEntry] \ GameEngine.Game =
        collectAll(rootJsonIndex, scene)
            |> List.find(entry -> entry#nodePath == nodePath)

    /// Sprite2D / TextureButton の topLeftOffset 計算（中央基準なら半サイズ分マイナス）。
    /// 純粋関数なので単体テストしやすい
    pub def boxTopLeftOffset(centered: Bool, size: Vec2.Vec2): Vec2.Vec2 =
        if (centered) {x = -size#x / 2.0, y = -size#y / 2.0}
        else {x = 0.0, y = 0.0}

    /// Label2D の表示矩形を計算する。FontAtlas のグリフ advance 合計から幅、
    /// ascent + descent から高さを出す。改行 (\n) があれば最も長い行を採用 + 行数分の高さ
    pub def labelRectInfo(label: Label2D): {size = Vec2.Vec2, topLeftOffset = Vec2.Vec2} =
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

    /// ノードの表示サイズと topLeftOffset を返す（編集対象でなければ None）
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
}
