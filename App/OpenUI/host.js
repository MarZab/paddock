// Paddock's host for OpenUI's renderer (backlog doc Browser, OpenUI tabs). Paddock calls
// paddockRender(document, state) with the agent's OpenUI Lang document (data, never code) and the
// form state it kept; this page posts back to Paddock, through its one message handler, only plain
// JSON: an action (a button or a submitted form, with its values), the renderer's problems, and
// state changes (kept by Paddock so switching tabs loses nothing).
(function () {
  'use strict';
  var openui = window.__OpenUI;
  var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.paddock;
  function post(message) {
    if (!handler) return;
    try { handler.postMessage(JSON.stringify(message)); } catch (e) { /* too large or not serializable */ }
  }
  // Dates become ISO strings, undefined is dropped: plain JSON only.
  function plain(value) {
    return value === undefined ? null : JSON.parse(JSON.stringify(value));
  }
  // OpenUI's form state ({form: {field: {value, componentType}}}) as {field: value}.
  function values(formState, formName) {
    var source = formState && formName && formState[formName] ? formState[formName] : formState;
    var result = {};
    if (!source || typeof source !== 'object') return result;
    Object.keys(source).forEach(function (key) {
      var entry = source[key];
      result[key] = entry && typeof entry === 'object' && 'value' in entry ? entry.value : entry;
    });
    return plain(result);
  }
  function onAction(event) {
    var params = event.params || {};
    var action = { type: event.type, message: event.humanFriendlyMessage || '' };
    if (params.url !== undefined) action.url = String(params.url);
    if (params.context !== undefined) action.context = plain(params.context);
    if (event.formName) action.form = event.formName;
    var fields = values(event.formState, event.formName);
    if (Object.keys(fields).length) action.values = fields;
    post({ kind: 'action', action: action });
  }
  function onError(errors) {
    post({
      kind: 'problems',
      problems: (errors || []).map(function (e) {
        return plain({ code: e.code, statementId: e.statementId, component: e.component, message: e.message, hint: e.hint, severity: e.severity });
      })
    });
  }
  if (!openui) {
    post({ kind: 'problems', problems: [{ code: 'renderer-missing', message: 'the OpenUI renderer did not load' }] });
    return;
  }
  var root = openui.createRoot(document.getElementById('root'));
  window.paddockRender = function (response, state) {
    root.render(openui.React.createElement(openui.Renderer, {
      response: String(response || ''),
      library: openui.openuiChatLibrary,
      isStreaming: false,
      initialState: state || undefined,
      onAction: onAction,
      onError: onError,
      onStateUpdate: function (snapshot) { post({ kind: 'state', state: plain(snapshot) }); }
    }));
  };
  post({ kind: 'ready' });
})();
