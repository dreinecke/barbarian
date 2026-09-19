import QtQuick

Item {
  id: controller

  property var rows: []
  property int motionDuration: 160
  property bool active: false
  property bool settling: false
  readonly property bool busy: active || settling
  property Item sourceRow: null
  property int sourceIndex: -1
  property Item targetRow: null
  property int targetIndex: -1
  property Item landingRow: null
  property int landingIndex: -1
  property var entry: ({})
  property point grabOffset: Qt.point(0, 0)
  property real previewX: 0
  property real previewY: 0
  property real previewWidth: 0
  property real previewHeight: 0

  signal dropped(Item fromRow, int fromIndex, Item toRow, int toIndex)
  signal dragCancelled()

  function begin(row, index, press, pointer) {
    reset()
    if (!enabled || index < 0 || index >= row.count) return
    var rect = row.tileRect(index)
    sourceRow = row
    sourceIndex = index
    entry = JSON.parse(JSON.stringify(row.model.get(index)))
    grabOffset = Qt.point(press.x - rect.x, press.y - rect.y)
    previewWidth = rect.width
    previewHeight = rect.height
    targetRow = row
    targetIndex = index
    active = true
    update(pointer)
  }

  function update(pointer) {
    if (!active) return
    previewX = pointer.x - grabOffset.x
    previewY = pointer.y - grabOffset.y
    var row = null
    for (var i = 0; i < rows.length; i++) {
      var candidate = rows[i]
      if (!candidate.visible || !candidate.enabled) continue
      var local = candidate.mapFromItem(controller, pointer.x, pointer.y)
      if (local.x < 0 || local.x > candidate.width || local.y < 0 || local.y > candidate.height) continue
      row = candidate
      break
    }
    if (!row) {
      targetRow = null
      targetIndex = -1
      return
    }
    var center = row.mapFromItem(controller, previewX + previewWidth / 2, previewY).x
    var excluded = row === sourceRow ? sourceIndex : -1
    var index = row.landingIndexAt(center, excluded, previewWidth)
    if (row === targetRow && index !== targetIndex) {
      var boundary = row.landingBoundary(index > targetIndex ? targetIndex + 1 : targetIndex,
                                         excluded, previewWidth)
      if (Math.abs(center - boundary) < row.hysteresis) return
    }
    targetRow = row
    targetIndex = index
  }

  function drop() {
    if (!active) return
    if (!targetRow) { cancel(); return }
    var from = sourceRow, fromIndex = sourceIndex
    var into = targetRow, intoIndex = targetIndex
    active = false
    landingRow = into
    landingIndex = intoIndex
    settling = true
    dropped(from, fromIndex, into, intoIndex)
    settle(into.tileRect(intoIndex, true))
  }

  function cancel() {
    if (!active) return
    var row = sourceRow, index = sourceIndex
    active = false
    landingRow = row
    landingIndex = index
    settling = true
    dragCancelled()
    settle(row.tileRect(index, true))
  }

  function settle(rect) {
    if (motionDuration <= 0) { reset(); return }
    landX.to = rect.x
    landY.to = rect.y
    landWidth.to = rect.width
    landing.restart()
  }

  function reset() {
    landing.stop()
    active = false
    settling = false
    sourceRow = null
    sourceIndex = -1
    targetRow = null
    targetIndex = -1
    landingRow = null
    landingIndex = -1
  }

  ParallelAnimation {
    id: landing
    onFinished: controller.reset()
    NumberAnimation { id: landX; target: controller; property: "previewX"; duration: controller.motionDuration; easing.type: Easing.OutCubic }
    NumberAnimation { id: landY; target: controller; property: "previewY"; duration: controller.motionDuration; easing.type: Easing.OutCubic }
    NumberAnimation { id: landWidth; target: controller; property: "previewWidth"; duration: controller.motionDuration; easing.type: Easing.OutCubic }
  }
}
