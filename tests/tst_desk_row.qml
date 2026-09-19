import QtQuick
import QtTest
import "../plugin" as Barbarian

// The desk chips' row: ReorderRow with variableWidths — tiles as wide as their names, the
// same pick-up, make-room and drop as the icon tiles.
Item {
  id: scene
  width: 700
  height: 200

  property int dropCount: 0
  property int activatedCount: 0
  property int activatedIndex: -1
  property int menuCount: 0
  property int selectedIndex: -1

  ListModel { id: desks }

  Barbarian.ReorderController {
    id: controller
    anchors.fill: parent
    rows: [row]
    motionDuration: 0
    onDropped: function(fromRow, fromIndex, toRow, toIndex) {
      scene.dropCount++
      if (fromIndex !== toIndex) desks.move(fromIndex, toIndex, 1)
    }
  }

  Barbarian.ReorderRow {
    id: row
    x: 20
    y: 40
    width: 660
    lane: "W"
    alignment: "center"
    variableWidths: true
    spacing: 4
    controller: controller
    model: desks
    tileHeight: 30
    verticalPadding: 18
    hysteresis: 3
    onSelected: function(index) { scene.selectedIndex = index }
    onActivated: function(index) { scene.activatedCount++; scene.activatedIndex = index }
    onMenuRequested: scene.menuCount++

    delegate: Rectangle {
      required property int index
      required property var model
      readonly property string identity: model.name
      x: row.itemX(index)
      y: row.verticalPadding
      width: model.w
      height: row.tileHeight
      visible: !row.isLifted(index)
      color: "#7aa2f7"
    }
  }

  TestCase {
    name: "DeskRow"
    when: windowShown
    property bool mouseHeld: false

    function fill(widths) {
      desks.clear()
      for (var i = 0; i < widths.length; i++) desks.append({ name: "D" + i, w: widths[i] })
    }

    function names() {
      var out = []
      for (var i = 0; i < desks.count; i++) out.push(desks.get(i).name)
      return out.join(",")
    }

    function pointerAt(x, y) {
      mouseMove(scene, x, y, 1, mouseHeld ? Qt.LeftButton : Qt.NoButton)
    }

    function centreOf(index) {
      var tile = row.itemAt(index)
      return row.mapToItem(scene, tile.x + tile.width / 2, row.verticalPadding + row.tileHeight / 2)
    }

    function begin(index) {
      var point = centreOf(index)
      pointerAt(point.x, point.y)
      mousePress(scene, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 1)
      mouseHeld = true
      pointerAt(point.x + Qt.styleHints.startDragDistance + 1, point.y)
      pointerAt(point.x + Qt.styleHints.startDragDistance + 2, point.y)
      tryCompare(controller, "active", true)
      return point
    }

    function release(x, y) {
      mouseRelease(scene, x, y, Qt.LeftButton, Qt.NoModifier, 1)
      mouseHeld = false
    }

    // Tiles never overlap and sit `spacing` apart, in model order.
    function verifyPacked() {
      for (var i = 1; i < desks.count; i++) {
        var before = row.itemAt(i - 1), after = row.itemAt(i)
        compare(after.x, before.x + before.width + row.spacing, "tile " + i + " sits right after tile " + (i - 1))
      }
    }

    function init() {
      controller.reset()
      controller.motionDuration = 0
      mouseHeld = false
      row.alignment = "center"
      row.reorderable = true
      row.ignoredIndex = -1
      fill([60, 90, 40, 120])
      scene.dropCount = 0
      scene.activatedCount = 0
      scene.activatedIndex = -1
      scene.menuCount = 0
      scene.selectedIndex = -1
      pointerAt(690, 190)
      wait(10)
    }

    function cleanup() {
      controller.reset()
      mouseRelease(scene, 690, 190, Qt.LeftButton, Qt.NoModifier, 1)
      mouseHeld = false
      wait(5)
    }

    function test_layout_data() {
      return [{ tag: "left", alignment: "left", start: 0 },
              { tag: "center", alignment: "center", start: Math.round((660 - 322) / 2) },
              { tag: "right", alignment: "right", start: 660 - 322 }]
    }

    // 60 + 90 + 40 + 120 wide, three 4px gaps: 322 in all.
    function test_layout(data) {
      row.alignment = data.alignment
      wait(10)
      compare(row.itemAt(0).x, data.start)
      verifyPacked()
    }

    function test_dragAcrossNeighbourMiddleSwaps() {
      begin(0)
      // D1's middle, halfway between where it stands with the gap before it and after it.
      var boundary = row.mapToItem(scene, row.landingBoundary(1, 0, 60), 0).x
      var y = centreOf(1).y
      pointerAt(boundary - row.hysteresis - 1, y)
      compare(controller.targetIndex, 0)
      pointerAt(boundary + row.hysteresis + 1, y)
      compare(controller.targetIndex, 1)
      // Inside the hysteresis band on the way back: it stays.
      pointerAt(boundary - 1, y)
      compare(controller.targetIndex, 1)
      pointerAt(boundary - row.hysteresis - 1, y)
      compare(controller.targetIndex, 0)
    }

    function test_dropReordersAndRepacks() {
      begin(0)
      var target = centreOf(3)
      pointerAt(target.x + 60, target.y)
      compare(controller.targetIndex, 3)
      release(target.x + 60, target.y)
      compare(scene.dropCount, 1)
      compare(names(), "D1,D2,D3,D0")
      wait(10)
      verifyPacked()
      compare(controller.busy, false)
    }

    function test_neighboursMakeRoomForTheDraggedWidth() {
      begin(3)
      var target = centreOf(0)
      pointerAt(target.x - 80, target.y)
      compare(controller.targetIndex, 0)
      // D0 moves right by the dragged tile's width plus a gap.
      compare(row.itemAt(0).x, row.landingX() + 120 + row.spacing)
    }

    function test_clickActivatesOnce() {
      var point = centreOf(2)
      mouseClick(scene, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 1)
      compare(scene.activatedCount, 1)
      compare(scene.activatedIndex, 2)
      compare(scene.dropCount, 0)
      compare(names(), "D0,D1,D2,D3")
    }

    function test_dragDoesNotActivate() {
      begin(1)
      var target = centreOf(3)
      pointerAt(target.x + 40, target.y)
      release(target.x + 40, target.y)
      compare(scene.dropCount, 1)
      compare(scene.activatedCount, 0)
    }

    function test_notReorderableStillClicksAndSelects() {
      row.reorderable = false
      var point = centreOf(1)
      pointerAt(point.x, point.y)
      mousePress(scene, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 1)
      mouseHeld = true
      pointerAt(point.x + 40, point.y)
      pointerAt(point.x + 80, point.y)
      compare(controller.active, false)
      release(point.x + 80, point.y)
      compare(names(), "D0,D1,D2,D3")
      mouseClick(scene, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 1)
      compare(scene.activatedIndex, 1)
      compare(scene.selectedIndex, 1)
    }

    function test_ignoredTileTakesNoPress() {
      row.ignoredIndex = 2
      var point = centreOf(2)
      mouseClick(scene, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 1)
      compare(scene.activatedCount, 0)
      var other = centreOf(1)
      mouseClick(scene, other.x, other.y, Qt.LeftButton, Qt.NoModifier, 1)
      compare(scene.activatedIndex, 1)
    }

    function test_rightClickOpensMenuOnly() {
      var point = centreOf(3)
      mouseClick(scene, point.x, point.y, Qt.RightButton, Qt.NoModifier, 1)
      compare(scene.menuCount, 1)
      compare(scene.activatedCount, 0)
    }

    function test_settleLandsOnTheFinalPlace() {
      controller.motionDuration = 60
      begin(0)
      var target = centreOf(2)
      pointerAt(target.x + 30, target.y)
      compare(controller.targetIndex, 2)
      release(target.x + 30, target.y)
      compare(names(), "D1,D2,D0,D3")
      tryCompare(controller, "settling", false)
      var landed = row.itemAt(2)
      compare(landed.identity, "D0")
      verifyPacked()
    }
  }
}
