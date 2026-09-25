import QtQuick
import qs.Commons
import qs.Ui

// The grid: sections of theme cards, a footer naming the selected theme with its action, and the
// confirmation. It draws and routes keys; ThemeStore does the work.
Item {
  id: view

  property var store: null
  property string filterText: ""
  property int selectedIndex: 0
  property string selectedSlug: ""
  property var pendingAction: null

  signal closeRequested()

  readonly property int cardWidth: 300
  readonly property int imageHeight: Math.round(cardWidth * 9 / 16)
  readonly property int labelHeight: 30
  readonly property int gap: 16
  readonly property int columns: Math.max(1, Math.min(6, Math.floor((width * 0.82 + gap) / (cardWidth + gap))))
  readonly property int gridWidth: columns * cardWidth + (columns - 1) * gap

  readonly property var sections: buildSections(store ? store.themes : [], filterText)
  readonly property var sectionOffsets: offsetsFor(sections)
  readonly property int themeCount: sectionOffsets.length ? sectionOffsets[sectionOffsets.length - 1] : 0
  readonly property var selectedTheme: themeAt(selectedIndex)
  readonly property int brokenCount: countKind(store ? store.themes : [], "broken")

  function countKind(themes, kind) {
    var n = 0
    for (var i = 0; i < themes.length; i++) if (themes[i].kind === kind) n++
    return n
  }

  function matchesFilter(theme, filter) {
    if (!filter) return true
    var f = filter.toLowerCase()
    return theme.label.toLowerCase().indexOf(f) !== -1 || theme.slug.indexOf(f) !== -1
  }

  function byLabel(a, b) { return a.label.localeCompare(b.label) }

  function buildSections(themes, filter) {
    var groups = {
      installed: { key: "installed", title: "Installed", tone: "accent", themes: [] },
      stock: { key: "stock", title: "Omarchy defaults", tone: "foreground", themes: [] },
      hidden: { key: "hidden", title: "Hidden from Omarchy's picker", tone: "muted", themes: [] },
      broken: { key: "broken", title: "Broken links", tone: "urgent", themes: [] }
    }
    for (var i = 0; i < themes.length; i++) {
      var t = themes[i]
      if (!matchesFilter(t, filter)) continue
      if (t.kind === "broken") groups.broken.themes.push(t)
      else if (t.kind === "stock") (t.hidden ? groups.hidden : groups.stock).themes.push(t)
      else groups.installed.themes.push(t)
    }
    var out = []
    var order = ["installed", "stock", "hidden", "broken"]
    for (var j = 0; j < order.length; j++) {
      var g = groups[order[j]]
      g.themes.sort(byLabel)
      if (g.themes.length > 0) out.push(g)
    }
    return out
  }

  function offsetsFor(list) {
    var offsets = [0]
    for (var i = 0; i < list.length; i++) offsets.push(offsets[i] + list[i].themes.length)
    return offsets
  }

  function locate(flatIndex) {
    for (var s = 0; s < sections.length; s++) {
      if (flatIndex < sectionOffsets[s + 1]) return { section: s, index: flatIndex - sectionOffsets[s] }
    }
    return null
  }

  function themeAt(flatIndex) {
    var at = locate(flatIndex)
    return at ? sections[at.section].themes[at.index] : null
  }

  function indexOfSlug(slug) {
    for (var s = 0; s < sections.length; s++) {
      var list = sections[s].themes
      for (var i = 0; i < list.length; i++) if (list[i].slug === slug) return sectionOffsets[s] + i
    }
    return -1
  }

  // Reads sectionOffsets rather than themeCount: this runs from onSectionOffsetsChanged, before
  // the bindings that hang off sectionOffsets have caught up.
  function select(flatIndex) {
    var count = sectionOffsets[sectionOffsets.length - 1] || 0
    if (count === 0) { selectedIndex = 0; selectedSlug = ""; return }
    selectedIndex = Math.max(0, Math.min(count - 1, flatIndex))
    var theme = themeAt(selectedIndex)
    selectedSlug = theme ? theme.slug : ""
  }

  // After a reload or a filter change, stay on the same theme if it is still there, otherwise on
  // the same spot — which after a removal is the theme that took its place.
  function reselect() {
    var found = indexOfSlug(selectedSlug)
    select(found >= 0 ? found : selectedIndex)
  }

  onSectionOffsetsChanged: reselect()

  function moveVertical(direction) {
    var at = locate(selectedIndex)
    if (!at) return
    var count = sections[at.section].themes.length
    var row = Math.floor(at.index / columns)
    var col = at.index % columns
    var rows = Math.ceil(count / columns)

    if (direction > 0 && row + 1 < rows) {
      select(sectionOffsets[at.section] + Math.min((row + 1) * columns + col, count - 1))
    } else if (direction > 0 && at.section + 1 < sections.length) {
      var next = sections[at.section + 1].themes.length
      select(sectionOffsets[at.section + 1] + Math.min(col, next - 1))
    } else if (direction < 0 && row > 0) {
      select(sectionOffsets[at.section] + (row - 1) * columns + col)
    } else if (direction < 0 && at.section > 0) {
      var prev = sections[at.section - 1].themes.length
      var lastRow = Math.ceil(prev / columns) - 1
      select(sectionOffsets[at.section - 1] + Math.min(lastRow * columns + col, prev - 1))
    }
  }

  // The card that is selected, once the Grid has placed it. Revealing waits a moment because a
  // card created by a reload or a filter change has no position until the positioners have run.
  property Item selectedCard: null
  onSelectedCardChanged: revealTimer.restart()
  onSelectedIndexChanged: revealTimer.restart()

  Timer {
    id: revealTimer
    interval: 30
    onTriggered: view.revealCard(view.selectedCard)
  }

  function revealCard(card) {
    if (!card || !card.selected || flick.height <= 0) return
    var p = card.mapToItem(flick.contentItem, 0, 0)
    var at = locate(selectedIndex)
    var headerRoom = at && at.index < columns ? sectionHeaderHeight + gap : gap
    var top = p.y - headerRoom
    var bottom = p.y + card.height + gap
    if (top < flick.contentY) flick.contentY = Math.max(0, top)
    else if (bottom > flick.contentY + flick.height)
      flick.contentY = Math.min(bottom - flick.height, Math.max(0, flick.contentHeight - flick.height))
  }

  readonly property int sectionHeaderHeight: 40

  // What the footer button does for the selected theme, and what the confirmation says.
  function actionFor(theme) {
    if (!theme) return null
    if (theme.active)
      return { verb: "", note: "This is the theme in use. Switch to another theme to remove it." }
    if (theme.kind === "stock" && theme.hidden)
      return { verb: "restore", button: "Restore", note: "Hidden from Omarchy's theme picker" }
    if (theme.kind === "stock")
      return {
        verb: "hide", button: "Hide", confirm: "Hide", destructive: false,
        note: "Ships with Omarchy",
        message: "Hide “" + theme.label + "”? It ships with Omarchy, so it cannot be deleted without root and would come back with the next update. Hiding takes it out of Omarchy's theme picker and puts it under Hidden here, where you can restore it."
      }
    if (theme.kind === "overlay")
      return {
        verb: "remove", button: "Remove", confirm: "Remove", destructive: true,
        note: "Your copy of an Omarchy theme",
        message: "Remove your copy of “" + theme.label + "”? Your folder moves to the trash. " + theme.label + " also ships with Omarchy, so it stays in the list as the original."
      }
    if (theme.kind === "link")
      return {
        verb: "remove", button: "Remove", confirm: "Remove", destructive: true,
        note: "A link in your themes folder",
        message: "Remove “" + theme.label + "”? This deletes the link in your themes folder. The folder it points to is left alone."
      }
    if (theme.kind === "broken")
      return {
        verb: "remove", button: "Remove", confirm: "Remove", destructive: true,
        note: "A link whose target is gone",
        message: "Remove the broken link “" + theme.label + "”? What it pointed to is already gone."
      }
    return {
      verb: "remove", button: "Remove", confirm: "Remove", destructive: true,
      note: "Installed in your themes folder",
      message: "Remove “" + theme.label + "”? Its folder moves to the trash, so you can get it back from there."
    }
  }

  readonly property var selectedAction: actionFor(selectedTheme)

  function requestAction() {
    var theme = selectedTheme
    var action = selectedAction
    if (!store || store.busy || !theme || !action || !action.verb) return
    if (action.verb === "restore") { store.restoreTheme(theme); return }
    openConfirm({ verb: action.verb, theme: theme }, action.message, action.confirm, action.destructive)
  }

  function requestRemoveBroken() {
    if (!store || store.busy || brokenCount === 0) return
    openConfirm({ verb: "remove-broken" },
      "Remove all " + brokenCount + " broken links from your themes folder? What they pointed to is already gone, and nothing else is touched.",
      "Remove all", true)
  }

  function openConfirm(action, message, confirmText, destructive) {
    pendingAction = action
    confirm.message = message
    confirm.confirmText = confirmText
    // A delete must be chosen on purpose, so Enter alone lands on Cancel; a hide can be undone.
    confirm.selectedIndex = destructive ? 0 : 1
    confirm.opened = true
  }

  function runPending() {
    var action = pendingAction
    confirm.opened = false
    pendingAction = null
    if (!action) return
    if (action.verb === "remove") store.removeTheme(action.theme)
    else if (action.verb === "hide") store.hideTheme(action.theme)
    else if (action.verb === "remove-broken") store.removeBrokenLinks()
  }

  function focusKeys() { keys.forceActiveFocus() }

  function reset() {
    filterText = ""
    confirm.opened = false
    pendingAction = null
    flick.contentY = 0
    select(0)
  }

  function toneColor(tone) {
    if (tone === "accent") return Color.accent
    if (tone === "urgent") return Color.urgent
    if (tone === "muted") return Util.alpha(Color.foreground, 0.55)
    return Color.foreground
  }

  // The wallpaper, dimmed, rather than the windows underneath: busy windows showing through made
  // the names and the footer hard to read.
  // 🛑 NO BLUR, AND NO layer.effect ANYWHERE IN THIS WINDOW. A MultiEffect blur on this image crashed
  // the whole shell on 2026-09-25 the first time the grid opened, and did it again on the first open
  // in a throwaway instance. The window's scale changes as it maps, Qt walks the item tree to pass
  // that on, and calls into an object that is no longer whole (SIGABRT, "pure virtual method called"
  // under QQuickWindow::physicalDpiChanged). Without the effect it opens and closes cleanly.
  property string backdropSource: ""

  Rectangle {
    anchors.fill: parent
    color: Color.background
  }

  Image {
    anchors.fill: parent
    source: view.backdropSource
    sourceSize.width: 1280
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: false
  }

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Color.background, 0.8)
  }

  MouseArea {
    anchors.fill: parent
    onClicked: view.closeRequested()
  }

  Item {
    id: keys
    anchors.fill: parent
    focus: true

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (confirm.opened) {
        event.accepted = confirm.handleKey(event)
        return
      }
      var shift = event.modifiers & Qt.ShiftModifier
      if (event.key === Qt.Key_Escape) {
        if (view.filterText) view.filterText = ""
        else view.closeRequested()
      } else if (event.key === Qt.Key_Delete && shift && view.selectedTheme && view.selectedTheme.kind === "broken") {
        view.requestRemoveBroken()
      } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        view.requestAction()
      } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) {
        view.select(view.selectedIndex - 1)
      } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
        view.select(view.selectedIndex + 1)
      } else if (event.key === Qt.Key_Up) {
        view.moveVertical(-1)
      } else if (event.key === Qt.Key_Down) {
        view.moveVertical(1)
      } else if (event.key === Qt.Key_Home) {
        view.select(0)
      } else if (event.key === Qt.Key_End) {
        view.select(view.themeCount - 1)
      } else if (Util.editsFilter(event, view.filterText)) {
        view.filterText = Util.editedFilter(event, view.filterText)
      } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= (view.filterText ? 32 : 33) && event.text.charCodeAt(0) !== 127
                 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
        view.filterText += event.text
      } else {
        return
      }
      event.accepted = true
    }
  }

  Item {
    id: content
    width: view.gridWidth
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: Math.round(view.height * 0.07)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Math.round(view.height * 0.04)

    MouseArea { anchors.fill: parent; onClicked: view.focusKeys() }

    Flickable {
      id: flick
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: footer.top
      anchors.bottomMargin: Style.space(20)
      contentWidth: width
      contentHeight: sectionColumn.height
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Behavior on contentY {
        enabled: !flick.moving
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }

      Column {
        id: sectionColumn
        width: flick.width
        spacing: view.gap * 2

        Repeater {
          model: view.sections

          delegate: Column {
            id: sectionBlock
            required property var modelData
            required property int index
            readonly property int sectionIndex: index
            width: sectionColumn.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              height: view.sectionHeaderHeight - Style.space(6)

              Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                text: sectionBlock.modelData.title
                color: view.toneColor(sectionBlock.modelData.tone)
                font.pixelSize: Style.font.heading
                font.weight: Font.DemiBold
              }

              Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                text: sectionBlock.modelData.themes.length
                color: Util.alpha(Color.foreground, 0.6)
                font.pixelSize: Style.font.body
              }
            }

            Grid {
              columns: view.columns
              columnSpacing: view.gap
              rowSpacing: view.gap

              Repeater {
                model: sectionBlock.modelData.themes

                delegate: ThemeCard {
                  id: card
                  required property var modelData
                  required property int index
                  theme: modelData
                  width: view.cardWidth
                  imageHeight: view.imageHeight
                  labelHeight: view.labelHeight
                  flatIndex: view.sectionOffsets[sectionBlock.sectionIndex] + index
                  selected: flatIndex === view.selectedIndex
                  onSelectedChanged: if (selected) view.selectedCard = card
                  Component.onCompleted: if (selected) view.selectedCard = card
                  onPicked: { view.select(flatIndex); view.focusKeys() }
                  onActivated: { view.select(flatIndex); view.requestAction() }
                }
              }
            }
          }
        }
      }
    }

    Text {
      visible: view.store && view.store.loaded && view.themeCount === 0
      anchors.centerIn: flick
      text: view.filterText ? "No theme matches “" + view.filterText + "”" : "No themes found"
      color: Util.alpha(Color.foreground, 0.7)
      font.pixelSize: Style.font.heading
    }

    Item {
      id: footer
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Style.space(112)

      Button {
        id: closeButton
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: Style.space(6)
        text: "Close"
        bordered: true
        onClicked: view.closeRequested()
      }

      Row {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Style.space(6)
        spacing: Style.space(8)

        Button {
          visible: view.selectedTheme !== null && view.selectedTheme.kind === "broken" && view.brokenCount > 1
          text: "Remove all " + view.brokenCount + " broken"
          bordered: true
          foreground: Color.urgent
          enabled: !(view.store && view.store.busy)
          onClicked: view.requestRemoveBroken()
        }

        Button {
          visible: view.selectedAction !== null && !!view.selectedAction.verb
          text: view.selectedAction && view.selectedAction.button ? view.selectedAction.button : ""
          bordered: true
          foreground: view.selectedAction && view.selectedAction.destructive ? Color.urgent : Color.foreground
          enabled: !(view.store && view.store.busy)
          onClicked: view.requestAction()
        }
      }

      Text {
        id: selectedName
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - Style.space(560)
        text: view.selectedTheme ? view.selectedTheme.label : ""
        color: Color.foreground
        font.pixelSize: Style.font.display
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      Text {
        id: selectedNote
        anchors.top: selectedName.bottom
        anchors.topMargin: Style.space(4)
        anchors.horizontalCenter: parent.horizontalCenter
        width: selectedName.width
        text: view.filterText ? "Filter: " + view.filterText
          : (view.selectedAction ? view.selectedAction.note : "")
        color: Util.alpha(Color.foreground, 0.7)
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      Text {
        anchors.top: selectedNote.bottom
        anchors.topMargin: Style.space(14)
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        font.pixelSize: Style.font.bodySmall
        color: view.store && view.store.message
          ? (view.store.messageIsError ? Color.urgent : Color.accent)
          : Util.alpha(Color.foreground, 0.6)
        text: view.store && view.store.busy ? "Working…"
          : (view.store && view.store.message ? view.store.message
          : "←↑↓→ move  ·  type to filter"
            + (view.selectedAction && view.selectedAction.button ? "  ·  Delete " + view.selectedAction.button.toLowerCase() : "")
            + (view.selectedTheme && view.selectedTheme.kind === "broken" && view.brokenCount > 1 ? "  ·  Shift+Delete all broken links" : "")
            + "  ·  Esc close")
      }
    }
  }

  ConfirmDialog {
    id: confirm
    anchors.fill: parent
    cancelText: "Cancel"
    onCanceled: { confirm.opened = false; view.pendingAction = null; view.focusKeys() }
    onConfirmed: { view.runPending(); view.focusKeys() }
  }
}
