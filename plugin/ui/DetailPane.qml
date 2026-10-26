import QtQuick
import Quickshell
import qs.Commons

// The selected row's detail beside the list (fork): a clipboard entry or a
// script menu document. detail: {title?, subtitle?, status?, loading?, image?,
// body?, mono?, blocks?: [{heading, text, mono, screens?}], metadata?: [{label, value}]}.
// A block's `screens` (ScriptMenu.screens) are drawn as monitors with their
// windows on them, the way the layout designer draws its canvas.
// With `pinMetadata` (clipboard entries) the label/value rows stay at the
// bottom and only the content above them scrolls.
Rectangle {
  id: pane

  property var detail: null
  property var look: null
  property real zoom: 1

  function px(v) { return Math.round(Style.space(v) * pane.zoom) }

  readonly property var d: pane.detail || ({})
  // A clipboard body wraps; a script's fenced block is a drawing, so it
  // shrinks to fit the width instead.
  readonly property var blocks: (pane.d.body ? [{ heading: "", text: pane.d.body, mono: !!pane.d.mono, wrap: true }] : [])
    .concat((pane.d.blocks || []).map(function(b) { return { heading: b.heading, text: b.text, mono: b.mono, wrap: !b.mono, screens: b.screens || [] } }))
  readonly property var metadata: pane.d.metadata || []
  readonly property bool pinned: !!pane.d.pinMetadata && pane.metadata.length > 0

  // A new entry starts at its top.
  onDetailChanged: flick.contentY = 0

  // A desktop entry's Icon= value as something an Image can load, or "".
  function iconSource(name) {
    var value = String(name || "")
    if (!value) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    return Quickshell.iconPath(value, true)
  }

  color: Util.alpha(look.foreground, 0.03)
  radius: Math.max(Style.cornerRadius, px(6))
  border.width: 1
  border.color: Util.alpha(look.foreground, 0.08)
  clip: true

  Flickable {
    id: flick
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: pane.pinned ? info.top : parent.bottom
    anchors.margins: pane.px(12)
    anchors.bottomMargin: pane.pinned ? pane.px(8) : pane.px(12)
    contentWidth: width
    contentHeight: content.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Column {
      id: content
      width: flick.width
      spacing: pane.px(10)

      Image {
        visible: !!pane.d.image
        width: parent.width
        height: visible ? Math.min(pane.px(220), Math.max(pane.px(60), implicitHeight * (width / Math.max(1, implicitWidth)))) : 0
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
        sourceSize.width: width * 2
        source: pane.d.image ? "file://" + pane.d.image : ""
      }

      Column {
        visible: !!pane.d.title
        width: parent.width
        spacing: pane.px(3)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: pane.d.title || ""
          color: pane.look.foreground
          wrapMode: Text.Wrap
          font.family: pane.look.fontFamily
          font.pixelSize: Math.round(Style.font.title * pane.zoom)
          font.bold: true
        }
        Text {
          visible: text.length > 0
          width: parent.width
          textFormat: Text.PlainText
          text: [pane.d.subtitle || "", pane.d.status || "", pane.d.loading ? "Loading…" : ""].filter(function(t) { return t }).join(" · ")
          color: pane.look.foreground
          opacity: 0.6
          wrapMode: Text.Wrap
          font.family: pane.look.fontFamily
          font.pixelSize: Math.round(Style.font.bodySmall * pane.zoom)
        }
      }

      Repeater {
        model: pane.blocks

        Column {
          required property var modelData
          width: content.width
          spacing: pane.px(4)

          Text {
            visible: !!modelData.heading
            width: parent.width
            textFormat: Text.PlainText
            text: modelData.heading || ""
            color: pane.look.foreground
            opacity: 0.5
            font.family: pane.look.fontFamily
            font.pixelSize: Math.round(Style.font.caption * pane.zoom)
            font.weight: Font.DemiBold
          }
          Repeater {
            model: modelData.screens

            Column {
              id: screen
              required property var modelData
              width: content.width
              spacing: pane.px(4)

              Text {
                visible: screen.modelData.label.length > 0
                width: parent.width
                textFormat: Text.PlainText
                text: screen.modelData.label
                color: pane.look.foreground
                opacity: 0.6
                elide: Text.ElideRight
                font.family: pane.look.fontFamily
                font.pixelSize: Math.round(Style.font.caption * pane.zoom)
              }

              Rectangle {
                id: monitor
                width: parent.width
                height: Math.round(width / screen.modelData.aspect)
                radius: Math.max(Style.cornerRadius, pane.px(4))
                color: Qt.darker(pane.look.background, 1.45)
                border.width: 1
                border.color: Util.alpha(pane.look.foreground, 0.22)
                clip: true

                Rectangle {
                  visible: screen.modelData.reservedTop > 0
                  width: parent.width
                  height: Math.max(2, screen.modelData.reservedTop * monitor.height)
                  color: Util.alpha(pane.look.foreground, 0.10)
                }

                Repeater {
                  model: screen.modelData.tiles

                  Rectangle {
                    id: tile
                    required property var modelData
                    readonly property real gap: pane.px(2)
                    readonly property string icon: pane.iconSource(tile.modelData.icon)
                    x: tile.modelData.x * monitor.width + tile.gap
                    y: tile.modelData.y * monitor.height + tile.gap
                    width: Math.max(2, tile.modelData.w * monitor.width - tile.gap * 2)
                    height: Math.max(2, tile.modelData.h * monitor.height - tile.gap * 2)
                    radius: Math.max(Style.cornerRadius, pane.px(4))
                    color: Util.alpha(pane.look.foreground, 0.10)
                    border.width: 1
                    border.color: Util.alpha(pane.look.foreground, 0.30)

                    Column {
                      anchors.centerIn: parent
                      width: parent.width - pane.px(8)
                      spacing: pane.px(3)

                      Item {
                        readonly property int side: Math.round(Math.min(pane.px(40), Math.max(pane.px(14), Math.min(tile.width, tile.height) * 0.3)))
                        visible: tile.height > pane.px(44)
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: side
                        height: side

                        Image {
                          anchors.fill: parent
                          visible: tile.icon.length > 0 && status !== Image.Error
                          source: tile.icon
                          sourceSize.width: parent.width * 2
                          sourceSize.height: parent.height * 2
                          fillMode: Image.PreserveAspectFit
                          smooth: true
                          asynchronous: true
                        }
                        // No icon in the theme: the app's initial in a disc.
                        Rectangle {
                          anchors.fill: parent
                          visible: !tile.icon.length
                          radius: width / 2
                          color: Util.alpha(pane.look.accent, 0.25)
                          Text {
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: tile.modelData.name.charAt(0).toUpperCase()
                            color: pane.look.foreground
                            font.family: pane.look.fontFamily
                            font.pixelSize: Math.round(parent.height * 0.5)
                            font.bold: true
                          }
                        }
                      }

                      Text {
                        width: parent.width
                        visible: tile.height > pane.px(18)
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.PlainText
                        text: tile.modelData.name
                        color: pane.look.foreground
                        elide: Text.ElideRight
                        font.family: pane.look.fontFamily
                        font.pixelSize: Math.round(Style.font.bodySmall * pane.zoom)
                      }

                      Text {
                        width: parent.width
                        visible: tile.modelData.size.length > 0 && tile.width > pane.px(80) && tile.height > pane.px(70)
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.PlainText
                        text: tile.modelData.size
                        color: pane.look.foreground
                        opacity: 0.45
                        elide: Text.ElideRight
                        font.family: pane.look.fontFamily
                        font.pixelSize: Math.round(Style.font.caption * pane.zoom)
                      }
                    }
                  }
                }
              }
            }
          }

          Text {
            visible: modelData.text.length > 0
            width: parent.width
            textFormat: Text.PlainText
            text: modelData.text
            color: pane.look.foreground
            wrapMode: modelData.wrap ? Text.WrapAnywhere : Text.NoWrap
            maximumLineCount: modelData.wrap ? 100000 : 100
            font.family: modelData.mono ? "monospace" : pane.look.fontFamily
            font.pixelSize: Math.round((modelData.mono ? Style.font.bodySmall : Style.font.body) * pane.zoom)
            fontSizeMode: modelData.wrap ? Text.FixedSize : Text.HorizontalFit
            minimumPixelSize: 6
          }
        }
      }

      Rectangle {
        visible: !pane.pinned && pane.metadata.length > 0 && (pane.blocks.length > 0 || !!pane.d.title || !!pane.d.image)
        width: parent.width
        height: 1
        color: Util.alpha(pane.look.foreground, 0.1)
      }

      Repeater {
        model: pane.pinned ? [] : pane.metadata
        delegate: metadataRow
      }
    }
  }

  // Shown only while there is more to scroll to.
  Rectangle {
    visible: flick.contentHeight > flick.height
    anchors.right: parent.right
    anchors.rightMargin: pane.px(3)
    y: flick.y + (flick.height - height) * (flick.contentY / Math.max(1, flick.contentHeight - flick.height))
    width: pane.px(3)
    height: Math.max(pane.px(20), flick.height * flick.height / Math.max(1, flick.contentHeight))
    radius: width / 2
    color: Util.alpha(pane.look.foreground, 0.3)
  }

  Column {
    id: info
    visible: pane.pinned
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: pane.px(12)
    spacing: pane.px(6)

    Rectangle {
      width: parent.width
      height: 1
      color: Util.alpha(pane.look.foreground, 0.1)
    }

    Repeater {
      model: pane.pinned ? pane.metadata : []
      delegate: metadataRow
    }
  }

  Component {
    id: metadataRow

    Item {
      required property var modelData
      width: parent ? parent.width : 0
      height: Math.max(label.implicitHeight, value.implicitHeight)

      Text {
        id: label
        width: Math.round(parent.width * 0.4)
        textFormat: Text.PlainText
        text: modelData.label
        color: pane.look.foreground
        opacity: 0.55
        elide: Text.ElideRight
        font.family: pane.look.fontFamily
        font.pixelSize: Math.round(Style.font.bodySmall * pane.zoom)
      }
      Text {
        id: value
        anchors.right: parent.right
        width: parent.width - label.width - pane.px(8)
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        text: modelData.value
        color: pane.look.foreground
        wrapMode: Text.WrapAnywhere
        maximumLineCount: 3
        elide: Text.ElideRight
        font.family: pane.look.fontFamily
        font.pixelSize: Math.round(Style.font.bodySmall * pane.zoom)
      }
    }
  }
}
