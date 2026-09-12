import QtQuick
import QtTest
import "../plugin" as Barbarian

Item {
  id: scene
  width: 700
  height: 360

  property int dropCount: 0
  property int cancelCount: 0
  property int menuCount: 0
  property int selectionCount: 0
  property int selectedIndex: -1
  property string selectedLane: ""
  property var lastDrop: ({})

  ListModel { id: leftModel }
  ListModel { id: rightModel }

  Barbarian.ReorderController {
    id: controller
    anchors.fill: parent
    rows: [leftRow, rightRow]
    motionDuration: 0
    onDragCancelled: scene.cancelCount++
    onDropped: function(fromRow, fromIndex, toRow, toIndex) {
      scene.dropCount++
      scene.lastDrop = { fromLane: fromRow.lane, fromIndex: fromIndex,
                         toLane: toRow.lane, toIndex: toIndex }
      if (fromRow === toRow) {
        if (fromIndex !== toIndex) fromRow.model.move(fromIndex, toIndex, 1)
        return
      }
      var entry = JSON.parse(JSON.stringify(fromRow.model.get(fromIndex)))
      fromRow.model.remove(fromIndex)
      toRow.model.insert(toIndex, entry)
    }
  }

  Component {
    id: tileDelegate
    Rectangle {
      required property int index
      required property var model
      readonly property var row: parent
      readonly property string identity: model.uid
      x: row.itemX(index)
      y: row.verticalPadding
      width: row.slotWidth - row.tileInset * 2
      height: row.tileHeight
      radius: 5
      visible: !row.isLifted(index)
      color: model.wid === "omarchy.spacer" ? "#777777" : "#7aa2f7"
      Behavior on x {
        NumberAnimation { duration: controller.motionDuration; easing.type: Easing.OutCubic }
      }
      Behavior on width {
        NumberAnimation { duration: controller.motionDuration; easing.type: Easing.OutCubic }
      }
    }
  }

  Barbarian.ReorderRow {
    id: leftRow
    x: 30
    y: 20
    width: 620
    lane: "L"
    controller: controller
    model: leftModel
    delegate: tileDelegate
    onSelected: function(index) {
      scene.selectionCount++
      scene.selectedLane = lane
      scene.selectedIndex = index
    }
    onMenuRequested: scene.menuCount++
  }

  Barbarian.ReorderRow {
    id: rightRow
    x: 30
    y: 210
    width: 620
    lane: "R"
    alignment: "right"
    controller: controller
    model: rightModel
    delegate: tileDelegate
    onSelected: function(index) {
      scene.selectionCount++
      scene.selectedLane = lane
      scene.selectedIndex = index
    }
    onMenuRequested: scene.menuCount++
  }

  Rectangle {
    x: controller.previewX
    y: controller.previewY
    width: controller.previewWidth
    height: controller.previewHeight
    visible: controller.busy
    color: "#f7768e"
    radius: 5
    z: 10
  }

  TestCase {
    id: tests
    name: "Reorder"
    when: windowShown
    property bool mouseHeld: false

    function fill(model, prefix, count) {
      model.clear()
      for (var i = 0; i < count; i++)
        model.append({ uid: prefix + i, wid: i === 1 || i === 3 ? "omarchy.spacer" : "widget." + prefix + i,
                       label: prefix + i, glyph: "", hid: false, lit: true })
    }

    function identities(model) {
      var result = []
      for (var i = 0; i < model.count; i++) result.push(model.get(i).uid)
      return result.join(",")
    }

    function tilePoint(row, index, offsetX, offsetY) {
      var rect = row.tileRect(index)
      return Qt.point(rect.x + (offsetX === undefined ? rect.width / 2 : offsetX),
                      rect.y + (offsetY === undefined ? rect.height / 2 : offsetY))
    }

    function pointerAt(x, y) {
      mouseMove(scene, x, y, 1, mouseHeld ? Qt.LeftButton : Qt.NoButton)
    }

    function press(row, index, offsetX, offsetY) {
      var point = tilePoint(row, index, offsetX, offsetY)
      pointerAt(point.x, point.y)
      mousePress(scene, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 1)
      mouseHeld = true
      compare(scene.selectedLane, row.lane)
      compare(scene.selectedIndex, index)
      return point
    }

    function begin(row, index, offsetX, offsetY) {
      var point = press(row, index, offsetX, offsetY)
      pointerAt(point.x + Qt.styleHints.startDragDistance + 1, point.y)
      pointerAt(point.x + Qt.styleHints.startDragDistance + 2, point.y)
      tryCompare(controller, "active", true)
      return point
    }

    function release(point) {
      mouseRelease(scene, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 1)
      mouseHeld = false
    }

    function centerOfSlot(row, index) {
      var count = row.count + (controller.sourceRow === row ? 0 : 1)
      var x = row.startFor(count) + (index + 0.5) * row.slotWidthFor(count)
      return row.mapToItem(scene, x, row.verticalPadding + row.tileHeight / 2)
    }

    function init() {
      controller.reset()
      controller.enabled = true
      mouseHeld = false
      controller.motionDuration = 0
      leftRow.width = 620
      rightRow.width = 620
      leftRow.verticalPadding = 18
      rightRow.verticalPadding = 18
      leftRow.alignment = "left"
      rightRow.alignment = "right"
      leftRow.visible = true
      rightRow.visible = true
      leftRow.enabled = true
      rightRow.enabled = true
      fill(leftModel, "L", 5)
      fill(rightModel, "R", 4)
      scene.dropCount = 0
      scene.cancelCount = 0
      scene.menuCount = 0
      scene.selectionCount = 0
      scene.selectedIndex = -1
      scene.selectedLane = ""
      scene.lastDrop = ({})
      pointerAt(680, 330)
      wait(10)
    }

    function cleanup() {
      controller.reset()
      mouseRelease(scene, 680, 330, Qt.LeftButton, Qt.NoModifier, 1)
      mouseHeld = false
      wait(5)
    }

    function test_preservesGrabOffset() {
      var point = begin(leftRow, 1, 7, 8)
      compare(controller.grabOffset.x, 7)
      compare(controller.grabOffset.y, 8)
      compare(controller.previewX, point.x + Qt.styleHints.startDragDistance + 2 - 7)
      compare(controller.previewY, point.y - 8)
      compare(controller.entry.uid, "L1")
      compare(identities(leftModel), "L0,L1,L2,L3,L4")
    }

    function test_stationaryPointerDoesNotDrift() {
      controller.motionDuration = 160
      begin(leftRow, 0)
      var point = centerOfSlot(leftRow, 3)
      pointerAt(point.x, point.y)
      compare(controller.targetIndex, 3)
      var previewX = controller.previewX
      var previewY = controller.previewY
      var neighborStart = leftRow.itemAt(1).x
      wait(220)
      compare(controller.previewX, previewX)
      compare(controller.previewY, previewY)
      compare(controller.targetIndex, 3)
      verify(leftRow.itemAt(1).x < neighborStart, "Neighbor should animate while ghost remains fixed")
      compare(identities(leftModel), "L0,L1,L2,L3,L4")
    }

    function test_hysteresisReversal() {
      begin(leftRow, 0)
      var boundary = leftRow.mapToItem(scene, leftRow.slotWidthFor(leftRow.count),
                                        leftRow.verticalPadding + leftRow.tileHeight / 2)
      pointerAt(boundary.x + 1, boundary.y)
      compare(controller.targetIndex, 0)
      pointerAt(boundary.x + leftRow.hysteresis + 1, boundary.y)
      compare(controller.targetIndex, 1)
      pointerAt(boundary.x - 1, boundary.y)
      compare(controller.targetIndex, 1)
      pointerAt(boundary.x - leftRow.hysteresis - 1, boundary.y)
      compare(controller.targetIndex, 0)
    }

    function test_sameRowDropCommitsOnce() {
      begin(leftRow, 0)
      var point = centerOfSlot(leftRow, 3)
      pointerAt(point.x, point.y)
      compare(scene.dropCount, 0)
      compare(identities(leftModel), "L0,L1,L2,L3,L4")
      release(point)
      compare(scene.dropCount, 1)
      compare(identities(leftModel), "L1,L2,L3,L0,L4")
      compare(controller.busy, false)
    }

    function test_crossRowDropCommitsOnce() {
      begin(leftRow, 2)
      var point = centerOfSlot(rightRow, 2)
      pointerAt(point.x, point.y)
      compare(controller.targetRow, rightRow)
      compare(controller.targetIndex, 2)
      compare(identities(leftModel), "L0,L1,L2,L3,L4")
      compare(identities(rightModel), "R0,R1,R2,R3")
      release(point)
      compare(scene.dropCount, 1)
      compare(identities(leftModel), "L0,L1,L3,L4")
      compare(identities(rightModel), "R0,R1,L2,R2,R3")
    }

    function test_emptyLaneAcceptsDrop() {
      rightModel.clear()
      wait(10)
      begin(leftRow, 2)
      var point = rightRow.mapToItem(scene, rightRow.width / 2, rightRow.height / 2)
      pointerAt(point.x, point.y)
      compare(controller.targetRow, rightRow)
      compare(controller.targetIndex, 0)
      release(point)
      compare(identities(rightModel), "L2")
      compare(identities(leftModel), "L0,L1,L3,L4")
    }

    function test_alignmentWidthChange_data() {
      return [{ tag: "right", alignment: "right" }, { tag: "center", alignment: "center" }]
    }

    function test_alignmentWidthChange(data) {
      rightRow.width = 220
      rightRow.alignment = data.alignment
      fill(rightModel, "R", 6)
      wait(10)
      controller.motionDuration = 160
      begin(leftRow, 0)
      var point = centerOfSlot(rightRow, 6)
      pointerAt(point.x, point.y)
      compare(controller.targetIndex, 6)
      wait(220)
      compare(rightRow.slotWidth, 24)
      release(point)
      compare(controller.settling, true)
      compare(controller.landingRow, rightRow)
      compare(controller.landingIndex, 6)
      var rect = rightRow.tileRect(6, true)
      tryCompare(controller, "settling", false)
      compare(controller.previewX, rect.x)
      compare(controller.previewY, rect.y)
      compare(controller.previewWidth, rect.width)
      compare(rightRow.itemAt(6).identity, "L0")
      compare(rightRow.itemAt(6).x, rect.x - rightRow.x)
    }

    function test_clickAndSubthresholdMotionDoNotReorder() {
      var point = press(leftRow, 2)
      pointerAt(point.x + Math.max(0, Qt.styleHints.startDragDistance - 1), point.y)
      compare(controller.active, false)
      release(point)
      compare(scene.dropCount, 0)
      compare(identities(leftModel), "L0,L1,L2,L3,L4")
      mouseClick(scene, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 1)
      compare(controller.busy, false)
      compare(scene.dropCount, 0)
    }

    function test_rightClickOnlyOpensMenu() {
      var point = tilePoint(leftRow, 2)
      mouseClick(scene, point.x, point.y, Qt.RightButton, Qt.NoModifier, 1)
      compare(scene.menuCount, 1)
      compare(controller.busy, false)
      compare(scene.dropCount, 0)
      compare(identities(leftModel), "L0,L1,L2,L3,L4")
    }

    function test_cancelKeepsOrderAndDoesNotRestart() {
      begin(leftRow, 0)
      var point = centerOfSlot(rightRow, 1)
      pointerAt(point.x, point.y)
      controller.cancel()
      compare(scene.cancelCount, 1)
      compare(controller.busy, false)
      pointerAt(point.x + 30, point.y)
      compare(controller.busy, false)
      release(Qt.point(point.x + 30, point.y))
      compare(scene.dropCount, 0)
      compare(identities(leftModel), "L0,L1,L2,L3,L4")
      compare(identities(rightModel), "R0,R1,R2,R3")
    }

    function test_invalidDrop_data() {
      return [{ tag: "workspace-gap", x: 330, y: 150 },
              { tag: "left-of-row", x: 10, y: 240 },
              { tag: "right-of-row", x: 680, y: 240 },
              { tag: "above-row", x: 80, y: 5 }]
    }

    function test_invalidDrop(data) {
      begin(leftRow, 0)
      pointerAt(data.x, data.y)
      compare(controller.targetRow, null)
      release(Qt.point(data.x, data.y))
      compare(scene.dropCount, 0)
      compare(scene.cancelCount, 1)
      compare(controller.busy, false)
      compare(identities(leftModel), "L0,L1,L2,L3,L4")
    }

    function test_disabledAndHiddenRowsRejectDrop() {
      begin(leftRow, 0)
      rightRow.enabled = false
      var point = rightRow.mapToItem(scene, rightRow.width / 2, rightRow.height / 2)
      pointerAt(point.x, point.y)
      compare(controller.targetRow, null)
      rightRow.enabled = true
      rightRow.visible = false
      pointerAt(point.x + 10, point.y)
      compare(controller.targetRow, null)
      release(point)
      compare(scene.dropCount, 0)
    }

    function test_duplicateSpacersPreserveIdentityDuringSettling() {
      controller.motionDuration = 160
      begin(leftRow, 1)
      var point = centerOfSlot(leftRow, 4)
      pointerAt(point.x, point.y)
      release(point)
      compare(identities(leftModel), "L0,L2,L3,L4,L1")
      compare(controller.settling, true)
      compare(controller.entry.uid, "L1")
      compare(leftRow.itemAt(2).identity, "L3")
      verify(leftRow.itemAt(2).visible)
      verify(!leftRow.itemAt(4).visible)
      tryCompare(controller, "settling", false)
      verify(leftRow.itemAt(4).visible)
      compare(leftRow.itemAt(4).identity, "L1")
    }

    function test_modelChangeCancelsActivePreview() {
      begin(leftRow, 0)
      leftModel.append({ uid: "new", wid: "widget.new", label: "New", glyph: "", hid: false, lit: true })
      compare(controller.busy, false)
      pointerAt(330, 240)
      compare(controller.busy, false)
      release(Qt.point(330, 240))
      compare(scene.dropCount, 0)
    }

    function test_nativeGrabCancellationRestoresOrder() {
      controller.motionDuration = 160
      begin(leftRow, 0)
      var point = centerOfSlot(leftRow, 3)
      pointerAt(point.x, point.y)
      leftRow.enabled = false
      tryCompare(controller, "active", false)
      compare(scene.cancelCount, 1)
      tryCompare(controller, "settling", false)
      leftRow.enabled = true
      pointerAt(point.x + 10, point.y)
      compare(controller.busy, false)
      release(Qt.point(point.x + 10, point.y))
      compare(scene.dropCount, 0)
      compare(identities(leftModel), "L0,L1,L2,L3,L4")
    }

    function test_immediateDragDuringSettling() {
      controller.motionDuration = 160
      begin(leftRow, 0)
      var point = centerOfSlot(leftRow, 3)
      pointerAt(point.x, point.y)
      release(point)
      compare(controller.settling, true)
      begin(rightRow, 1)
      compare(controller.active, true)
      compare(controller.settling, false)
      compare(controller.entry.uid, "R1")
      point = centerOfSlot(rightRow, 3)
      pointerAt(point.x, point.y)
      release(point)
      tryCompare(controller, "settling", false)
      compare(scene.dropCount, 2)
      compare(identities(leftModel), "L1,L2,L3,L0,L4")
      compare(identities(rightModel), "R0,R2,R3,R1")
    }

    function test_crossRowDuplicateSpacerIdentity() {
      begin(leftRow, 3)
      var point = centerOfSlot(rightRow, 1)
      pointerAt(point.x, point.y)
      release(point)
      compare(identities(leftModel), "L0,L1,L2,L4")
      compare(identities(rightModel), "R0,L3,R1,R2,R3")
      compare(rightModel.get(1).wid, "omarchy.spacer")
      compare(rightModel.get(2).wid, "omarchy.spacer")
      compare(rightModel.get(4).wid, "omarchy.spacer")
      compare(leftModel.get(1).uid, "L1")
    }

    function test_dragBackToOriginalSlotDoesNotChangeOrder() {
      begin(leftRow, 2)
      var point = centerOfSlot(rightRow, 4)
      pointerAt(point.x, point.y)
      point = centerOfSlot(leftRow, 2)
      pointerAt(point.x, point.y)
      compare(controller.targetRow, leftRow)
      compare(controller.targetIndex, 2)
      release(point)
      compare(identities(leftModel), "L0,L1,L2,L3,L4")
      compare(identities(rightModel), "R0,R1,R2,R3")
    }

    function test_stationaryHoverKeepsKeyboardSelection() {
      controller.motionDuration = 160
      var point = tilePoint(leftRow, 0)
      pointerAt(point.x, point.y)
      compare(scene.selectedIndex, 0)
      var selectionCount = scene.selectionCount
      leftModel.move(0, 3, 1)
      scene.selectedIndex = 3
      wait(220)
      compare(scene.selectionCount, selectionCount)
      compare(scene.selectedIndex, 3)
      compare(leftModel.get(scene.selectedIndex).uid, "L0")
      pointerAt(point.x + 1, point.y)
      verify(scene.selectionCount > selectionCount)
      compare(scene.selectedIndex, 0)
      compare(leftModel.get(scene.selectedIndex).uid, "L1")
    }

    function test_stationaryHoverKeepsSelectionWhenModelInserts() {
      var point = tilePoint(rightRow, 1)
      pointerAt(point.x, point.y)
      compare(scene.selectedIndex, 1)
      var selectionCount = scene.selectionCount
      rightModel.insert(0, { uid: "new", wid: "widget.new", label: "New", glyph: "", hid: false, lit: true })
      scene.selectedIndex = 0
      wait(20)
      compare(scene.selectionCount, selectionCount)
      compare(scene.selectedIndex, 0)
      pointerAt(point.x + 1, point.y)
      verify(scene.selectionCount > selectionCount)
      compare(scene.selectedIndex, 2)
      compare(rightModel.get(scene.selectedIndex).uid, "R1")
    }

    function test_disabledControllerCannotStartDrag() {
      controller.enabled = false
      var point = tilePoint(leftRow, 0)
      mousePress(scene, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 1)
      mouseHeld = true
      pointerAt(point.x + Qt.styleHints.startDragDistance + 1, point.y)
      pointerAt(point.x + Qt.styleHints.startDragDistance + 2, point.y)
      compare(controller.busy, false)
      release(point)
      compare(scene.dropCount, 0)
      compare(identities(leftModel), "L0,L1,L2,L3,L4")
      controller.enabled = true
    }

    function test_rowResizeCancelsActiveDrag_data() {
      return [{ tag: "source-width", target: false, dimension: "width", size: 160 },
              { tag: "destination-width", target: true, dimension: "width", size: 170 },
              { tag: "source-height", target: false, dimension: "verticalPadding", size: 20 },
              { tag: "destination-height", target: true, dimension: "verticalPadding", size: 20 }]
    }

    function test_rowResizeCancelsActiveDrag(data) {
      begin(leftRow, 0)
      var row = data.target ? rightRow : leftRow
      var point = centerOfSlot(row, 3)
      pointerAt(point.x, point.y)
      compare(controller.targetIndex, 3)
      row[data.dimension] = data.size
      compare(controller.active, false)
      pointerAt(point.x + 1, point.y)
      compare(controller.active, false)
      release(Qt.point(point.x + 1, point.y))
      compare(scene.dropCount, 0)
      compare(identities(leftModel), "L0,L1,L2,L3,L4")
      compare(identities(rightModel), "R0,R1,R2,R3")
    }

    function test_resizeDuringSettlingResetsGhost() {
      controller.motionDuration = 160
      begin(leftRow, 2)
      var point = centerOfSlot(rightRow, 2)
      pointerAt(point.x, point.y)
      release(point)
      compare(controller.settling, true)
      compare(rightRow.itemAt(2).visible, false)
      rightRow.width = 220
      compare(controller.busy, false)
      compare(controller.landingRow, null)
      compare(rightRow.itemAt(2).visible, true)
      compare(rightRow.itemAt(2).identity, "L2")
      wait(220)
      compare(scene.dropCount, 1)
      compare(identities(leftModel), "L0,L1,L3,L4")
      compare(identities(rightModel), "R0,R1,L2,R2,R3")
    }
  }
}
