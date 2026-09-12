import QtQuick
import "." as Reordering

Item {
  id: row

  required property Reordering.ReorderController controller
  required property var model
  required property Component delegate
  property string lane: ""
  property string alignment: "left"
  property real maximumSlotWidth: 32
  property real minimumSlotWidth: 22
  property real tileInset: 2
  property real tileHeight: 30
  property real verticalPadding: 18
  property real hysteresis: 3
  readonly property int count: model.count
  readonly property bool removing: controller.active && controller.sourceRow === row
  readonly property bool receiving: controller.active && controller.targetRow === row
  readonly property int previewCount: count - (removing ? 1 : 0) + (receiving ? 1 : 0)
  readonly property real slotWidth: slotWidthFor(previewCount)
  readonly property int hoveredIndex: !controller.busy && pointer.containsMouse
    ? indexAt(pointer.mouseX, pointer.mouseY) : -1

  signal selected(int index)
  signal menuRequested(int index, Item anchor)

  height: tileHeight + verticalPadding * 2

  function slotWidthFor(itemCount) {
    return Math.max(minimumSlotWidth, Math.min(maximumSlotWidth, Math.floor(width / (itemCount + 2))))
  }

  function startFor(itemCount) {
    var step = slotWidthFor(itemCount)
    if (alignment === "right") return width - itemCount * step
    if (alignment === "center") return Math.round((width - (itemCount + 2) * step) / 2)
    return 0
  }

  function itemX(index) {
    var position = index
    if (removing && index > controller.sourceIndex) position--
    if (receiving && position >= controller.targetIndex) position++
    return startFor(previewCount) + position * slotWidth + tileInset
  }

  function isLifted(index) {
    return (controller.active && controller.sourceRow === row && controller.sourceIndex === index)
      || (controller.settling && controller.landingRow === row && controller.landingIndex === index)
  }

  function itemAt(index) { return tiles.itemAt(index) }

  function tileRect(index, destination) {
    var tile = itemAt(index)
    var step = slotWidthFor(count)
    var x = destination || !tile ? startFor(count) + index * step + tileInset : tile.x
    var y = destination || !tile ? verticalPadding : tile.y
    var p = mapToItem(controller, x, y)
    return Qt.rect(p.x, p.y, destination || !tile ? step - 2 * tileInset : tile.width, tileHeight)
  }

  function indexAt(x, y) {
    if (y < 0 || y > height) return -1
    for (var i = 0; i < count; i++) {
      var tile = itemAt(i)
      if (tile && x >= tile.x - tileInset && x < tile.x + tile.width + tileInset) return i
    }
    return -1
  }

  function cancelForGeometryChange() {
    if (!controller || (controller.sourceRow !== row && controller.targetRow !== row
      && controller.landingRow !== row)) return
    if (controller.active) controller.cancel()
    else if (controller.settling) controller.reset()
  }

  onVisibleChanged: if (!visible && controller.sourceRow === row) controller.reset()
  onCountChanged: if (controller.active) controller.reset()
  onWidthChanged: cancelForGeometryChange()
  onHeightChanged: cancelForGeometryChange()

  Repeater {
    id: tiles
    model: row.model
    delegate: row.delegate
  }

  Item { id: dragHandle }

  MouseArea {
    id: pointer
    anchors.fill: parent
    z: 1
    enabled: row.controller.enabled
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: row.controller.active ? Qt.ClosedHandCursor
      : row.hoveredIndex >= 0 ? Qt.OpenHandCursor : Qt.ArrowCursor
    drag.target: dragHandle
    drag.axis: Drag.XAndYAxis
    property int pressedIndex: -1
    property point pressPosition: Qt.point(0, 0)

    onEntered: {
      if (row.hoveredIndex >= 0) row.selected(row.hoveredIndex)
    }

    onPressed: function(mouse) {
      if (row.controller.settling) row.controller.reset()
      pressedIndex = row.indexAt(mouse.x, mouse.y)
      if (pressedIndex < 0) { mouse.accepted = false; return }
      pressPosition = mapToItem(row.controller, mouse.x, mouse.y)
      row.selected(pressedIndex)
    }
    drag.onActiveChanged: {
      if (drag.active && pressedIndex >= 0)
        row.controller.begin(row, pressedIndex, pressPosition,
          pointer.mapToItem(row.controller, pointer.mouseX, pointer.mouseY))
    }
    onPositionChanged: function(mouse) {
      if (row.controller.active && row.controller.sourceRow === row)
        row.controller.update(mapToItem(row.controller, mouse.x, mouse.y))
      else if (!row.controller.busy && !pressed) {
        var index = row.indexAt(mouse.x, mouse.y)
        if (index >= 0) row.selected(index)
      }
    }
    onReleased: function(mouse) {
      if (row.controller.active && row.controller.sourceRow === row) {
        row.controller.update(mapToItem(row.controller, mouse.x, mouse.y))
        row.controller.drop()
      }
      pressedIndex = -1
    }
    onCanceled: {
      if (row.controller.sourceRow === row) row.controller.cancel()
      pressedIndex = -1
    }
  }

  TapHandler {
    acceptedButtons: Qt.RightButton
    enabled: !row.controller.busy
    onTapped: function(eventPoint) {
      var index = row.indexAt(eventPoint.position.x, eventPoint.position.y)
      if (index >= 0) row.menuRequested(index, row.itemAt(index))
    }
  }
}
