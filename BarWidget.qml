import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.paulohenrique000.team-matches"

  readonly property var teams: panelLoader.item ? panelLoader.item.configuredTeams : []

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (!panelLoader.item) return
    panelLoader.item.refresh()
    panelLoader.item.refreshTeamSummaries()
  }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function recentResultFor(team) {
    if (!panelLoader.item) return null
    var summary = panelLoader.item.teamSummaries[String(Number(team.id))]
    var result = summary && summary.last
    return Model.isRecentResult(result, panelLoader.item.now.getTime() / 1000, 8) ? result : null
  }

  function fixtureText(team) {
    if (!panelLoader.item) return "…"
    var live = panelLoader.item.liveGameFor(team)
    if (live) return Model.opponentScore(live, team.id)
    var result = root.recentResultFor(team)
    if (result) return Model.opponentScore(result, team.id)
    var game = panelLoader.item.nextGameFor(team)
    return game && game.startTimestamp
      ? Model.relativeTime(game.startTimestamp, panelLoader.item.now.getTime() / 1000)
      : "—"
  }

  function teamIsLive(team) {
    return !!(panelLoader.item && panelLoader.item.liveGameFor(team))
  }

  function teamHasRecentResult(team) {
    return root.recentResultFor(team) !== null
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  // WidgetButton registers the whole summary with the bar's click dispatcher.
  // Its label is hidden; the compact, mixed-size row below is the visual label.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: " "
    labelVisible: false
    fixedWidth: summaryRow.implicitWidth + Style.space(12)
    fixedHeight: Style.space(26)
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    Row {
      id: summaryRow
      anchors.centerIn: parent
      spacing: Style.space(5)

      Text {
        visible: root.teams.length === 0
        text: "󰒸 Teams"
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }

      Repeater {
        model: root.teams
        delegate: Row {
          required property var modelData
          required property int index
          spacing: Style.space(4)

          Text {
            text: Model.sportIcon(String(modelData.sport || "")) + " " + Model.shortName(modelData.name)
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: Number(modelData.id) === Number(panelLoader.item && panelLoader.item.teamId)
          }
          // Next-fixture time is deliberately visually secondary.
          Text {
            text: root.fixtureText(modelData)
            color: root.teamIsLive(modelData) ? Color.urgent : (root.teamHasRecentResult(modelData) ? (root.bar ? root.bar.foreground : Color.foreground) : Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4))
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: (root.teamIsLive(modelData) || root.teamHasRecentResult(modelData)) ? Style.font.body : Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            visible: index < root.teams.length - 1
            text: "|"
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.6)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }
  }
}
