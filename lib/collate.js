(function() {
  var Collate, async, coffee, fs, jsp, less, path, pro, wait, _Collator,
    __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

  fs = require('fs');

  path = require('path');

  async = require('async');

  coffee = require('coffee-script');

  less = require('less');

  jsp = require('uglify-js').parser;

  pro = require('uglify-js').uglify;

  wait = function(milliseconds, func) {
    return setTimeout(func, milliseconds);
  };

  Collate = (function() {

    function Collate() {}

    Collate.prototype.collate = function(target, sources, options) {
      var collator;
      if (options == null) options = {};
      if (options.compress == null) options.compress = true;
      collator = new _Collator(target, sources, options);
      return collator.collate();
    };

    return Collate;

  })();

  _Collator = (function() {

    function _Collator(target, sources, options) {
      var source,
        _this = this;
      this.target = target;
      this.sources = sources;
      this.options = options;
      this._writeTarget = __bind(this._writeTarget, this);
      this._compileSource = __bind(this._compileSource, this);
      this._compileSources = __bind(this._compileSources, this);
      this._rewatch = __bind(this._rewatch, this);
      this._watchEvent = __bind(this._watchEvent, this);
      this.collate = __bind(this.collate, this);
      if (options.basedir != null) {
        this.target = this.options.basedir + this.target;
        this.sources = (function() {
          var _i, _len, _ref, _results;
          _ref = this.sources;
          _results = [];
          for (_i = 0, _len = _ref.length; _i < _len; _i++) {
            source = _ref[_i];
            _results.push(this.options.basedir + source);
          }
          return _results;
        }).call(this);
      }
      this.target = path.resolve(this.target);
      this.sources = (function() {
        var _i, _len, _ref, _results;
        _ref = this.sources;
        _results = [];
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          source = _ref[_i];
          _results.push(path.resolve(source));
        }
        return _results;
      }).call(this);
      if (this.options.watch) {
        async.map(this.sources, fs.stat, function(err, stats) {
          return _this._stats = stats;
        });
      }
    }

    _Collator.prototype.collate = function() {
      var _this = this;
      return async.series([this._compileSources, this._writeTarget], function(err, results) {
        if (err) console.log(err);
        console.log("" + ((new Date).toLocaleTimeString()) + " - collated " + (path.basename(_this.target)));
        if (_this.options.watch) return _this._rewatch();
      });
    };

    _Collator.prototype._watchEvent = function(event, filename) {
      var _this = this;
      clearTimeout(this._watchTimeout);
      return this._watchTimeout = wait(25, function() {
        var watcher, _i, _len, _ref;
        _ref = _this._watchers;
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          watcher = _ref[_i];
          watcher.close();
        }
        return async.map(_this.sources, fs.stat, function(err, stats) {
          var i, prev, stat, _len2;
          for (i = 0, _len2 = stats.length; i < _len2; i++) {
            stat = stats[i];
            prev = _this._stats[i];
            if (stat.size !== prev.size || stat.mtime.getTime() !== prev.mtime.getTime()) {
              console.log("" + ((new Date).toLocaleTimeString()) + " - " + (path.basename(_this.sources[i])) + " changed");
              _this._compiledSources[i] = null;
              _this._stats[i] = stat;
            }
          }
          if (_this._compiledSources.indexOf(null) !== -1) {
            return _this.collate();
          } else {
            return _this._rewatch();
          }
        });
      });
    };

    _Collator.prototype._rewatch = function() {
      var source;
      return this._watchers = (function() {
        var _i, _len, _ref, _results;
        _ref = this.sources;
        _results = [];
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          source = _ref[_i];
          _results.push(fs.watch(source, this._watchEvent));
        }
        return _results;
      }).call(this);
    };

    _Collator.prototype._compileSources = function(callback) {
      var compileIfChanged, _i, _ref, _results,
        _this = this;
      if (!this._compiledSources) {
        return async.map(this.sources, this._compileSource, function(err, results) {
          _this._compiledSources = results;
          return callback(err);
        });
      } else {
        compileIfChanged = function(i, _callback) {
          if (!(_this._compiledSources[i] != null)) {
            return _this._compileSource(_this.sources[i], function(err, result) {
              _this._compiledSources[i] = result;
              return _callback(null);
            });
          } else {
            return _callback(null);
          }
        };
        return async.map((function() {
          _results = [];
          for (var _i = 0, _ref = this._compiledSources.length; 0 <= _ref ? _i < _ref : _i > _ref; 0 <= _ref ? _i++ : _i--){ _results.push(_i); }
          return _results;
        }).apply(this), compileIfChanged, callback);
      }
    };

    _Collator.prototype._compileSource = function(source, callback) {
      var compile, compress, ext, read, uglify;
      ext = path.extname(source);
      compress = this.options.compress;
      uglify = function(js) {
        var ast;
        ast = jsp.parse(js);
        ast = pro.ast_mangle(ast);
        ast = pro.ast_squeeze(ast);
        return pro.gen_code(ast);
      };
      read = function(_callback) {
        return fs.readFile(source, _callback);
      };
      compile = function(result, _callback) {
        var less_options;
        result = result.toString();
        switch (ext) {
          case '.js':
            if (compress) result = uglify(result);
            return _callback(null, result);
          case '.coffee':
            result = coffee.compile(result);
            if (compress) result = uglify(result);
            return _callback(null, result);
          case '.css':
          case '.less':
            less_options = {
              filename: source,
              paths: [path.dirname(source)]
            };
            return new less.Parser(less_options).parse(result, function(err, tree) {
              if (!err) {
                result = tree.toCSS({
                  compress: compress
                });
              }
              return _callback(err, result);
            });
        }
      };
      return async.waterfall([read, compile], callback);
    };

    _Collator.prototype._writeTarget = function(callback) {
      var compiledSource, ws, _i, _len, _ref;
      ws = fs.createWriteStream(this.target);
      _ref = this._compiledSources;
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        compiledSource = _ref[_i];
        ws.write(compiledSource);
        if (this.target.indexOf('.js') !== -1) ws.write(';\n');
      }
      ws.end();
      return callback(null);
    };

    return _Collator;

  })();

  module.exports = new Collate;

}).call(this);
