// Tests for CameraScene — カメラ追従設定とビューポートオフセット
// 共通ヘルパーは TestGame.flix を参照

// ========================================================================
// カメラの初期構築
// ========================================================================

/// カメラの初期状態（enabled / anchor / offset / position）
///   addCamera は鳥の初期 X (144) に配置、FixedTopLeft、offset=(-72, 0) で有効化される
@Test
def testCameraInitialState(): Unit \ Assert =
    match Scene.getEngineNode("camera" :: Nil, testScene()) {
        case Some(EngineNode.Camera2DWithState(cam, _)) =>
            Assert.assertEq(
                expected = (true, Camera2DAnchorMode.FixedTopLeft, (-72.0, 0.0), (144.0, 0.0)),
                (Camera2D.isEnabled(cam),
                 Camera2D.getAnchorMode(cam),
                 vecToTuple(Camera2D.getOffset(cam)),
                 vecToTuple(Node2D.getPosition(cam))))
        case _ => bug!("camera not found")
    }

// ========================================================================
// Camera2D ビューポートオフセット（CameraScene が依存する挙動）
// ========================================================================

/// FixedTopLeft では position+offset がビューポート左上、
/// DragCenter では position+offset がビューポート中心になる
///
///   FixedTopLeft: pos=(200, 0), offset=(-72, 0), viewport=288x512
///                 → 左上 = (200-72, 0) = (128, 0)
///   DragCenter:   pos=(200, 256), offset=(0, 0), viewport=288x512
///                 → 左上 = (200-144, 256-256) = (56, 0)
@Test
def testCameraViewportOffsetByAnchorMode(): Unit \ Assert =
    let viewport = {viewportWidth = 288.0, viewportHeight = 512.0};
    let fixedCam = Camera2D.makeWithOffset({x = 200.0, y = 0.0}, {x = -72.0, y = 0.0})
        |> Camera2D.setAnchorMode(Camera2DAnchorMode.FixedTopLeft);
    let dragCam = Camera2D.make({x = 200.0, y = 256.0});
    Assert.assertEq(
        expected = ((128.0, 0.0), (56.0, 0.0)),
        (vecToTuple(Camera2D.getViewportOffset(fixedCam, viewport)),
         vecToTuple(Camera2D.getViewportOffset(dragCam, viewport))))
