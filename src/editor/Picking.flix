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
        entries
            |> List.filterMap(entry -> hitInfo(mousePos, entry, scene))
            |> highestZ
            |> Option.map(hit -> (hit#entry, hit#globalPos))

    /// 1 件分のヒット情報。z は `Scene.effectiveZIndexAt` の値（fold 中で再計算しないよう
    /// 事前に詰めておく）
    type alias HitInfo = {
        z = Int32,
        entry = EditableNode.EditableEntry,
        globalPos = Vec2.Vec2
    }

    /// マウスが entry の bbox 内なら HitInfo を返す
    def hitInfo(mousePos: Vec2.Vec2, entry: EditableNode.EditableEntry,
                scene: Scene[NodeTag]): Option[HitInfo] =
        let globalPos = Scene.globalPositionAt(entry#nodePath, scene);
        if (Rect2.hasPoint(mousePos, makeBBox(globalPos, entry)))
            Some({z = Scene.effectiveZIndexAt(entry#nodePath, scene),
                  entry = entry, globalPos = globalPos})
        else None

    /// hits の中から z 最大を返す。同値時は後発（preorder で後）を優先するため `>=` 比較
    def highestZ(hits: List[HitInfo]): Option[HitInfo] =
        List.foldLeft((best, cand) ->
            match best {
                case None    => Some(cand)
                case Some(b) => if (cand#z >= b#z) Some(cand) else best
            }, None, hits)

    /// グローバル位置と EditableEntry から表示矩形 Rect2 を作る
    pub def makeBBox(refPos: Vec2.Vec2,
                     entry: EditableNode.EditableEntry): Rect2.Rect2 =
        let topLeft = Vec2.add(refPos, entry#topLeftOffset);
        {position = topLeft, size = {x = entry#width, y = entry#height}}
}
