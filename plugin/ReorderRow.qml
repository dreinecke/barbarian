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
  // Tiles of their own widths instead of equal slots (the desk chips, each as wide as its name),
  // `spacing` apart. The delegates' own widths are read, so a delegate must not size itself from
  // its position.
  property bool variableWidths: false
  property real spacing: 0
  // Bumped as delegates come and go, so positions that depend on a later tile's width are
  // worked out again once that tile exists.
  property int layoutVersion: 0
  // false: tiles can be clicked, selected and right-clicked but not picked up.
  property bool reorderable: true
  // A tile whose presses go to what it holds instead (a desk chip being renamed in place).
  property int ignoredIndex: -1
  readonly property int count: model.count
  readonly property bool removing: controller.active && controller.sourceRow === row
  readonly property bool receiving: controller.active && controller.targetRow === row
  readonly property int previewCount: count - (removing ? 1 : 0) + (receiving ? 1 : 0)
  readonly property real slotWidth: slotWidthFor(previewCount)
  readonly property int hoveredIndex: !controller.busy && pointer.containsMouse
    ? indexAt(pointer.mouseX, pointer.mouseY) : -1

  signal selected(int index)
  signal activated(int index)
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

  function widthOf(index) {
    void layoutVersion
    var tile = tiles.itemAt(index)
    return tile ? tile.width : 0
  }

  // Where a run of the given widths starts, so that it sits against the row's aligned edge.
  function variableStart(total) {
    if (alignment === "right") return width - total
    if (alignment === "center") return Math.round((width - total) / 2)
    return 0
  }

  // The left edges of `indices` laid side by side, with an extra `insertWidth` wide space before
  // position `insertAt` (-1 for none).
  function variableEdges(indices, insertAt, insertWidth) {
    var total = insertAt >= 0 ? insertWidth : 0
    for (var i = 0; i < indices.length; i++) total += widthOf(indices[i])
    var items = indices.length + (insertAt >= 0 ? 1 : 0)
    total += Math.max(0, items - 1) * spacing
    var x = variableStart(total), edges = []
    for (var j = 0; j < indices.length; j++) {
      if (j === insertAt) x += insertWidth + spacing
      edges.push(x)
      x += widthOf(indices[j]) + spacing
    }
    return edges
  }

  function remainingIndices(excluded) {
    var indices = []
    for (var i = 0; i < count; i++) if (i !== excluded) indices.push(i)
    return indices
  }

  function itemX(index) {
    if (variableWidths) {
      var indices = remainingIndices(removing ? controller.sourceIndex : -1)
      var edges = variableEdges(indices, receiving ? controller.targetIndex : -1, controller.previewWidth)
      var at = indices.indexOf(index)
      return at < 0 ? 0 : edges[at]
    }
    var position = index
    if (removing && index > controller.sourceIndex) position--
    if (receiving && position >= controller.targetIndex) position++
    return startFor(previewCount) + position * slotWidth + tileInset
  }

  // The landing position a dragged tile of width `draggedWidth` centred at `center` asks for,
  // counted among the row's tiles without `excluded` (the dragged tile, when it came from here).
  function landingIndexAt(center, excluded, draggedWidth) {
    var remaining = count - (excluded >= 0 ? 1 : 0)
    if (!variableWidths) {
      var step = slotWidthFor(remaining + 1)
      return Math.max(0, Math.min(remaining, Math.floor((center - startFor(remaining + 1)) / step)))
    }
    var index = 0
    while (index < remaining && landingBoundary(index + 1, excluded, draggedWidth) < center) index++
    return index
  }

  // Where landing position `k` meets `k - 1`. Equal slots: their shared edge. Tiles of their own
  // widths: halfway between the two places the tile before the gap can stand — so a tile swaps
  // with a neighbour as the dragged tile's centre passes the neighbour's middle, whichever side
  // the gap is on, and never swaps straight back.
  function landingBoundary(k, excluded, draggedWidth) {
    var remaining = count - (excluded >= 0 ? 1 : 0)
    if (!variableWidths) return startFor(remaining + 1) + k * slotWidthFor(remaining + 1)
    var indices = remainingIndices(excluded)
    var edges = variableEdges(indices, -1, 0)
    // The gap widens the run by the dragged tile, which moves the run's aligned start.
    var shift = (draggedWidth + spacing) / 2
    var offset = alignment === "right" ? -2 * shift : alignment === "center" ? -shift : 0
    return edges[k - 1] + offset + widthOf(indices[k - 1]) / 2 + shift
  }

  // Where the dragged tile would land, for a marker under the gap.
  function landingX() {
    if (!receiving) return 0
    var k = controller.targetIndex
    if (!variableWidths) return startFor(previewCount) + k * slotWidth + tileInset
    var indices = remainingIndices(removing ? controller.sourceIndex : -1)
    var edges = variableEdges(indices, k, controller.previewWidth)
    if (k < indices.length) return edges[k] - controller.previewWidth - spacing
    if (indices.length === 0) return variableStart(controller.previewWidth)
    var last = indices[indices.length - 1]
    return edges[indices.length - 1] + widthOf(last) + spacing
  }

  function isLifted(index) {
    return (controller.active && controller.sourceRow === row && controller.sourceIndex === index)
      || (controller.settling && controller.landingRow === row && controller.landingIndex === index)
  }

  function itemAt(index) { return tiles.itemAt(index) }

  function tileRect(index, destination) {
    var tile = itemAt(index)
    var y = destination || !tile ? verticalPadding : tile.y
    if (variableWidths) {
      var x = destination || !tile ? variableEdges(remainingIndices(-1), -1, 0)[index] : tile.x
      var p = mapToItem(controller, x, y)
      return Qt.rect(p.x, p.y, widthOf(index), tileHeight)
    }
    var step = slotWidthFor(count)
    var ux = destination || !tile ? startFor(count) + index * step + tileInset : tile.x
    var up = mapToItem(controller, ux, y)
    return Qt.rect(up.x, up.y, destination || !tile ? step - 2 * tileInset : tile.width, tileHeight)
  }

  function indexAt(x, y) {
    if (y < 0 || y > height) return -1
    var reach = variableWidths ? spacing / 2 : tileInset
    for (var i = 0; i < count; i++) {
      var tile = itemAt(i)
      if (tile && x >= tile.x - reach && x < tile.x + tile.width + reach) return i
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
    onItemAdded: row.layoutVersion++
    onItemRemoved: row.layoutVersion++
  }

  // A move renumbers the tiles while the Repeater is still reordering them, so a position
  // worked out in the middle of it can read the wrong tile's width. Once it has settled,
  // everything is worked out again.
  Connections {
    target: row.variableWidths ? row.model : null
    function onRowsMoved() { Qt.callLater(function() { row.layoutVersion++ }) }
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
    drag.target: row.reorderable ? dragHandle : null
    drag.axis: Drag.XAndYAxis
    property int pressedIndex: -1
    property point pressPosition: Qt.point(0, 0)

    onEntered: {
      if (row.hoveredIndex >= 0) row.selected(row.hoveredIndex)
    }

    onPressed: function(mouse) {
      if (row.controller.settling) row.controller.reset()
      pressedIndex = row.indexAt(mouse.x, mouse.y)
      if (pressedIndex < 0 || pressedIndex === row.ignoredIndex) {
        pressedIndex = -1
        mouse.accepted = false
        return
      }
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
      } else if (pressedIndex >= 0 && !row.controller.busy && row.indexAt(mouse.x, mouse.y) === pressedIndex) {
        row.activated(pressedIndex)
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
