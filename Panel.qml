import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.paulohenrique000.team-matches"
  ipcTarget: "io.github.paulohenrique000.team-matches"

  property var anchorItem: null
  property var hostWidget: null
  property string selectedSport: ""
  property var searchResults: []
  property var lastMatch: null
  property var liveMatch: null
  property var nextMatches: []
  // Cached live/next fixtures per followed team power the compact multi-team bar.
  property var teamSummaries: ({})
  property date now: new Date()
  property var lastUpdatedAt: null
  property bool searching: false
  property bool addingTeam: false
  property string requestedQuery: ""
  property int fetchingTeamId: 0
  property bool refreshing: false
  property string errorText: ""

  // `teamId`/`teamName` were used by v0.1. Keep reading them once so an
  // existing single-team setup migrates automatically when another team is added.
  readonly property var configuredTeams: {
    if (settings && settings.teams instanceof Array) return settings.teams
    if (settings && Number(settings.teamId || 0) > 0)
      return [{ id: Number(settings.teamId), name: String(settings.teamName || ""), sport: String(settings.teamSport || "") }]
    return []
  }
  readonly property int activeIndex: {
    var wanted = Number(settings && settings.activeTeamId || 0)
    for (var index = 0; index < configuredTeams.length; index++)
      if (Number(configuredTeams[index].id) === wanted) return index
    return 0
  }
  readonly property var activeTeam: configuredTeams.length > activeIndex ? configuredTeams[activeIndex] : null
  readonly property int teamId: Number(activeTeam && activeTeam.id || 0)
  readonly property string teamName: String(activeTeam && activeTeam.name || "")
  readonly property string teamSport: String(activeTeam && activeTeam.sport || "")
  readonly property string themeAccent: String(Color.accent)
  readonly property color foreground: root.bar ? root.bar.foreground : Color.foreground
  readonly property bool hasLiveGames: {
    for (var id in teamSummaries) if (teamSummaries[id] && teamSummaries[id].live) return true
    return false
  }
  readonly property string nextCountdown: nextMatches.length > 0 ? Model.relativeTime(nextMatches[0].startTimestamp, now.getTime() / 1000) : ""
  readonly property string barLabel: teamId > 0
    ? Model.sportIcon(teamSport) + " " + Model.shortName(teamName)
      + (nextCountdown !== "" ? " · " + nextCountdown : (lastMatch ? " " + Model.score(lastMatch, "home") + "–" + Model.score(lastMatch, "away") : ""))
    : "\uf1e3 Teams"

  component TeamName: Row {
    required property var team
    property color nameColor: root.foreground
    property string textFontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    property int textFontSize: Style.font.body
    spacing: Style.space(4)
    Rectangle {
      visible: Model.clubColor(team && team.teamColors && team.teamColors.primary) !== ""
      width: visible ? Style.space(8) : 0
      height: width
      radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      color: Model.clubColor(team && team.teamColors && team.teamColors.primary)
    }
    Text {
      text: String(team && team.name || "")
      textFormat: Text.PlainText
      color: parent.nameColor
      font.family: parent.textFontFamily
      font.pixelSize: parent.textFontSize
      elide: Text.ElideRight
    }
  }

  component EventLine: Row {
    required property var event
    property bool includeScore: false
    property string textFontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    property int textFontSize: Style.font.body
    width: parent ? parent.width : implicitWidth
    spacing: Style.space(5)
    TeamName {
      team: event && event.homeTeam
      nameColor: Number(team && team.id) === root.teamId ? Color.accent : root.foreground
      textFontFamily: parent.textFontFamily
      textFontSize: parent.textFontSize
    }
    Text {
      text: includeScore ? Model.score(event, "home") + "  ·  " + Model.score(event, "away") : "vs"
      textFormat: Text.PlainText
      color: root.foreground
      font.family: parent.textFontFamily
      font.pixelSize: parent.textFontSize
      font.bold: true
    }
    TeamName {
      team: event && event.awayTeam
      nameColor: Number(team && team.id) === root.teamId ? Color.accent : root.foreground
      textFontFamily: parent.textFontFamily
      textFontSize: parent.textFontSize
    }
  }

  component EventMeta: Row {
    required property var event
    property bool showRelativeTime: root.nextMatches.length > 0 && Number(event && event.id) === Number(root.nextMatches[0].id)
    spacing: Style.space(5)
    readonly property string competition: event && event.tournament ? String(event.tournament.name || "") : ""
    readonly property string when: event && event.startTimestamp ? Qt.formatDateTime(new Date(event.startTimestamp * 1000), "ddd d MMM · HH:mm") : "Date pending"
    Text { visible: parent.competition !== ""; text: parent.competition; textFormat: Text.PlainText; color: Qt.darker(root.foreground, 1.4); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.caption }
    Text { visible: parent.competition !== ""; text: "·"; textFormat: Text.PlainText; color: Qt.darker(root.foreground, 1.4); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.caption }
    Text { text: parent.when; textFormat: Text.PlainText; color: Qt.darker(root.foreground, 1.4); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.caption }
    Text { visible: parent.showRelativeTime; text: "·"; textFormat: Text.PlainText; color: Qt.darker(root.foreground, 1.4); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.caption }
    Text { visible: parent.showRelativeTime; text: Model.relativeTime(event && event.startTimestamp, now.getTime() / 1000); textFormat: Text.PlainText; color: Color.accent; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.caption }
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    for (var changed in values) {
      if (values[changed] === undefined) delete entry[changed]
      else entry[changed] = values[changed]
    }
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function chooseSport(sport) {
    selectedSport = sport.slug
    searchResults = []
    errorText = ""
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function queueSearch() {
    var query = searchField.text.trim()
    if (query.length < 3) {
      searchDebounce.stop()
      searchResults = []
      errorText = ""
      return
    }
    searchDebounce.restart()
  }

  function searchTeams() {
    var query = searchField.text.trim()
    if (query.length < 3 || searchProc.running) return
    requestedQuery = query
    searching = true
    errorText = ""
    searchProc.command = ["curl", "-fsS", "--max-time", "8", "--max-filesize", "262144",
                          "https://www.sofascore.com/api/v1/search/teams?q=" + encodeURIComponent(query)]
    searchProc.running = true
  }

  function backToSports() {
    searchDebounce.stop()
    requestedQuery = ""
    selectedSport = ""
    searchResults = []
    errorText = ""
    searchField.text = ""
  }

  function persistTeams(entries, activeId) {
    persistSettings({ teams: entries, activeTeamId: activeId,
                      teamId: undefined, teamName: undefined, teamSport: undefined })
  }

  function beginAddTeam() {
    if (configuredTeams.length >= 4) return
    addingTeam = true
    backToSports()
  }

  function chooseTeam(team) {
    var entries = configuredTeams.slice()
    var id = Number(team.id)
    var alreadyAdded = entries.some(function(entry) { return Number(entry.id) === id })
    if (!alreadyAdded) entries.push({ id: id, name: String(team.name || ""),
                                     sport: String(team.sport && team.sport.slug || selectedSport) })
    persistTeams(entries, id)
    addingTeam = false
    lastMatch = null
    liveMatch = null
    nextMatches = []
    lastUpdatedAt = null
    errorText = ""
    Qt.callLater(root.refresh)
    Qt.callLater(root.refreshTeamSummaries)
  }

  function selectTeam(index) {
    if (index < 0 || index >= configuredTeams.length) return
    persistSettings({ activeTeamId: Number(configuredTeams[index].id) })
    addingTeam = false
    selectedSport = ""
    searchResults = []
    lastMatch = null
    liveMatch = null
    nextMatches = []
    lastUpdatedAt = null
    errorText = ""
    Qt.callLater(root.refresh)
  }

  function removeActiveTeam() {
    var entries = configuredTeams.filter(function(entry) { return Number(entry.id) !== teamId })
    var nextId = entries.length > 0 ? Number(entries[Math.min(activeIndex, entries.length - 1)].id) : 0
    persistTeams(entries, nextId)
    addingTeam = false
    selectedSport = ""
    searchResults = []
    lastMatch = null
    liveMatch = null
    nextMatches = []
    lastUpdatedAt = null
    errorText = ""
    if (nextId > 0) Qt.callLater(root.refresh)
  }

  function nextGameFor(team) {
    var summary = team ? teamSummaries[String(Number(team.id))] : null
    return summary ? summary.next : null
  }

  function liveGameFor(team) {
    var summary = team ? teamSummaries[String(Number(team.id))] : null
    return summary ? summary.live : null
  }

  function refreshTeamSummaries() {
    if (configuredTeams.length === 0 || summaryProc.running) return
    var ids = configuredTeams.map(function(team) { return Number(team.id) }).filter(function(id) { return id > 0 })
    if (ids.length === 0) return
    summaryProc.command = ["bash", "-c", "for id in " + ids.join(" ") + "; do printf '%s\\t' \"$id\"; curl -fsS --max-time 8 --max-filesize 262144 \"https://www.sofascore.com/api/v1/team/$id/events/last/0\"; printf '\\t'; curl -fsS --max-time 8 --max-filesize 262144 \"https://www.sofascore.com/api/v1/team/$id/events/next/0\"; printf '\\n'; done"]
    summaryProc.running = true
  }

  function refreshLiveEvents() {
    if (liveProc.running) return
    var pairs = []
    for (var id in teamSummaries) {
      var live = teamSummaries[id] && teamSummaries[id].live
      if (live && Number(live.id || 0) > 0) pairs.push(Number(id) + ":" + Number(live.id))
    }
    if (pairs.length === 0) return
    liveProc.command = ["bash", "-c", "for pair in " + pairs.join(" ") + "; do team=${pair%%:*}; event=${pair#*:}; printf '%s\\t' \"$team\"; curl -fsS --max-time 8 --max-filesize 262144 \"https://www.sofascore.com/api/v1/event/$event\"; printf '\\n'; done"]
    liveProc.running = true
  }

  function refresh() {
    if (teamId <= 0 || lastProc.running || nextProc.running) return
    refreshing = true
    fetchingTeamId = teamId
    errorText = ""
    lastProc.running = true
    nextProc.running = true
  }

  function open() { root.controller.show(); if (teamId > 0) root.refresh(); root.refreshTeamSummaries() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  function finishRefresh() {
    Qt.callLater(function() {
      root.refreshing = lastProc.running || nextProc.running
      if (!root.refreshing && root.fetchingTeamId !== root.teamId) root.refresh()
      else if (!root.refreshing) root.lastUpdatedAt = new Date()
    })
  }

  Timer {
    id: searchDebounce
    interval: 300
    onTriggered: root.searchTeams()
  }

  Process {
    id: searchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (searchField.text.trim() !== root.requestedQuery) return
        root.searchResults = Model.searchTeams(text, root.selectedSport)
        if (root.searchResults.length === 0) root.errorText = "No " + Model.sportFor(root.selectedSport).name.toLowerCase() + " teams found"
      }
    }
    onExited: function(code) {
      root.searching = false
      if (code !== 0 && searchField.text.trim() === root.requestedQuery) root.errorText = "Could not reach the team search"
      if (searchField.text.trim() !== root.requestedQuery) root.queueSearch()
    }
  }

  Process {
    id: summaryProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var received = Model.teamSummaries(text)
        root.teamSummaries = Object.assign({}, root.teamSummaries, received)
      }
    }
  }

  Process {
    id: liveProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var updates = Model.liveEventUpdates(text)
        var merged = Object.assign({}, root.teamSummaries)
        for (var id in updates) {
          merged[id] = Object.assign({}, merged[id] || {}, updates[id])
          if (Number(id) === root.teamId) {
            root.liveMatch = updates[id].live || null
            if (updates[id].last) root.lastMatch = updates[id].last
            root.lastUpdatedAt = new Date()
          }
        }
        root.teamSummaries = merged
      }
    }
  }

  Process {
    id: lastProc
    command: ["curl", "-fsS", "--max-time", "8", "--max-filesize", "262144", "https://www.sofascore.com/api/v1/team/" + root.teamId + "/events/last/0"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.fetchingTeamId !== root.teamId) return
        root.liveMatch = Model.liveEvent(Model.parseEvents(text))
        var match = Model.latestCompleted(Model.parseEvents(text))
        if (match) root.lastMatch = match
        else root.errorText = "No recent completed match found"
        var summaries = Object.assign({}, root.teamSummaries)
        summaries[String(root.teamId)] = Object.assign({}, summaries[String(root.teamId)] || {}, { live: root.liveMatch, last: match })
        root.teamSummaries = summaries
      }
    }
    onExited: function(code) {
      if (code !== 0 && root.fetchingTeamId === root.teamId) root.errorText = "Could not load the latest result"
      root.finishRefresh()
    }
  }

  Process {
    id: nextProc
    command: ["curl", "-fsS", "--max-time", "8", "--max-filesize", "262144", "https://www.sofascore.com/api/v1/team/" + root.teamId + "/events/next/0"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.fetchingTeamId !== root.teamId) return
        root.nextMatches = Model.upcoming(Model.parseEvents(text), 3)
        if (root.nextMatches.length === 0) root.errorText = "No upcoming fixtures found"
      }
    }
    onExited: function(code) {
      if (code !== 0 && root.fetchingTeamId === root.teamId) root.errorText = "Could not load upcoming fixtures"
      root.finishRefresh()
    }
  }

  Timer {
    interval: 1800000
    running: root.configuredTeams.length > 0
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshTeamSummaries()
  }

  Timer {
    interval: 60000
    running: root.teamId > 0
    repeat: true
    onTriggered: root.now = new Date()
  }

  Timer {
    interval: 60000
    running: root.hasLiveGames
    repeat: true
    onTriggered: root.refreshLiveEvents()
  }

  Timer {
    interval: 7200000
    running: root.teamId > 0
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(300))

    Column {
      id: content
      anchors.fill: parent
      spacing: Style.space(8)

      Row {
        visible: configuredTeams.length > 0
        width: parent.width
        spacing: Style.space(5)
        Repeater {
          model: root.configuredTeams
          delegate: Rectangle {
            required property var modelData
            required property int index
            width: Math.min(Style.space(96), tabContent.implicitWidth + Style.space(20))
            height: Style.space(32)
            radius: Style.cornerRadius
            color: index === root.activeIndex ? Style.hoverFillFor(root.foreground, Color.accent) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
            Row {
              id: tabContent
              anchors.centerIn: parent
              spacing: Style.space(4)
              Image {
                width: Style.space(20)
                height: Style.space(20)
                source: "https://api.sofascore.com/api/v1/team/" + Number(modelData.id) + "/image"
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 40
                sourceSize.height: 40
              }
              Text {
                text: Model.shortName(modelData.name)
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                font.bold: index === root.activeIndex
              }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.selectTeam(index) }
          }
        }
        PanelActionButton {
          visible: configuredTeams.length < 4
          iconText: "+"
          foreground: Qt.darker(root.foreground, 1.35)
          hoverColor: root.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: Style.font.body
          size: Style.space(20)
          onClicked: root.beginAddTeam()
        }
      }

      Text {
        visible: configuredTeams.length === 0
        text: "Add a team"
        color: root.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Column {
        visible: (teamId <= 0 || addingTeam) && selectedSport === ""
        width: parent.width
        spacing: Style.space(6)
        Text { text: "SPORT"; color: Qt.darker(root.foreground, 1.4); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1 }
        Grid {
          width: parent.width
          columns: 2
          columnSpacing: Style.space(6)
          rowSpacing: Style.space(6)
          Repeater {
            model: Model.sports
            delegate: Rectangle {
              required property var modelData
              width: (parent.width - parent.columnSpacing) / 2
              height: Style.space(30)
              radius: Style.cornerRadius
              color: sportArea.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
              Text { anchors.left: parent.left; anchors.leftMargin: Style.space(9); anchors.verticalCenter: parent.verticalCenter; text: modelData.icon + "  " + modelData.name; color: root.foreground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.caption }
              MouseArea { id: sportArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.chooseSport(modelData) }
            }
          }
        }
      }

      Column {
        visible: (teamId <= 0 || addingTeam) && selectedSport !== ""
        width: parent.width
        spacing: Style.space(7)
        Item {
          width: parent.width
          height: Math.max(sportSearchTitle.implicitHeight, backButton.implicitHeight)
          Text { id: sportSearchTitle; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: Model.sportIcon(selectedSport) + " " + Model.sportFor(selectedSport).name + " — search team"; color: root.foreground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
          Text { id: backButton; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "← Back"; color: Qt.darker(root.foreground, 1.35); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.caption
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.backToSports() }
          }
        }
        TextField {
          id: searchField
          width: parent.width
          placeholderText: "Type at least 3 letters"
          foreground: root.foreground
          accent: Color.accent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          onTextChanged: root.queueSearch()
          onAccepted: root.searchTeams()
        }
        Text { visible: searching; text: "Searching…"; color: Qt.darker(root.foreground, 1.4); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.caption }
        Repeater {
          model: root.searchResults
          delegate: Rectangle {
            required property var modelData
            width: parent.width
            height: Style.space(34)
            radius: Style.cornerRadius
            color: resultArea.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
            Column { anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: Style.space(9); anchors.rightMargin: Style.space(9); anchors.verticalCenter: parent.verticalCenter; spacing: 1
              Text { text: String(modelData.name || ""); textFormat: Text.PlainText; color: root.foreground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.body; elide: Text.ElideRight; width: parent.width }
              Text { text: String(modelData.country && modelData.country.name || ""); textFormat: Text.PlainText; color: Qt.darker(root.foreground, 1.4); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.caption; elide: Text.ElideRight; width: parent.width }
            }
            MouseArea { id: resultArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.chooseTeam(modelData) }
          }
        }
      }

      Column {
        visible: teamId > 0 && !addingTeam
        width: parent.width
        spacing: Style.space(6)
        Text { text: refreshing ? "UPDATING" : (liveMatch ? "● LIVE · " + String(liveMatch.status && liveMatch.status.description || "").toUpperCase() : "LAST RESULT"); textFormat: Text.PlainText; color: liveMatch ? Color.urgent : Qt.darker(root.foreground, 1.4); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1 }
        EventLine { event: liveMatch || lastMatch; includeScore: true; width: parent.width; visible: event !== null }
        EventMeta { event: liveMatch || lastMatch; visible: event !== null }
        Rectangle { width: parent.width; height: 1; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) }
        Text { text: "NEXT GAMES"; color: Qt.darker(root.foreground, 1.4); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1 }
        Repeater {
          model: root.nextMatches
          delegate: Column { required property var modelData; width: parent.width; spacing: 1
            EventLine { event: modelData; width: parent.width }
            EventMeta { event: modelData }
          }
        }
      }

      PanelSeparator {
        visible: teamId > 0 && !addingTeam
        foreground: root.foreground
      }

      Item {
        visible: teamId > 0 && !addingTeam
        width: parent.width
        implicitHeight: Math.max(updatedLabel.implicitHeight, refreshButton.implicitHeight)

        Text {
          id: updatedLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: lastUpdatedAt ? "󰅐  Updated " + Qt.formatDateTime(lastUpdatedAt, "HH:mm") : "Updating…"
          color: Qt.darker(root.foreground, 1.55)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }

        PanelActionButton {
          id: refreshButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰑐"
          foreground: Qt.darker(root.foreground, 1.55)
          hoverColor: root.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: Style.font.caption
          size: Style.space(20)
          enabled: !root.refreshing
          onClicked: root.refresh()
        }

        Item {
          id: removeButton
          anchors.right: refreshButton.left
          anchors.rightMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(20)
          height: width

          Text {
            anchors.centerIn: parent
            text: "×"
            textFormat: Text.PlainText
            color: removeArea.containsMouse ? Color.urgent : Qt.darker(root.foreground, 1.55)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }
          MouseArea {
            id: removeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.removeActiveTeam()
          }
          Text {
            visible: removeArea.containsMouse
            anchors.right: parent.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: "Remove team"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      Text { visible: errorText !== ""; width: parent.width; text: errorText; color: Color.urgent; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
    }
  }
}
