// Picking — マウス位置から hit する編集対象ノードを 1 件選ぶ（Godot Object Picking 準拠）
//
// 純粋関数として切り出してあるため `GameEngine.Game` 等のエフェクトモック不要で
// テストできる（候補のリストを呼び出し側が組み立てる前提）。
// Z-index の優先付けは `Scene.effectiveZIndexAt` に揃えるので、レンダラの
// 描画順とエディタの選択順が常に一致する

mod Picking {

    /// 与えられた候補の中からマウス位置にヒットするものを 1 件返す。
    /// 複数 hit する場合はレンダラの draw-order と同じ計算
    /// （Scene.effectiveZIndexAt）で最も上に描かれるノードを優先する。
    /// z-index が同値のときは entries の後ろ（preorder で後 = より深い／後発）を採用
    pub def pickTopAt(mousePos: Vec2.Vec2,
                      entries: List[EditableNode.EditableEntry],
                      scene: Scene[NodeTag]):
            Option[(EditableNode.EditableEntry, Vec2.Vec2)] =
        let hits = entries |> List.filterMap(entry -> {
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

    /// グローバル位置と EditableEntry から表示矩形 Rect2 を作る
    pub def makeBBox(refPos: Vec2.Vec2,
                     entry: EditableNode.EditableEntry): Rect2.Rect2 =
        let topLeft = Vec2.add(refPos, entry#topLeftOffset);
        {position = topLeft, size = {x = entry#width, y = entry#height}}
}
