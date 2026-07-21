// MV3 service workers do not provide `window`; map legacy globals for MV2 code.
self.window = self;
self.global = self;

importScripts('ext/sjcl.js', 'global.min.js');
