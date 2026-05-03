// Tests for Overlay — エディタ ON 表示 + 選択枠の描画
//
// Scene 変換が中心なので、ノード追加結果（ファサードの子に何があるか）を確認する形で
// 検証する。`addSelectionBox` は `EditableNode.findByNodePath` 経由で
// `GameEngine.Game.getTextureInfo` を使うのでモックハンドラを噛ませる

mod TestOverlay {

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

    /// すべての texture が 32x32 を返す GameEngine.Game ハンドラ
    def withMockTexture32(f: Unit -> a \ ef + GameEngine.Game): a \ ef =
        run f() with handler GameEngine.Game {
            def render(_, k) = k(())
            def shouldClose(k) = k(false)
            def getDeltaTime(k) = k(0.016)
            def isKeyPressed(_, k) = k(false)
            def getMousePosition(k) = k({x = 0.0, y = 0.0})
            def isMouseButtonPressed(_, k) = k(false)
            def getFontAtlas(_, _) = bug!("font not used")
            def getViewportRect(k) = k({position = {x = 0.0, y = 0.0}, size = {x = 480.0, y = 720.0}})
            def getTextureInfo(_, k) = k(Some({id = 0i32, width = 32.0, height = 32.0}))
        }

    // ====================================================================
    // addEditorIndicator — EDITOR ラベルを最前面 CanvasLayer に追加
    // ====================================================================

    /// 空シーンに addEditorIndicator すると、ラベル用 CanvasLayer + その下の Label2D が増える
    @Test
    def testAddEditorIndicatorAddsLayerAndLabel(): Unit \ Assert =
        let s: Scene[NodeTag] = Scene.empty();
        let result = Overlay.addEditorIndicator(testFontAtlas(), s);
        let layerExists =
            Scene.getEngineNode("_editor_indicator_layer" :: Nil, result)
                |> Option.exists(node -> match node {
                    case EngineNode.CanvasLayerWithState(_, _) => true
                    case _ => false
                });
        let labelExists =
            Scene.getEngineNode("_editor_indicator_layer" :: "_editor_indicator_label" :: Nil, result)
                |> Option.exists(node -> match node {
                    case EngineNode.Label2DWithState(_, _) => true
                    case _ => false
                });
        Assert.assertEq(expected = (true, true), (layerExists, labelExists))

    /// addEditorIndicator は元のシーンの他のノードを破壊しない
    @Test
    def testAddEditorIndicatorPreservesExistingNodes(): Unit \ Assert =
        let sprite = Sprite2D.make("dummy.png", {x = 0.0, y = 0.0}, {x = 1.0, y = 1.0});
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s |> Scene.addNode("hero",
            EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag));
        let result = Overlay.addEditorIndicator(testFontAtlas(), scene);
        let heroStillThere = Option.nonEmpty(
            Scene.getEngineNode("hero" :: Nil, result));
        Assert.assertEq(expected = true, heroStillThere)

    // ====================================================================
    // addSelectionBox — 選択中ノードを 4 辺で囲む
    // ====================================================================

    /// selected = None なら scene は変わらない
    @Test
    def testAddSelectionBoxNoneIsNoOp(): Unit \ Assert =
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s;
        let result = withMockTexture32(() ->
            Overlay.addSelectionBox(Map.empty(), None, scene));
        let boxLayerAbsent = Option.isEmpty(
            Scene.getEngineNode("_editor_box_layer" :: Nil, result));
        Assert.assertEq(expected = true, boxLayerAbsent)

    /// 選択中 entry がない（rootJsonIndex に登録外）なら何も追加しない
    def testAddSelectionBoxUnknownRootIsNoOp(): Unit \ {Assert, GameEngine.Game} =
        let sprite = Sprite2D.make("dummy.png", {x = 0.0, y = 0.0}, {x = 1.0, y = 1.0});
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s |> Scene.addNode("hero",
            EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag));
        // index に "hero" を入れていない → entry が見つからない
        let result = Overlay.addSelectionBox(
            Map.empty(),
            Some(("hero.json", "hero" :: Nil)),
            scene);
        let boxLayerAbsent = Option.isEmpty(
            Scene.getEngineNode("_editor_box_layer" :: Nil, result));
        Assert.assertEq(expected = true, boxLayerAbsent)

    @Test
    def testAddSelectionBoxUnknownRootIsNoOpRunner(): Unit \ Assert =
        withMockTexture32(testAddSelectionBoxUnknownRootIsNoOp)

    /// 選択中ノードがあれば 4 辺の ColorRect が追加される（top/bottom/left/right）
    def testAddSelectionBoxAddsFourEdges(): Unit \ {Assert, GameEngine.Game} =
        let sprite = Sprite2D.make("dummy.png", {x = 100.0, y = 100.0}, {x = 1.0, y = 1.0});
        let s: Scene[NodeTag] = Scene.empty();
        let scene = s |> Scene.addNode("hero",
            EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag));
        let index = Map#{"hero" => "hero.json"};
        let result = Overlay.addSelectionBox(
            index,
            Some(("hero.json", "hero" :: Nil)),
            scene);
        let isColorRect = node -> match node {
            case EngineNode.ColorRectWithState(_, _) => true
            case _                                   => false
        };
        let layerName = "_editor_box_layer";
        let top = Scene.getEngineNode(layerName :: "top" :: Nil, result)
            |> Option.exists(isColorRect);
        let bottom = Scene.getEngineNode(layerName :: "bottom" :: Nil, result)
            |> Option.exists(isColorRect);
        let left = Scene.getEngineNode(layerName :: "left" :: Nil, result)
            |> Option.exists(isColorRect);
        let right = Scene.getEngineNode(layerName :: "right" :: Nil, result)
            |> Option.exists(isColorRect);
        Assert.assertEq(expected = (true, true, true, true), (top, bottom, left, right))

    @Test
    def testAddSelectionBoxAddsFourEdgesRunner(): Unit \ Assert =
        withMockTexture32(testAddSelectionBoxAddsFourEdges)
}
