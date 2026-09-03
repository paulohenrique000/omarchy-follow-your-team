var sports = [
  { slug: "football", name: "Football", icon: "󰒸" },
  { slug: "basketball", name: "Basketball", icon: "󰠆" },
  { slug: "american-football", name: "American football", icon: "󰉝" },
  { slug: "baseball", name: "Baseball", icon: "󰡒" },
  { slug: "ice-hockey", name: "Hockey", icon: "󰡺" },
  { slug: "volleyball", name: "Volleyball", icon: "󰦴" },
  { slug: "cricket", name: "Cricket", icon: "󰵭" },
  { slug: "rugby", name: "Rugby", icon: "󰶙" }
]

function sportFor(slug) {
  for (var i = 0; i < sports.length; i++) if (sports[i].slug === slug) return sports[i]
  return { slug: slug || "", name: "Sport", icon: "\uf1e3" }
}

function sportIcon(slug) {
  return sportFor(slug).icon
}

function parse(raw) {
  try { return JSON.parse(String(raw || "{}")) } catch (error) { return {} }
}

function searchTeams(raw, sportSlug) {
  var parsed = parse(raw)
  var results = Array.isArray(parsed.results) ? parsed.results : []
  return results.filter(function(result) {
    return result && result.type === "team" && result.entity
      && (!sportSlug || result.entity.sport && result.entity.sport.slug === sportSlug)
  }).map(function(result) { return result.entity }).slice(0, 6)
}

function parseEvents(raw) {
  var parsed = parse(raw)
  return Array.isArray(parsed.events) ? parsed.events : []
}

function latestCompleted(events) {
  var latest = null
  ;(events || []).forEach(function(event) {
    if (!event || !event.status || event.status.type !== "finished") return
    if (!latest || Number(event.startTimestamp || 0) > Number(latest.startTimestamp || 0)) latest = event
  })
  return latest
}

function upcoming(events, count) {
  return (events || []).filter(function(event) {
    return event && (!event.status || event.status.type !== "canceled")
  }).sort(function(a, b) {
    return Number(a.startTimestamp || 0) - Number(b.startTimestamp || 0)
  }).slice(0, count || 3)
}

function score(event, side) {
  if (!event || !event[side + "Score"]) return "–"
  var value = event[side + "Score"]
  if (value.current !== undefined && value.current !== null) return String(value.current)
  if (value.normaltime !== undefined && value.normaltime !== null) return String(value.normaltime)
  return "–"
}

function opponent(event, teamId) {
  if (!event || !event.homeTeam || !event.awayTeam) return ""
  return Number(event.homeTeam.id) === Number(teamId) ? String(event.awayTeam.name || "") : String(event.homeTeam.name || "")
}

function isHome(event, teamId) {
  return !!event && !!event.homeTeam && Number(event.homeTeam.id) === Number(teamId)
}

function escapeHtml(value) {
  return String(value || "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/\"/g, "&quot;").replace(/'/g, "&#39;")
}

function relativeTime(timestamp, now) {
  var reference = now === undefined || now === null ? Date.now() / 1000 : Number(now)
  var seconds = Math.max(0, Math.round(Number(timestamp || 0) - reference))
  if (seconds < 90) return "in 1 min"
  if (seconds < 3600) return "in " + Math.round(seconds / 60) + " min"
  if (seconds < 86400) return "in " + Math.round(seconds / 3600) + "h"
  return "in " + Math.round(seconds / 86400) + " days"
}

function liveEvent(events) {
  var live = null
  ;(events || []).forEach(function(event) {
    if (!event || !event.status || event.status.type !== "inprogress") return
    if (!live || Number(event.startTimestamp || 0) > Number(live.startTimestamp || 0)) live = event
  })
  return live
}

// Each line is: team-id <tab> last-events JSON <tab> next-events JSON.
function teamSummaries(raw) {
  var result = {}
  String(raw || "").split("\n").forEach(function(line) {
    var first = line.indexOf("\t")
    var second = first < 0 ? -1 : line.indexOf("\t", first + 1)
    if (first < 1 || second < 0) return
    var id = line.slice(0, first)
    var previous = parseEvents(line.slice(first + 1, second))
    var live = liveEvent(previous)
    var games = upcoming(parseEvents(line.slice(second + 1)), 1)
    result[id] = { live: live, last: latestCompleted(previous), next: games.length > 0 ? games[0] : null }
  })
  return result
}

// Each line is: followed-team-id <tab> event JSON from /event/<event-id>.
function liveEventUpdates(raw) {
  var result = {}
  String(raw || "").split("\n").forEach(function(line) {
    var divider = line.indexOf("\t")
    if (divider < 1) return
    var parsed = parse(line.slice(divider + 1))
    var event = parsed && parsed.event ? parsed.event : null
    if (!event) return
    if (event.status && event.status.type === "inprogress") result[line.slice(0, divider)] = { live: event }
    else if (event.status && event.status.type === "finished") result[line.slice(0, divider)] = { live: null, last: event }
    else result[line.slice(0, divider)] = { live: null }
  })
  return result
}

function teamScore(event, teamId) {
  if (!event) return ""
  var ownHome = Number(event.homeTeam && event.homeTeam.id) === Number(teamId)
  return score(event, ownHome ? "home" : "away") + "–" + score(event, ownHome ? "away" : "home")
}

function liveScore(event, teamId) {
  if (!event) return ""
  var period = event.status && event.status.description ? " · " + event.status.description : ""
  return teamScore(event, teamId) + period
}

// Compact followed-team-first score for the bar: "2–0 MIR".
function opponentScore(event, teamId) {
  if (!event) return ""
  var ownHome = Number(event.homeTeam && event.homeTeam.id) === Number(teamId)
  var opponentTeam = ownHome ? event.awayTeam : event.homeTeam
  return teamScore(event, teamId) + " " + shortName(opponentTeam && opponentTeam.name)
}

function isRecentResult(event, now, hours) {
  if (!event || !event.status || event.status.type !== "finished") return false
  var reference = now === undefined || now === null ? Date.now() / 1000 : Number(now)
  // SofaScore exposes the start of the final period for many sports; it is a
  // closer approximation of finish time than kickoff/first-pitch.
  var finishedAround = Number(event.lastPeriodStartTimestamp || event.startTimestamp || 0)
  var age = reference - finishedAround
  return age >= 0 && age < (hours || 8) * 60 * 60
}

function shortName(name) {
  var words = String(name || "").split(/\s+/).filter(function(word) { return word.length > 0 })
  if (words.length === 0) return ""
  if (words.length === 1) return words[0].slice(0, 3).toUpperCase()
  return words.map(function(word) { return word.charAt(0) }).join("").slice(0, 4).toUpperCase()
}

if (typeof module !== "undefined") module.exports = {
  sports: sports, sportFor: sportFor, sportIcon: sportIcon, searchTeams: searchTeams,
  parseEvents: parseEvents, latestCompleted: latestCompleted, upcoming: upcoming,
  score: score, opponent: opponent, isHome: isHome, escapeHtml: escapeHtml,
  relativeTime: relativeTime, liveEvent: liveEvent, teamSummaries: teamSummaries,
  liveEventUpdates: liveEventUpdates, teamScore: teamScore, liveScore: liveScore,
  opponentScore: opponentScore, isRecentResult: isRecentResult,
  shortName: shortName
}
