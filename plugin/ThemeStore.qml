import QtQuick
import Quickshell
import Quickshell.Io

// The themes and the four things that can be done to them. Every disk change runs through
// bin/theme-remover — its header says why Omarchy's own themes are hidden rather than deleted.
Item {
  id: store

  property string helper: ""
  property var themes: []
  property bool loaded: false
  property bool busy: false
  property string message: ""
  property bool messageIsError: false

  readonly property string pickerSignature: Quickshell.env("HOME") + "/.cache/omarchy/theme-selector/fast-signature"

  function reload() {
    if (!helper || listProc.running) return
    listProc.command = [helper, "list"]
    listProc.running = true
  }

  function removeTheme(theme) { run(["remove", theme.slug]) }
  function hideTheme(theme) { run(["hide", theme.slug]) }
  function restoreTheme(theme) { run(["restore", theme.slug]) }
  function removeBrokenLinks() { run(["remove-broken"]) }

  function run(args) {
    if (!helper || busy) return
    busy = true
    message = ""
    messageIsError = false
    actionProc.command = [helper].concat(args)
    actionProc.running = true
  }

  function prune() {
    if (!helper || pruneProc.running) return
    pruneProc.command = [helper, "prune"]
    pruneProc.running = true
  }

  Process {
    id: listProc
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    onExited: function(exitCode) {
      var parsed = null
      try { parsed = JSON.parse(String(listOut.text || "[]")) } catch (e) { parsed = null }
      if (exitCode === 0 && Array.isArray(parsed)) {
        store.themes = parsed
      } else {
        store.message = "Could not read the themes folder"
        store.messageIsError = true
      }
      store.loaded = true
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      var out = String(actionOut.text || "").trim()
      var err = String(actionErr.text || "").trim()
      store.messageIsError = exitCode !== 0
      store.message = exitCode === 0 ? out : (err || out || "That did not work")
      store.busy = false
      store.reload()
    }
  }

  Process { id: pruneProc }

  // Omarchy rewrites this file whenever it rebuilds its theme picker's cache, and a rebuild
  // brings hidden themes back, so a new signature means prune. ⚠️ IT IS READ EVERY 15 SECONDS, NOT
  // ONLY WATCHED: in a throwaway VM on 2026-09-25 a watch set while the file did not exist yet (a
  // fresh machine) never fired, not even after two rebuilds had written it. A restore deletes the
  // file and Omarchy writes it anew, which is the same situation. Reading a 2 KB file is cheap.
  property string lastPickerSignature: ""

  function pickerSignatureRead(text) {
    if (text === lastPickerSignature) return
    lastPickerSignature = text
    if (text) prune()
  }

  FileView {
    id: pickerSignatureFile
    path: store.pickerSignature
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: store.pickerSignatureRead(text())
    onLoadFailed: store.pickerSignatureRead("")
  }

  Timer {
    interval: 15000
    repeat: true
    running: true
    onTriggered: pickerSignatureFile.reload()
  }
}
