import QtQuick
import qs.Commons
import qs.Ui

// One theme: its preview, its name underneath, a badge when it is in use, your copy of an
// Omarchy theme, a link, or a broken link, and on hover a × that removes or hides it.
Item {
  id: card

  property var theme: ({})
  property int flatIndex: 0
  property bool selected: false
  property int imageHeight: 169
  property int labelHeight: 30
  // What the × does — "Remove" or "Hide" — or "" for no ×. The grid decides.
  property string removeLabel: ""

  signal picked()
  signal activated()
  signal removeRequested()

  readonly property bool hidden: theme.hidden === true
  readonly property bool hovered: mouse.containsMouse || removeArea.containsMouse
  readonly property string badge: theme.active ? "CURRENT"
    : theme.kind === "overlay" ? "YOUR COPY"
    : theme.kind === "link" ? "LINK"
    : theme.kind === "broken" ? "BROKEN"
    : ""

  height: imageHeight + labelHeight

  Rectangle {
    id: frame
    anchors.fill: parent
    color: Color.background
    border.width: card.selected ? 2 : 1
    border.color: card.selected ? Color.accent : Util.alpha(Color.foreground, card.hovered ? 0.45 : 0.18)

    Item {
      id: imageArea
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: frame.border.width
      height: card.imageHeight - frame.border.width
      clip: true

      Image {
        id: preview
        anchors.fill: parent
        source: card.theme.preview ? Util.fileUrl(card.theme.preview) : ""
        sourceSize.width: card.width * 2
        sourceSize.height: card.imageHeight * 2
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        opacity: card.hidden ? 0.35 : 1
      }

      Text {
        visible: preview.status !== Image.Ready
        anchors.centerIn: parent
        width: parent.width - Style.space(24)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: card.theme.kind === "broken" ? "Link target is gone" : (preview.status === Image.Loading ? "" : "No preview")
        color: Util.alpha(Color.foreground, 0.45)
        font.pixelSize: Style.font.body
      }

      Rectangle {
        visible: card.badge !== ""
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Style.space(8)
        // Steps left of the × while it shows, rather than sitting under it.
        anchors.rightMargin: removeMark.visible ? Style.space(14) + removeMark.width : Style.space(8)
        width: badgeText.implicitWidth + Style.space(12)
        height: badgeText.implicitHeight + Style.space(6)
        color: card.theme.active ? Color.accent
          : card.theme.kind === "broken" ? Color.urgent
          : Util.alpha(Color.background, 0.85)
        border.width: card.theme.active || card.theme.kind === "broken" ? 0 : 1
        border.color: Util.alpha(Color.foreground, 0.4)

        Text {
          id: badgeText
          anchors.centerIn: parent
          text: card.badge
          color: card.theme.active || card.theme.kind === "broken" ? Color.background : Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
        }
      }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: frame.border.width
      height: card.labelHeight - frame.border.width
      color: Util.alpha(Color.foreground, 0.07)

      Text {
        anchors.fill: parent
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideMiddle
        text: card.theme.label || ""
        color: card.hidden ? Util.alpha(Color.foreground, 0.55) : Color.foreground
        font.pixelSize: Style.font.body
        font.weight: card.selected ? Font.DemiBold : Font.Normal
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: card.picked()
    onDoubleClicked: card.activated()
  }

  // Hover reveals a × in the top-right corner (Dave, 2026-09-26: "a small x in the top right of
  // every swatch to remove that theme"), the same dark disc and red ✕ as on the panel's background
  // tiles. It asks first, as Delete does.
  Rectangle {
    id: removeMark
    visible: card.removeLabel !== "" && card.hovered
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: frame.border.width + Style.space(8)
    width: Style.space(26)
    height: width
    radius: width / 2
    color: Qt.rgba(0, 0, 0, removeArea.containsMouse ? 0.55 : 0.35)

    Text {
      anchors.centerIn: parent
      text: "\u2715"
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.bold: true
      color: removeArea.containsMouse ? "#ff6b81" : "#ff3d5a"
    }

    MouseArea {
      id: removeArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: card.removeRequested()
    }

    PanelToolTip {
      visible: removeArea.containsMouse
      text: card.removeLabel
    }
  }
}
