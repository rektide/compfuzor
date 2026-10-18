// automation-masking.js — normalize the patched build's automation surface
// and TRIPWIRE every probe of it.
//
// Masked surface (values a stock Firefox reports):
//   navigator.webdriver        -> false
//   navigator.plugins          -> 5 Chrome-compat PDF entries
//   navigator.mimeTypes        -> 2 entries (application/pdf, text/pdf)
//   navigator.pdfViewerEnabled -> true
//
// Instrumentation: every read (including `typeof navigator.webdriver`,
// destructuring, Reflect.get), every Object.getOwnPropertyDescriptor(s) probe
// of these keys on navigator/Navigator.prototype, and every
// Function.prototype.toString native-check of our getters or wrapped builtins
// fires a console.warn naming the kind, the key, and the caller's stack site.
// The getters and wrappers themselves report native-shaped toString() output
// so the tripwire does not become its own tell.
//
// Known gaps (in-operator style probes): `'webdriver' in navigator` and
// hasOwnProperty do not invoke getters and are not observable without a
// navigator Proxy, which would be a larger fingerprint seam than the signal.
(function () {
  'use strict';

  var MASK_KEYS = ['webdriver', 'plugins', 'mimeTypes', 'pdfViewerEnabled'];
  var PREFIX = '[automation-masking]';
  var seen = {};

  function callerSite() {
    try {
      var lines = String(new Error().stack || '').split('\n');
      for (var i = 1; i < lines.length && i < 7; i++) {
        var line = lines[i].replace(/^\s*at\s*/, '').trim();
        if (line.indexOf('automation-masking') === -1 && line.indexOf(PREFIX) === -1) {
          return line.slice(0, 180);
        }
      }
      return 'unknown';
    } catch (error) {
      return 'unknown';
    }
  }

  function report(kind, key) {
    try {
      var who = callerSite();
      var signature = kind + ':' + key + ':' + who;
      var repeat = seen[signature] ? ' (repeat)' : '';
      seen[signature] = true;
      console.warn(PREFIX + ' ' + kind + ' ' + key + repeat + ' <- ' + who);
    } catch (error) {}
  }

  // Functions that must answer native-looking toString() probes.
  var maskedFns = [];
  function nativeStringFor(fn) {
    for (var i = 0; i < maskedFns.length; i++) {
      if (maskedFns[i].fn === fn) {
        return 'function ' + maskedFns[i].name + '() {\n    [native code]\n}';
      }
    }
    return null;
  }

  function defineMasked(key, getValue) {
    var getter = function () {
      report('read', key);
      return getValue();
    };
    try { Object.defineProperty(getter, 'name', { value: key }); } catch (error) {}
    maskedFns.push({ fn: getter, name: key });
    Object.defineProperty(Navigator.prototype, key, {
      get: getter,
      enumerable: true,
      configurable: true,
    });
  }

  // Stock PDF-viewer surface: 5 Chrome-compat plugin entries, 2 MIME types.
  var PLUGIN_NAMES = ['PDF Viewer', 'Chrome PDF Viewer', 'Chromium PDF Viewer', 'Microsoft Edge PDF Viewer', 'WebKit built-in PDF Viewer'];
  function mkMime(type, suffixes, description, plugin) {
    var m = Object.create(MimeType.prototype);
    Object.defineProperties(m, {
      type: { value: type, enumerable: true },
      suffixes: { value: suffixes, enumerable: true },
      description: { value: description, enumerable: true },
      enabledPlugin: { value: plugin, enumerable: true },
    });
    return m;
  }
  var plugins = Object.create(PluginArray.prototype);
  PLUGIN_NAMES.forEach(function (name, i) {
    var p = Object.create(Plugin.prototype);
    var m = mkMime('application/pdf', 'pdf', 'Portable Document Format', p);
    Object.defineProperties(p, {
      0: { value: m, enumerable: true },
      name: { value: name, enumerable: true },
      filename: { value: 'internal-pdf-viewer', enumerable: true },
      description: { value: 'Portable Document Format', enumerable: true },
      length: { value: 1, enumerable: true },
    });
    Object.defineProperty(p, 'item', { value: function (i2) { return i2 === 0 ? m : null; } });
    Object.defineProperty(p, 'namedItem', { value: function (t) { return t === 'application/pdf' ? m : null; } });
    Object.defineProperty(plugins, i, { value: p, enumerable: true });
    Object.defineProperty(plugins, name, { value: p, enumerable: true });
  });
  Object.defineProperty(plugins, 'length', { value: PLUGIN_NAMES.length });
  Object.defineProperty(plugins, 'item', { value: function (i) { return this[i] || null; } });
  Object.defineProperty(plugins, 'namedItem', { value: function (n) { return this[n] || null; } });
  Object.defineProperty(plugins, 'refresh', { value: function () {} });
  var appPdf = mkMime('application/pdf', 'pdf', 'Portable Document Format', plugins[0]);
  var textPdf = mkMime('text/pdf', 'pdf', 'Portable Document Format', plugins[0]);
  var mimeTypes = Object.create(MimeTypeArray.prototype);
  Object.defineProperty(mimeTypes, 0, { value: appPdf, enumerable: true });
  Object.defineProperty(mimeTypes, 1, { value: textPdf, enumerable: true });
  Object.defineProperty(mimeTypes, 'application/pdf', { value: appPdf, enumerable: true });
  Object.defineProperty(mimeTypes, 'text/pdf', { value: textPdf, enumerable: true });
  Object.defineProperty(mimeTypes, 'length', { value: 2 });
  Object.defineProperty(mimeTypes, 'item', { value: function (i) { return this[i] || null; } });
  Object.defineProperty(mimeTypes, 'namedItem', { value: function (t) { return this[t] || null; } });

  defineMasked('webdriver', function () { return false; });
  defineMasked('plugins', function () { return plugins; });
  defineMasked('mimeTypes', function () { return mimeTypes; });
  defineMasked('pdfViewerEnabled', function () { return true; });

  // Descriptor probes: getOwnPropertyDescriptor(s) on navigator for the
  // masked keys never fire the getters, so intercept the builtin itself.
  function looksLikeNavigatorTarget(target) {
    try {
      return target === navigator || target === Navigator.prototype || target === Object.getPrototypeOf(navigator);
    } catch (error) {
      return false;
    }
  }
  var origGOPD = Object.getOwnPropertyDescriptor;
  var gopdWrapper = function getOwnPropertyDescriptor(target, key) {
    if (looksLikeNavigatorTarget(target) && MASK_KEYS.indexOf(String(key)) !== -1) {
      report('descriptor-probe', String(key));
    }
    return origGOPD.call(Object, target, key);
  };
  maskedFns.push({ fn: gopdWrapper, name: 'getOwnPropertyDescriptor' });
  Object.getOwnPropertyDescriptor = gopdWrapper;

  var origGOPDs = Object.getOwnPropertyDescriptors;
  if (typeof origGOPDs === 'function') {
    var gopdsWrapper = function getOwnPropertyDescriptors(target) {
      if (looksLikeNavigatorTarget(target)) {
        report('descriptor-probe', 'getOwnPropertyDescriptors');
      }
      return origGOPDs.call(Object, target);
    };
    maskedFns.push({ fn: gopdsWrapper, name: 'getOwnPropertyDescriptors' });
    Object.getOwnPropertyDescriptors = gopdsWrapper;
  }

  // Native-object checks: Function.prototype.toString on our getters or the
  // wrapped builtins must answer with a native-looking string, and the check
  // itself is reported.
  var origToString = Function.prototype.toString;
  var toStringWrapper = function toString() {
    var fake = nativeStringFor(this);
    if (fake !== null) {
      report('native-check', 'function');
      return fake;
    }
    return origToString.call(this);
  };
  maskedFns.push({ fn: toStringWrapper, name: 'toString' });
  Function.prototype.toString = toStringWrapper;
})();
